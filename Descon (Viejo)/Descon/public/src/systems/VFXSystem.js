// VFXSystem.js (Architecture v116.10 Modular Gfx Engine)
export default class VFXSystem {
    constructor(scene) {
        this.scene = scene;
        this.app = scene.app;
        this.world = scene.world;
    }

    handleBossEffect(data) {
        switch (data.type) {
            case 'vacuum':
                this.createNovaEffect(data.x, data.y, data.radius || 1200);
                break;
            case 'rift':
                this.createVoidRiftEffect(data.x, data.y, data.duration || 4000);
                break;
            case 'leech':
                // TODO: Visual de Leech v116.10
                break;
        }
    }

    createNovaEffect(x, y, radius) {
        const ring = new PIXI.Graphics();
        ring.lineStyle(6, 0xbc13fe, 1);
        ring.drawCircle(0, 0, 10);
        ring.x = x; ring.y = y;
        this.world.addChild(ring);

        let scale = 1;
        let hasHitPlayer = false; 
        const anim = () => {
            scale += 0.8; 
            ring.scale.set(scale);
            ring.alpha -= 0.005; 
            
            if (!hasHitPlayer && this.scene.player && !this.scene.player.isDead) {
                const logicalRadius = scale * 8;
                const dist = Math.hypot(this.scene.player.container.x - x, this.scene.player.container.y - y);
                if (Math.abs(dist - logicalRadius) < 60) { 
                    hasHitPlayer = true;
                    const angle = Math.atan2(this.scene.player.container.y - y, this.scene.player.container.x - x);
                    this.scene.player.vx += Math.cos(angle) * 22; 
                    this.scene.player.vy += Math.sin(angle) * 22;
                }
            }

            if (scale > 150 || ring.alpha <= 0) { 
                ring.destroy();
                this.app.ticker.remove(anim);
            }
        };
        this.app.ticker.add(anim);
    }

    createVoidRiftEffect(x, y, duration) {
        const rift = new PIXI.Graphics();
        rift.lineStyle(4, 0xbc13fe, 1);
        rift.beginFill(0xbc13fe, 0.2);
        rift.drawCircle(0, 0, 80);
        rift.x = x; rift.y = y;
        this.world.addChildAt(rift, 0);

        let scaleCounter = 0;
        const anim = () => {
            scaleCounter += 0.1;
            rift.scale.set(1 + Math.sin(scaleCounter) * 0.2);
            if (rift.destroyed) this.app.ticker.remove(anim);
        };
        this.app.ticker.add(anim);
        setTimeout(() => { 
            if(!rift.destroyed) { 
                rift.destroy(); 
                this.app.ticker.remove(anim); 
            } 
        }, duration);
    }
}
