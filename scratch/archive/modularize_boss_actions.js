const fs = require('fs');
const path = require('path');

const targetPath = path.resolve('e:/Descon/descon/scripts/systems/EntityManager.gd');
let content = fs.readFileSync(targetPath, 'utf8');

const startMarker = 'func _handle_shield_steal_action(data: Dictionary):';
const endMarker = 'active_meteor_zones[m_id] = { "zone_2d": zone_2d }';

const startIndex = content.indexOf(startMarker);
const endIndex = content.indexOf(endMarker);

if (startIndex === -1 || endIndex === -1) {
    console.error("Markers not found! startIndex:", startIndex, "endIndex:", endIndex);
    process.exit(1);
}

const replacement = `# ==============================================================================
# BOSS MECHANICS (Delegadas en BossActionHandler)
# ==============================================================================
func _handle_shield_steal_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_shield_steal_action(data)

func _handle_life_steal_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_life_steal_action(data)

func _handle_sleep_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_sleep_action(data)

func _handle_death_mark_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_death_mark_action(data)

func _handle_ascension_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_ascension_action(data)

func _ascension_land_enemy(enemy_id: String, dest: Vector2):
	if boss_action_handler: boss_action_handler.ascension_land_enemy(enemy_id, dest)

func _ascension_clear_jump(enemy_id: String):
	if boss_action_handler: boss_action_handler.ascension_clear_jump(enemy_id)

func _ascension_reset_all_offsets():
	if boss_action_handler: boss_action_handler.ascension_reset_all_offsets()

func _handle_meteor_action(data: Dictionary):
	if boss_action_handler: boss_action_handler.handle_meteor_action(data)

func _handle_meteor_zone_action(data: Dictionary) -> void:
	if boss_action_handler: boss_action_handler.handle_meteor_zone_action(data)`;

const newContent = content.substring(0, startIndex) + replacement + content.substring(endIndex + endMarker.length);

fs.writeFileSync(targetPath, newContent, 'utf8');
console.log("Reemplazo exitoso en EntityManager.gd!");
console.log("Longitud anterior:", content.length, "Nueva longitud:", newContent.length);
