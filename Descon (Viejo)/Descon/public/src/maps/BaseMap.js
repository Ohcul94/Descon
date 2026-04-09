// BaseMap.js (Estructura Maestra de Escenarios v97.10)
export default class BaseMap {
    constructor(scene, config = {}) {
        this.scene = scene;
        this.config = {
            width: config.width || 4000,
            height: config.height || 4000,
            bgTexture: config.bgTexture || 'stars',
            name: config.name || 'SISTEMA DESCONOCIDO'
        };
        this.stars = [];
    }

    // Inicialización visual del mapa (v97.10)
    setup() {
        // Fondo Tiling (v69.30)
        this.bg = new PIXI.TilingSprite(
            PIXI.Texture.from(this.config.bgTexture),
            this.scene.app.screen.width,
            this.scene.app.screen.height
        );
        this.bg.alpha = 0.4;
        this.scene.app.stage.addChildAt(this.bg, 0); // Al fondo

        // Generar Estrellas de Fondo (Optimización Pixi v97.10)
        this.generateStars();
    }

    generateStars() {
        const starCount = 300;
        for (let i = 0; i < starCount; i++) {
            const star = new PIXI.Graphics();
            star.beginFill(0xffffff, Math.random());
            star.drawCircle(0, 0, Math.random() * 2);
            star.endFill();
            star.x = Math.random() * this.config.width;
            star.y = Math.random() * this.config.height;
            this.scene.world.addChildAt(star, 0); // Debajo de las naves
            this.stars.push(star);
        }
    }

    update(delta, player) {
        // Parallax suave (v97.10)
        if (this.bg && player && player.container) {
            this.bg.tilePosition.x = -player.container.x * 0.1;
            this.bg.tilePosition.y = -player.container.y * 0.1;
        }
    }

    destroy() {
        if (this.bg) this.bg.destroy();
        this.stars.forEach(s => s.destroy());
    }
}
