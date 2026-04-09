/**
 * CLASE DamageText: Representa los números flotantes de daño en pantalla.
 */
export default class DamageText extends Phaser.GameObjects.Text {
    constructor(scene, x, y, text, color) {
        super(scene, x, y, text, {
            fontFamily: 'Orbitron',
            fontSize: '16px',
            fontWeight: 'bold',
            fill: color,
            stroke: '#000000',
            strokeThickness: 3
        });
        
        scene.add.existing(this);
        this.setOrigin(0.5).setDepth(200);

        // Animación de subida y desvanecimiento
        scene.tweens.add({
            targets: this,
            y: y - 60,
            alpha: 0,
            duration: 1200,
            ease: 'Cubic.easeOut',
            onComplete: () => this.destroy()
        });
    }
}
