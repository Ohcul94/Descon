export default class Enemy {
    constructor(scene, x, y, texture, config) {
        this.scene = scene;
        this.config = config;
        this.id = 'e_' + Math.random().toString(36).substr(2, 9);
        
        this.container = new PIXI.Container();
        this.container.x = x;
        this.container.y = y;

        this.sprite = new PIXI.Sprite(PIXI.Texture.from(texture));
        this.sprite.anchor.set(0.5);
        this.container.addChild(this.sprite);

        this.maxHp = config.maxHp || config.hp || 2000;
        this.hp = config.hp || this.maxHp;
        this.maxShield = config.maxShield || config.shield || 500;
        this.shield = config.shield || this.maxShield;
        this.lastShoot = 0;

        this.createHUD();
    }

    createHUD() {
        this.nameTag = new PIXI.Text(this.config.name, { 
            fontFamily: 'Orbitron', 
            fontSize: 13, 
            fill: 0xffffff, 
            align: 'center', 
            fontWeight: 'bold' 
        });
        this.nameTag.anchor.set(0.5);
        this.nameTag.y = -86;
        this.container.addChild(this.nameTag);

        this.shTag = new PIXI.Text(`SH: ${this.shield}`, { 
            fontFamily: 'Rajdhani', 
            fontSize: 11, 
            fill: 0xffffff, 
            align: 'center' 
        });
        this.shTag.anchor.set(0.5);
        this.shTag.y = -72;
        this.container.addChild(this.shTag);

        this.hpTag = new PIXI.Text(`HP: ${this.hp}`, { 
            fontFamily: 'Rajdhani', 
            fontSize: 11, 
            fill: 0xffffff, 
            align: 'center' 
        });
        this.hpTag.anchor.set(0.5);
        this.hpTag.y = -60;
        this.container.addChild(this.hpTag);

        this.bars = new PIXI.Graphics();
        this.container.addChild(this.bars);
    }

    update(delta, player) {
        if (!this.container.parent) return;
        this.drawBars();
    }

    drawBars() {
        if (this.isDead || !this.bars || this.bars.destroyed) return;
        // Actualizar Textos
        this.shTag.text = `SH: ${Math.ceil(this.shield)}`;
        this.shTag.visible = this.shield > 0;
        this.hpTag.text = `HP: ${Math.ceil(this.hp)}`;

        this.bars.clear();
        const hpPct = this.hp / this.maxHp;
        const shPct = this.shield / this.maxShield;
        
        const barW = 44; 
        const gap = 2;   
        const segments = 4; 
        const segW = (barW - (gap * (segments - 1))) / segments;

        // Dibujar Barras Segmentadas (v5 Style)
        for (let i = 0; i < segments; i++) {
            const x = -(barW / 2) + (i * (segW + gap));
            
            // Escudo
            this.bars.beginFill(0x003333, 0.4).drawRect(x, -51, segW, 3).endFill();
            const shFill = Math.max(0, Math.min(1, (shPct * barW - (i * (segW + gap))) / segW));
            if (shFill > 0) this.bars.beginFill(0x00ffff, 1).drawRect(x, -51, segW * shFill, 3).endFill();
            
            // Vida
            this.bars.beginFill(0x330000, 0.4).drawRect(x, -43, segW, 3).endFill();
            const hpFill = Math.max(0, Math.min(1, (hpPct * barW - (i * (segW + gap))) / segW));
            if (hpFill > 0) this.bars.beginFill(hpPct > 0.3 ? 0x00ff00 : 0xff0000, 1).drawRect(x, -43, segW * hpFill, 3).endFill();
        }
    }

    takeDamage(amt) {
        if (this.shield >= amt) this.shield -= amt; 
        else { this.hp -= (amt - this.shield); this.shield = 0; }

        if (this.hp <= 0) this.die();
    }

    die() {
        if (this.isDead) return;
        this.isDead = true;
        this.scene.events.emit('enemyDead', this);
        if (this.container) {
            this.container.visible = false;
            // v120.20: La destrucción ocurre en el next frame de MainScene para evitar errores de null position
        }
    }
}
