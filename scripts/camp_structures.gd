class_name CampStructures
extends RefCounted
## Factory and classes for 3D camp structures:
## - LumberjackCamp: log canopy, firewood piles, chopping stump with axe.
## - MercenaryCamp: pavilion tent, flagpole with pennant, weapon rack with swords & shields,
##   plus mercenary hiring capability.

const LOG_PILE_MODEL: String = "res://assets/models/log_pile.glb"
const TREE_STUMP_MODEL: String = "res://assets/models/tree_stump.glb"
const AXE_MODEL: String = "res://assets/models/icon_axe.glb"
const FLAG_MODEL: String = "res://assets/models/icon_flag.glb"
const SWORD_MODEL: String = "res://assets/models/icon_sword.glb"
const MERCENARY_SCENE: String = "res://scenes/mercenary.tscn"


static func create_lumberjack_camp() -> LumberjackCamp:
	var camp := LumberjackCamp.new()
	camp.name = "LumberjackCamp"
	return camp


static func create_mercenary_camp() -> MercenaryCamp:
	var camp := MercenaryCamp.new()
	camp.name = "MercenaryCamp"
	return camp


# ==============================================================================
# Lumberjack Camp
# ==============================================================================
class LumberjackCamp extends Node3D:
	func _init() -> void:
		_build_structure()

	func _build_structure() -> void:
		var wood_mat := StandardMaterial3D.new()
		wood_mat.albedo_color = Color(0.42, 0.28, 0.16)
		wood_mat.roughness = 0.85

		var cut_mat := StandardMaterial3D.new()
		cut_mat.albedo_color = Color(0.82, 0.72, 0.48)
		cut_mat.roughness = 0.7

		# --- 1. Log Canopy (Навес из бревен) ---
		var canopy := Node3D.new()
		canopy.name = "LogCanopy"
		add_child(canopy)

		# 4 vertical log posts
		var post_mesh := CylinderMesh.new()
		post_mesh.material = wood_mat
		post_mesh.top_radius = 0.08
		post_mesh.bottom_radius = 0.08
		post_mesh.height = 1.8
		post_mesh.radial_segments = 6

		var post_coords := [
			Vector3(-1.0, 0.9, -0.7),
			Vector3(1.0, 0.9, -0.7),
			Vector3(-1.0, 0.9, 0.7),
			Vector3(1.0, 0.9, 0.7),
		]
		for i in post_coords.size():
			var post := MeshInstance3D.new()
			post.name = "Post%d" % i
			post.mesh = post_mesh
			post.position = post_coords[i]
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(post)

		# Horizontal frame beams
		var beam_x_mesh := BoxMesh.new()
		beam_x_mesh.material = wood_mat
		beam_x_mesh.size = Vector3(2.2, 0.12, 0.12)

		var beam_front := MeshInstance3D.new()
		beam_front.mesh = beam_x_mesh
		beam_front.position = Vector3(0.0, 1.75, 0.7)
		beam_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(beam_front)

		var beam_back := MeshInstance3D.new()
		beam_back.mesh = beam_x_mesh
		beam_back.position = Vector3(0.0, 1.9, -0.7)
		beam_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(beam_back)

		# Slanted roof cover
		var roof_mesh := BoxMesh.new()
		roof_mesh.material = wood_mat
		roof_mesh.size = Vector3(2.35, 0.06, 1.65)

		var roof := MeshInstance3D.new()
		roof.name = "CanopyRoof"
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, 1.88, 0.0)
		roof.rotation.x = deg_to_rad(-6.0)
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(roof)

		# --- 2. Firewood Piles (Поленницы дров) ---
		var pile_root := Node3D.new()
		pile_root.name = "FirewoodPiles"
		add_child(pile_root)

		if ResourceLoader.exists(LOG_PILE_MODEL):
			var pile_scene: PackedScene = load(LOG_PILE_MODEL)
			var pile1: Node3D = pile_scene.instantiate()
			pile1.position = Vector3(0.3, 0.0, -0.2)
			pile1.scale = Vector3(0.8, 0.8, 0.8)
			pile1.rotation.y = deg_to_rad(15)
			pile_root.add_child(pile1)

			var pile2: Node3D = pile_scene.instantiate()
			pile2.position = Vector3(-0.5, 0.0, -0.3)
			pile2.scale = Vector3(0.65, 0.65, 0.65)
			pile2.rotation.y = deg_to_rad(-40)
			pile_root.add_child(pile2)
		else:
			# Procedural stacked logs
			var log_mesh := CylinderMesh.new()
			log_mesh.material = wood_mat
			log_mesh.top_radius = 0.09
			log_mesh.bottom_radius = 0.09
			log_mesh.height = 1.0
			log_mesh.radial_segments = 6

			var log_offsets := [
				Vector3(-0.4, 0.09, -0.2), Vector3(-0.2, 0.09, -0.2), Vector3(0.0, 0.09, -0.2),
				Vector3(-0.3, 0.24, -0.2), Vector3(-0.1, 0.24, -0.2),
				Vector3(-0.2, 0.38, -0.2)
			]
			for offset in log_offsets:
				var l := MeshInstance3D.new()
				l.mesh = log_mesh
				l.rotation.z = deg_to_rad(90)
				l.position = offset
				pile_root.add_child(l)

		# --- 3. Chopping Stump with Axe (Чурбак с топором) ---
		var stump_root := Node3D.new()
		stump_root.name = "ChoppingStump"
		stump_root.position = Vector3(0.8, 0.0, 1.1)
		add_child(stump_root)

		if ResourceLoader.exists(TREE_STUMP_MODEL):
			var stump_scene: PackedScene = load(TREE_STUMP_MODEL)
			var stump: Node3D = stump_scene.instantiate()
			stump.scale = Vector3(0.55, 0.55, 0.55)
			stump_root.add_child(stump)
		else:
			var stump_mesh := CylinderMesh.new()
			stump_mesh.material = wood_mat
			stump_mesh.top_radius = 0.3
			stump_mesh.bottom_radius = 0.35
			stump_mesh.height = 0.5
			var sm := MeshInstance3D.new()
			sm.mesh = stump_mesh
			sm.position.y = 0.25
			stump_root.add_child(sm)

		# Axe embedded in the stump
		if ResourceLoader.exists(AXE_MODEL):
			var axe_scene: PackedScene = load(AXE_MODEL)
			var axe: Node3D = axe_scene.instantiate()
			axe.name = "Axe"
			axe.position = Vector3(0.0, 0.35, 0.0)
			axe.rotation.x = deg_to_rad(25)
			axe.rotation.y = deg_to_rad(45)
			axe.scale = Vector3(0.45, 0.45, 0.45)
			stump_root.add_child(axe)
		else:
			var metal_mat := StandardMaterial3D.new()
			metal_mat.albedo_color = Color(0.7, 0.72, 0.75)
			metal_mat.metallic = 0.8
			var axe_head := BoxMesh.new()
			axe_head.material = metal_mat
			axe_head.size = Vector3(0.04, 0.15, 0.2)
			var ahm := MeshInstance3D.new()
			ahm.mesh = axe_head
			ahm.position = Vector3(0.0, 0.45, 0.0)
			stump_root.add_child(ahm)


