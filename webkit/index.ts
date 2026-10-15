import { createLiveEncoder, liveEncodingSupported, type LiveEncoder, type LiveEncoderSettings } from './liveEncoder';
import { createLivePlayer, base64ToBytes, type LiveHealth, type LivePlayer } from './livePlayer';
import { RelayClient, relayUrlUsable, FRAME_INIT, FRAME_KEY, FRAME_DELTA, FLAG_NONE, FLAG_DISCONTINUITY, type RelayGrant, type PublishHandle, type JoinHandle } from './relaySocket';

export { createGameRender } from './gameRender';
export type { GameRender } from './gameRender';
export { createLiveEncoder, liveEncodingSupported, pickLiveMime } from './liveEncoder';
export { createLivePlayer, livePlaybackSupported, base64ToBytes } from './livePlayer';
export { RelayClient, relayUrlUsable } from './relaySocket';
export type { LiveEncoder, LiveEncoderSettings } from './liveEncoder';
export type { LivePlayer, LiveHealth } from './livePlayer';
export type { RelayGrant } from './relaySocket';

export const MediaMsg = {
    begin: 'bridgeMedia:begin',
    audio: 'bridgeMedia:audio',
    end: 'bridgeMedia:end',
    anchor: 'bridgeMedia:anchor',
    feed: 'bridgeMedia:feed',
    ended: 'bridgeMedia:ended',
    transport: 'bridgeMedia:transport',
} as const;

export const MediaCb = {
    chunk: 'bridgeMediaChunk',
    failed: 'bridgeMediaFailed',
    resync: 'bridgeMediaResync',
    token: 'bridgeMediaRelayToken',
    transport: 'bridgeMediaTransport',
} as const;

export interface BeginPayload { id: string; enc?: Partial<LiveEncoderSettings>; audio?: boolean }
export interface AudioPayload { id: string; on?: boolean }
export interface EndPayload { id: string }
export interface FeedPayload { id: string; chunk: string; init?: boolean; mime?: string | null }
export interface EndedPayload { id: string; reason?: string }
export interface TransportPayload { id: string; relay?: boolean }

type Send = (name: string, data: unknown) => unknown;

const INTENDED = new Set(['reset', 'ended', 'stop', 'closing', 'host_left_relay', 'stream_ended']);

async function grant(send: Send, role: RelayGrant['role'], id?: string, gen?: number, action: string = MediaCb.token): Promise<RelayGrant | null> {
    let res: unknown;
    try { res = await send(action, { role, id, gen }); } catch { return null; }
    const g = res as Partial<RelayGrant> | false | null;
    if (!g || typeof g !== 'object' || typeof g.token !== 'string' || typeof g.url !== 'string') return null;
    if (!relayUrlUsable(g.url)) return null;
    return { url: g.url, token: g.token, key: g.key ?? '', role: g.role ?? role, gen: g.gen ?? 0, ttlSeconds: g.ttlSeconds ?? 45, expiresAt: g.expiresAt ?? 0 };
}

async function blobBytes(blob: Blob): Promise<Uint8Array<ArrayBuffer>> {
    const buf = await blob.arrayBuffer();
    return new Uint8Array(buf);
}

function blobBase64(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => { const r = reader.result as string; const c = r.indexOf(','); resolve(c >= 0 ? r.slice(c + 1) : r); };
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
    });
}

export interface LiveHostOptions {
    send: Send;

    onMic?: (open: boolean) => void;
    onState?: (hosting: boolean) => void;

    onTransport?: (relay: boolean) => void;
}

export interface LiveHost {
    handle(action: string, data: unknown): boolean;
    readonly hosting: boolean;
    readonly relay: boolean;
    stop(): void;
}

