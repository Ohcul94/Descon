const getAdminUsernames = () => {
    const adminEnv = process.env.ADMIN_USERNAMES || 'caelli94';
    return adminEnv.split(',').map(name => name.trim().toLowerCase());
};

const isAdmin = (username) => {
    if (!username) return false;
    return getAdminUsernames().includes(username.toLowerCase());
};

const isAdminSocket = (socket) => {
    if (!socket) return false;
    if (socket.dbUser && socket.dbUser.username) {
        return isAdmin(socket.dbUser.username);
    }
    return false;
};

// --- CONTROL DE LOGIN FALLIDOS (ANTI-FUERZA BRUTA) ---
const loginFailures = new Map(); // IP -> { count, lockUntil }

const checkLoginLock = (ip) => {
    if (!ip) return { locked: false };
    const record = loginFailures.get(ip);
    if (record && record.lockUntil > Date.now()) {
        return { locked: true, remaining: Math.ceil((record.lockUntil - Date.now()) / 1000) };
    }
    return { locked: false };
};

const registerLoginFailure = (ip) => {
    if (!ip) return;
    const record = loginFailures.get(ip) || { count: 0, lockUntil: 0 };
    record.count++;
    if (record.count >= 5) {
        record.lockUntil = Date.now() + 15 * 60 * 1000; // Bloqueo de 15 minutos
    }
    loginFailures.set(ip, record);
};

const registerLoginSuccess = (ip) => {
    if (!ip) return;
    loginFailures.delete(ip);
};

module.exports = {
    getAdminUsernames,
    isAdmin,
    isAdminSocket,
    checkLoginLock,
    registerLoginFailure,
    registerLoginSuccess
};
