class_name CampStructures
extends RefCounted
## Factory and classes for 3D camp structures:
## - LumberjackCamp: rustic woodcutter's lodge/shed with pitched roof, rafters,
##   firewood piles, chopping stump with axe, woodcutter banner, and selection ring.
## - MercenaryCamp: authentic medieval canvas pavilion with noble blue & gold trims,
##   canopy entrance, guy ropes, heraldic swallowtail pennant, weapon rack with shields,
##   swords, armor stand, mercenary hiring, and selection ring.

const LOG_PILE_MODEL: String = "res://assets/models/log_pile.glb"
const TREE_STUMP_MODEL: String = "res://assets/models/tree_stump.glb"
const AXE_MODEL: String = "res://assets/models/icon_axe.glb"
const FLAG_MODEL: String = "res://assets/models/icon_flag.glb"
const SWORD_MODEL: String = "res://assets/models/icon_sword.glb"
const MERCENARY_SCENE: String = "res://scenes/mercenary.tscn"


static func create_lumberjack_camp() -> LumberjackCamp:
	var camp := LumberjackCamp.new()
	camp.name = "LumberjackCamp"
	camp.add_to_group(&"camps")
	return camp


static func create_mercenary_camp() -> MercenaryCamp:
	var camp := MercenaryCamp.new()
	camp.name = "MercenaryCamp"
	camp.add_to_group(&"camps")
	return camp


