const VERTEX_SHADER =  `
attribute vec2 a_position;
attribute vec2 a_texCoord;
varying vec2 v_texCoord;
void main() {
  // readPixels devuelve las filas de abajo arriba: se invierte aquí para que
  // el ImageData salga derecho, igual que hace el shader del teléfono.
  v_texCoord = vec2(a_texCoord.x, 1.0 - a_texCoord.y);
  gl_Position = vec4(a_position, 0.0, 1.0);
}`;

const FRAGMENT_SHADER =  `
precision mediump float;
varying vec2 v_texCoord;
uniform sampler2D u_texture;
void main() {
  gl_FragColor = texture2D(u_texture, v_texCoord);
}`;

const MIN_FPS = 1;
const MAX_FPS = 60;

export interface GameRender {
    renderToTarget(canvas: HTMLCanvasElement): void;
    setTargetFps(fps: number): void;
    framesRendered(): number;

    stop(): void;
}

function compileShader(gl: WebGLRenderingContext, type: number, source: string): WebGLShader {
    const shader = gl.createShader(type);
    if (!shader) throw new Error('createShader failed');
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(shader) ?? '(no log)';
        gl.deleteShader(shader);
        throw new Error(`Shader compile failed: ${log}`);
    }
    return shader;
}

function linkProgram(gl: WebGLRenderingContext, vs: WebGLShader, fs: WebGLShader): WebGLProgram {
    const program = gl.createProgram();
    if (!program) throw new Error('createProgram failed');
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        const log = gl.getProgramInfoLog(program) ?? '(no log)';
        gl.deleteProgram(program);
        throw new Error(`Program link failed: ${log}`);
    }
    return program;
}

