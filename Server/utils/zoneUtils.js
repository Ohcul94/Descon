// Server/utils/zoneUtils.js
// v1.0: Normalización y saneamiento centralizado de zonas para consistencia en todo el servidor

const normalizeZone = (z) => {
    if (z === undefined || z === null) return 1;
    if (typeof z === 'string') {
        if (z.startsWith('extract_')) {
            const parts = z.split('_');
            return parseInt(parts[1]) || 10;
        }
        if (z.startsWith('dungeon_') || z.startsWith('dungeon')) {
            return 99;
        }
        if (!isNaN(z) && z.trim() !== '') {
            return Number(z);
        }
        return z;
    }
    return z;
};

const isSameZone = (a, b) => {
    if (!a || !b) return false;
    const za = a.zone !== undefined ? a.zone : a;
    const zb = b.zone !== undefined ? b.zone : b;
    return normalizeZone(za) === normalizeZone(zb);
};

module.exports = {
    normalizeZone,
    isSameZone
};