export function createLiveHost(o: LiveHostOptions): LiveHost {
    let encoder: LiveEncoder | null = null;
    let id: string | null = null;
    let relay: RelayClient | null = null;
    let pub: PublishHandle | null = null;
    let gen = 0;
    let mime = '';
    let enc: Partial<LiveEncoderSettings> = {};
    let chain: Promise<void> = Promise.resolve();
    let republishing = false;
    let onRelay = false;

    const EVENT_PROFILE = { width: 640, fps: 15, bitrate: 800_000 };
    function fullProfile() {
        return { width: enc.width ?? 1280, fps: enc.fps ?? 24, bitrate: enc.bitrate ?? 4_000_000 };
    }
    function eventProfile() {
        const full = fullProfile();
        return { width: Math.min(full.width, EVENT_PROFILE.width), fps: Math.min(full.fps, EVENT_PROFILE.fps), bitrate: Math.min(full.bitrate, EVENT_PROFILE.bitrate) };
    }
    const log = (msg: string) => console.info('[bridgeMedia] emisor: ' + msg);

    function tellTransport(sid: string, relayNow: boolean) {
        onRelay = relayNow;
        void o.send(MediaCb.transport, { id: sid, relay: relayNow });
        o.onTransport?.(relayNow);
    }

    function dropRelay(sid: string, why: string) {
        const had = pub !== null;
        pub?.close();
        pub = null;
        relay?.close(why);
        relay = null;
        if (had && id === sid) {
            log('relay perdido (' + why + '), vuelvo a eventos con perfil bajo');
            tellTransport(sid, false);

            encoder?.setQuality(eventProfile());
            encoder?.anchor();
        }
    }

    async function publishRelay(sid: string): Promise<boolean> {
        if (!encoder || id !== sid || republishing) return false;
        republishing = true;
        try {
            if (!relay || !relay.isOpen) {
                const session = await grant(o.send, 'session');
                if (!session) { log('sin pase de sesión: el servidor no tiene relay configurado o la URL no vale'); return false; }
                if (id !== sid) return false;
                const client = new RelayClient(session.url, session.token);
                const ok = await client.connect((reason) => {
                    if (relay !== client) return;
                    relay = null;
                    pub = null;
                    if (id === sid) {
                        if (!INTENDED.has(reason)) log('socket cerrado (' + reason + '), vuelvo a eventos con perfil bajo');
                        tellTransport(sid, false);
                        encoder?.setQuality(eventProfile());
                        encoder?.anchor();
                    }
                });
                if (!ok) { log('no se pudo conectar a ' + session.url); client.close(); return false; }
                if (id !== sid) { client.close(); return false; }
                relay = client;
            }
            gen += 1;
            const g = await grant(o.send, 'publish', sid, gen);
            if (!g) { log('el servidor no concedió el pase de emisión'); return false; }
            if (id !== sid || !relay) return false;
            pub?.close();
            pub = null;
            const aspect = window.innerWidth > 0 && window.innerHeight > 0 ? window.innerHeight / window.innerWidth : 9 / 16;
            const width = Math.round(enc.width ?? 1280);
            const handle = await relay.publish({
                grant: g,
                desc: { mode: 'video', wire: 'mse', codec: /vp9/i.test(mime) ? 'vp9' : 'vp8', mime, width, height: Math.round(width * aspect), fps: enc.fps ?? 24, bitrate: enc.bitrate ?? 4_000_000 },
                onKeyframeRequest: () => { encoder?.anchor(); },
                onState: (state) => { if (state === 'ended') dropRelay(sid, 'stream_ended'); },
                onError: (_code, fatal) => { if (fatal) dropRelay(sid, 'relay_error'); },
            });
            if (!handle) { log('el relay rechazó la publicación (mira su consola)'); return false; }
            if (id !== sid) return false;
            pub = handle;
            log('publicando en ' + g.url + ' (gen ' + gen + ')');
            tellTransport(sid, true);

            encoder.setQuality(fullProfile());
            encoder.anchor();
            return true;
        } finally {
            republishing = false;
        }
    }

    function stop() {
        const sid = id;
        encoder?.stop();
        encoder = null;
        pub?.close();
        pub = null;
        relay?.close('stop');
        relay = null;
        onRelay = false;
        if (sid !== null) { id = null; o.onMic?.(false); o.onState?.(false); }
    }

    async function begin(p: BeginPayload) {
        stop();
        id = p.id;
        enc = p.enc ?? {};
        gen = 0;
        mime = '';
        if (!liveEncodingSupported()) {
            void o.send(MediaCb.failed, { id: p.id });
            id = null;
            return;
        }
        const sid = p.id;

        encoder = createLiveEncoder({
            enc: { ...enc, ...eventProfile() },
            onChunk: (blob, init, key, m) => {
                if (id !== sid) return;

                const audioChanged = init && mime !== '' && /opus/i.test(m) !== /opus/i.test(mime);
                const firstInit = init && mime === '';
                if (init) mime = m;
                chain = chain.then(async () => {
                    if (id !== sid) return;

                    if (firstInit && !pub) {
                        void publishRelay(sid).then((ok) => { if (!ok && id === sid && (pub || relay)) dropRelay(sid, 'publish_failed'); });
                    }
                    if (pub && relay?.isOpen) {
                        if (audioChanged) {
                            const ok = await publishRelay(sid);
                            if (!ok) dropRelay(sid, 'republish_failed');
                            return;
                        }
                        const bytes = await blobBytes(blob);
                        const kind = init ? FRAME_INIT : key ? FRAME_KEY : FRAME_DELTA;
                        if (!pub.send(kind, FLAG_NONE, bytes) && kind !== FRAME_DELTA) dropRelay(sid, 'send_failed');
                        return;
                    }
                    const b64 = await blobBase64(blob);
                    if (id !== sid) return;
                    void o.send(MediaCb.chunk, { id: sid, chunk: b64, init, mime: init ? m : undefined });
                }).catch(() => {});
            },
            onFail: () => {
                if (id !== sid) return;
                void o.send(MediaCb.failed, { id: sid });
                stop();
            },
        });
        o.onState?.(true);
        if (p.audio) {
            const ok = await encoder.enableMic();
            o.onMic?.(ok);
        }
    }

    return {
        get hosting() { return id !== null; },
        get relay() { return onRelay; },
        stop,
        handle(action, data) {
            switch (action) {
                case MediaMsg.begin: {
                    const p = data as BeginPayload | undefined;
                    if (p?.id) void begin(p);
                    return true;
                }
                case MediaMsg.audio: {
                    const p = data as AudioPayload | undefined;
                    if (!p || p.id !== id || !encoder) return true;
                    if (p.on) void encoder.enableMic().then(ok => o.onMic?.(ok));
                    else { encoder.disableMic(); o.onMic?.(false); }
                    return true;
                }
                case MediaMsg.anchor: {
                    const p = data as EndPayload | undefined;
                    if (!p || p.id !== id || !encoder) return true;
                    encoder.anchor();
                    return true;
                }
                case MediaMsg.end: {
                    const p = data as EndPayload | undefined;
                    if (!p || p.id !== id) return true;
                    stop();
                    return true;
                }
                default:
                    return false;
            }
        },
    };
}

