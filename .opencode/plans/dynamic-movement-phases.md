# Plan: Sistema de Fases Dinámicas por Condiciones para MovementPhases

## Problema Actual
Las `movementPhases` son estáticas: se asignan al spawn y nunca cambian. Solo kamikaze tiene activación condicional por HP. No hay transiciones dinámicas (idle → combat → berserk).

## Solución
Convertir `movementPhases` en un **autómata de estados** donde cada fase tiene `conditions` opcionales. El servidor evalúa condiciones cada tick y transiciona entre fases.

---

## 1. Estructura de Config (adicional, retrocompatible)

```json
{
  "movementPhases": [
    {
      "type": "prowler",
      "speed": 300,
      "patrolRange": 300,
      "conditions": { "engagement": "idle" }
    },
    {
      "type": "chase",
      "speed": 400,
      "stopDist": 120,
      "conditions": { "engagement": "combat" }
    },
    {
      "type": "zigzag",
      "speed": 500,
      "amplitude": 80,
      "frequency": 2.0,
      "conditions": { "engagement": "combat", "timeInCombatMs": 10000 }
    },
    {
      "type": "kamikaze",
      "activationHP": 10,
      "speed": 500,
      "conditions": { "hpPercentBelow": 10 }
    }
  ]
}
```

**Sin `conditions`** = se usa como antes (retrocompatible).

## 2. Tipos de Condiciones

| Condición | Tipo | Descripción |
|-----------|------|-------------|
| `engagement` | `"idle"` / `"combat"` / `"returning"` | Estado de engagement |
| `hpPercentBelow` | Number (0-100) | Activa cuando HP% < valor |
| `shieldPercentBelow` | Number (0-100) | Activa cuando Shield% < valor |
| `timeInCombatMs` | Number | Tiempo mínimo en combate |
| `timeSinceSpawnMs` | Number | Tiempo desde spawn |

**Prioridad**: Primer match en el array gana.

---

## 3. Archivos a Modificar

### A. `Server/behaviors/BaseAI.js` (Core --server)

**Insertar después de línea ~252** (después del cálculo de `_inCombat`, antes de la lógica de regeneración):

#### Método `_evaluatePhaseConditions(phases, now, hpPercent, shieldPercent)`:

```javascript
_evaluatePhaseConditions(phases, now, hpPercent, shieldPercent) {
    for (let i = 0; i < phases.length; i++) {
        const p = phases[i];
        if (!p.conditions) return i; // Sin condiciones = fallback

        const c = p.conditions;

        // engagement check
        if (c.engagement) {
            if (c.engagement === 'idle' && this._inCombat) continue;
            if (c.engagement === 'combat' && !this._inCombat) continue;
            if (c.engagement === 'returning' && !this.enemy.returningToSpawn) continue;
        }

        // HP check
        if (c.hpPercentBelow !== undefined) {
            if (hpPercent > c.hpPercentBelow) continue;
        }

        // Shield check
        if (c.shieldPercentBelow !== undefined) {
            if (shieldPercent > c.shieldPercentBelow) continue;
        }

        // Time in combat check
        if (c.timeInCombatMs !== undefined) {
            const combatTime = now - (this.enemy.chaseStartTime || now);
            if (combatTime < c.timeInCombatMs) continue;
        }

        // Time since spawn check
        if (c.timeSinceSpawnMs !== undefined) {
            const spawnTime = now - (this.enemy.spawnTime || now);
            if (spawnTime < c.timeSinceSpawnMs) continue;
        }

        return i; // First match wins
    }
    return 0; // Fallback to first phase
}
```

#### Modificar `update()` — Reemplazar el bloque kamikaze estático (líneas ~462-477):

```javascript
// ANTES (código actual):
const phases = cfg.movementPhases || [];
const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
const kamikazePhase = phases.find(p => p.type === 'kamikaze');
if (kamikazePhase && hpPercent <= (kamikazePhase.activationHP || 30)) {
    // kamikaze logic...
}

// DESPUÉS (código nuevo):
const phases = cfg.movementPhases || [];
const hpPercent = (this.enemy.hp / this.enemy.maxHp) * 100;
const shieldPercent = this.enemy.maxShield > 0
    ? (this.enemy.shield / this.enemy.maxShield) * 100 : 100;

// Evaluar fase activa por condiciones
const newPhaseIndex = this._evaluatePhaseConditions(phases, now, hpPercent, shieldPercent);
if (newPhaseIndex !== (this.enemy._currentPhaseIndex || 0)) {
    const prevIndex = this.enemy._currentPhaseIndex || 0;
    this.enemy._currentPhaseIndex = newPhaseIndex;
    const newPhase = phases[newPhaseIndex];

    if (newPhase) {
        // Copiar parámetros de movimiento al config del cerebro
        const phaseKeys = ['speed', 'stopDist', 'idealDist', 'orbitRadius',
            'chargeCooldown', 'amplitude', 'frequency', 'patrolRange',
            'changeTrigger', 'changeInterval', 'changeType'];
        phaseKeys.forEach(k => {
            if (newPhase[k] !== undefined) this.config[k] = newPhase[k];
        });

        // Actualizar tipo de movimiento si cambió
        const newType = newPhase.type;
        if (newType && newType !== this._lastMovementType) {
            this._lastMovementType = newType;
            this.enemy.movementType = newType;
        }

        // Notificar cambio de fase a clientes
        io.to(`zone_${this.enemy.zone}`).emit('enemyPhaseChange', {
            id: this.enemy.id,
            phaseIndex: newPhaseIndex,
            phaseType: newPhase.type,
            totalPhases: phases.length
        });
    }
}

// Lógica Kamikaze (preservada)
const kamikazePhase = phases.find(p => p.type === 'kamikaze');
if (kamikazePhase && hpPercent <= (kamikazePhase.activationHP || 30)) {
    if (!this.enemy.isKamikazeActive) {
        this.enemy.isKamikazeActive = true;
        this.enemy.kamikazeStartTime = now;
        this.enemy.isRamming = true;
        io.to(`zone_${this.enemy.zone}`).emit('serverEnemyAction', {
            id: this.enemy.id, action: "kamikaze_start",
            duration: kamikazePhase.duration || 5000
        });
    }
}
```

