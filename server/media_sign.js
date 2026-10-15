const crypto = require('node:crypto');

const PREFIX = 'sdmr1';
const HEX64 = /^[0-9a-f]{64}$/;

function b64url(buf) {
    return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function mediaRelayToken(keyHex, claimsJson) {
    if (typeof keyHex !== 'string' || !HEX64.test(keyHex)) return '';
    if (typeof claimsJson !== 'string' || claimsJson === '') return '';
    try {
        JSON.parse(claimsJson);
    } catch {
        return '';
    }
    const part = b64url(Buffer.from(claimsJson, 'utf8'));
    const mac = crypto.createHmac('sha256', Buffer.from(keyHex, 'hex')).update(Buffer.from(`${PREFIX}.${part}`, 'ascii')).digest();
    const token = `${PREFIX}.${part}.${b64url(mac)}`;
    return token.length <= 1024 ? token : '';
}

function mediaRandomHex(bytes) {
    const n = Math.max(1, Math.min(64, Math.floor(Number(bytes) || 16)));
    return crypto.randomBytes(n).toString('hex');
}

function mediaHmacHex(keyHex, message) {
    if (typeof keyHex !== 'string' || !HEX64.test(keyHex) || typeof message !== 'string') return '';
    return crypto.createHmac('sha256', Buffer.from(keyHex, 'hex')).update(message, 'utf8').digest('hex');
}

const register = typeof exports === 'function' ? exports : global.exports;
register('MediaRelayToken', mediaRelayToken);
register('MediaRandomHex', mediaRandomHex);
register('MediaHmacHex', mediaHmacHex);