# ==============================================================================
# Mercenary Camp
# ==============================================================================
class MercenaryCamp extends Node3D:
	const HIRE_COST: int = 40
	signal mercenary_hired(mercenary: Mercenary)

	var game_state: GameState = null
	var sim: Sim = null
	var hero: Hero = null
	var gate_position: Vector3 = Vector3.ZERO
	var mercenaries: Array[Mercenary] = []

	func _init() -> void:
		_build_structure()

	func _build_structure() -> void:
		var tent_mat := StandardMaterial3D.new()
		tent_mat.albedo_color = Color(0.22, 0.36, 0.58)
		tent_mat.roughness = 0.8

		var trim_mat := StandardMaterial3D.new()
		trim_mat.albedo_color = Color(0.85, 0.72, 0.25)
		trim_mat.roughness = 0.6

		var wood_mat := StandardMaterial3D.new()
		wood_mat.albedo_color = Color(0.45, 0.3, 0.18)

		var metal_mat := StandardMaterial3D.new()
		metal_mat.albedo_color = Color(0.75, 0.78, 0.82)
		metal_mat.metallic = 0.7
		metal_mat.roughness = 0.3

		# --- 1. Tent / Pavilion (Шатёр/палатка) ---
		var tent := Node3D.new()
		tent.name = "Tent"
		add_child(tent)

		# Tent walls
		var wall_mesh := CylinderMesh.new()
		wall_mesh.material = tent_mat
		wall_mesh.top_radius = 1.15
		wall_mesh.bottom_radius = 1.25
		wall_mesh.height = 1.2
		wall_mesh.radial_segments = 8

		var wall := MeshInstance3D.new()
		wall.name = "TentWall"
		wall.mesh = wall_mesh
		wall.position = Vector3(0.0, 0.6, 0.0)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(wall)

		# Conical tent roof
		var roof_mesh := CylinderMesh.new()
		roof_mesh.material = trim_mat
		roof_mesh.top_radius = 0.05
		roof_mesh.bottom_radius = 1.35
		roof_mesh.height = 1.1
		roof_mesh.radial_segments = 8

		var roof := MeshInstance3D.new()
		roof.name = "TentRoof"
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, 1.7, 0.0)
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(roof)

		# --- 2. Flagpole with Pennant (Флагшток с вымпелом) ---
		var flagpole := Node3D.new()
		flagpole.name = "Flagpole"
		flagpole.position = Vector3(1.7, 0.0, -0.4)
		add_child(flagpole)

		var pole_mesh := CylinderMesh.new()
		pole_mesh.material = wood_mat
		pole_mesh.top_radius = 0.04
		pole_mesh.bottom_radius = 0.05
		pole_mesh.height = 3.2
		pole_mesh.radial_segments = 6

		var pole := MeshInstance3D.new()
		pole.mesh = pole_mesh
		pole.position.y = 1.6
		flagpole.add_child(pole)

		if ResourceLoader.exists(FLAG_MODEL):
			var flag_scene: PackedScene = load(FLAG_MODEL)
			var flag: Node3D = flag_scene.instantiate()
			flag.position = Vector3(0.0, 2.7, 0.0)
			flag.scale = Vector3(0.7, 0.7, 0.7)
			flagpole.add_child(flag)
		else:
			var banner_mat := StandardMaterial3D.new()
			banner_mat.albedo_color = Color(0.85, 0.2, 0.2)
			var banner_mesh := BoxMesh.new()
			banner_mesh.material = banner_mat
			banner_mesh.size = Vector3(0.6, 0.35, 0.03)
			var banner := MeshInstance3D.new()
			banner.mesh = banner_mesh
			banner.position = Vector3(0.32, 2.9, 0.0)
			flagpole.add_child(banner)

		# --- 3. Weapon Rack with Swords & Shields (Стойка с мечами/щитами) ---
		var rack := Node3D.new()
		rack.name = "WeaponRack"
		rack.position = Vector3(-1.6, 0.0, 0.6)
		rack.rotation.y = deg_to_rad(45)
		add_child(rack)

		var stand_mesh := BoxMesh.new()
		stand_mesh.material = wood_mat
		stand_mesh.size = Vector3(0.08, 1.1, 0.08)

		var stand_l := MeshInstance3D.new()
		stand_l.mesh = stand_mesh
		stand_l.position = Vector3(-0.45, 0.55, 0.0)
		rack.add_child(stand_l)

		var stand_r := MeshInstance3D.new()
		stand_r.mesh = stand_mesh
		stand_r.position = Vector3(0.45, 0.55, 0.0)
		rack.add_child(stand_r)

		var cross_mesh := BoxMesh.new()
		cross_mesh.material = wood_mat
		cross_mesh.size = Vector3(1.1, 0.08, 0.08)

		var crossbar := MeshInstance3D.new()
		crossbar.mesh = cross_mesh
		crossbar.position = Vector3(0.0, 0.75, 0.0)
		rack.add_child(crossbar)

		# Swords on the rack
		if ResourceLoader.exists(SWORD_MODEL):
			var sword_scene: PackedScene = load(SWORD_MODEL)
			var sword1: Node3D = sword_scene.instantiate()
			sword1.position = Vector3(-0.2, 0.45, 0.05)
			sword1.rotation.x = deg_to_rad(15)
			sword1.scale = Vector3(0.45, 0.45, 0.45)
			rack.add_child(sword1)

			var sword2: Node3D = sword_scene.instantiate()
			sword2.position = Vector3(0.2, 0.45, 0.05)
			sword2.rotation.x = deg_to_rad(15)
			sword2.scale = Vector3(0.45, 0.45, 0.45)
			rack.add_child(sword2)

		# Round shields on the rack
		var shield_mat := StandardMaterial3D.new()
		shield_mat.albedo_color = Color(0.25, 0.45, 0.65)
		shield_mat.roughness = 0.5

		var shield_mesh := CylinderMesh.new()
		shield_mesh.material = shield_mat
		shield_mesh.top_radius = 0.24
		shield_mesh.bottom_radius = 0.24
		shield_mesh.height = 0.04
		shield_mesh.radial_segments = 8

		var shield := MeshInstance3D.new()
		shield.mesh = shield_mesh
		shield.position = Vector3(0.0, 0.5, 0.06)
		shield.rotation.x = deg_to_rad(85)
		rack.add_child(shield)

	## Hires a mercenary for 40 gold and registers it with the simulation.
	func hire_mercenary(gs: GameState = null, s: Sim = null) -> Mercenary:
		var target_gs := gs if gs != null else game_state
		var target_sim := s if s != null else sim
		if target_gs != null and not target_gs.spend(Vector2i(HIRE_COST, 0)):
			return null

		var merc: Mercenary = null
		if ResourceLoader.exists(MERCENARY_SCENE):
			var scene: PackedScene = load(MERCENARY_SCENE)
			merc = scene.instantiate() as Mercenary
		else:
			merc = Mercenary.new()

		var spawn_pos: Vector3 = global_position + Vector3(0.8, 0.0, 1.2)
		merc.position = spawn_pos
		merc.patrol_center = gate_position if gate_position != Vector3.ZERO else spawn_pos
		merc.hero = hero
		add_sibling(merc)
		mercenaries.append(merc)

		if target_sim != null:
			target_sim.add_mercenary(merc)

		mercenary_hired.emit(merc)
		return merc
