export const SDMR_HEADER_BYTES = 24;
const SDMR_MAGIC = 0xa7;
const SDMR_VERSION = 0x01;
export const SDMR_SUBPROTOCOL = 'sdphone-media-v1';

export const FRAME_INIT = 0x01;
export const FRAME_KEY = 0x02;
export const FRAME_DELTA = 0x03;

export const FLAG_NONE = 0x00;
export const FLAG_REPLAY = 0x01;
export const FLAG_DISCONTINUITY = 0x02;

const CONNECT_TIMEOUT_MS = 4000;
const OP_TIMEOUT_MS = 3000;
const PING_MS = 10_000;
const MAX_MESSAGE_BYTES = 1_048_576;

export interface RelayGrant {
    url: string;
    token: string;
    key: string;
    role: 'session' | 'publish' | 'watch';
    gen: number;
    ttlSeconds: number;
    expiresAt: number;
}

export interface RelayDesc {
    mode: 'video';
    wire: 'mse';
    codec: string;
    mime: string;
    width: number;
    height: number;
    fps: number;
    bitrate: number;
}

export interface RelayFrame {
    kind: number;
    flags: number;
    gen: number;
    seq: number;
    payload: Uint8Array<ArrayBuffer>;
}

export interface PublishHandle {
    readonly sid: number;
    readonly gen: number;

    send(kind: number, flags: number, payload: Uint8Array): boolean;
    close(): void;
}

export interface JoinHandle {
    readonly sid: number;
    requestKeyframe(): void;
    close(): void;
}

export interface PublishOptions {
    grant: RelayGrant;
    desc: RelayDesc;
    onKeyframeRequest?: (reason: string) => void;
    onState?: (state: string, reason: string) => void;
    onError?: (code: string, fatal: boolean) => void;
}

export interface JoinOptions {
    grant: RelayGrant;
    onFrame: (frame: RelayFrame) => void;
    onDesc?: (mime: string, gen: number) => void;
    onState?: (state: string, reason: string, mime: string) => void;
    onError?: (code: string, fatal: boolean) => void;
}

interface ControlMessage {
    t?: string;
    sid?: number;
    key?: string;
    gen?: number;
    code?: string;
    reason?: string;
    fatal?: boolean;
    state?: string;
    mime?: string;
    ts?: number;
}

interface StreamRec {
    sid: number;
    key: string;
    role: 'pub' | 'view';
    seq: number;
    onFrame?: (f: RelayFrame) => void;
    onDesc?: (mime: string, gen: number) => void;
    onState?: (state: string, reason: string, mime: string) => void;
    onKeyframeRequest?: (reason: string) => void;
    onError?: (code: string, fatal: boolean) => void;
}

interface Pending {
    role: 'pub' | 'view';
    key: string;
    rec: StreamRec;
    settle: (sid: number | null, msg: ControlMessage | null) => void;
}

export function relayUrlUsable(url: string): boolean {
    if (!url) return false;
    if (url.startsWith('wss://')) return true;
    if (!url.startsWith('ws://')) return false;
    const host = (url.slice(5).split('/')[0].split('@').pop() ?? '').replace(/:\d+$/, '');
    return host === 'localhost' || host === '127.0.0.1' || host === '[::1]';
}

function encodeFrame(kind: number, flags: number, sid: number, gen: number, seq: number, payload: Uint8Array): Uint8Array {
    const out = new Uint8Array(SDMR_HEADER_BYTES + payload.byteLength);
    const dv = new DataView(out.buffer);
    dv.setUint8(0, SDMR_MAGIC);
    dv.setUint8(1, SDMR_VERSION);
    dv.setUint8(2, kind & 0xff);
    dv.setUint8(3, flags & 0xff);
    dv.setUint32(4, sid >>> 0);
    dv.setUint32(8, gen >>> 0);
    dv.setUint32(12, seq >>> 0);
    dv.setBigUint64(16, BigInt(Math.max(0, Math.floor(performance.now() * 1000))));
    out.set(payload, SDMR_HEADER_BYTES);
    return out;
}

function decodeFrame(data: ArrayBuffer): { sid: number; frame: RelayFrame } | null {
    if (data.byteLength < SDMR_HEADER_BYTES) return null;
    const dv = new DataView(data);
    if (dv.getUint8(0) !== SDMR_MAGIC || dv.getUint8(1) !== SDMR_VERSION) return null;
    const kind = dv.getUint8(2);

    const payload = new Uint8Array(new ArrayBuffer(data.byteLength - SDMR_HEADER_BYTES));
    payload.set(new Uint8Array(data, SDMR_HEADER_BYTES));
    return {
        sid: dv.getUint32(4),
        frame: { kind, flags: dv.getUint8(3), gen: dv.getUint32(8), seq: dv.getUint32(12), payload },
    };
}