#### Inicializar `_currentPhaseIndex` en el constructor:

```javascript
constructor(enemy, config, state) {
    this.enemy = enemy;
    this.config = config;
    this.state = state;
    this.lastAction = 0;
    this._isDefenseSkillActive = false;
    this._currentPhaseIndex = 0;       // NUEVO
    this._lastMovementType = null;      // NUEVO
}
```

---

### B. `AdminDash/js/definitions.js` (UI - definitions)

Agregar campos de condiciones al `DEFAULT_MOVEMENT_LIB`:

```javascript
// Agregar a cada entrada del DEFAULT_MOVEMENT_LIB:
// "conditions" como campo nuevo con tipo especial
```

Campos de condiciones a agregar:

```javascript
const CONDITION_FIELDS = [
    { key: 'engagement', label: 'Estado', type: 'select',
      options: [
        { value: 'idle', label: '🪫 Reposo (fuera de combate)' },
        { value: 'combat', label: '⚔️ En combate' },
        { value: 'returning', label: '↩️ Regresando al spawn' }
      ]},
    { key: 'hpPercentBelow', label: 'HP por debajo de (%)', type: 'number', min: 0, max: 100 },
    { key: 'shieldPercentBelow', label: 'Escudo por debajo de (%)', type: 'number', min: 0, max: 100 },
    { key: 'timeInCombatMs', label: 'Tiempo en combate (ms)', type: 'number', min: 0 },
    { key: 'timeSinceSpawnMs', label: 'Tiempo desde spawn (ms)', type: 'number', min: 0 }
];
```

---

### C. `AdminDash/js/renderers.js` (UI - editor visual)

En `renderEnemyDetail()`, dentro del bloque de movementPhases (~línea 1476-1511), agregar UI de condiciones debajo de cada fase:

```html
<!-- Sección de Condiciones de Activación -->
<div style="margin-top: 1rem; padding-top: 0.5rem; border-top: 1px dashed rgba(234, 179, 8, 0.3);">
    <label style="color:#eab308; font-size: 0.7rem; font-weight:bold;">⚡ CONDICIONES DE ACTIVACIÓN</label>
    <div class="form-grid" style="margin-top: 0.5rem;">
        ${CONDITION_FIELDS.map(field => `
            <div class="field">
                <label>${field.label}</label>
                ${field.type === 'select'
                    ? `<select onchange="...">
                         <option value="">Sin restricción</option>
                         ${field.options.map(o => `<option value="${o.value}">${o.label}</option>`).join('')}
                       </select>`
                    : `<input type="number" min="${field.min || 0}" max="${field.max || 999999}"
                         placeholder="Sin restricción"
                         onchange="...">`
                }
            </div>
        `).join('')}
    </div>
</div>
```

---

### D. `AdminDash/js/app.js` (UI - helpers)

Agregar función para gestionar condiciones:

```javascript
function updateMovementPhaseCondition(enemyId, phaseIdx, conditionKey, value) {
    const phase = config.enemyModels[enemyId].movementPhases[phaseIdx];
    if (!phase.conditions) phase.conditions = {};
    if (value === '' || value === null || value === undefined || value === 0) {
        delete phase.conditions[conditionKey];
        if (Object.keys(phase.conditions).length === 0) {
            delete phase.conditions;
        }
    } else {
        phase.conditions[conditionKey] = value;
    }
}
```

---

## 4. No se Modifica

- `config.json` — Las condiciones son opcionales, sin cambios forzados
- `gameLoop.js` — Ya llama `ai.update()` donde vive la lógica
- `Enemy.gd` — El cliente solo interpola posiciones del servidor
- `AIManager.js` — La asignación inicial de cerebro IA sigue igual
- `movementHandler.js` — Movimiento de jugadores no se toca
- `combatHandlers.js` — Combate no se toca

---

## 5. Retrocompatibilidad

- Sin campo `conditions` → fase funciona como antes
- El array `movementPhases` se mantiene como array indexado
- Los existing enemies en config.json no necesitan cambios
- BossAI.movementPhases existentes (tipo "boss") siguen funcionando igual

---

## 6. Evento `enemyPhaseChange` (para Godot - opcional)

El cliente puede escuchar este evento para efectos visuales:
```gdscript
# En Enemy.gd o un script de VFX
NetworkManager.enemy_phase_change.connect(_on_enemy_phase_change)

func _on_enemy_phase_change(data):
    if data.id == self.name:
        # Cambiar color del aura,播放动画, etc.
        pass
```

---

## Resumen de Cambios

| Archivo | Líneas aprox. | Impacto |
|---------|---------------|---------|
| `Server/behaviors/BaseAI.js` | +50 líneas | Core del sistema |
| `AdminDash/js/definitions.js` | +15 líneas | Definición de campos |
| `AdminDash/js/renderers.js` | +40 líneas | UI de condiciones |
| `AdminDash/js/app.js` | +15 líneas | Helper de condiciones |
| **Total** | ~120 líneas | Bajo riesgo |
