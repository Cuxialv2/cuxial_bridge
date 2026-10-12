import { createGameRender, type GameRender } from './gameRender';

export interface LiveEncoderSettings {
    width: number;
    bitrate: number;
    fps: number;
    timesliceMs: number;
    keyframeMs: number;

    codec: 'vp9' | 'vp8';
}

export interface LiveEncoderOptions {
    enc: Partial<LiveEncoderSettings>;

    onChunk: (blob: Blob, init: boolean, key: boolean, mime: string) => void;

    onFail: (reason: string) => void;
}

export interface LiveEncoder {
    enableMic(): Promise<boolean>;
    disableMic(): void;

    anchor(): void;

    setQuality(q: { width?: number; fps?: number; bitrate?: number }): void;
    readonly micOpen: boolean;
    stop(): void;
}

const DEFAULTS: LiveEncoderSettings = { width: 1280, bitrate: 4_000_000, fps: 24, timesliceMs: 250, keyframeMs: 10000, codec: 'vp9' };
const MIN_ANCHOR_MS = 1000;

export function pickLiveMime(withAudio: boolean, codec: 'vp9' | 'vp8' = 'vp9'): string {
    const MR = (window as any).MediaRecorder as typeof MediaRecorder | undefined;
    if (!MR || typeof MR.isTypeSupported !== 'function') return '';
    const order = codec === 'vp8' ? ['vp8', 'vp9'] : ['vp9', 'vp8'];
    const candidates = withAudio
        ? [...order.map(c => `video/webm;codecs="${c},opus"`), 'video/webm']
        : [...order.map(c => `video/webm;codecs=${c}`), 'video/webm'];
    for (const c of candidates) if (MR.isTypeSupported(c)) return c;
    return '';
}

export function liveEncodingSupported(): boolean {
    return typeof HTMLCanvasElement !== 'undefined'
        && typeof HTMLCanvasElement.prototype.captureStream === 'function'
        && !!(window as any).MediaRecorder
        && pickLiveMime(false) !== '';
}

export function createLiveEncoder(options: LiveEncoderOptions): LiveEncoder {
    const enc: LiveEncoderSettings = { ...DEFAULTS, ...options.enc };

    let render: GameRender;
    const source = document.createElement('canvas');
    source.style.display = 'none';
    document.body.append(source);
    try {
        render = createGameRender();
        render.setTargetFps(enc.fps);
        render.renderToTarget(source);
    } catch (err) {
        source.remove();
        options.onFail(err instanceof Error ? err.message : String(err));
        return { enableMic: async () => false, disableMic() {}, anchor() {}, setQuality() {}, micOpen: false, stop() {} };
    }

    const aspect = window.innerWidth > 0 && window.innerHeight > 0 ? window.innerHeight / window.innerWidth : 9 / 16;
    let pump: ReturnType<typeof setInterval> | null = null;
    let videoStream: MediaStream | null = null;

    function dropOutput() {
        if (pump !== null) { clearInterval(pump); pump = null; }
        try { videoStream?.getTracks().forEach(t => t.stop()); } catch {  }
        videoStream = null;
    }

    function buildOutput(): boolean {
        dropOutput();
        const outW = Math.max(160, Math.round(enc.width));
        const outH = Math.max(90, Math.round(outW * aspect));
        const canvas = document.createElement('canvas');
        canvas.width = outW;
        canvas.height = outH;
        const octx = canvas.getContext('2d');
        if (!octx) return false;
        const src = source;
        pump = setInterval(() => {
            if (src.width && src.height) octx.drawImage(src, 0, 0, outW, outH);
        }, Math.max(1, Math.round(1000 / enc.fps)));

        try {
            videoStream = canvas.captureStream(enc.fps);
        } catch {
            dropOutput();
            return false;
        }
        render.setTargetFps(enc.fps);
        return true;
    }

    if (!buildOutput()) {
        render.stop();
        source.remove();
        options.onFail('captureStream');
        return { enableMic: async () => false, disableMic() {}, anchor() {}, setQuality() {}, micOpen: false, stop() {} };
    }

    let mic: MediaStream | null = null;
    let recorder: MediaRecorder | null = null;
    let stopped = false;
    let mime = '';
    let seq = 0;

    function composeStream(): MediaStream {
        const tracks: MediaStreamTrack[] = [...(videoStream?.getVideoTracks() ?? [])];
        if (mic) tracks.push(...mic.getAudioTracks());
        return new MediaStream(tracks);
    }

    function spin() {
        if (stopped) return;
        mime = pickLiveMime(mic !== null, enc.codec) || pickLiveMime(false, enc.codec);
        let rec: MediaRecorder;
        try {
            rec = new MediaRecorder(composeStream(), { ...(mime ? { mimeType: mime } : {}), videoBitsPerSecond: enc.bitrate, audioBitsPerSecond: 48_000 });
        } catch {
            try {
                rec = new MediaRecorder(composeStream());
                mime = rec.mimeType || mime;
            } catch (err) {
                options.onFail(err instanceof Error ? err.message : 'MediaRecorder');
                return;
            }
        }
        seq = 0;
        const mine = rec;
        rec.ondataavailable = (event) => {
            if (mine !== recorder || stopped || !event.data || !event.data.size) return;
            const init = seq === 0;
            const key = seq === 1;
            seq += 1;
            options.onChunk(event.data, init, key, mime);
        };
        rec.onerror = () => { if (mine === recorder && !stopped) anchor(); };
        rec.start(enc.timesliceMs);
        recorder = rec;
    }

    function anchor() {
        const old = recorder;
        recorder = null;
        if (old && old.state !== 'inactive') {
            try { old.ondataavailable = null; old.stop(); } catch {  }
        }
        spin();
    }

    const beat = setInterval(anchor, Math.max(MIN_ANCHOR_MS, enc.keyframeMs));
    spin();

    return {
        get micOpen() { return mic !== null; },

        anchor() { if (!stopped) anchor(); },

        setQuality(q) {
            if (stopped) return;
            const width = Math.round(q.width ?? enc.width);
            const fps = Math.round(q.fps ?? enc.fps);
            const bitrate = Math.round(q.bitrate ?? enc.bitrate);
            const sizeChanged = width !== enc.width || fps !== enc.fps;
            if (!sizeChanged && bitrate === enc.bitrate) return;
            enc.width = width;
            enc.fps = fps;
            enc.bitrate = bitrate;
            if (sizeChanged && !buildOutput()) { options.onFail('captureStream'); return; }
            anchor();
        },

        async enableMic() {
            if (stopped) return false;
            if (mic) return true;
            try {
                mic = await navigator.mediaDevices.getUserMedia({
                    audio: { autoGainControl: false, echoCancellation: false, noiseSuppression: false },
                });
            } catch {
                mic = null;
                return false;
            }
            if (stopped) { mic.getTracks().forEach(t => t.stop()); mic = null; return false; }
            anchor();
            return true;
        },

        disableMic() {
            if (!mic) return;
            mic.getTracks().forEach(t => t.stop());
            mic = null;
            if (!stopped) anchor();
        },

        stop() {
            if (stopped) return;
            stopped = true;
            clearInterval(beat);
            const old = recorder;
            recorder = null;
            if (old && old.state !== 'inactive') {
                try { old.ondataavailable = null; old.stop(); } catch {  }
            }
            dropOutput();
            render.stop();
            source.remove();
            mic?.getTracks().forEach(t => t.stop());
            mic = null;
        },
    };
}
