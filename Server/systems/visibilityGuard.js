/**
 * visibilityGuard.js
 * Control de visibilidad de ítems "ojito" (flag hidden).
 * Igual mecánica que las naves (shipModels.hidden), aplicada a municiones, armas,
 * escudos y motores. Todo lo marcado como hidden queda inaccesible para los jugadores:
 * no se muestra en tienda, bodega, inventario ni equipado, y el servidor bloquea
 * compra, equipamiento y disparo incluso si un cliente hackeado lo intenta.
 */

function isItemConfigHidden(config, category, itemId) {
    if (!config || !config.shopItems) return false;
    const cat = String(category).toLowerCase();
    const id = String(itemId);
    const shop = config.shopItems;

    if (cat === 'ammo') {
        const ammo = shop.ammo || {};
        for (const type of Object.keys(ammo)) {
            const list = Array.isArray(ammo[type]) ? ammo[type] : [];
            const found = list.find(i => i && String(i.id) === id);
            if (found) return !!found.hidden;
        }
        return false;
    }

    if (cat === 'ships' || cat === 'ship') {
        const list = Array.isArray(config.shipModels) ? config.shipModels : [];
        const found = list.find(i => i && String(i.id) === id);
        return !!(found && found.hidden);
    }

    if (cat === 'weapons' || cat === 'shields' || cat === 'engines' || cat === 'extra') {
        const list = Array.isArray(shop[cat]) ? shop[cat] : [];
        const found = list.find(i => i && String(i.id) === id);
        return !!(found && found.hidden);
    }

    return false;
}

function isAmmoTierHidden(config, type, tierIndex) {
    if (!config || !config.shopItems || !config.shopItems.ammo) return false;
    const list = config.shopItems.ammo[type];
    if (!Array.isArray(list)) return false;
    const entry = list[tierIndex];
    return !!(entry && entry.hidden);
}

function sanitizeInventoryForClient(inventory, config) {
    if (!Array.isArray(inventory)) return inventory;
    return inventory.filter(it => {
        if (!it || it.id === undefined || it.id === null) return true;
        return !isItemConfigHidden(config, 'weapons', it.id)
            && !isItemConfigHidden(config, 'shields', it.id)
            && !isItemConfigHidden(config, 'engines', it.id)
            && !isItemConfigHidden(config, 'extra', it.id)
            && !isItemConfigHidden(config, 'ammo', it.id);
    });
}

function sanitizeEquipForClient(equip, config) {
    if (!equip || typeof equip !== 'object') return equip;
    const out = {};
    for (const slot of ['w', 's', 'e', 'x']) {
        const list = equip[slot];
        out[slot] = Array.isArray(list) ? sanitizeInventoryForClient(list, config) : list;
    }
    return out;
}

function sanitizeAmmoForClient(ammoMap, config) {
    if (!ammoMap || typeof ammoMap !== 'object') return ammoMap;
    const out = {};
    for (const type of Object.keys(ammoMap)) {
        const list = ammoMap[type];
        if (!Array.isArray(list)) { out[type] = list; continue; }
        out[type] = list.map((count, idx) => isAmmoTierHidden(config, type, idx) ? 0 : count);
    }
    return out;
}

function sanitizeGameDataForClient(gameData, config) {
    if (!gameData || typeof gameData !== 'object') return gameData;
    const copy = JSON.parse(JSON.stringify(gameData));
    if (Array.isArray(copy.inventory)) copy.inventory = sanitizeInventoryForClient(copy.inventory, config);
    if (copy.equipped && typeof copy.equipped === 'object') copy.equipped = sanitizeEquipForClient(copy.equipped, config);
    if (copy.equippedByShip) {
        if (copy.equippedByShip instanceof Map) {
            const mapped = {};
            copy.equippedByShip.forEach((v, k) => { mapped[k] = sanitizeEquipForClient(v, config); });
            copy.equippedByShip = mapped;
        } else if (typeof copy.equippedByShip === 'object') {
            const mapped = {};
            for (const k of Object.keys(copy.equippedByShip)) {
                mapped[k] = sanitizeEquipForClient(copy.equippedByShip[k], config);
            }
            copy.equippedByShip = mapped;
        }
    }
    if (copy.ammo && typeof copy.ammo === 'object') copy.ammo = sanitizeAmmoForClient(copy.ammo, config);
    return copy;
}

module.exports = {
    isItemConfigHidden,
    isAmmoTierHidden,
    sanitizeInventoryForClient,
    sanitizeEquipForClient,
    sanitizeAmmoForClient,
    sanitizeGameDataForClient
};