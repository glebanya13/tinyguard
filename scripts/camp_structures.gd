# gdlint:disable=max-file-lines
class_name CampStructures
extends RefCounted
## Factory and classes for 3D camp structures:
## - LumberjackCamp: rustic woodcutter's lodge/shed with pitched roof, rafters,
##   firewood piles, chopping stump with axe, woodcutter banner, and selection ring.
## - MercenaryCamp: authentic medieval canvas pavilion with noble blue & gold trims,
##   canopy entrance, guy ropes, heraldic swallowtail pennant, weapon rack with shields,
##   swords, armor stand, mercenary hiring, and selection ring.

const CAMP_MODEL: String = "res://assets/models/camp_lumber.glb"
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
class LumberjackCamp:
	extends Node3D
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
		# Ambient Ring (permanently visible warm translucent yellow circle on the ground)
		var ambient_ring := MeshInstance3D.new()
		ambient_ring.name = "AmbientRing"
		var amb_mesh := TorusMesh.new()
		amb_mesh.inner_radius = 1.95
		amb_mesh.outer_radius = 2.05
		amb_mesh.rings = 24
		amb_mesh.ring_segments = 4
		var amb_mat := StandardMaterial3D.new()
		amb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amb_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.4)
		amb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ambient_ring.mesh = amb_mesh
		ambient_ring.material_override = amb_mat
		ambient_ring.position = Vector3(0.0, 0.03, 0.0)
		ambient_ring.visible = true
		ambient_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ambient_ring)

		# Selection Ring (solid gold glowing circle at ground level when selected)
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 1.95
		ring_mesh.outer_radius = 2.08
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 4
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.9, 0.2, 1.0)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_selection_ring.mesh = ring_mesh
		_selection_ring.material_override = ring_mat
		_selection_ring.position = Vector3(0.0, 0.05, 0.0)
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
		# Lodge, firewood stack, chopping block with axe and banner are one baked model
		# (assets/blender/build_camp.py): one mesh, one draw call, the shared palette material.
		var model: Node3D = (load(CAMP_MODEL) as PackedScene).instantiate()
		model.name = "LogCanopy"
		add_child(model)


