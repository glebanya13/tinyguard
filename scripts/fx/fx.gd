class_name Fx
extends Node3D
## Game-feel layer of a battle: damage and gold numbers, death puffs, muzzle
## sparks, build / upgrade rings, sword slashes, footstep dust, castle shake and
## red vignette when a life is lost, victory confetti, selection pulse and the
## UI click.
##
## Purely visual and one-way: it listens to signals of the battle (and reads the
## positions they carry) but never writes simulation state, never uses the sim
## RNG (it has its own, seeded randomly) and adds nothing the state hash sees.
## GameSettings.effects_now() decides how much happens: off = nothing, minimum = the
## essentials (gold numbers, death puffs, build rings, castle hit, confetti),
## full = everything. The level creates one Fx and calls setup().

const CLICK_SOUND: AudioStream = preload("res://assets/audio/ui_click.wav")
const CONFETTI_SOUND: AudioStream = preload("res://assets/audio/confetti.wav")

const GOLD := Color(1.0, 0.85, 0.35)
const SPARK := Color(1.0, 0.93, 0.62)
const DUST := Color(0.86, 0.78, 0.62)
const SMOKE := Color(0.62, 0.62, 0.66)
const FROST := Color(0.65, 0.9, 1.0)
const BOLT := Color(0.7, 0.8, 1.0)
const WOOD_CHIP := Color(0.78, 0.55, 0.32)
const HURT := Color(1.0, 0.25, 0.2)
const CONFETTI: Array[Color] = [
	Color(1.0, 0.35, 0.4),
	Color(1.0, 0.82, 0.25),
	Color(0.4, 0.85, 0.5),
	Color(0.4, 0.7, 1.0),
	Color(0.85, 0.5, 1.0),
]
const TRANSPARENT := Color(1, 1, 1, 0)

## At most one damage number per enemy this often, and overall (milliseconds).
const DAMAGE_GAP_MS := 220
const DAMAGE_GAP_ALL_MS := 70
## Hits from this much damage are drawn bigger and orange.
const BIG_HIT := 20.0
const BURST_DRAG := 2.0
const SHAKE_DECAY := 7.0
const FOOTSTEP_GAP := 0.2
const SELECT_PULSE_GAP := 0.9
const CONFETTI_SECONDS := 1.6

## Colour of the sparks: the default, or the tint of the worn cosmetic (drawing only).
var _spark: Color = SPARK

var _camera: Camera3D = null
var _game_state: GameState = null
var _hero: Hero = null
var _castle: Node3D = null
var _hud: CanvasLayer = null
var _rng := RandomNumberGenerator.new()
var _dots: FxParticles = null
var _rings: FxParticles = null
var _layer: CanvasLayer = null
var _vignette: TextureRect = null
var _click: AudioStreamPlayer = null
var _celebrate_sound: AudioStreamPlayer = null
var _numbers: FxNumbers = null
var _damage_gate: Dictionary = {}
var _next_damage_ms: int = 0
var _shake: float = 0.0
var _vignette_alpha: float = 0.0
var _last_lives: int = -1
var _castle_tween: Tween = null
var _castle_scale: Vector3 = Vector3.ONE
var _step_timer: float = 0.0
var _selected: TowerSlot = null
var _select_timer: float = 0.0
var _confetti_left: float = 0.0
## shutdown() was called: nothing happens any more.
var _down: bool = false


func _ready() -> void:
	_rng.randomize()  # never the sim RNG: nothing here may influence the battle


