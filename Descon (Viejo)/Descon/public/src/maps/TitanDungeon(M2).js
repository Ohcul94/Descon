// TitanDungeon.js (Guarida del Titán v97.30)
import BaseMap from './BaseMap.js';

export default class TitanDungeon extends BaseMap {
    constructor(scene) {
        super(scene, {
            width: 2000,
            height: 2000,
            bgTexture: 'stars',
            name: 'TITAN BOSS DUNGEON'
        });
    }

    setup() {
        super.setup();
        console.log(`DESCON: Entrando en ${this.config.name}... PELIGRO DETECTADO.`);
        
        // Efecto de Alerta Roja (v97.30 Estético Boss)
        this.addRedAlert();
    }

    addRedAlert() {
        const warning = new PIXI.Graphics();
        warning.beginFill(0xff3300, 0.08); // Brillo naranja/rojo
        warning.drawRect(0, 0, this.config.width, this.config.height);
        warning.endFill();
        warning.filters = [new PIXI.BlurFilter(50)];
        this.scene.world.addChildAt(warning, 0);
    }
}