export function createGameRender(): GameRender {
    const glCanvas = document.createElement('canvas');
    glCanvas.style.display = 'none';
    document.body.append(glCanvas);

    const gl = glCanvas.getContext('webgl', {
        alpha: false,
        antialias: false,
        depth: false,
        premultipliedAlpha: false,
        preserveDrawingBuffer: false,
    });
    if (!gl) {
        glCanvas.remove();
        throw new Error('WEBGL_NOT_SUPPORTED');
    }

    const vs = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
    const fs = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
    const program = linkProgram(gl, vs, fs);
    gl.useProgram(program);

    const positions = new Float32Array([-1, -1, 1, -1, -1, 1, 1, -1, 1, 1, -1, 1]);
    const texCoords = new Float32Array([0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1]);

    const posBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, posBuf);
    gl.bufferData(gl.ARRAY_BUFFER, positions, gl.STATIC_DRAW);
    const aPos = gl.getAttribLocation(program, 'a_position');
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

    const tcBuf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, tcBuf);
    gl.bufferData(gl.ARRAY_BUFFER, texCoords, gl.STATIC_DRAW);
    const aTc = gl.getAttribLocation(program, 'a_texCoord');
    gl.enableVertexAttribArray(aTc);
    gl.vertexAttribPointer(aTc, 2, gl.FLOAT, false, 0, 0);

    let width = 0;
    let height = 0;
    let gameTex: WebGLTexture | null = null;
    let fbo: WebGLFramebuffer | null = null;
    let fboTex: WebGLTexture | null = null;

    function buildGameTexture(w: number, h: number) {
        if (gameTex) gl!.deleteTexture(gameTex);
        const tex = gl!.createTexture();
        gl!.activeTexture(gl!.TEXTURE0);
        gl!.bindTexture(gl!.TEXTURE_2D, tex);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MIN_FILTER, gl!.NEAREST);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MAG_FILTER, gl!.NEAREST);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_S, gl!.CLAMP_TO_EDGE);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.CLAMP_TO_EDGE);
        gl!.pixelStorei(gl!.UNPACK_ALIGNMENT, 1);

        gl!.texImage2D(gl!.TEXTURE_2D, 0, gl!.RGB, 1, 1, 0, gl!.RGB, gl!.UNSIGNED_BYTE, new Uint8Array([0, 0, 0]));
        gl!.texImage2D(gl!.TEXTURE_2D, 0, gl!.RGB, w, h, 0, gl!.RGB, gl!.UNSIGNED_BYTE, new Uint8Array(w * h * 3));

        gl!.texParameterf(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.CLAMP_TO_EDGE);
        gl!.texParameterf(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.MIRRORED_REPEAT);
        gl!.texParameterf(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.REPEAT);
        gameTex = tex;
    }

    function buildTarget(w: number, h: number) {
        if (fbo) gl!.deleteFramebuffer(fbo);
        if (fboTex) gl!.deleteTexture(fboTex);
        fboTex = gl!.createTexture();
        gl!.activeTexture(gl!.TEXTURE1);
        gl!.bindTexture(gl!.TEXTURE_2D, fboTex);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MIN_FILTER, gl!.LINEAR);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_MAG_FILTER, gl!.NEAREST);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_S, gl!.CLAMP_TO_EDGE);
        gl!.texParameteri(gl!.TEXTURE_2D, gl!.TEXTURE_WRAP_T, gl!.CLAMP_TO_EDGE);
        gl!.texImage2D(gl!.TEXTURE_2D, 0, gl!.RGBA, w, h, 0, gl!.RGBA, gl!.UNSIGNED_BYTE, null);
        fbo = gl!.createFramebuffer();
        gl!.bindFramebuffer(gl!.FRAMEBUFFER, fbo);
        gl!.framebufferTexture2D(gl!.FRAMEBUFFER, gl!.COLOR_ATTACHMENT0, gl!.TEXTURE_2D, fboTex, 0);
        gl!.bindFramebuffer(gl!.FRAMEBUFFER, null);
        gl!.activeTexture(gl!.TEXTURE0);
    }

    function rebuild() {
        const w = window.innerWidth;
        const h = window.innerHeight;
        if (w <= 0 || h <= 0) return;
        width = w;
        height = h;
        glCanvas.width = w;
        glCanvas.height = h;
        buildGameTexture(w, h);
        buildTarget(w, h);
        gl!.useProgram(program);
        gl!.activeTexture(gl!.TEXTURE0);
        gl!.bindTexture(gl!.TEXTURE_2D, gameTex);
        gl!.uniform1i(gl!.getUniformLocation(program, 'u_texture'), 0);
    }

    rebuild();

    let target: HTMLCanvasElement | null = null;
    let ctx: CanvasRenderingContext2D | null = null;
    let pixels: Uint8ClampedArray<ArrayBuffer> | null = null;
    let image: ImageData | null = null;
    let bufW = 0;
    let bufH = 0;
    let pump: ReturnType<typeof setInterval> | null = null;
    let pumpMs = Math.round(1000 / 20);
    let frames = 0;
    let stopped = false;

    const onResize = () => { if (!stopped) rebuild(); };
    window.addEventListener('resize', onResize);

    function animate() {
        if (stopped || !target || !gl || !fbo) return;
        const w = width;
        const h = height;
        if (w <= 0 || h <= 0) return;

        if (bufW !== w || bufH !== h || !pixels || !image || !ctx) {
            bufW = w;
            bufH = h;
            const buffer = new ArrayBuffer(w * h * 4);
            pixels = new Uint8ClampedArray(buffer);
            image = new ImageData(pixels, w, h);
            target.width = w;
            target.height = h;
            ctx = target.getContext('2d');
            if (!ctx) return;
        }

        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
        gl.viewport(0, 0, w, h);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, gameTex);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);

        ctx.putImageData(image, 0, 0);
        frames += 1;
    }

    function startPump() {
        if (pump !== null) clearInterval(pump);
        pump = setInterval(animate, pumpMs);
    }

    return {
        renderToTarget(canvas) {
            target = canvas;
            bufW = 0;
            bufH = 0;
            startPump();
        },

        setTargetFps(fps) {
            const want = Math.round(Math.min(MAX_FPS, Math.max(MIN_FPS, fps || MAX_FPS)));
            const ms = Math.max(1, Math.round(1000 / want));
            if (ms === pumpMs) return;
            pumpMs = ms;
            if (pump !== null) startPump();
        },

        framesRendered() { return frames; },

        stop() {
            if (stopped) return;
            stopped = true;
            if (pump !== null) { clearInterval(pump); pump = null; }
            target = null;
            ctx = null;
            window.removeEventListener('resize', onResize);
            if (gameTex) gl!.deleteTexture(gameTex);
            if (fboTex) gl!.deleteTexture(fboTex);
            if (fbo) gl!.deleteFramebuffer(fbo);
            gl!.deleteBuffer(posBuf);
            gl!.deleteBuffer(tcBuf);
            gl!.deleteProgram(program);
            gl!.deleteShader(vs);
            gl!.deleteShader(fs);
            const lose = gl!.getExtension('WEBGL_lose_context');
            if (lose) lose.loseContext();
            glCanvas.remove();
        },
    };
}