# ==============================================================================
# Mercenary Camp
# ==============================================================================
class MercenaryCamp:
	extends Node3D
	signal mercenary_hired(mercenary: Mercenary)
	signal camp_tapped

	## Prices, the limit of living knights and their stats (resources/mercenary.tres).
	var config: MercenaryConfig = Mercenary.CONFIG
	## Hires this battle (the dead count too): every hire makes the next one dearer.
	var hired_total: int = 0

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
		# Ambient Ring (permanently visible warm translucent yellow circle on the ground)
		var ambient_ring := MeshInstance3D.new()
		ambient_ring.name = "AmbientRing"
		var amb_mesh := TorusMesh.new()
		amb_mesh.inner_radius = 2.15
		amb_mesh.outer_radius = 2.25
		amb_mesh.rings = 24
		amb_mesh.ring_segments = 4
		var amb_mat := StandardMaterial3D.new()
		amb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amb_mat.albedo_color = Color(1.0, 0.85, 0.2, 0.4)
		amb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ambient_ring.mesh = amb_mesh
		ambient_ring.material_override = amb_mat
		ambient_ring.position = Vector3(0.0, 0.03, 0.0)
		ambient_ring.visible = true
		ambient_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ambient_ring)

		# Selection Ring (noble golden glowing circle at ground level when selected)
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionRing"
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 2.15
		ring_mesh.outer_radius = 2.28
		ring_mesh.rings = 24
		ring_mesh.ring_segments = 4
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.albedo_color = Color(1.0, 0.9, 0.2, 1.0)
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_selection_ring.mesh = ring_mesh
		_selection_ring.material_override = ring_mat
		_selection_ring.position = Vector3(0.0, 0.05, 0.0)
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
		# Authentic refined medieval materials
		var canvas_mat := StandardMaterial3D.new()
		canvas_mat.albedo_color = Color(0.92, 0.89, 0.82)  # Natural warm tailored linen cloth
		canvas_mat.roughness = 0.78

		var blue_mat := StandardMaterial3D.new()
		blue_mat.albedo_color = Color(0.14, 0.28, 0.64)  # Noble royal blue with rich satin sheen
		blue_mat.roughness = 0.48

		var gold_mat := StandardMaterial3D.new()
		gold_mat.albedo_color = Color(0.96, 0.82, 0.26)  # Heraldic gilded brass/gold
		gold_mat.metallic = 0.75
		gold_mat.roughness = 0.26

		var cord_mat := StandardMaterial3D.new()
		cord_mat.albedo_color = Color(0.86, 0.74, 0.38)  # Braided gold/rope seam cords
		cord_mat.roughness = 0.55

		var dark_wood := StandardMaterial3D.new()
		dark_wood.albedo_color = Color(0.36, 0.24, 0.14)
		dark_wood.roughness = 0.85

		var dark_inside := StandardMaterial3D.new()
		dark_inside.albedo_color = Color(0.10, 0.09, 0.08)
		dark_inside.roughness = 0.95

		var steel_mat := StandardMaterial3D.new()
		steel_mat.albedo_color = Color(0.92, 0.94, 0.98)  # Mirror-polished knight steel
		steel_mat.metallic = 0.96
		steel_mat.roughness = 0.12

		var dark_steel := StandardMaterial3D.new()
		dark_steel.albedo_color = Color(0.55, 0.58, 0.65)
		dark_steel.metallic = 0.85
		dark_steel.roughness = 0.30

		var red_mat := StandardMaterial3D.new()
		red_mat.albedo_color = Color(0.72, 0.14, 0.14)  # Heraldic knight crimson red
		red_mat.roughness = 0.45

		var iron_mat := StandardMaterial3D.new()
		iron_mat.albedo_color = Color(0.28, 0.30, 0.34)  # Forged iron bands and fittings
		iron_mat.metallic = 0.75
		iron_mat.roughness = 0.38

		var rope_mat := StandardMaterial3D.new()
		rope_mat.albedo_color = Color(0.68, 0.58, 0.42)  # Woven hemp guy ropes
		rope_mat.roughness = 0.88

		var lantern_brass := StandardMaterial3D.new()
		lantern_brass.albedo_color = Color(0.92, 0.76, 0.24)
		lantern_brass.metallic = 0.82
		lantern_brass.roughness = 0.28

		var lantern_glow_mat := StandardMaterial3D.new()
		lantern_glow_mat.albedo_color = Color(1.0, 0.82, 0.35)
		lantern_glow_mat.emission_enabled = true
		lantern_glow_mat.emission = Color(1.0, 0.78, 0.28)
		lantern_glow_mat.emission_energy_multiplier = 2.0

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

		# Vertical seam cords along the 12 facet seams of the wall
		var wall_seam_mesh := CylinderMesh.new()
		wall_seam_mesh.material = cord_mat
		wall_seam_mesh.top_radius = 0.012
		wall_seam_mesh.bottom_radius = 0.014
		wall_seam_mesh.height = 1.25
		wall_seam_mesh.radial_segments = 4

		for seg in 12:
			var angle: float = deg_to_rad(float(seg) * 30.0 + 15.0)
			var seam_node := MeshInstance3D.new()
			seam_node.mesh = wall_seam_mesh
			seam_node.position = Vector3(1.42 * sin(angle), 0.625, 1.42 * cos(angle))
			seam_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tent.add_child(seam_node)

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

		# Golden crest trims: upper and lower border ribbons on valance
		var trim_top_mesh := CylinderMesh.new()
		trim_top_mesh.material = gold_mat
		trim_top_mesh.top_radius = 1.495
		trim_top_mesh.bottom_radius = 1.495
		trim_top_mesh.height = 0.035
		trim_top_mesh.radial_segments = 12

		var trim_top := MeshInstance3D.new()
		trim_top.mesh = trim_top_mesh
		trim_top.position = Vector3(0.0, 1.30, 0.0)
		trim_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(trim_top)

		var trim_bot_mesh := CylinderMesh.new()
		trim_bot_mesh.material = gold_mat
		trim_bot_mesh.top_radius = 1.50
		trim_bot_mesh.bottom_radius = 1.50
		trim_bot_mesh.height = 0.03
		trim_bot_mesh.radial_segments = 12

		var trim_bot := MeshInstance3D.new()
		trim_bot.mesh = trim_bot_mesh
		trim_bot.position = Vector3(0.0, 1.14, 0.0)
		trim_bot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(trim_bot)

		# 12 golden vandyke crest dags (pennon teeth) hanging down below valance
		var dag_mesh := BoxMesh.new()
		dag_mesh.material = gold_mat
		dag_mesh.size = Vector3(0.16, 0.07, 0.02)

		for seg in 12:
			var angle: float = deg_to_rad(float(seg) * 30.0)
			var dag := MeshInstance3D.new()
			dag.mesh = dag_mesh
			dag.position = Vector3(1.50 * sin(angle), 1.10, 1.50 * cos(angle))
			dag.rotation.y = angle
			dag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tent.add_child(dag)

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

		# 12 angled roof ridge seam cords running from finial to eaves
		var roof_cord_mesh := CylinderMesh.new()
		roof_cord_mesh.material = cord_mat
		roof_cord_mesh.top_radius = 0.012
		roof_cord_mesh.bottom_radius = 0.014
		roof_cord_mesh.height = 1.82
		roof_cord_mesh.radial_segments = 4

		for seg in 12:
			var angle: float = deg_to_rad(float(seg) * 30.0 + 15.0)
			var ridge_pivot := Node3D.new()
			ridge_pivot.rotation.y = angle
			tent.add_child(ridge_pivot)

			var ridge_cord := MeshInstance3D.new()
			ridge_cord.mesh = roof_cord_mesh
			ridge_cord.position = Vector3(0.0, 1.88, 0.78)
			ridge_cord.rotation.x = deg_to_rad(-48.2)
			ridge_cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ridge_pivot.add_child(ridge_cord)

		# Gilded collar ring at roof peak
		var collar_mesh := CylinderMesh.new()
		collar_mesh.material = gold_mat
		collar_mesh.top_radius = 0.12
		collar_mesh.bottom_radius = 0.14
		collar_mesh.height = 0.06
		collar_mesh.radial_segments = 12

		var collar := MeshInstance3D.new()
		collar.mesh = collar_mesh
		collar.position = Vector3(0.0, 2.50, 0.0)
		collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tent.add_child(collar)

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
		finial.position = Vector3(0.0, 2.68, 0.0)
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

		# Entrance canopy awning with gold border trim
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

		# Gold heraldic crest emblem on awning
		var awning_crest_mesh := BoxMesh.new()
		awning_crest_mesh.material = gold_mat
		awning_crest_mesh.size = Vector3(0.24, 0.045, 0.24)
		var awning_crest := MeshInstance3D.new()
		awning_crest.mesh = awning_crest_mesh
		awning_crest.position = Vector3(0.0, 0.01, 0.0)
		awning.add_child(awning_crest)

		# 2 wooden awning support poles with polished brass ferrule caps
		var pole_m := CylinderMesh.new()
		pole_m.material = dark_wood
		pole_m.top_radius = 0.03
		pole_m.bottom_radius = 0.035
		pole_m.height = 1.2
		pole_m.radial_segments = 6

		var brass_cap_m := CylinderMesh.new()
		brass_cap_m.material = lantern_brass
		brass_cap_m.top_radius = 0.036
		brass_cap_m.bottom_radius = 0.036
		brass_cap_m.height = 0.06
		brass_cap_m.radial_segments = 6

		for px in [-0.52, 0.52]:
			var ap := MeshInstance3D.new()
			ap.mesh = pole_m
			ap.position = Vector3(px, 0.6, 2.12)
			ap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tent.add_child(ap)

			var cap_top := MeshInstance3D.new()
			cap_top.mesh = brass_cap_m
			cap_top.position = Vector3(0.0, 0.58, 0.0)
			ap.add_child(cap_top)

		# Hanging brass camp lantern by the entrance
		var lantern_bracket := MeshInstance3D.new()
		var bracket_m := BoxMesh.new()
		bracket_m.material = iron_mat
		bracket_m.size = Vector3(0.03, 0.03, 0.22)
		lantern_bracket.mesh = bracket_m
		lantern_bracket.position = Vector3(0.52, 1.15, 2.22)
		tent.add_child(lantern_bracket)

		var lantern := Node3D.new()
		lantern.name = "CampLantern"
		lantern.position = Vector3(0.52, 1.02, 2.32)
		tent.add_child(lantern)

		var lantern_body := MeshInstance3D.new()
		var l_mesh := CylinderMesh.new()
		l_mesh.material = lantern_brass
		l_mesh.top_radius = 0.06
		l_mesh.bottom_radius = 0.05
		l_mesh.height = 0.16
		l_mesh.radial_segments = 6
		lantern_body.mesh = l_mesh
		lantern.add_child(lantern_body)

		var lantern_core := MeshInstance3D.new()
		var core_m := CylinderMesh.new()
		core_m.material = lantern_glow_mat
		core_m.top_radius = 0.04
		core_m.bottom_radius = 0.04
		core_m.height = 0.10
		core_m.radial_segments = 6
		lantern_core.mesh = core_m
		lantern.add_child(lantern_core)

		var lantern_light := OmniLight3D.new()
		lantern_light.light_color = Color(1.0, 0.82, 0.45)
		lantern_light.light_energy = 0.85
		lantern_light.omni_range = 3.6
		lantern_light.omni_attenuation = 1.2
		lantern.add_child(lantern_light)

		# Guy ropes with wooden tensioners and forged iron stakes around pavilion
		var rope_mesh := CylinderMesh.new()
		rope_mesh.material = rope_mat
		rope_mesh.top_radius = 0.012
		rope_mesh.bottom_radius = 0.012
		rope_mesh.height = 1.35
		rope_mesh.radial_segments = 4

		var tensioner_m := BoxMesh.new()
		tensioner_m.material = dark_wood
		tensioner_m.size = Vector3(0.04, 0.08, 0.04)

		var stake_mesh := CylinderMesh.new()
		stake_mesh.material = iron_mat
		stake_mesh.top_radius = 0.025
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

			var tensioner := MeshInstance3D.new()
			tensioner.mesh = tensioner_m
			tensioner.position = Vector3(0.0, 0.45, 1.95)
			tensioner.rotation.x = deg_to_rad(-28.2)
			rope_pivot.add_child(tensioner)

			var stake := MeshInstance3D.new()
			stake.mesh = stake_mesh
			stake.position = Vector3(0.0, 0.08, 2.15)
			stake.rotation.x = deg_to_rad(-20.0)
			stake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rope_pivot.add_child(stake)

		# Iron-banded oak armory supply chest beside tent
		var chest := Node3D.new()
		chest.name = "ArmoryChest"
		chest.position = Vector3(1.45, 0.0, 1.55)
		chest.rotation.y = deg_to_rad(-25.0)
		tent.add_child(chest)

		var chest_body_m := BoxMesh.new()
		chest_body_m.material = dark_wood
		chest_body_m.size = Vector3(0.55, 0.32, 0.34)
		var chest_body := MeshInstance3D.new()
		chest_body.mesh = chest_body_m
		chest_body.position.y = 0.16
		chest.add_child(chest_body)

		var chest_lid_m := CylinderMesh.new()
		chest_lid_m.material = dark_wood
		chest_lid_m.top_radius = 0.17
		chest_lid_m.bottom_radius = 0.17
		chest_lid_m.height = 0.56
		chest_lid_m.radial_segments = 8
		var chest_lid := MeshInstance3D.new()
		chest_lid.mesh = chest_lid_m
		chest_lid.position.y = 0.32
		chest_lid.rotation.z = deg_to_rad(90.0)
		chest.add_child(chest_lid)

		# Iron bands on chest
		var band_m := BoxMesh.new()
		band_m.material = iron_mat
		band_m.size = Vector3(0.04, 0.36, 0.36)
		for bx in [-0.18, 0.18]:
			var band := MeshInstance3D.new()
			band.mesh = band_m
			band.position = Vector3(bx, 0.18, 0.0)
			chest.add_child(band)

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

		# Swallowtail Heraldic Pennant (noble blue cloth with gold fringe borders)
		var pennant_body_mesh := BoxMesh.new()
		pennant_body_mesh.material = blue_mat
		pennant_body_mesh.size = Vector3(0.65, 0.45, 0.02)

		var pennant_body := MeshInstance3D.new()
		pennant_body.mesh = pennant_body_mesh
		pennant_body.position = Vector3(0.36, 3.25, 0.0)
		pennant_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flagpole.add_child(pennant_body)

		# Gold fringe trim on top and bottom of pennant body
		var fringe_h_mesh := BoxMesh.new()
		fringe_h_mesh.material = gold_mat
		fringe_h_mesh.size = Vector3(0.65, 0.03, 0.025)

		var fringe_top := MeshInstance3D.new()
		fringe_top.mesh = fringe_h_mesh
		fringe_top.position = Vector3(0.36, 3.46, 0.0)
		flagpole.add_child(fringe_top)

		var fringe_bot := MeshInstance3D.new()
		fringe_bot.mesh = fringe_h_mesh
		fringe_bot.position = Vector3(0.36, 3.04, 0.0)
		flagpole.add_child(fringe_bot)

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

		# Polished metallic swords on the rack
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
			# Polished steel blades with fuller grooves and gilded hilts
			var blade_m := BoxMesh.new()
			blade_m.material = steel_mat
			blade_m.size = Vector3(0.05, 0.82, 0.02)

			var fuller_m := BoxMesh.new()
			fuller_m.material = dark_steel
			fuller_m.size = Vector3(0.015, 0.68, 0.022)

			var hilt_m := BoxMesh.new()
			hilt_m.material = gold_mat
			hilt_m.size = Vector3(0.22, 0.03, 0.03)

			var pommel_m := CylinderMesh.new()
			pommel_m.material = gold_mat
			pommel_m.top_radius = 0.028
			pommel_m.bottom_radius = 0.028
			pommel_m.height = 0.04
			pommel_m.radial_segments = 6

			for sx in [-0.24, 0.24]:
				var sw := Node3D.new()
				sw.position = Vector3(sx, 0.45, 0.06)
				sw.rotation.x = deg_to_rad(12)

				var b := MeshInstance3D.new()
				b.mesh = blade_m
				sw.add_child(b)

				var fl := MeshInstance3D.new()
				fl.mesh = fuller_m
				fl.position.y = -0.05
				sw.add_child(fl)

				var h := MeshInstance3D.new()
				h.mesh = hilt_m
				h.position.y = 0.32
				sw.add_child(h)

				var pml := MeshInstance3D.new()
				pml.mesh = pommel_m
				pml.position.y = 0.46
				sw.add_child(pml)

				rack.add_child(sw)

		# Heraldic Painted Knight Shields on rack:
		# Noble gilded rim, quartered royal blue and crimson red heraldic face, polished steel dome boss
		var shield_root := Node3D.new()
		shield_root.position = Vector3(0.0, 0.52, 0.07)
		shield_root.rotation.x = deg_to_rad(85)
		rack.add_child(shield_root)

		# Golden outer protective rim
		var rim_mesh := CylinderMesh.new()
		rim_mesh.material = gold_mat
		rim_mesh.top_radius = 0.28
		rim_mesh.bottom_radius = 0.28
		rim_mesh.height = 0.04
		rim_mesh.radial_segments = 16

		var rim := MeshInstance3D.new()
		rim.mesh = rim_mesh
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shield_root.add_child(rim)

		# Quartered heraldic face
		var quarter_mesh := BoxMesh.new()
		quarter_mesh.size = Vector3(0.24, 0.042, 0.24)

		# Top-left and bottom-right: Royal Blue
		var q_blue1 := MeshInstance3D.new()
		q_blue1.mesh = quarter_mesh
		quarter_mesh.material = blue_mat
		q_blue1.position = Vector3(-0.12, 0.002, -0.12)
		shield_root.add_child(q_blue1)

		var q_blue2 := MeshInstance3D.new()
		var q_bm2 := BoxMesh.new()
		q_bm2.material = blue_mat
		q_bm2.size = Vector3(0.24, 0.042, 0.24)
		q_blue2.mesh = q_bm2
		q_blue2.position = Vector3(0.12, 0.002, 0.12)
		shield_root.add_child(q_blue2)

		# Top-right and bottom-left: Heraldic Crimson Red
		var q_red1 := MeshInstance3D.new()
		var q_rm1 := BoxMesh.new()
		q_rm1.material = red_mat
		q_rm1.size = Vector3(0.24, 0.042, 0.24)
		q_red1.mesh = q_rm1
		q_red1.position = Vector3(0.12, 0.002, -0.12)
		shield_root.add_child(q_red1)

		var q_red2 := MeshInstance3D.new()
		var q_rm2 := BoxMesh.new()
		q_rm2.material = red_mat
		q_rm2.size = Vector3(0.24, 0.042, 0.24)
		q_red2.mesh = q_rm2
		q_red2.position = Vector3(-0.12, 0.002, 0.12)
		shield_root.add_child(q_red2)

		# Gilded dividing heraldic cross
		var s_cross_v := MeshInstance3D.new()
		var sc_vm := BoxMesh.new()
		sc_vm.material = gold_mat
		sc_vm.size = Vector3(0.04, 0.046, 0.52)
		s_cross_v.mesh = sc_vm
		shield_root.add_child(s_cross_v)

		var s_cross_h := MeshInstance3D.new()
		var sc_hm := BoxMesh.new()
		sc_hm.material = gold_mat
		sc_hm.size = Vector3(0.52, 0.046, 0.04)
		s_cross_h.mesh = sc_hm
		shield_root.add_child(s_cross_h)

		# Polished steel shield boss
		var boss_mesh := CylinderMesh.new()
		boss_mesh.material = steel_mat
		boss_mesh.top_radius = 0.06
		boss_mesh.bottom_radius = 0.08
		boss_mesh.height = 0.04
		boss_mesh.radial_segments = 10

		var boss := MeshInstance3D.new()
		boss.mesh = boss_mesh
		boss.position = Vector3(0.0, 0.04, 0.0)
		shield_root.add_child(boss)

		# Golden boss apex stud
		var stud_m := SphereMesh.new()
		stud_m.material = gold_mat
		stud_m.radius = 0.02
		stud_m.height = 0.04
		var stud := MeshInstance3D.new()
		stud.mesh = stud_m
		stud.position = Vector3(0.0, 0.06, 0.0)
		shield_root.add_child(stud)

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

		# Steel knight breastplate / cuirass with gold collar
		var cuirass_mesh := BoxMesh.new()
		cuirass_mesh.material = steel_mat
		cuirass_mesh.size = Vector3(0.38, 0.45, 0.22)
		var cuirass := MeshInstance3D.new()
		cuirass.mesh = cuirass_mesh
		cuirass.position.y = 0.88
		cuirass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		armor_stand.add_child(cuirass)

		var cuirass_collar_m := BoxMesh.new()
		cuirass_collar_m.material = gold_mat
		cuirass_collar_m.size = Vector3(0.30, 0.04, 0.23)
		var cuirass_collar := MeshInstance3D.new()
		cuirass_collar.mesh = cuirass_collar_m
		cuirass_collar.position.y = 1.09
		armor_stand.add_child(cuirass_collar)

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

		var visor_m := BoxMesh.new()
		visor_m.material = dark_steel
		visor_m.size = Vector3(0.18, 0.04, 0.12)
		var visor := MeshInstance3D.new()
		visor.mesh = visor_m
		visor.position = Vector3(0.0, 1.25, 0.07)
		armor_stand.add_child(visor)

	## Gold of the next hire (grows with every hire of the battle).
	func hire_cost() -> int:
		return config.hire_cost(hired_total)

	## Mercenaries alive now (the dead leave `mercenaries` when they fall).
	func alive_count() -> int:
		var n: int = 0
		for m: Mercenary in mercenaries:
			if is_instance_valid(m) and m.is_alive():
				n += 1
		return n

	## True while one more knight may be hired (below `config.max_alive`).
	func can_hire_more() -> bool:
		return alive_count() < config.max_alive

	## Hires a mercenary for hire_cost() gold and registers it with the simulation.
	## Null: the limit of living mercenaries is reached or the gold is short.
	func hire_mercenary(gs: GameState = null, s: Sim = null) -> Mercenary:
		var target_gs := gs if gs != null else game_state
		var target_sim := s if s != null else sim
		if not can_hire_more():
			return null
		if target_gs != null and not target_gs.spend(Vector2i(hire_cost(), 0)):
			return null
		hired_total += 1

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
		merc.config = config
		merc.died.connect(_on_mercenary_died.bind(merc))
		add_sibling(merc)
		mercenaries.append(merc)

		if target_sim != null:
			target_sim.add_mercenary(merc)

		mercenary_hired.emit(merc)
		return merc

	func _on_mercenary_died(merc: Mercenary) -> void:
		mercenaries.erase(merc)
