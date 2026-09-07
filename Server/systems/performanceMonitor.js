// Server/systems/performanceMonitor.js
// v370.1: Monitores de rendimiento y telemetría AAA en RAM

const os = require('os');

function initPerformanceMonitor(state) {
    if (!state) return;

    state.performance = {
        // Tick metrics
        avgTickTime: 0,
        maxTickTime: 0,
        lastTickDuration: 0,
        p99TickTime: 0,   // Percentil 99 de latencia de tick
        p50TickTime: 0,   // Mediana real del tick
        // CPU / Memoria
        memoryUsage: {},
        cpuUsage: 0,
        rssHistory: [],   // Últimos 60 samples de RSS (MB)
        heapHistory: [],  // Últimos 60 samples de heapUsed (MB)
        // Red — bytes globales
        network: {
            totalBytesSent: 0,
            totalBytesReceived: 0
        },
        // PPS (Paquetes por Segundo) — globales del proceso
        ppsIn: 0,
        ppsOut: 0,
        // Acumuladores internos entre intervalos
        _pktIn: 0,
        _pktOut: 0,
        _bytesOutAcc: 0,  // Acumulador de egreso en el intervalo
        _bytesInAcc: 0
    };

    let lastCpuUsage = process.cpuUsage();
    let lastCpuTime = Date.now();

    const timer = setInterval(() => {
        const elapsedMs = Date.now() - lastCpuTime;
        if (elapsedMs <= 0) return;
        const usage = process.cpuUsage(lastCpuUsage);
        lastCpuUsage = process.cpuUsage();
        lastCpuTime = Date.now();

        // CPU del proceso Node.js (no de la VM completa)
        const totalMs = (usage.user + usage.system) / 1000;
        const cpusCount = os.cpus().length || 1;
        const percent = (totalMs / elapsedMs) * 100 / cpusCount;
        state.performance.cpuUsage = parseFloat(percent.toFixed(2));

        // Memoria — sample actual
        const mem = process.memoryUsage();
        const rssMB  = parseFloat((mem.rss      / 1024 / 1024).toFixed(2));
        const heapMB = parseFloat((mem.heapUsed / 1024 / 1024).toFixed(2));
        state.performance.memoryUsage = {
            heapUsed:  heapMB,
            heapTotal: parseFloat((mem.heapTotal / 1024 / 1024).toFixed(2)),
            rss:       rssMB
        };

        // Historial circular de memoria (máx 60 puntos = 2 minutos)
        state.performance.rssHistory.push(rssMB);
        state.performance.heapHistory.push(heapMB);
        if (state.performance.rssHistory.length  > 60) state.performance.rssHistory.shift();
        if (state.performance.heapHistory.length > 60) state.performance.heapHistory.shift();

        // PPS calculado sobre el intervalo de 2s
        const elapsedSec = elapsedMs / 1000;
        state.performance.ppsIn  = parseFloat((state.performance._pktIn  / elapsedSec).toFixed(1));
        state.performance.ppsOut = parseFloat((state.performance._pktOut / elapsedSec).toFixed(1));
        state.performance._pktIn  = 0;
        state.performance._pktOut = 0;

        // Sincronizar acumuladores de bytes al contador global
        state.performance.network.totalBytesSent     += state.performance._bytesOutAcc;
        state.performance.network.totalBytesReceived += state.performance._bytesInAcc;
        state.performance._bytesOutAcc = 0;
        state.performance._bytesInAcc  = 0;
    }, 2000);

    return {
        timer,
        stop: () => clearInterval(timer)
    };
}

module.exports = {
    initPerformanceMonitor
};
