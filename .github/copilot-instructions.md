Purpose
-------
This file gives quick, actionable guidance to AI coding agents working in this repo so they can be immediately productive. Focus on the two primary areas: the Godot client in `descon/` and the Node.js game server in `MMO_Server/`.

Quick Architecture Summary
-------------------------
- **Server (MMO_Server)**: Node.js + Express + Socket.IO. Single shared `state` object ([MMO_Server/state.js](MMO_Server/state.js)) holds `players`, `enemies`, `activeSessions`, and global counters. Main entry: [MMO_Server/server.js](MMO_Server/server.js). Systems and handlers are modular under `MMO_Server/systems/`, `MMO_Server/events/`, `MMO_Server/handlers/`, and AI behaviors in `MMO_Server/behaviors/`.
- **Client (descon/)**: Godot project. Main scene: [descon/scenes/MainGame.tscn](descon/scenes/MainGame.tscn). Web/export builds exist in `Ejecutable Web/` for quick test deployment.

Key Integration Points
----------------------
- Socket events are registered via handler modules and system registration functions called from `server.js` (e.g., `registerCombatHandlers`, `registerInventoryHandlers`). Follow that pattern when adding new events.
- Persistent data uses MongoDB models in `MMO_Server/models/` (e.g., `User`, `Session`, `Clan`). Server expects `MONGODB_URI` in environment or .env.
- Server configuration and server-side game definitions are loaded from `MMO_Server/config.json` (see usage in `server.js`).

Developer Workflows
-------------------
- Run server locally:

  - Install deps in `MMO_Server/` and start:

    npm install
    npm run dev    # uses nodemon

  - Production start: `npm start` (runs `node server.js`).

- MongoDB: set `MONGODB_URI` in `MMO_Server/.env` or environment. The server logs DB connect attempts on startup.
- Godot client: open the `descon/` project in Godot and run `MainGame.tscn`. For quick web testing, use files in `Ejecutable Web/`.
- Debug helpers: there are `debug_launch.bat` scripts at the repo root and in `descon/`—inspect them for environment specifics and paths.

Project-Specific Patterns & Conventions
--------------------------------------
- Single shared `state` object (do not create competing globals). Mutate `state` fields rather than replacing the object.
- Add socket event handlers by creating a module under `handlers/` or `systems/` and exporting a `register*Handlers(io, state, ...)` function; call it from `server.js`.
- AI and spawn logic lives in `systems/AIManager.js` and `events/HordeManager.js`. Use `aiManager.serverSpawnEnemy(...)` for server-side spawning.
- Inventory and item canonical data are maintained in `SERVER_CONFIG` (loaded from `config.json`)—sync code uses this master list to normalize older item records.

Files to Inspect First
----------------------
- [MMO_Server/server.js](MMO_Server/server.js) — server bootstrap and orchestration (event registration, game loop start, DB, config).
- [MMO_Server/state.js](MMO_Server/state.js) — canonical shared state shape.
- `MMO_Server/systems/` and `MMO_Server/events/` — where core game logic is implemented.
- [descon/scenes/MainGame.tscn](descon/scenes/MainGame.tscn) and `descon/scripts/` — client-side structure.

When Changing Behavior
----------------------
- If you change network event names or payload shapes, update both the server handler module and the Godot client code that emits/listens to those events.
- DB migrations: server code performs minor migrations (see `server.js` inventory migration logic). If you change schemas in `MMO_Server/models/`, include conversion logic where needed.

Notes for the Agent
-------------------
- Be conservative: prefer small, focused edits. Follow existing registration patterns (create `registerXHandlers` functions rather than injecting ad-hoc handlers in `server.js`).
- Use existing utilities: logging in `MMO_Server/utils/logger.js`, grid logic in `MMO_Server/systems/GridManager.js`.
- Look for `v*` version comments in `server.js` for historical context—they indicate migration or behavior rationale.

If anything in this file is unclear or you'd like the agent to expand a particular section with examples, tell me which area to expand (server run steps, typical handler template, or client-side event example).
