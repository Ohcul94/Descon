// GalaxyMap.js (Sector Inicial v97.20)
import BaseMap from './BaseMap.js';

export default class GalaxyMap extends BaseMap {
    constructor(scene) {
        super(scene, {
            width: 4000,
            height: 4000,
            bgTexture: 'stars',
            name: 'GALAXY SECTOR 1'
        });
    }

    setup() {
        super.setup();
        console.log(`DESCON: Entrando en ${this.config.name}...`);
        
        // Agregar nubes de nebulosa (v97.20 Estético)
        this.addNebula();
    }

    addNebula() {
        // Lógica visual específica del Sector 1
        const nebula = new PIXI.Graphics();
        nebula.beginFill(0x00ffff, 0.05);
        nebula.drawCircle(2000, 2000, 1500);
        nebula.endFill();
        nebula.filters = [new PIXI.BlurFilter(100)];
        this.scene.world.addChildAt(nebula, 0);
    }
}
