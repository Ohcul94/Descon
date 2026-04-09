/**
 * MINIMAP SYSTEM: Versión PixiJS v7.5
 * Dibuja los puntos de radar en el canvas del HUD o en un overlay.
 */
export default class MinimapSystem {
    constructor(scene) {
        this.scene = scene;
        this.container = document.getElementById('minimap-container');
        this.canvas = document.createElement('canvas');
        this.ctx = this.canvas.getContext('2d');
        
        this.setup();
    }

    setup() {
        if (!this.container) return;
        
        this.canvas.width = 200;
        this.canvas.height = 200;
        this.canvas.style.width = '100%';
        this.canvas.style.height = '100%';
        this.container.appendChild(this.canvas);
        
        // AUTOPILOTO: Clic en minimapa v66.5 (Y TOUCH v74.20)
        const handleMinimapInteraction = (e) => {
            e.stopPropagation();
            if (e.cancelable) e.preventDefault();

            const rect = this.canvas.getBoundingClientRect();
            const clientX = e.touches ? e.touches[0].clientX : e.clientX;
            const clientY = e.touches ? e.touches[0].clientY : e.clientY;
            
            const x = clientX - rect.left;
            const y = clientY - rect.top;
            
            const mapSize = 200; 
            const scale = mapSize / rect.width; 
            
            const worldSize = this.scene.worldSize;
            const worldX = (x * scale) * (worldSize / mapSize);
            const worldY = (y * scale) * (worldSize / mapSize);
            
            if (this.scene.player) {
                this.scene.player.setAutopilot(worldX, worldY);
                if (window.hudNotify) window.hudNotify("SISTEMA DE NAVEGACIÓN: COORDENADAS FIJADAS", 'info');
            }
        };

        this.canvas.onmousedown = handleMinimapInteraction;
        this.canvas.ontouchstart = handleMinimapInteraction;

        // Ticker de dibujo (Independiente o desde la escena)
        this.scene.app.ticker.add(() => this.draw());
    }

    draw() {
        if (!this.ctx || !this.scene.player) return;

        const ctx = this.ctx;
        const worldSize = this.scene.worldSize;
        const mapSize = 200;
        const scale = mapSize / worldSize;

        // Limpiar fondo
        ctx.clearRect(0, 0, mapSize, mapSize);
        ctx.fillStyle = 'rgba(0, 20, 30, 0.5)';
        ctx.fillRect(0, 0, mapSize, mapSize);

        // Jugador Local (Cálculo de posición en minimapa)
        const lx = this.scene.player.container.x * scale;
        const ly = this.scene.player.container.y * scale;

        // DIBUJAR TRAYECTORIA v66.6
        if (this.scene.player.isAutopilotActive && this.scene.player.autopilotTarget) {
            const tx = this.scene.player.autopilotTarget.x * scale;
            const ty = this.scene.player.autopilotTarget.y * scale;
            ctx.strokeStyle = 'rgba(0, 255, 0, 0.4)';
            ctx.setLineDash([4, 4]);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(lx, ly);
            ctx.lineTo(tx, ty);
            ctx.stroke();
            ctx.setLineDash([]);
            
            // Punto de destino
            ctx.fillStyle = 'rgba(0, 255, 0, 0.8)';
            ctx.beginPath();
            ctx.arc(tx, ty, 3, 0, Math.PI * 2);
            ctx.fill();
        }
        
        // Cuadrícula simple
        ctx.strokeStyle = 'rgba(0, 255, 255, 0.1)';
        ctx.strokeRect(0, 0, mapSize, mapSize);

        // Dibujar Enemigos (Puntos Naranja v13.1.3)
        this.scene.entities.enemies.forEach(enemy => {
            // v119.20: Saneamiento de Integridad de Radar
            if (!enemy || enemy.isDead || !enemy.container || enemy.container.destroyed) return; 
            const ex = enemy.container.x * scale;
            const ey = enemy.container.y * scale;
            ctx.fillStyle = '#ff6600';
            ctx.beginPath();
            ctx.arc(ex, ey, 2, 0, Math.PI * 2);
            ctx.fill();
        });

        // Dibujar Jugadores Remotos (Celeste Neón v11.9)
        this.scene.entities.remotePlayers.forEach(p => {
            // v119.20: Saneamiento de Integridad de Radar
            if (!p || !p.container || p.container.destroyed) return; 
            const px = p.container.x * scale;
            const py = p.container.y * scale;
            ctx.fillStyle = '#00ffff'; 
            ctx.beginPath();
            ctx.arc(px, py, 2.5, 0, Math.PI * 2);
            ctx.fill();
        });

        // Dibujar Jugador Local (Punto Verde)
        ctx.fillStyle = '#00ff00';
        ctx.beginPath();
        ctx.arc(lx, ly, 3, 0, Math.PI * 2);
        ctx.fill();
        
        // Efecto de barrido (opcional)
        ctx.strokeStyle = '#00ff00';
        ctx.globalAlpha = 0.2;
        ctx.strokeRect(lx - 5, ly - 5, 10, 10);
        ctx.globalAlpha = 1.0;
    }
}
