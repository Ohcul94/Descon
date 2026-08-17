// bugReportManager.js (v1.0) - Almacenamiento y validación de reportes de bugs
// Todos los campos de texto se tratan como TEXTO PLANO: se eliminan caracteres
// de control y nunca se interpretan como código/HTML.
const fs = require('fs-extra');
const path = require('path');

const DATA_DIR = path.join(__dirname, '..', 'data');
const REPORTS_FILE = path.join(DATA_DIR, 'bugReports.json');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_DESC_CHARS = 1000;
const MAX_IMAGES = 2;
const MAX_IMAGE_BYTES = 3 * 1024 * 1024; // 3 MB por imagen
const ALLOWED_MIMES = new Set(['image/png', 'image/jpeg', 'image/webp']);

let reports = [];
let nextId = 1;
let loaded = false;

function init() {
    if (loaded) return;
    loaded = true;
    try {
        if (fs.existsSync(REPORTS_FILE)) {
            const raw = fs.readJsonSync(REPORTS_FILE);
            if (Array.isArray(raw)) {
                reports = raw;
                nextId = reports.reduce((m, r) => Math.max(m, Number(r.id) || 0), 0) + 1;
            }
        }
    } catch (e) {
        console.error('[BUG-REPORT] Error cargando reportes:', e.message);
    }
}

function save() {
    try {
        fs.ensureDirSync(DATA_DIR);
        fs.writeJsonSync(REPORTS_FILE, reports, { spaces: 2 });
    } catch (e) {
        console.error('[BUG-REPORT] Error guardando reportes:', e.message);
    }
}

function sanitizeText(raw, maxLen = 1000) {
    if (typeof raw !== 'string') return '';
    let out = '';
    for (const ch of raw) {
        const code = ch.codePointAt(0);
        if (code < 32 && code !== 10) continue; // Elimina control chars, conserva saltos de línea
        out += ch;
    }
    return out.trim().substring(0, maxLen);
}

function isValidEmail(email) {
    return typeof email === 'string' && EMAIL_RE.test(email) && email.length <= 200;
}

function validateImages(images) {
    if (images === undefined || images === null) return { ok: true, images: [] };
    if (!Array.isArray(images)) return { ok: false, error: 'REPORTE RECHAZADO: IMÁGENES INVÁLIDAS.' };
    if (images.length > MAX_IMAGES) return { ok: false, error: 'REPORTE RECHAZADO: MÁXIMO ' + MAX_IMAGES + ' IMÁGENES.' };

    const clean = [];
    for (const img of images) {
        if (!img || typeof img !== 'object') return { ok: false, error: 'REPORTE RECHAZADO: IMAGEN INVÁLIDA.' };
        const mime = typeof img.mime === 'string' ? img.mime.toLowerCase() : '';
        const data = typeof img.data === 'string' ? img.data : '';
        if (!ALLOWED_MIMES.has(mime)) return { ok: false, error: 'REPORTE RECHAZADO: FORMATO DE IMAGEN NO SOPORTADO.' };
        if (!data || data.length < 32) return { ok: false, error: 'REPORTE RECHAZADO: IMAGEN VACÍA O CORRUPTO.' };
        // Verificación de tamaño decodificado (aprox) contra el máximo permitido
        if (data.length > (MAX_IMAGE_BYTES * 4) / 3 + 64) {
            return { ok: false, error: 'REPORTE RECHAZADO: IMAGEN SUPERIOR A 3 MB.' };
        }
        const name = sanitizeText(String(img.name || 'imagen'), 80) || 'imagen';
        clean.push({ name, mime, data });
    }
    return { ok: true, images: clean };
}

function addReport({ nick, email, phone, description, images, zone, level, ip }) {
    init();
    const report = {
        id: nextId++,
        nick: sanitizeText(String(nick || 'Desconocido'), 40),
        email: sanitizeText(String(email || ''), 200),
        phone: sanitizeText(String(phone || ''), 40),
        description: sanitizeText(String(description || ''), MAX_DESC_CHARS),
        images: images || [],
        zone: Number(zone) || 1,
        level: Number(level) || 1,
        ip: sanitizeText(String(ip || ''), 60),
        status: 'open',
        createdAt: new Date().toISOString()
    };
    reports.unshift(report);
    save();
    return report;
}

function getAll() {
    init();
    return reports;
}

function removeReport(id) {
    init();
    const numId = Number(id);
    const before = reports.length;
    reports = reports.filter(r => Number(r.id) !== numId);
    if (reports.length !== before) save();
    return reports;
}

function setStatus(id, status) {
    init();
    const numId = Number(id);
    const report = reports.find(r => Number(r.id) === numId);
    if (!report) return false;
    report.status = status === 'resolved' ? 'resolved' : 'open';
    save();
    return true;
}

module.exports = { init, sanitizeText, isValidEmail, validateImages, addReport, getAll, removeReport, setStatus };