## Wires the layer to a battle. Everything it needs comes in here, once.
func setup(
	camera: Camera3D,
	wave_manager: WaveManager,
	build_manager: BuildManager,
	game_state: GameState,
	heroes: Array[Hero],
	castle: Node3D,
	hud: CanvasLayer
) -> void:
	_camera = camera
	_spark = Cosmetics.fx_tint(SPARK)
	_game_state = game_state
	_castle = castle
	_hud = hud
	_hero = heroes[0] if not heroes.is_empty() else null
	_last_lives = game_state.lives
	if castle:
		_castle_scale = castle.scale
	build_manager.tower_built.connect(_on_tower_built)
	build_manager.tower_upgraded.connect(_on_tower_upgraded)
	build_manager.tower_sold.connect(_on_tower_sold)
	build_manager.slot_selected.connect(_on_slot_selected)
	build_manager.selection_cleared.connect(_on_selection_cleared)
	game_state.lives_changed.connect(_on_lives_changed)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.all_waves_cleared.connect(_on_victory, CONNECT_DEFERRED)
	for hero in heroes:
		hero.swung.connect(_on_hero_swung)
		hero.spun.connect(_on_hero_spun)
		hero.wood_gathered.connect(_on_wood_gathered)
	get_tree().node_added.connect(_on_node_added)
	for button: Node in hud.find_children("*", "BaseButton", true, false):
		_hook_button(button as BaseButton)
	_click = AudioStreamPlayer.new()
	_click.stream = CLICK_SOUND
	_click.volume_db = -6.0
	add_child(_click)


func _exit_tree() -> void:
	if _camera:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	if _castle and is_instance_valid(_castle):
		_castle.scale = _castle_scale


## The battle is being left: stop listening to the scene and drawing before it is freed.
func shutdown() -> void:
	_down = true
	set_process(false)
	var tree: SceneTree = get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	if _castle_tween:
		_castle_tween.kill()
		_castle_tween = null
	_switch_off()


## Effects that are on at all (minimum and full).
func enabled() -> bool:
	return not _down and GameSettings.effects_now() >= GameSettings.FX_MIN


## The extra effects of the full level.
func full() -> bool:
	return GameSettings.effects_now() >= GameSettings.FX_FULL


func _process(delta: float) -> void:
	if not enabled():
		_switch_off()
		return
	if _dots == null:
		return  # nothing has happened yet
	_update_shake(delta)
	_numbers.step(delta, _camera)
	_update_confetti(delta)
	if full():
		_update_footsteps(delta)
		_update_selection_pulse(delta)


# --- signal handlers ----------------------------------------------------------


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		var enemy := node as Enemy
		enemy.died.connect(_on_enemy_died.bind(enemy))
		enemy.damaged.connect(_on_enemy_damaged.bind(enemy))
	elif node is BaseButton and _hud != null and _hud.is_ancestor_of(node):
		_hook_button(node as BaseButton)


func _on_enemy_died(reward: int, enemy: Enemy) -> void:
	_damage_gate.erase(enemy.get_instance_id())
	if not enabled() or not is_instance_valid(enemy):
		return
	var at: Vector3 = enemy.get_aim_point()
	var tint: Color = enemy.data.fx_color if enemy.data else HURT
	var boss: bool = enemy.is_boss()
	var count: int = (14 if boss else 6) if full() else (8 if boss else 3)
	_burst(at, count, 1.6, 0.9, 0.7 if boss else 0.34, 0.05, Color(tint, 0.9), Color(tint, 0.0))
	_burst(at, maxi(roundi(count * 0.5), 1), 2.4, 1.4, 0.12, 0.03, _spark, _spark, 0.4, 5.0)
	_text("+%d" % reward, at + Vector3.UP * 0.4, GOLD, 30 if boss else 24)
	if boss:
		_kick(0.3)


func _on_enemy_damaged(amount: float, enemy: Enemy) -> void:
	if not full() or not is_instance_valid(enemy) or enemy.health <= 0.0:
		return
	var now: int = Time.get_ticks_msec()
	var id: int = enemy.get_instance_id()
	if now < _next_damage_ms or now < int(_damage_gate.get(id, 0)):
		return
	_next_damage_ms = now + DAMAGE_GAP_ALL_MS
	_damage_gate[id] = now + DAMAGE_GAP_MS
	var big: bool = amount >= BIG_HIT
	_text(
		str(roundi(amount)),
		enemy.get_aim_point() + Vector3.UP * 0.5,
		Color(1.0, 0.6, 0.25) if big else Color(1, 1, 1),
		28 if big else 22
	)