export class RelayClient {
    private ws: WebSocket | null = null;
    private open = false;
    private closed = false;
    private streams = new Map<number, StreamRec>();
    private pending: Pending[] = [];
    private pingTimer = 0;
    private onClosed: ((reason: string) => void) | null = null;

    constructor(private readonly url: string, private readonly sessionToken: string) {}

    connect(onClosed?: (reason: string) => void): Promise<boolean> {
        this.onClosed = onClosed ?? null;
        return new Promise<boolean>((resolve) => {
            let done = false;
            const finish = (ok: boolean) => { if (!done) { done = true; resolve(ok); } };
            let ws: WebSocket;
            try {
                ws = new WebSocket(this.url, SDMR_SUBPROTOCOL);
            } catch {
                finish(false);
                return;
            }
            ws.binaryType = 'arraybuffer';
            this.ws = ws;
            const timer = window.setTimeout(() => { if (!this.open) { this.close('connect_timeout'); finish(false); } }, CONNECT_TIMEOUT_MS);
            ws.onopen = () => {
                this.sendJson({ t: 'hello', v: 1, token: this.sessionToken, app: 'cuxial', device: 'nui', build: '1' });
            };
            ws.onmessage = (ev: MessageEvent) => {
                if (this.ws !== ws) return;
                if (typeof ev.data === 'string') {
                    const msg = this.parse(ev.data);
                    if (!msg) return;
                    if (msg.t === 'welcome') {
                        window.clearTimeout(timer);
                        this.open = true;
                        this.startPing();
                        finish(true);
                        return;
                    }
                    this.onControl(msg);
                } else if (ev.data instanceof ArrayBuffer) {
                    this.onBinary(ev.data);
                }
            };
            ws.onerror = () => {  };
            ws.onclose = (ev: CloseEvent) => {
                if (this.ws !== ws) return;
                window.clearTimeout(timer);
                const wasOpen = this.open;
                this.teardown(`close_${ev.code}`);
                if (!wasOpen) finish(false);
            };
        });
    }

    get isOpen(): boolean {
        return this.open && !this.closed && this.ws !== null && this.ws.readyState === WebSocket.OPEN;
    }

    publish(o: PublishOptions): Promise<PublishHandle | null> {
        const rec: StreamRec = { sid: 0, key: o.grant.key, role: 'pub', seq: 0, onKeyframeRequest: o.onKeyframeRequest, onState: o.onState, onError: o.onError };
        const d = o.desc;
        return this.request(rec, {
            t: 'publish', token: o.grant.token, key: o.grant.key, gen: o.grant.gen,
            mode: d.mode, wire: d.wire, codec: d.codec, mime: d.mime,
            width: Math.max(0, Math.floor(d.width)), height: Math.max(0, Math.floor(d.height)), fps: Math.max(0, Math.floor(d.fps)),
            bitrate: Math.max(1, Math.min(12_000_000, Math.floor(d.bitrate))),
        }).then((sid) => {
            if (sid === null) return null;
            const gen = o.grant.gen;
            return {
                sid,
                gen,
                send: (kind, flags, payload) => {
                    if (!this.isOpen || !this.streams.has(sid)) return false;
                    if (payload.byteLength + SDMR_HEADER_BYTES > MAX_MESSAGE_BYTES) return false;
                    rec.seq += 1;
                    try { this.ws!.send(encodeFrame(kind, flags, sid, gen, rec.seq, payload)); } catch { return false; }
                    return true;
                },
                close: () => {
                    if (this.streams.delete(sid)) this.sendJson({ t: 'unpublish', sid });
                },
            };
        });
    }

    join(o: JoinOptions): Promise<JoinHandle | null> {
        const rec: StreamRec = { sid: 0, key: o.grant.key, role: 'view', seq: 0, onFrame: o.onFrame, onDesc: o.onDesc, onState: o.onState, onError: o.onError };
        return this.request(rec, { t: 'join', token: o.grant.token, key: o.grant.key }).then((sid) => {
            if (sid === null) return null;
            return {
                sid,
                requestKeyframe: () => { this.sendJson({ t: 'keyframe', sid }); },
                close: () => {
                    if (this.streams.delete(sid)) this.sendJson({ t: 'leave', sid });
                },
            };
        });
    }

    close(reason = 'closing'): void {
        if (this.closed) return;
        const ws = this.ws;
        if (ws && ws.readyState === WebSocket.OPEN) {
            try { ws.send(JSON.stringify({ t: 'bye', reason })); } catch {  }
            try { ws.close(1000, reason); } catch {  }
        }
        this.teardown(reason);
    }

