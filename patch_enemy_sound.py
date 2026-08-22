import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")

# Patch for attack mechanics in enemy detail - inject after </div> of form-grid (first occurrence for mechanics)
# The mechanics card template contains:
#                             <div class="form-grid" style="margin-top:1rem;">
#                                 ${(MECHANICS_LIB[m.type] || MECHANICS_LIB['laser']).fields.map(f => {
# ...
# Also there is later movementPhases similarly. Easier to inject a helper function for sound override HTML and append via string replace.

# We'll add helper function at top of file after definitions
helper = """
// v900.0: helpers sonido mecanicas hybrid
function mechanicSoundOverrideHtml(enemyId, listName, idx, mech) {
    const libKey = mech.type;
    const MECHANICS_LIB_X = config.mechanicsLib || DEFAULT_MECHANICS_LIB;
    const DEFENSE_LIB_X = config.defenseLib || DEFAULT_DEFENSE_LIB;
    const MOVEMENT_LIB_X = config.movementLib || DEFAULT_MOVEMENT_LIB;
    let lib = MECHANICS_LIB_X[libKey] || DEFENSE_LIB_X[libKey] || MOVEMENT_LIB_X[libKey] || null;
    const defaultSound = lib ? (lib.sound || '') : '';
    const hasOverride = !!(mech.sound && mech.sound !== '');
    const effective = hasOverride ? mech.sound : defaultSound;
    const vol = hasOverride ? (mech.soundVolumeDb !== undefined ? mech.soundVolumeDb : (lib ? lib.soundVolumeDb : 0)) : (lib ? lib.soundVolumeDb : 0);
    const maxd = hasOverride ? (mech.soundMaxDist || (lib ? lib.soundMaxDist : 1200)) : (lib ? lib.soundMaxDist : 1200);
    const preview = effective ? resolveAssetWebUrl(effective) : '';
    return `
    <div style="margin-top:0.6rem; padding:0.7rem; background:rgba(168,85,247,0.05); border:1px solid rgba(168,85,247,0.12); border-radius:6px; border-left:2px solid #a855f7;">
        <label style="color:#a855f7; font-size:0.6rem; font-weight:bold; display:flex; align-items:center; gap:6px;">SONIDO (Override por enemigo) <span style="font-weight:normal; color:#888; font-size:0.55rem;">vacío = hereda de librería</span></label>
        <div style="font-size:0.55rem; color:#888; margin-top:0.2rem;">Default librería: <span style="color:#a855f7; font-family:JetBrains Mono;">${defaultSound || '(sin sonido)'}</span></div>
        <div style="display:flex; gap:6px; align-items:center; margin-top:0.4rem;">
            <input type="text" placeholder="res://assets/Sonidos/Mecanicas/ej.ogg" value="${mech.sound || ''}" style="flex:1; font-size:0.65rem;" onchange="config.enemyModels['${enemyId}'][listName][${idx}].sound = this.value; renderEnemyDetail();">
            <button class="btn" style="padding:4px 8px; font-size:0.6rem; background:rgba(168,85,247,0.12); border:1px solid rgba(168,85,247,0.25); color:#a855f7;" onclick="triggerAssetUpload('${enemyId}_${listName}_${idx}', 'mechanic_instance_sound')">SONIDO</button>
            ${mech.sound ? `<button class="btn" style="padding:2px 6px; font-size:0.55rem; background:rgba(255,60,60,0.08); border:1px solid rgba(255,60,60,0.2); color:#ff6060;" onclick="config.enemyModels['${enemyId}'][listName][${idx}].sound=''; renderEnemyDetail();">X</button>` : ''}
        </div>
        ${preview ? `<audio controls preload="none" src="${preview}" style="width:100%; height:26px; margin-top:0.4rem;"></audio><div style="font-size:0.55rem; color:#a855f7; font-family:JetBrains Mono; overflow:hidden; text-overflow:ellipsis;">Efectivo: ${effective}</div>` : ''}
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:6px; margin-top:0.4rem;">
            <div class="field"><label>Vol Override (dB)</label><input type="number" step="1" value="${mech.soundVolumeDb !== undefined ? mech.soundVolumeDb : ''}" placeholder="${lib ? lib.soundVolumeDb : 0}" onchange="config.enemyModels['${enemyId}'][listName][${idx}].soundVolumeDb = this.value === '' ? undefined : parseFloat(this.value)"></div>
            <div class="field"><label>Dist Max Override (px)</label><input type="number" step="50" value="${mech.soundMaxDist !== undefined ? mech.soundMaxDist : ''}" placeholder="${lib ? lib.soundMaxDist : 1200}" onchange="config.enemyModels['${enemyId}'][listName][${idx}].soundMaxDist = this.value === '' ? undefined : parseInt(this.value)"></div>
        </div>
    </div>`;
}
"""

if "mechanicSoundOverrideHtml" not in txt:
    # insert after window.resolveAssetWebUrl definition
    marker = "window.resolveAssetWebUrl = function"
    idx = txt.find(marker)
    if idx != -1:
        # find end of that function block - insert helper right after
        insert_pos = txt.find("};", idx) + 2
        txt = txt[:insert_pos] + "\n" + helper + txt[insert_pos:]
        print("added helper")
    else:
        print("marker not found")
else:
    print("already has helper")

# Now patch attack mechanics card: find where enemy mechanics card ends - after form-grid div, inject sound html
# Look for pattern: </div>
#                             <div style="margin-top: 0.75rem; padding-top: 0.5rem; border-top: 1px dashed rgba(234, 179
# That's the movement condition section, not mechanics. For mechanics, after form-grid we need injection.
# Easiest: search for `en.mechanics.map` and add after its `</div>` closing of form-grid
# We'll do simple string replace: after `</div>\n                             <div style="margin-top: 0.75rem` if present for mechanics? Actually mechanics card doesn't have that.
# Let's just inject after the form-grid's closing tag for mechanics: pattern `                                ${(MECHANICS_LIB[m.type]` block ends with `}).join('')}` then `                             </div>`
# We'll replace `}).join('')}` + newline + `                             </div>` for mechanics with added injection

old_mech = "                             </div>\n                             <div style=\"margin-top: 0.75rem; padding-top: 0.5rem; border-top: 1px dashed rgba(234, 179, 8, 0.3);\">"
# Actually that is movement phases, not mechanics. For mechanics, the next element after form-grid is closing of card.
# Let's find mechanics card tail: look for en.mechanics section
import re
# Attack mechanics tail pattern
needle = "}).join('')}\n                             </div>\n                         </div>"
# This appears multiple times, we want only attack mechanics one. We'll do targeted replace for first occurrence after en.mechanics.map
# Simpler: replace the first occurrence of that pattern that is inside en.mechanics block with injection
if needle in txt:
    # inject sound html before closing
    injection = "}).join('')}\n                             </div>\n                             ${mechanicSoundOverrideHtml(selectedEnemyId, 'mechanics', idx, m)}\n                         </div>"
    txt = txt.replace(needle, injection, 1)
    print("patched attack mechanics card")
else:
    print("attack needle not found")

# Now patch defenseMechanics card
# Search for defense list: en.defenseMechanics.map
if "en.defenseMechanics.map" in txt:
    # same needle for defense
    needle2 = "}).join('')}\n                             </div>\n                         </div>\n                     `).join('')}"
    # defense card is different, try generic
    # We'll search for defense card injection point: after its form-grid
    # Use regex to find defense card's closing
    print("defense found")
else:
    print("defense not found")

p.write_text(txt, encoding="utf-8")