func _on_tower_fired(target: Enemy, tower: Tower) -> void:
	if not full() or not is_instance_valid(target):
		return
	var aim: Vector3 = target.sim_position() - tower.global_position
	aim.y = 0.0
	var dir: Vector3 = aim.normalized() if aim.length() > 0.01 else Vector3.FORWARD
	var muzzle: Vector3 = (
		tower.global_position + Vector3.UP * tower.muzzle_height + dir * tower.muzzle_reach
	)
	if tower.chain_targets > 0:
		_burst(muzzle, 4, 1.5, 1.0, 0.14, 0.02, BOLT, BOLT, 0.25)
		_burst(target.get_aim_point(), 5, 2.2, 1.0, 0.16, 0.02, Color.WHITE, BOLT, 0.3)
	elif tower.splash_radius > 0.0:
		_burst(muzzle + dir * 0.2, 3, 1.2, 0.8, 0.45, 0.1, SMOKE, Color(SMOKE, 0.0), 0.6)
		_burst(muzzle + dir * 0.3, 4, 3.0, 0.5, 0.16, 0.02, Color(1, 0.7, 0.3), _spark, 0.25)
	elif tower.slow_factor < 1.0:
		_burst(muzzle, 5, 1.0, 1.0, 0.14, 0.04, FROST, Color(FROST, 0.0), 0.7, 1.6)
	else:
		_burst(muzzle + dir * 0.15, 2, 1.6, 0.4, 0.14, 0.02, _spark, Color(_spark, 0.0), 0.2)


func _on_tower_built(slot: TowerSlot, tower: Tower) -> void:
	tower.fired.connect(_on_tower_fired.bind(tower))
	if not enabled():
		return
	var at: Vector3 = slot.global_position
	_ring(at, 0.4, 2.0, Color(1, 0.95, 0.8, 0.9), 0.5)
	_burst(
		at + Vector3.UP * 0.3, 6 if full() else 3, 1.8, 1.6, 0.18, 0.03, _spark, _spark, 0.7, 3.0
	)


func _on_tower_upgraded(slot: TowerSlot, tower: Tower) -> void:
	if not enabled():
		return
	var at: Vector3 = slot.global_position
	_ring(at, 0.4, 2.4, Color(1.0, 0.85, 0.35, 0.95), 0.6)
	_ring(at + Vector3.UP * 0.03, 0.2, 1.5, Color(1.0, 1.0, 0.8, 0.8), 0.45)
	_burst(at + Vector3.UP * 0.5, 9 if full() else 4, 1.4, 2.2, 0.2, 0.04, GOLD, _spark, 0.9, -1.0)
	if full() and is_instance_valid(tower):
		var base: Vector3 = tower.scale
		var tween := tower.create_tween()
		tween.tween_property(tower, "scale", base * 1.16, 0.09)
		tween.tween_property(tower, "scale", base, 0.3).set_trans(Tween.TRANS_BACK)


func _on_tower_sold(slot: TowerSlot, _refund: Vector2i) -> void:
	if enabled():
		_ring(slot.global_position, 0.3, 1.4, Color(0.9, 0.9, 0.9, 0.7), 0.4)


func _on_slot_selected(slot: TowerSlot) -> void:
	_selected = slot
	_select_timer = 0.0


func _on_selection_cleared() -> void:
	_selected = null


func _on_lives_changed(lives: int) -> void:
	var lost: bool = _last_lives >= 0 and lives < _last_lives
	var gained: bool = _last_lives >= 0 and lives > _last_lives
	_last_lives = lives
	if not enabled() or _castle == null:
		return
	var at: Vector3 = _castle.global_position + Vector3.UP * 1.2
	if lost:
		_kick(0.28 if full() else 0.14)
		_vignette_alpha = 0.7 if full() else 0.45
		_burst(
			at, 7 if full() else 4, 2.2, 1.2, 0.4, 0.05, Color(0.75, 0.65, 0.55), SMOKE, 0.7, 4.0
		)
		_burst(at, 5, 2.6, 1.0, 0.16, 0.04, HURT, Color(HURT, 0.0), 0.6, 3.0)
		_punch_castle()
	elif gained:
		_burst(at, 8, 1.2, 2.0, 0.2, 0.04, Color(0.6, 1.0, 0.55), _spark, 1.0, -1.5)
		_ring(_castle.global_position, 0.6, 3.0, Color(0.6, 1.0, 0.55, 0.85), 0.7)


