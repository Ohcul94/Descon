// AncientDungeon(M3).js (Misterio Violeta v98.10)
import BaseMap from './BaseMap.js';

export default class AncientDungeon extends BaseMap {
    constructor(scene) {
        super(scene, {
            width: 2500, // Un poco más grande que la de Titán
            height: 2500,
            bgTexture: 'stars',
            name: 'ANCIENT VOID DUNGEON'
        });
    }

    setup() {
        super.setup();
        console.log(`DESCON: Teletransporte a ${this.config.name} completado.`);
        
        // Efecto de Nebulosa Violeta (v98.10)
        this.addVoidMist();
    }

    addVoidMist() {
        const mist = new PIXI.Graphics();
        mist.beginFill(0xbc13fe, 0.08); // Púrpura Admin/Místico
        mist.drawRect(0, 0, this.config.width, this.config.height);
        mist.endFill();
        mist.filters = [new PIXI.BlurFilter(60)];
        this.scene.world.addChildAt(mist, 0);
    }
}
