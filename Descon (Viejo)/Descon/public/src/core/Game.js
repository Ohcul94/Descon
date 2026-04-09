import MainScene from '../scenes/MainScene.js';

let app = null;

window.initGame = () => { // Removido async en v7.x
    try {
        if (app) {
            console.log("Reiniciando instancia de PixiJS...");
            app.destroy(true, { children: true, texture: true, baseTexture: true });
            app = null;
        }

        console.log("Lanzando Descon v7.5 Pixi Engine (v7 Compatibility)...");
        
        // Constructor clásico sincronico de PixiJS v7
        app = new PIXI.Application({
            backgroundColor: 0x000005,
            resizeTo: window,
            antialias: true,
            resolution: window.devicePixelRatio || 1,
            autoDensity: true,
            hello: true // Muestra la versión en consola
        });

        // UNIFICAR FPS v72.01
        app.ticker.maxFPS = 60;
        app.ticker.minFPS = 30;

        document.getElementById('game-container').appendChild(app.view); // En v7 es .view, no .canvas

        // Inicializar la escena principal
        const scene = new MainScene(app);
        app.stage.addChild(scene.container);

        // Exponer para debugging
        window.pixiApp = app;
        window.currentScene = scene;

    } catch (e) {
        console.error("FATAL: No se pudo iniciar el motor PixiJS:", e);
    }
};

export default app;