func _on_wave_started(_wave: int, _total: int, boss: bool) -> void:
	if enabled() and boss:
		_kick(0.22)


func _on_victory() -> void:
	if _game_state.is_defeated or not enabled():
		return
	_ensure_built()
	process_mode = Node.PROCESS_MODE_ALWAYS  # the end screen pauses the tree
	_confetti_left = CONFETTI_SECONDS
	if _celebrate_sound == null:
		_celebrate_sound = AudioStreamPlayer.new()
		_celebrate_sound.stream = CONFETTI_SOUND
		_celebrate_sound.volume_db = -4.0
		add_child(_celebrate_sound)
	_celebrate_sound.play()


func _on_hero_swung(origin: Vector3, yaw: float) -> void:
	if not full():
		return
	var count: int = 6
	for i in count:
		var a: float = yaw + lerpf(-0.9, 0.9, float(i) / (count - 1))
		var out := Vector3(sin(a), 0.0, cos(a))
		var at: Vector3 = origin + out * 0.9 + Vector3.UP * 0.8
		_emit_dot(at, out * 2.4, 0.22, 0.34, 0.06, Color(1, 1, 0.9, 0.9), Color(_spark, 0.0))


func _on_hero_spun(origin: Vector3) -> void:
	if not full():
		return
	_ring(origin + Vector3.UP * 0.05, 0.6, 4.6, Color(1.0, 0.95, 0.75, 0.85), 0.4)
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		var out := Vector3(sin(a), 0.0, cos(a))
		_emit_dot(
			origin + out * 0.8 + Vector3.UP * 0.8, out * 3.0, 0.3, 0.3, 0.05, _spark, TRANSPARENT
		)


func _on_wood_gathered(_amount: int, at: Vector3) -> void:
	if full():
		_burst(at + Vector3.UP * 1.1, 6, 2.4, 1.6, 0.12, 0.04, WOOD_CHIP, WOOD_CHIP, 0.6, 9.0)


# --- visuals ------------------------------------------------------------------


func _update_shake(delta: float) -> void:
	if _shake > 0.002:
		_shake *= exp(-SHAKE_DECAY * delta)
		_camera.h_offset = _rng.randf_range(-_shake, _shake)
		_camera.v_offset = _rng.randf_range(-_shake, _shake)
	elif _camera.h_offset != 0.0 or _camera.v_offset != 0.0:
		_shake = 0.0
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(_vignette_alpha - delta * 1.6, 0.0)
		_vignette.modulate.a = _vignette_alpha
		_vignette.visible = _vignette_alpha > 0.01


func _update_confetti(delta: float) -> void:
	if _confetti_left <= 0.0 or _dots == null:
		return
	_confetti_left -= delta
	var per_second: float = 55.0 if full() else 20.0
	var n: int = roundi(per_second * delta + _rng.randf() * 0.5)
	var center: Vector3 = _camera.global_position
	var focus: Vector3 = _hero.global_position if _hero else center
	for i in n:
		var at := Vector3(
			focus.x + _rng.randf_range(-8.0, 8.0),
			_rng.randf_range(7.0, 10.0),
			focus.z + _rng.randf_range(-5.0, 5.0)
		)
		var vel := Vector3(_rng.randf_range(-0.8, 0.8), -_rng.randf_range(0.5, 2.0), 0.0)
		var c: Color = CONFETTI[_rng.randi() % CONFETTI.size()]
		_emit_dot(at, vel, _rng.randf_range(2.6, 3.4), 0.4, 0.34, c, c, 1.2, 0.4)


