export type LiveHealth = 'starting' | 'live' | 'recovering' | 'ended' | 'failed';

export interface LivePlayerOptions {
    onHealth?: (health: LiveHealth) => void;

    onNeedInit?: () => void;

    onAudio?: (hasAudio: boolean) => void;

    keepSeconds?: number;

    maxLagSeconds?: number;
}

export interface LivePlayer {
    feed(bytes: Uint8Array<ArrayBuffer> | null, init: boolean, mime?: string | null): void;
    markEnded(): void;
    destroy(): void;
    readonly health: LiveHealth;
}

const DEFAULT_MIME = 'video/webm';
const WATCHDOG_MS = 500;
const STALL_MS = 4000;
const REBUILD_MAX = 4;

const B64_JUNK = /[^A-Za-z0-9+/=]/g;

function base64ToBytes(b64: string): Uint8Array<ArrayBuffer> | null {
    let clean = b64;
    const junk = b64.match(B64_JUNK);
    if (junk) {
        clean = b64.replace(B64_JUNK, '');
        console.warn(`[bridgeMedia] trozo con ${junk.length} caracteres no base64 (len ${b64.length}): ${JSON.stringify(junk.slice(0, 8))}`);
    }
    const pad = clean.length % 4;
    if (pad === 1) {
        console.warn(`[bridgeMedia] trozo truncado (len ${clean.length}): ...${clean.slice(-12)}`);
        clean = clean.slice(0, -1);
    } else if (pad > 0) {
        clean += '='.repeat(4 - pad);
    }
    let bin: string;
    try {
        bin = atob(clean);
    } catch (err) {
        console.warn(`[bridgeMedia] trozo indecodificable (len ${b64.length}): ${err instanceof Error ? err.message : String(err)}`);
        return null;
    }
    const out = new Uint8Array(new ArrayBuffer(bin.length));
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
}

export { base64ToBytes };

export function livePlaybackSupported(mime?: string): boolean {
    if (typeof window === 'undefined' || typeof (window as any).MediaSource === 'undefined') return false;
    if (mime && typeof MediaSource.isTypeSupported === 'function') return MediaSource.isTypeSupported(mime);
    return true;
}

export function createLivePlayer(video: HTMLVideoElement, options: LivePlayerOptions = {}): LivePlayer {
    const keep = options.keepSeconds ?? 8;
    const maxLag = options.maxLagSeconds ?? 1.6;

    let ms: MediaSource | null = null;
    let sb: SourceBuffer | null = null;
    let url: string | null = null;
    let mime = DEFAULT_MIME;
    let header: Uint8Array<ArrayBuffer> | null = null;
    let queue: Uint8Array<ArrayBuffer>[] = [];
    let destroyed = false;
    let health: LiveHealth = 'starting';
    let lastProgressAt = 0;
    let lastTime = -1;
    let rebuilds = 0;
    let opened = false;

    let awaitingInit = false;
    let lastNeedInitAt = 0;

    const setHealth = (h: LiveHealth) => {
        if (health === h || destroyed) return;
        health = h;
        options.onHealth?.(h);
    };

    function teardownSource() {
        if (sb && ms) {
            try { sb.abort(); } catch {  }
            try { ms.removeSourceBuffer(sb); } catch {  }
        }
        if (ms && ms.readyState === 'open') { try { ms.endOfStream(); } catch {  } }
        if (url) { URL.revokeObjectURL(url); url = null; }
        sb = null;
        ms = null;
        opened = false;
        try { video.removeAttribute('src'); video.load(); } catch {  }
    }

    function pump() {
        if (destroyed || !sb || !opened || sb.updating || queue.length === 0) return;
        const next = queue.shift()!;
        try {
            sb.appendBuffer(next);
        } catch {
            queue.unshift(next);
            if (!trim(true)) rebuild('append');
        }
    }

    function trim(force = false): boolean {
        if (!sb || sb.updating || !video.buffered.length) return false;
        const start = video.buffered.start(0);
        const cut = video.currentTime - (force ? 1 : keep);
        if (cut - start < 1) return false;
        try { sb.remove(start, cut); return true; } catch { return false; }
    }

    function catchUp() {
        if (!video.buffered.length) return;
        const end = video.buffered.end(video.buffered.length - 1);
        if (end - video.currentTime > maxLag) {
            try { video.currentTime = Math.max(0, end - 0.25); } catch {  }
        }
        if (video.paused) void video.play().catch(() => {});
    }

    function build() {
        teardownSource();
        if (!livePlaybackSupported(mime)) { setHealth('failed'); return; }
        ms = new MediaSource();
        url = URL.createObjectURL(ms);
        const mine = ms;
        ms.addEventListener('sourceopen', () => {
            if (destroyed || mine !== ms) return;
            try {
                sb = mine.addSourceBuffer(mime);
                sb.mode = 'sequence';
            } catch {
                setHealth('failed');
                return;
            }
            sb.addEventListener('updateend', () => {
                if (destroyed) return;
                trim();
                pump();
            });
            sb.addEventListener('error', () => rebuild('sourcebuffer'));
            opened = true;

            if (header) queue.unshift(header);
            pump();
        });
        video.src = url;
        void video.play().catch(() => {});
    }

    function rebuild(reason: string) {
        if (destroyed || !header) return;
        rebuilds += 1;
        if (rebuilds > REBUILD_MAX) { setHealth('failed'); return; }
        setHealth('recovering');

        queue = queue.filter(q => q !== header);
        build();
        void reason;
    }

    const watchdog = setInterval(() => {
        if (destroyed || health === 'ended' || health === 'failed') return;
        const t = video.currentTime;
        const now = performance.now();
        if (t !== lastTime) { lastTime = t; lastProgressAt = now; if (health !== 'live') { setHealth('live'); rebuilds = 0; } }
        else if (lastProgressAt && now - lastProgressAt > STALL_MS && queue.length === 0 && header) {
            lastProgressAt = now;
            rebuild('stall');
        }
        catchUp();
    }, WATCHDOG_MS);

    return {
        get health() { return health; },

        feed(bytes, init, chunkMime) {
            if (destroyed || health === 'ended') return;
            if (!bytes) {
                if (!awaitingInit) {
                    awaitingInit = true;
                    setHealth('recovering');
                }
                const now = performance.now();
                if (now - lastNeedInitAt > 1000) { lastNeedInitAt = now; options.onNeedInit?.(); }
                return;
            }
            if (init) awaitingInit = false;
            else if (awaitingInit) return;
            if (init) {
                const nextMime = chunkMime && chunkMime !== '' ? chunkMime : mime;
                const codecChanged = nextMime !== mime || !ms;
                mime = nextMime;
                header = bytes;
                options.onAudio?.(/opus|audio/i.test(mime));
                if (codecChanged) {
                    queue = [];
                    rebuilds = 0;
                    build();
                    return;
                }
            }
            if (!header) return;
            queue.push(bytes);
            pump();
        },

        markEnded() {
            setHealth('ended');
        },

        destroy() {
            if (destroyed) return;
            destroyed = true;
            clearInterval(watchdog);
            queue = [];
            header = null;
            teardownSource();
        },
    };
}
