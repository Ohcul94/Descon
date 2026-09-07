const fs = require('fs');
const path = require('path');

const targetPath = path.resolve('e:/Descon/descon/scripts/entities/Entity.gd');
let content = fs.readFileSync(targetPath, 'utf8');

// 1. Agregar const EntityMechanicsVFXScript y var _mechanics_vfx en la cabecera
const headerTarget = 'const WreckageDrawingScript = preload("res://scripts/ui/WreckageDrawing.gd")';
const headerAddition = `const WreckageDrawingScript = preload("res://scripts/ui/WreckageDrawing.gd")
const EntityMechanicsVFXScript = preload("res://scripts/entities/EntityMechanicsVFX.gd")
var _mechanics_vfx: EntityMechanicsVFX = null`;

if (!content.includes(headerTarget)) {
    console.error("Header target not found!");
    process.exit(1);
}
content = content.replace(headerTarget, headerAddition);

// 2. Inicializar _mechanics_vfx en _ready()
const readyTarget = `	var sm_script = SpheresManagerScript
	if sm_script:
		var sm = sm_script.new()
		sm.name = "SpheresManager"
		add_child(sm)
		sm.spheres_updated.connect(_update_3d_spheres)`;

const readyAddition = `	var sm_script = SpheresManagerScript
	if sm_script:
		var sm = sm_script.new()
		sm.name = "SpheresManager"
		add_child(sm)
		sm.spheres_updated.connect(_update_3d_spheres)

	# Inicialización de VFX de Mecánicas Desacoplado
	var mvfx_script = EntityMechanicsVFXScript
	if mvfx_script:
		_mechanics_vfx = mvfx_script.new()
		_mechanics_vfx.name = "EntityMechanicsVFX"
		_mechanics_vfx.setup(self)
		add_child(_mechanics_vfx)`;

if (!content.includes(readyTarget)) {
    console.error("Ready target not found!");
    process.exit(1);
}
content = content.replace(readyTarget, readyAddition);

// 3. Reemplazar bloque 1: _on_enemy_action hasta _update_auras
const b1Start = 'func _on_enemy_action(data):\n\tif str(data.id) != entity_id: return';
const b1End = 'a_data.particles_3d.position.z = global_position.y * s_factor * correction_z\n';

const idxB1Start = content.indexOf(b1Start);
const idxB1End = content.indexOf(b1End, idxB1Start);

if (idxB1Start === -1 || idxB1End === -1) {
    console.error("Bloque 1 not found!", idxB1Start, idxB1End);
    process.exit(1);
}

const b1Replacement = `# ==============================================================================
# MECÁNICAS DE ENEMIGOS Y AURAS (Delegadas en EntityMechanicsVFX)
# ==============================================================================
func _on_enemy_action(data):
	if _mechanics_vfx: _mechanics_vfx.handle_enemy_action(data)

func _stop_orbital_orbit():
	if _mechanics_vfx: _mechanics_vfx.stop_orbital_orbit()

func _fire_orbital_strike():
	if _mechanics_vfx: _mechanics_vfx.fire_orbital_strike()

func _on_enemy_aura(data):
	if _mechanics_vfx: _mechanics_vfx.handle_enemy_aura(data)

func _update_auras(delta):
	if _mechanics_vfx: _mechanics_vfx.update_auras(delta)
`;

content = content.substring(0, idxB1Start) + b1Replacement + content.substring(idxB1End + b1End.length);

// 4. Reemplazar bloque 2: apply_color_aura hasta remove_color_aura
const b2Start = 'var _color_aura_3d_root: Node3D = null\n\nfunc apply_color_aura(color_name: String):';
const b2End = 'func remove_color_aura():\n\tif is_instance_valid(_color_aura_3d_root):\n\t\t_color_aura_3d_root.queue_free()\n\t_color_aura_3d_root = null\n';

const idxB2Start = content.indexOf(b2Start);
const idxB2End = content.indexOf(b2End, idxB2Start);

if (idxB2Start === -1 || idxB2End === -1) {
    console.error("Bloque 2 not found!", idxB2Start, idxB2End);
    process.exit(1);
}

const b2Replacement = `# ==============================================================================
# AURAS DE COLOR Y WATER ORB (Delegadas en EntityMechanicsVFX)
# ==============================================================================
func apply_color_aura(color_name: String):
	if _mechanics_vfx: _mechanics_vfx.apply_color_aura(color_name)

func remove_color_aura():
	if _mechanics_vfx: _mechanics_vfx.remove_color_aura()

func _setup_water_orb_3d():
	if _mechanics_vfx: _mechanics_vfx.setup_water_orb_3d()
`;

content = content.substring(0, idxB2Start) + b2Replacement + content.substring(idxB2End + b2End.length);

fs.writeFileSync(targetPath, content, 'utf8');
console.log("Reemplazo exitoso en Entity.gd!");