func _update_footsteps(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_step_timer -= delta
	if _step_timer > 0.0 or _hero.velocity.length() < 1.0:
		return
	_step_timer = FOOTSTEP_GAP
	var at: Vector3 = _hero.global_position + Vector3.UP * 0.08
	_emit_dot(
		at,
		Vector3(_rng.randf_range(-0.2, 0.2), 0.5, _rng.randf_range(-0.2, 0.2)),
		0.4,
		0.16,
		0.4,
		Color(DUST, 0.55),
		Color(DUST, 0.0),
		0.0,
		2.0
	)


func _update_selection_pulse(delta: float) -> void:
	if _selected == null or not is_instance_valid(_selected):
		return
	_select_timer -= delta
	if _select_timer <= 0.0:
		_select_timer = SELECT_PULSE_GAP
		var at: Vector3 = _selected.global_position + Vector3.UP * 0.1
		_ring(at, 0.5, 1.5, Color(1.0, 0.95, 0.6, 0.55), 0.85)


## Camera shake of `amount` metres (the strongest running shake wins).
func _kick(amount: float) -> void:
	_ensure_built()
	_shake = maxf(_shake, amount)


func _punch_castle() -> void:
	if _castle_tween:
		_castle_tween.kill()
	_castle.scale = _castle_scale
	_castle_tween = _castle.create_tween()
	_castle_tween.tween_property(_castle, "scale", _castle_scale * Vector3(1.05, 0.92, 1.05), 0.07)
	_castle_tween.tween_property(_castle, "scale", _castle_scale, 0.3).set_trans(Tween.TRANS_BACK)


## Effects were switched off in the settings: stop whatever is still running.
func _switch_off() -> void:
	if _dots == null:
		return
	_dots.clear()
	_rings.clear()
	_numbers.clear()
	_shake = 0.0
	_vignette_alpha = 0.0
	_vignette.hide()
	_confetti_left = 0.0
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0


# --- helpers ------------------------------------------------------------------


## Particle layers, number pool and vignette: built the first time they are needed.
func _ensure_built() -> void:
	if _dots != null:
		return
	_rings = FxParticles.new()
	_rings.flat = true
	_rings.name = "Rings"
	add_child(_rings)
	_dots = FxParticles.new()
	_dots.name = "Dots"
	add_child(_dots)
	_layer = CanvasLayer.new()
	_layer.layer = 0  # under the HUD
	add_child(_layer)
	_vignette = _make_vignette()
	_layer.add_child(_vignette)
	_numbers = FxNumbers.new()
	_layer.add_child(_numbers)


func _make_vignette() -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([Color(HURT, 0.0), Color(HURT, 0.0), Color(HURT, 0.5)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.visible = false
	return rect


## A number that rises from a world point and fades out.
func _text(text: String, world: Vector3, color: Color, font_size: int) -> void:
	_ensure_built()
	_numbers.add(text, world, color, font_size)


func _emit_dot(
	at: Vector3,
	velocity: Vector3,
	life: float,
	size_from: float,
	size_to: float,
	color_from: Color,
	color_to: Color,
	gravity: float = 0.0,
	drag: float = 0.0
) -> void:
	_ensure_built()
	_dots.emit(at, velocity, life, size_from, size_to, color_from, color_to, gravity, drag)


## `count` dots flying out of `at` in random directions (upwards by `lift`).
func _burst(
	at: Vector3,
	count: int,
	speed: float,
	lift: float,
	size_from: float,
	size_to: float,
	color_from: Color,
	color_to: Color,
	life: float = 0.5,
	gravity: float = 0.0
) -> void:
	for i in count:
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.0, lift), _rng.randf_range(-1.0, 1.0)
		)
		var v: Vector3 = dir.normalized() * speed * _rng.randf_range(0.5, 1.0)
		_emit_dot(
			at,
			v,
			life * _rng.randf_range(0.8, 1.2),
			size_from,
			size_to,
			color_from,
			color_to,
			gravity,
			BURST_DRAG
		)


## A ring lying on the ground that grows from `from_radius` to `to_radius` and fades.
func _ring(at: Vector3, from_radius: float, to_radius: float, color: Color, life: float) -> void:
	_ensure_built()
	var shrink: float = 1.0 / 0.84  # the ring sits at 84% of the texture radius
	_rings.emit(
		Vector3(at.x, 0.09, at.z),
		Vector3.ZERO,
		life,
		from_radius * 2.0 * shrink,
		to_radius * 2.0 * shrink,
		color,
		Color(color, 0.0)
	)


func _hook_button(button: BaseButton) -> void:
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)


func _play_click() -> void:
	if _click and _click.is_inside_tree():
		_click.pitch_scale = _rng.randf_range(0.95, 1.05)
		_click.play()
