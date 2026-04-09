# Historial del Proyecto: Galactic MMO

## Sesión 24/03/2026

### Objetivo
Organizar el proyecto para evitar el caos y asegurar que no se pierda el progreso por fallos en el chat o el entorno.

### Decisiones Técnicas
1. **Reorganización Estructural**: Se migra de una carpeta plana a una estructura `public/server/docs`.
2. **Consolidación de Lógica**: La lógica de Phaser se mueve completamente a `js/game.js`, dejando el HTML limpio solo para UI.
3. **Registro de Chat**: Se crea este archivo para documentar lo que vamos hablando y haciendo.

### Estado Actual del Prototipo
- Movimiento básico con Phaser implementado.
- Servidor Socket.io para multijugador básico (posición y rotación).
- HUD de Neón con sistema de enfriamiento de armas (Q, W, E).
- Mapa de 4000x4000 con generación de estrellas.
- Enemigos básicos que disparan.
- Menú de equipamiento (ESC).

### Notas de Chat ("Lo que creíamos borrado")
- Se estaba trabajando en arreglar el renderizado que se quedaba en negro (resuelto previamente).
- Se busca un diseño "Premium" con estética neón y moderna.
- Se implementó ngrok como opción para jugar con amigos.