    private request(rec: StreamRec, control: Record<string, unknown>): Promise<number | null> {
        if (!this.isOpen) return Promise.resolve(null);
        return new Promise<number | null>((resolve) => {
            let settled = false;
            const timer = window.setTimeout(() => settle(null, null), OP_TIMEOUT_MS);
            const settle = (sid: number | null, msg: ControlMessage | null) => {
                if (settled) return;
                settled = true;
                window.clearTimeout(timer);
                this.pending = this.pending.filter(p => p.rec !== rec);
                if (sid !== null) {
                    rec.sid = sid;
                    this.streams.set(sid, rec);
                    if (msg && typeof msg.mime === 'string') rec.onDesc?.(msg.mime, msg.gen ?? 0);
                }
                resolve(sid);
            };
            this.pending.push({ role: rec.role, key: rec.key, rec, settle });
            if (!this.sendJson(control)) settle(null, null);
        });
    }

    private takePending(role: 'pub' | 'view', key: string | undefined): Pending | null {
        const i = this.pending.findIndex(p => p.role === role && p.key === key);
        if (i < 0) return null;
        return this.pending[i];
    }

    private onControl(msg: ControlMessage): void {
        switch (msg.t) {
            case 'ready': {
                const op = this.takePending('pub', msg.key);
                if (op && typeof msg.sid === 'number') op.settle(msg.sid, msg); else if (typeof msg.sid === 'number') this.sendJson({ t: 'unpublish', sid: msg.sid });
                return;
            }
            case 'joined': {
                const op = this.takePending('view', msg.key);
                if (op && typeof msg.sid === 'number') op.settle(msg.sid, msg); else if (typeof msg.sid === 'number') this.sendJson({ t: 'leave', sid: msg.sid });
                return;
            }
            case 'stream': {
                const rec = typeof msg.sid === 'number' ? this.streams.get(msg.sid) : undefined;
                if (!rec) return;
                const mime = typeof msg.mime === 'string' ? msg.mime : '';
                if (mime && rec.role === 'view') rec.onDesc?.(mime, msg.gen ?? 0);
                rec.onState?.(msg.state ?? '', msg.reason ?? '', mime);
                if (msg.state === 'ended') this.streams.delete(msg.sid!);
                return;
            }
            case 'keyframe': {
                const rec = typeof msg.sid === 'number' ? this.streams.get(msg.sid) : undefined;
                rec?.onKeyframeRequest?.(msg.reason ?? 'viewer_request');
                return;
            }
            case 'error': {
                const code = String(msg.code ?? 'error');
                const fatal = msg.fatal === true;
                if (typeof msg.sid === 'number') {
                    const rec = this.streams.get(msg.sid);
                    rec?.onError?.(code, fatal);
                    if (fatal) this.streams.delete(msg.sid);
                } else {
                    for (const p of [...this.pending]) p.settle(null, null);
                    for (const rec of this.streams.values()) rec.onError?.(code, fatal);
                }
                if (fatal) console.warn('[bridgeMedia] relay:', code, msg.reason ?? '');
                return;
            }
            case 'bye':
                return;
            default:
                return;
        }
    }

    private onBinary(data: ArrayBuffer): void {
        const decoded = decodeFrame(data);
        if (!decoded) return;
        const rec = this.streams.get(decoded.sid);
        if (!rec || rec.role !== 'view') return;
        rec.onFrame?.(decoded.frame);
    }

    private parse(raw: string): ControlMessage | null {
        try {
            const msg = JSON.parse(raw) as ControlMessage;
            return msg && typeof msg === 'object' && typeof msg.t === 'string' ? msg : null;
        } catch {
            return null;
        }
    }

    private sendJson(message: Record<string, unknown>): boolean {
        const ws = this.ws;
        if (!ws || ws.readyState !== WebSocket.OPEN) return false;
        try { ws.send(JSON.stringify(message)); } catch { return false; }
        return true;
    }

    private startPing(): void {
        this.stopPing();
        this.pingTimer = window.setInterval(() => { this.sendJson({ t: 'ping', ts: Date.now() }); }, PING_MS);
    }

    private stopPing(): void {
        if (this.pingTimer) { window.clearInterval(this.pingTimer); this.pingTimer = 0; }
    }

    private teardown(reason: string): void {
        if (this.closed) return;
        this.closed = true;
        this.open = false;
        this.stopPing();
        for (const p of [...this.pending]) p.settle(null, null);
        this.pending = [];
        for (const rec of this.streams.values()) rec.onState?.('ended', reason, '');
        this.streams.clear();
        this.ws = null;
        this.onClosed?.(reason);
        this.onClosed = null;
    }
}
