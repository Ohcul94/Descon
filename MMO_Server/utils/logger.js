const colors = {
    reset: "\x1b[0m",
    bright: "\x1b[1m",
    red: "\x1b[31m",
    green: "\x1b[32m",
    yellow: "\x1b[33m",
    blue: "\x1b[34m",
    magenta: "\x1b[35m",
    cyan: "\x1b[36m",
    gray: "\x1b[90m"
};

const levels = {
    ERROR: 0,
    WARN: 1,
    INFO: 2,
    DEBUG: 3
};

// Por defecto usamos INFO si no hay variable de entorno
const LOG_LEVEL = (process.env.LOG_LEVEL || "INFO").toUpperCase();
const currentLevel = levels[LOG_LEVEL] !== undefined ? levels[LOG_LEVEL] : levels.INFO;

const Logger = {
    error: (tag, msg) => {
        if (levels.ERROR <= currentLevel) {
            console.error(`${colors.red}${colors.bright}[ERROR-${tag}]${colors.reset} ${msg}`);
        }
    },
    warn: (tag, msg) => {
        if (levels.WARN <= currentLevel) {
            console.warn(`${colors.yellow}[WARN-${tag}]${colors.reset} ${msg}`);
        }
    },
    info: (tag, msg) => {
        if (levels.INFO <= currentLevel) {
            console.log(`${colors.cyan}[${tag}]${colors.reset} ${msg}`);
        }
    },
    success: (tag, msg) => {
        if (levels.INFO <= currentLevel) {
            console.log(`${colors.green}[${tag}]${colors.reset} ${msg}`);
        }
    },
    debug: (tag, msg) => {
        if (levels.DEBUG <= currentLevel) {
            console.log(`${colors.gray}[DEBUG-${tag}]${colors.reset} ${msg}`);
        }
    },
    system: (msg) => {
        if (levels.INFO <= currentLevel) {
            console.log(`${colors.magenta}${colors.bright}[SYSTEM]${colors.reset} ${msg}`);
        }
    }
};

module.exports = Logger;