# ==============================================================================
# Lumberjack Camp
# ==============================================================================
class LumberjackCamp extends Node3D:
	signal camp_tapped

	var is_selected: bool = false
	var _selection_ring: MeshInstance3D = null

	func _init() -> void:
		_build_structure()
		_build_interaction()

	func set_selected(selected: bool) -> void:
		is_selected = selected
		if _selection_ring != null:
			_selection_ring.visible = selected

	func select() -> void:
		set_selected(true)

	func deselect() -> void:
		set_selected(false)

	func _build_interaction() -> void:
		# Selection Ring (golden glowing circle at ground level)
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 1.95
		ring_mesh.outer_radius = 2.08
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 4
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.88, 0.35, 0.95)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_selection_ring.mesh = ring_mesh
		_selection_ring.material_override = ring_mat
		_selection_ring.position = Vector3(0.0, 0.04, 0.0)
		_selection_ring.visible = false
		_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_selection_ring)

		# Tap detection via Area3D on collision layer 1
		var area := Area3D.new()
		area.name = "CampArea"
		area.collision_layer = 1
		area.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 2.0
		cyl.height = 2.5
		shape.shape = cyl
		shape.position = Vector3(0.0, 1.25, 0.0)
		area.add_child(shape)
		add_child(area)

	func _build_structure() -> void:
		var dark_wood := StandardMaterial3D.new()
		dark_wood.albedo_color = Color(0.36, 0.24, 0.14)
		dark_wood.roughness = 0.88

		var plank_wood := StandardMaterial3D.new()
		plank_wood.albedo_color = Color(0.48, 0.34, 0.20)
		plank_wood.roughness = 0.82

		var cut_wood := StandardMaterial3D.new()
		cut_wood.albedo_color = Color(0.82, 0.72, 0.48)
		cut_wood.roughness = 0.7

		var metal_mat := StandardMaterial3D.new()
		metal_mat.albedo_color = Color(0.72, 0.75, 0.80)
		metal_mat.metallic = 0.85
		metal_mat.roughness = 0.3

		var banner_mat := StandardMaterial3D.new()
		banner_mat.albedo_color = Color(0.24, 0.42, 0.22)
		banner_mat.roughness = 0.8

		# --- 1. Rustic Timber Lodge / Canopy (LogCanopy) ---
		var canopy := Node3D.new()
		canopy.name = "LogCanopy"
		add_child(canopy)

		# Timber floor / foundation base
		var deck_mesh := BoxMesh.new()
		deck_mesh.material = dark_wood
		deck_mesh.size = Vector3(2.5, 0.08, 1.9)
		var deck := MeshInstance3D.new()
		deck.name = "TimberDeck"
		deck.mesh = deck_mesh
		deck.position = Vector3(0.0, 0.04, 0.0)
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(deck)

		# 6 solid timber support posts
		var post_mesh := CylinderMesh.new()
		post_mesh.material = dark_wood
		post_mesh.top_radius = 0.075
		post_mesh.bottom_radius = 0.085
		post_mesh.height = 1.65
		post_mesh.radial_segments = 8

		var post_coords := [
			Vector3(-1.05, 0.825, -0.75),
			Vector3(0.0, 0.825, -0.75),
			Vector3(1.05, 0.825, -0.75),
			Vector3(-1.05, 0.825, 0.75),
			Vector3(0.0, 0.825, 0.75),
			Vector3(1.05, 0.825, 0.75),
		]
		for i in post_coords.size():
			var post := MeshInstance3D.new()
			post.name = "Post%d" % i
			post.mesh = post_mesh
			post.position = post_coords[i]
			post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(post)

		# Horizontal timber header beams (X-direction)
		var beam_x_mesh := BoxMesh.new()
		beam_x_mesh.material = dark_wood
		beam_x_mesh.size = Vector3(2.4, 0.12, 0.12)

		var beam_back := MeshInstance3D.new()
		beam_back.mesh = beam_x_mesh
		beam_back.position = Vector3(0.0, 1.65, -0.75)
		beam_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(beam_back)

		var beam_front := MeshInstance3D.new()
		beam_front.mesh = beam_x_mesh
		beam_front.position = Vector3(0.0, 1.65, 0.75)
		beam_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(beam_front)

		# Horizontal timber tie beams (Z-direction)
		var beam_z_mesh := BoxMesh.new()
		beam_z_mesh.material = dark_wood
		beam_z_mesh.size = Vector3(0.12, 0.12, 1.62)

		for z_x in [-1.05, 1.05]:
			var bz := MeshInstance3D.new()
			bz.mesh = beam_z_mesh
			bz.position = Vector3(z_x, 1.65, 0.0)
			bz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(bz)

		# Central ridge beam at apex
		var ridge_mesh := BoxMesh.new()
		ridge_mesh.material = dark_wood
		ridge_mesh.size = Vector3(2.5, 0.12, 0.12)
		var ridge := MeshInstance3D.new()
		ridge.name = "RidgeBeam"
		ridge.mesh = ridge_mesh
		ridge.position = Vector3(0.0, 2.05, 0.0)
		ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(ridge)

		# Gable end vertical struts & triangular trusses
		var truss_mesh := BoxMesh.new()
		truss_mesh.material = dark_wood
		truss_mesh.size = Vector3(0.08, 0.4, 0.08)
		for gx in [-1.05, 1.05]:
			var strut := MeshInstance3D.new()
			strut.mesh = truss_mesh
			strut.position = Vector3(gx, 1.85, 0.0)
			strut.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(strut)

		# Sloping rafters under the roof planes
		var rafter_mesh := BoxMesh.new()
		rafter_mesh.material = dark_wood
		rafter_mesh.size = Vector3(0.06, 0.06, 1.05)

		for rx in [-0.9, 0.0, 0.9]:
			var r_back := MeshInstance3D.new()
			r_back.mesh = rafter_mesh
			r_back.position = Vector3(rx, 1.85, -0.42)
			r_back.rotation.x = deg_to_rad(-25.0)
			r_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(r_back)

			var r_front := MeshInstance3D.new()
			r_front.mesh = rafter_mesh
			r_front.position = Vector3(rx, 1.85, 0.42)
			r_front.rotation.x = deg_to_rad(25.0)
			r_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.add_child(r_front)

		# Pitched wooden roof cover: two sloping cedar plank planes
		var roof_half_mesh := BoxMesh.new()
		roof_half_mesh.material = plank_wood
		roof_half_mesh.size = Vector3(2.6, 0.05, 1.05)

		var roof_back := MeshInstance3D.new()
		roof_back.name = "RoofBack"
		roof_back.mesh = roof_half_mesh
		roof_back.position = Vector3(0.0, 1.88, -0.44)
		roof_back.rotation.x = deg_to_rad(-25.0)
		roof_back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(roof_back)

		var roof_front := MeshInstance3D.new()
		roof_front.name = "RoofFront"
		roof_front.mesh = roof_half_mesh
		roof_front.position = Vector3(0.0, 1.88, 0.44)
		roof_front.rotation.x = deg_to_rad(25.0)
		roof_front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(roof_front)

		# Woodcutter banner hanging from front beam
		var banner := MeshInstance3D.new()
		banner.name = "Banner"
		var banner_m := BoxMesh.new()
		banner_m.material = banner_mat
		banner_m.size = Vector3(0.42, 0.65, 0.02)
		banner.mesh = banner_m
		banner.position = Vector3(-0.75, 1.35, 0.78)
		banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.add_child(banner)

		# --- 2. Firewood Piles (Поленницы дров) ---
		var pile_root := Node3D.new()
		pile_root.name = "FirewoodPiles"
		add_child(pile_root)

		if ResourceLoader.exists(LOG_PILE_MODEL):
			var pile_scene: PackedScene = load(LOG_PILE_MODEL)
			var pile1: Node3D = pile_scene.instantiate()
			pile1.position = Vector3(-0.35, 0.08, -0.15)
			pile1.scale = Vector3(0.75, 0.75, 0.75)
			pile1.rotation.y = deg_to_rad(10)
			pile_root.add_child(pile1)
		else:
			# Procedural stacked round firewood logs
			var log_mesh := CylinderMesh.new()
			log_mesh.material = dark_wood
			log_mesh.top_radius = 0.085
			log_mesh.bottom_radius = 0.085
			log_mesh.height = 0.95
			log_mesh.radial_segments = 8

			var log_offsets := [
				Vector3(-0.45, 0.16, -0.2), Vector3(-0.25, 0.16, -0.2), Vector3(-0.05, 0.16, -0.2),
				Vector3(-0.35, 0.31, -0.2), Vector3(-0.15, 0.31, -0.2),
				Vector3(-0.25, 0.46, -0.2)
			]
			for offset in log_offsets:
				var l := MeshInstance3D.new()
				l.mesh = log_mesh
				l.rotation.z = deg_to_rad(90)
				l.position = offset
				l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pile_root.add_child(l)

		# --- 3. Chopping Stump with Axe (Чурбак с топором) ---
		var stump_root := Node3D.new()
		stump_root.name = "ChoppingStump"
		stump_root.position = Vector3(0.9, 0.0, 1.05)
		add_child(stump_root)

		if ResourceLoader.exists(TREE_STUMP_MODEL):
			var stump_scene: PackedScene = load(TREE_STUMP_MODEL)
			var stump: Node3D = stump_scene.instantiate()
			stump.scale = Vector3(0.55, 0.55, 0.55)
			stump_root.add_child(stump)
		else:
			var stump_mesh := CylinderMesh.new()
			stump_mesh.material = dark_wood
			stump_mesh.top_radius = 0.28
			stump_mesh.bottom_radius = 0.34
			stump_mesh.height = 0.48
			stump_mesh.radial_segments = 10
			var sm := MeshInstance3D.new()
			sm.mesh = stump_mesh
			sm.position.y = 0.24
			stump_root.add_child(sm)

			var cap_mesh := CylinderMesh.new()
			cap_mesh.material = cut_wood
			cap_mesh.top_radius = 0.26
			cap_mesh.bottom_radius = 0.26
			cap_mesh.height = 0.02
			var cap := MeshInstance3D.new()
			cap.mesh = cap_mesh
			cap.position.y = 0.48
			stump_root.add_child(cap)

		# Axe embedded in the stump
		if ResourceLoader.exists(AXE_MODEL):
			var axe_scene: PackedScene = load(AXE_MODEL)
			var axe: Node3D = axe_scene.instantiate()
			axe.name = "Axe"
			axe.position = Vector3(0.0, 0.38, 0.0)
			axe.rotation.x = deg_to_rad(22)
			axe.rotation.y = deg_to_rad(45)
			axe.scale = Vector3(0.48, 0.48, 0.48)
			stump_root.add_child(axe)
		else:
			# Procedural woodcutter axe
			var handle_mesh := CylinderMesh.new()
			handle_mesh.material = dark_wood
			handle_mesh.top_radius = 0.022
			handle_mesh.bottom_radius = 0.025
			handle_mesh.height = 0.65
			var handle := MeshInstance3D.new()
			handle.mesh = handle_mesh
			handle.position = Vector3(0.08, 0.55, 0.0)
			handle.rotation.z = deg_to_rad(-28)
			stump_root.add_child(handle)

			var axe_head := BoxMesh.new()
			axe_head.material = metal_mat
			axe_head.size = Vector3(0.04, 0.14, 0.2)
			var ahm := MeshInstance3D.new()
			ahm.mesh = axe_head
			ahm.position = Vector3(0.0, 0.48, 0.0)
			stump_root.add_child(ahm)