export interface LiveViewerOptions {
    onHealth?: (health: LiveHealth) => void;
    onAudio?: (hasAudio: boolean) => void;
    onEnded?: (reason: string) => void;

    send?: Send;

    onTransport?: (relay: boolean) => void;

    tokenAction?: string;

    relayOnly?: boolean;
}

export interface LiveViewer {
    watch(id: string): void;
    handle(action: string, data: unknown): boolean;
    readonly id: string | null;
    readonly health: LiveHealth;
    readonly relay: boolean;
    destroy(): void;
}

export function createLiveViewer(video: HTMLVideoElement, o: LiveViewerOptions = {}): LiveViewer {
    let player: LivePlayer | null = null;
    let id: string | null = null;
    let relay: RelayClient | null = null;
    let join: JoinHandle | null = null;
    let relayMime = '';
    let onRelay = false;
    let joining = false;
    const vlog = (msg: string) => console.info('[bridgeMedia] espectador: ' + msg);

    function leaveRelay(why: string) {
        join?.close();
        join = null;
        relay?.close(why);
        relay = null;
        onRelay = false;
    }

    async function joinRelay(sid: string) {
        if (joining || !o.send) return;
        joining = true;
        try {
            const session = await grant(o.send, 'session', undefined, undefined, o.tokenAction);
            if (!session) { vlog('sin pase de sesión para el relay'); return; }
            if (id !== sid) return;
            const client = new RelayClient(session.url, session.token);
            const ok = await client.connect((reason) => {
                if (relay !== client) return;
                relay = null;
                join = null;
                onRelay = false;
                if (!INTENDED.has(reason)) vlog('socket cerrado (' + reason + ')');
                o.onTransport?.(false);
            });
            if (!ok) { vlog('no se pudo conectar a ' + session.url); client.close(); return; }
            if (id !== sid) { client.close(); return; }
            const g = await grant(o.send, 'watch', sid, undefined, o.tokenAction);
            if (!g) { vlog('el servidor no concedió el pase de espectador'); client.close(); return; }
            if (id !== sid) { client.close(); return; }
            const handle = await client.join({
                grant: g,
                onDesc: (mime) => { if (mime) relayMime = mime; },
                onFrame: (f) => {
                    if (!player || id !== sid) return;
                    if (f.kind !== FRAME_INIT && f.kind !== FRAME_KEY && f.kind !== FRAME_DELTA) return;
                    if ((f.flags & FLAG_DISCONTINUITY) !== 0 && f.kind !== FRAME_INIT) {
                        player.feed(null, false);
                        return;
                    }
                    player.feed(f.payload, f.kind === FRAME_INIT, f.kind === FRAME_INIT ? relayMime || null : null);
                },
                onState: (state, reason) => {
                    if (state === 'ended' && id === sid) {
                        leaveRelay(reason);
                        o.onTransport?.(false);
                    }
                },
            });
            if (!handle) { vlog('el relay rechazó la unión'); client.close(); return; }
            if (id !== sid) { client.close(); return; }
            relay = client;
            join = handle;
            onRelay = true;
            vlog('viendo por ' + g.url);
            o.onTransport?.(true);
        } finally {
            joining = false;
        }
    }

    function reset() {
        leaveRelay('reset');
        player?.destroy();
        player = null;
        relayMime = '';
    }

    return {
        get id() { return id; },
        get health() { return player?.health ?? 'starting'; },
        get relay() { return onRelay; },

        watch(next) {
            reset();
            id = next;
            const sid = next;
            player = createLivePlayer(video, {
                onHealth: o.onHealth,
                onAudio: o.onAudio,
                onNeedInit: () => {
                    if (join) join.requestKeyframe();
                    else if (!o.relayOnly) void o.send?.(MediaCb.resync, { id: sid });
                },
            });
            if (o.relayOnly) void joinRelay(sid);
        },

        handle(action, data) {
            if (action === MediaMsg.transport) {
                const p = data as TransportPayload | undefined;
                if (!p || p.id !== id) return true;
                if (p.relay && !onRelay) void joinRelay(p.id);
                else if (!p.relay && onRelay) { leaveRelay('host_left_relay'); o.onTransport?.(false); }
                return true;
            }
            if (action === MediaMsg.feed) {
                const p = data as FeedPayload | undefined;
                if (!p || p.id !== id || !player || typeof p.chunk !== 'string') return true;
                if (onRelay) return true;
                player.feed(base64ToBytes(p.chunk), p.init === true, p.mime ?? null);
                return true;
            }
            if (action === MediaMsg.ended) {
                const p = data as EndedPayload | undefined;
                if (!p || p.id !== id) return true;
                leaveRelay('ended');
                player?.markEnded();
                o.onEnded?.(p.reason ?? 'ended');
                return true;
            }
            return false;
        },

        destroy() {
            reset();
            id = null;
        },
    };
}