# ==============================================================================
# Mercenary Camp
# ==============================================================================
class MercenaryCamp extends Node3D:
	const HIRE_COST: int = 40
	signal mercenary_hired(mercenary: Mercenary)
	signal camp_tapped

	var game_state: GameState = null
	var sim: Sim = null
	var hero: Hero = null
	var gate_position: Vector3 = Vector3.ZERO
	var mercenaries: Array[Mercenary] = []
	var is_selected: bool = false

	var _selection_ring: MeshInstance3D = null

	func _init() -> void:
		_build_structure()
		_build_interaction()

	func set_selected(selected: bool) -> void:
		is_selected = selected
		if _selection_ring != null:
			_selection_ring.visible = selected

	func select() -> void:
		set_selected(true)

	func deselect() -> void:
		set_selected(false)

	func _build_interaction() -> void:
		# Selection Ring (noble golden glowing circle at ground level)
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 2.15
		ring_mesh.outer_radius = 2.28
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 4
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.88, 0.35, 0.95)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_selection_ring.mesh = ring_mesh
		_selection_ring.material_override = ring_mat
		_selection_ring.position = Vector3(0.0, 0.04, 0.0)
		_selection_ring.visible = false
		_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_selection_ring)

		# Tap detection via Area3D on collision layer 1
		var area := Area3D.new()
		area.name = "CampArea"
		area.collision_layer = 1
		area.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 2.3
		cyl.height = 2.8
		shape.shape = cyl
		shape.position = Vector3(0.0, 1.4, 0.0)
		area.add_child(shape)
		add_child(area)

	func _build_structure() -> void:
		# Authentic medieval materials
		var canvas_mat := StandardMaterial3D.new()
		canvas_mat.albedo_color = Color(0.88, 0.85, 0.78)  # Natural warm linen cloth
		canvas_mat.roughness = 0.85

		var blue_mat := StandardMaterial3D.new()
		blue_mat.albedo_color = Color(0.18, 0.32, 0.62)    # Noble royal blue matching knight
		blue_mat.roughness = 0.65

		var gold_mat := StandardMaterial3D.new()
		gold_mat.albedo_color = Color(0.88, 0.74, 0.25)    # Heraldic brass/gold
		gold_mat.roughness = 0.45
		gold_mat.metallic = 0.25

		var dark_wood := StandardMaterial3D.new()
		dark_wood.albedo_color = Color(0.38, 0.26, 0.16)
		dark_wood.roughness = 0.85

		var dark_inside := StandardMaterial3D.new()
		dark_inside.albedo_color = Color(0.12, 0.10, 0.09)
		dark_inside.roughness = 0.95

		var steel_mat := StandardMaterial3D.new()
		steel_mat.albedo_color = Color(0.78, 0.80, 0.84)
		steel_mat.metallic = 0.85
		steel_mat.roughness = 0.25

		# --- 1. Authentic Canvas Pavilion (Tent) ---
		var tent := Node3D.new()
		tent.name = "Tent"
		add_child(tent)

		# 12-sided faceted canvas pavilion walls
		var wall_mesh := CylinderMesh.new()
		wall_mesh.material = canvas_mat
		wall_mesh.top_radius = 1.38
		wall_mesh.bottom_radius = 1.45
		wall_mesh.height = 1.25
		wall_mesh.radial_segments = 12

		var wall := MeshInstance3D.new()
		wall.name = "TentWall"
		wall.mesh = wall_mesh
		wall.position = Vector3(0.0, 0.625, 0.0)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(wall)

		# Noble blue valance border ring at the eaves
		var valance_mesh := CylinderMesh.new()
		valance_mesh.material = blue_mat
		valance_mesh.top_radius = 1.48
		valance_mesh.bottom_radius = 1.49
		valance_mesh.height = 0.16
		valance_mesh.radial_segments = 12

		var valance := MeshInstance3D.new()
		valance.name = "EavesValance"
		valance.mesh = valance_mesh
		valance.position = Vector3(0.0, 1.22, 0.0)
		valance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(valance)

		# Gold trim ribbon just above valance
		var trim_mesh := CylinderMesh.new()
		trim_mesh.material = gold_mat
		trim_mesh.top_radius = 1.495
		trim_mesh.bottom_radius = 1.495
		trim_mesh.height = 0.04
		trim_mesh.radial_segments = 12

		var trim_ring := MeshInstance3D.new()
		trim_ring.mesh = trim_mesh
		trim_ring.position = Vector3(0.0, 1.30, 0.0)
		trim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(trim_ring)

		# Conical canvas pavilion roof
		var roof_mesh := CylinderMesh.new()
		roof_mesh.material = canvas_mat
		roof_mesh.top_radius = 0.08
		roof_mesh.bottom_radius = 1.48
		roof_mesh.height = 1.25
		roof_mesh.radial_segments = 12

		var roof := MeshInstance3D.new()
		roof.name = "TentRoof"
		roof.mesh = roof_mesh
		roof.position = Vector3(0.0, 1.88, 0.0)
		roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(roof)

		# Brass pinnacle finial atop pavilion peak
		var finial_mesh := CylinderMesh.new()
		finial_mesh.material = gold_mat
		finial_mesh.top_radius = 0.01
		finial_mesh.bottom_radius = 0.07
		finial_mesh.height = 0.35
		finial_mesh.radial_segments = 8

		var finial := MeshInstance3D.new()
		finial.name = "RoofFinial"
		finial.mesh = finial_mesh
		finial.position = Vector3(0.0, 2.65, 0.0)
		finial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(finial)

		# Tent entrance opening (dark interior)
		var door_mesh := BoxMesh.new()
		door_mesh.material = dark_inside
		door_mesh.size = Vector3(0.72, 1.05, 0.05)
		var door := MeshInstance3D.new()
		door.name = "Entrance"
		door.mesh = door_mesh
		door.position = Vector3(0.0, 0.525, 1.42)
		door.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(door)

		# Entrance canopy awning
		var awning_mesh := BoxMesh.new()
		awning_mesh.material = blue_mat
		awning_mesh.size = Vector3(1.15, 0.035, 0.8)

		var awning := MeshInstance3D.new()
		awning.name = "CanopyAwning"
		awning.mesh = awning_mesh
		awning.position = Vector3(0.0, 1.28, 1.76)
		awning.rotation.x = deg_to_rad(-18.0)
		awning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(awning)

		# 2 wooden awning support poles
		var pole_m := CylinderMesh.new()
		pole_m.material = dark_wood
		pole_m.top_radius = 0.03
		pole_m.bottom_radius = 0.035
		pole_m.height = 1.2
		pole_m.radial_segments = 6

		for px in [-0.52, 0.52]:
			var ap := MeshInstance3D.new()
			ap.mesh = pole_m
			ap.position = Vector3(px, 0.6, 2.12)
			ap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tent.add_child(ap)

		# Guy ropes with wooden stakes around pavilion
		var rope_mesh := CylinderMesh.new()
		rope_mesh.material = dark_wood
		rope_mesh.top_radius = 0.012
		rope_mesh.bottom_radius = 0.012
		rope_mesh.height = 1.35
		rope_mesh.radial_segments = 4

		var stake_mesh := CylinderMesh.new()
		stake_mesh.material = dark_wood
		stake_mesh.top_radius = 0.03
		stake_mesh.bottom_radius = 0.01
		stake_mesh.height = 0.25
		stake_mesh.radial_segments = 6

		for deg in [60, 120, 180, 240, 300]:
			var rad := deg_to_rad(float(deg))
			var rope_pivot := Node3D.new()
			rope_pivot.rotation.y = rad
			tent.add_child(rope_pivot)

			var rope := MeshInstance3D.new()
			rope.mesh = rope_mesh
			rope.position = Vector3(0.0, 0.625, (1.48 + 2.15) * 0.5)
			rope.rotation.x = deg_to_rad(-28.2)
			rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rope_pivot.add_child(rope)

			var stake := MeshInstance3D.new()
			stake.mesh = stake_mesh
			stake.position = Vector3(0.0, 0.08, 2.15)
			stake.rotation.x = deg_to_rad(-20.0)
			stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rope_pivot.add_child(stake)

		# --- 2. Flagpole with Medieval Swallowtail Pennant (Flagpole) ---
		var flagpole := Node3D.new()
		flagpole.name = "Flagpole"
		flagpole.position = Vector3(1.85, 0.0, 0.3)
		add_child(flagpole)

		var mast_mesh := CylinderMesh.new()
		mast_mesh.material = dark_wood
		mast_mesh.top_radius = 0.04
		mast_mesh.bottom_radius = 0.05
		mast_mesh.height = 3.6
		mast_mesh.radial_segments = 8

		var mast := MeshInstance3D.new()
		mast.mesh = mast_mesh
		mast.position.y = 1.8
		mast.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(mast)

		# Brass spearhead finial
		var spear_finial := MeshInstance3D.new()
		spear_finial.mesh = finial_mesh
		spear_finial.position.y = 3.7
		spear_finial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(spear_finial)

		# Swallowtail Heraldic Pennant (two forked tails)
		var pennant_body_mesh := BoxMesh.new()
		pennant_body_mesh.material = blue_mat
		pennant_body_mesh.size = Vector3(0.65, 0.45, 0.02)

		var pennant_body := MeshInstance3D.new()
		pennant_body.mesh = pennant_body_mesh
		pennant_body.position = Vector3(0.36, 3.25, 0.0)
		pennant_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(pennant_body)

		# Gold heraldic cross on pennant body
		var cross_v_mesh := BoxMesh.new()
		cross_v_mesh.material = gold_mat
		cross_v_mesh.size = Vector3(0.08, 0.32, 0.03)
		var cross_v := MeshInstance3D.new()
		cross_v.mesh = cross_v_mesh
		cross_v.position = Vector3(0.36, 3.25, 0.0)
		cross_v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(cross_v)

		var cross_h_mesh := BoxMesh.new()
		cross_h_mesh.material = gold_mat
		cross_h_mesh.size = Vector3(0.32, 0.08, 0.03)
		var cross_h := MeshInstance3D.new()
		cross_h.mesh = cross_h_mesh
		cross_h.position = Vector3(0.36, 3.25, 0.0)
		cross_h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(cross_h)

		# Swallowtail fork upper tail
		var tail_top_mesh := BoxMesh.new()
		tail_top_mesh.material = blue_mat
		tail_top_mesh.size = Vector3(0.42, 0.16, 0.02)
		var tail_top := MeshInstance3D.new()
		tail_top.mesh = tail_top_mesh
		tail_top.position = Vector3(0.85, 3.38, 0.0)
		tail_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(tail_top)

		# Swallowtail fork lower tail
		var tail_bot_mesh := BoxMesh.new()
		tail_bot_mesh.material = blue_mat
		tail_bot_mesh.size = Vector3(0.42, 0.16, 0.02)
		var tail_bot := MeshInstance3D.new()
		tail_bot.mesh = tail_bot_mesh
		tail_bot.position = Vector3(0.85, 3.12, 0.0)
		tail_bot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(tail_bot)

		# Gold edge trim on tail ends
		var gold_tip_m := BoxMesh.new()
		gold_tip_m.material = gold_mat
		gold_tip_m.size = Vector3(0.08, 0.16, 0.025)
		var tip1 := MeshInstance3D.new()
		tip1.mesh = gold_tip_m
		tip1.position = Vector3(1.02, 3.38, 0.0)
		flagpole.add_child(tip1)
		var tip2 := MeshInstance3D.new()
		tip2.mesh = gold_tip_m
		tip2.position = Vector3(1.02, 3.12, 0.0)
		flagpole.add_child(tip2)

		# --- 3. Weapon Rack & Armor Stand (WeaponRack) ---
		var rack := Node3D.new()
		rack.name = "WeaponRack"
		rack.position = Vector3(-1.7, 0.0, 0.5)
		rack.rotation.y = deg_to_rad(35)
		add_child(rack)

		var stand_mesh := BoxMesh.new()
		stand_mesh.material = dark_wood
		stand_mesh.size = Vector3(0.09, 1.15, 0.09)

		var stand_l := MeshInstance3D.new()
		stand_l.mesh = stand_mesh
		stand_l.position = Vector3(-0.48, 0.58, 0.0)
		stand_l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rack.add_child(stand_l)

		var stand_r := MeshInstance3D.new()
		stand_r.mesh = stand_mesh
		stand_r.position = Vector3(0.48, 0.58, 0.0)
		stand_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rack.add_child(stand_r)

		var cross_mesh := BoxMesh.new()
		cross_mesh.material = dark_wood
		cross_mesh.size = Vector3(1.2, 0.09, 0.09)

		var crossbar := MeshInstance3D.new()
		crossbar.mesh = cross_mesh
		crossbar.position = Vector3(0.0, 0.8, 0.0)
		crossbar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rack.add_child(crossbar)

		# Swords on the rack
		if ResourceLoader.exists(SWORD_MODEL):
			var sword_scene: PackedScene = load(SWORD_MODEL)
			var sword1: Node3D = sword_scene.instantiate()
			sword1.position = Vector3(-0.25, 0.48, 0.06)
			sword1.rotation.x = deg_to_rad(15)
			sword1.scale = Vector3(0.48, 0.48, 0.48)
			rack.add_child(sword1)

			var sword2: Node3D = sword_scene.instantiate()
			sword2.position = Vector3(0.25, 0.48, 0.06)
			sword2.rotation.x = deg_to_rad(15)
			sword2.scale = Vector3(0.48, 0.48, 0.48)
			rack.add_child(sword2)
		else:
			# Procedural steel swords
			var blade_m := BoxMesh.new()
			blade_m.material = steel_mat
			blade_m.size = Vector3(0.05, 0.8, 0.02)
			var hilt_m := BoxMesh.new()
			hilt_m.material = gold_mat
			hilt_m.size = Vector3(0.18, 0.03, 0.03)

			for sx in [-0.22, 0.22]:
				var sw := Node3D.new()
				sw.position = Vector3(sx, 0.45, 0.06)
				sw.rotation.x = deg_to_rad(12)
				var b := MeshInstance3D.new()
				b.mesh = blade_m
				sw.add_child(b)
				var h := MeshInstance3D.new()
				h.mesh = hilt_m
				h.position.y = 0.32
				sw.add_child(h)
				rack.add_child(sw)

		# Knight Shields on rack (noble blue + gold trim + steel boss)
		var shield_mesh := CylinderMesh.new()
		shield_mesh.material = blue_mat
		shield_mesh.top_radius = 0.26
		shield_mesh.bottom_radius = 0.26
		shield_mesh.height = 0.04
		shield_mesh.radial_segments = 12

		var boss_mesh := CylinderMesh.new()
		boss_mesh.material = steel_mat
		boss_mesh.top_radius = 0.07
		boss_mesh.bottom_radius = 0.08
		boss_mesh.height = 0.03
		boss_mesh.radial_segments = 8

		var shield := MeshInstance3D.new()
		shield.mesh = shield_mesh
		shield.position = Vector3(0.0, 0.52, 0.07)
		shield.rotation.x = deg_to_rad(85)
		shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rack.add_child(shield)

		var boss := MeshInstance3D.new()
		boss.mesh = boss_mesh
		boss.position = Vector3(0.0, 0.03, 0.0)
		shield.add_child(boss)

		# Armor Stand (Knight Dummy) next to weapon rack
		var armor_stand := Node3D.new()
		armor_stand.name = "ArmorStand"
		armor_stand.position = Vector3(-0.95, 0.0, -0.2)
		rack.add_child(armor_stand)

		var stand_post_mesh := CylinderMesh.new()
		stand_post_mesh.material = dark_wood
		stand_post_mesh.top_radius = 0.04
		stand_post_mesh.bottom_radius = 0.05
		stand_post_mesh.height = 1.3
		stand_post_mesh.radial_segments = 6

		var dummy_post := MeshInstance3D.new()
		dummy_post.mesh = stand_post_mesh
		dummy_post.position.y = 0.65
		dummy_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		armor_stand.add_child(dummy_post)

		# Crossbar for shoulders
		var shoulder_mesh := BoxMesh.new()
		shoulder_mesh.material = dark_wood
		shoulder_mesh.size = Vector3(0.55, 0.06, 0.06)
		var shoulder := MeshInstance3D.new()
		shoulder.mesh = shoulder_mesh
		shoulder.position.y = 1.05
		shoulder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		armor_stand.add_child(shoulder)

		# Steel knight breastplate / cuirass
		var cuirass_mesh := BoxMesh.new()
		cuirass_mesh.material = steel_mat
		cuirass_mesh.size = Vector3(0.38, 0.45, 0.22)
		var cuirass := MeshInstance3D.new()
		cuirass.mesh = cuirass_mesh
		cuirass.position.y = 0.88
		cuirass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		armor_stand.add_child(cuirass)

		# Steel knight helmet on top
		var helm_mesh := CylinderMesh.new()
		helm_mesh.material = steel_mat
		helm_mesh.top_radius = 0.11
		helm_mesh.bottom_radius = 0.12
		helm_mesh.height = 0.22
		helm_mesh.radial_segments = 10
		var helm := MeshInstance3D.new()
		helm.mesh = helm_mesh
		helm.position.y = 1.25
		helm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		armor_stand.add_child(helm)

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
