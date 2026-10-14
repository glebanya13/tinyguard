class_name Tutorial
extends CanvasLayer
## Interactive first-launch tutorial on level 1 (LevelCatalog.tutorial). Lives
## in its own CanvasLayer over the HUD and only observes the game: it listens
## to the real signals (Hero.wood_gathered, WaveManager.wave_started/
## wave_cleared/enemy_killed, BuildManager.slot_selected/tower_built/
## tower_upgraded) and polls hero state, and advances only on what the player
## actually did. Pacing: the wave clock is held (WaveManager.schedule_next_wave
## with a very long delay — the public API) until the player is ready for it;
## from the "real wave" step on the level runs on its normal 30 s clock.
## Normal levels never create this node.

signal step_changed(step: Step)

enum Step { WELCOME, CHOP, SLIMES, SELECT, BUILD, MOVE, SPIN, WAVE, UPGRADE, DONE }

## How long the held wave clock is set to (seconds), i.e. "not until we say so".
const HOLD_SECONDS := 36000.0
## The "real wave" starts this long after the step is shown (seconds).
const WAVE_DELAY := 4.0
## The hero has to walk this far for the movement step (metres).
const MOVE_DISTANCE := 2.0
## Modal buttons ignore taps for this long after appearing (accidental taps).
const MODAL_GUARD_MS := 450
const COUNTED_STEPS: Array[Step] = [
	Step.CHOP,
	Step.SLIMES,
	Step.SELECT,
	Step.BUILD,
	Step.MOVE,
	Step.SPIN,
	Step.WAVE,
	Step.UPGRADE,
]
const POINTER_COLOR := Color(1.0, 0.84, 0.32)
const OUTLINE_COLOR := Color(0.06, 0.09, 0.2)
## The pointer looks for a new target this often (frames).
const RETARGET_FRAMES := 10

var _step: Step = Step.WELCOME
var _game_state: GameState
var _waves: WaveManager
var _build: BuildManager
var _hero: Hero
var _camera: Camera3D
var _hud: Node = null
var _need_wood: int = 0
var _need_gold: int = 0
var _move_from: Vector3 = Vector3.ZERO
var _spin_seen: float = 0.0
var _wave_target: int = -1
var _tower_slot: TowerSlot = null
var _pointer_target: Node3D = null
var _highlight: Control = null
var _retarget: int = 0
var _modal_shown_at: int = 0
var _modal_kind: StringName = &""
var _gift_note: String = ""
## The step the skip dialog interrupted.
var _before_skip: Step = Step.WELCOME

@onready var _pointer: Control = $Root/Pointer
@onready var _coach: Control = $Root/Coach
@onready var _step_label: Label = $Root/Coach/Box/Header/Step
@onready var _title: Label = $Root/Coach/Box/Title
@onready var _body: Label = $Root/Coach/Box/Body
@onready var _skip: Button = $Root/Coach/Box/Header/SkipButton
@onready var _modal: Control = $Root/Modal
@onready var _modal_title: Label = $Root/Modal/Center/Panel/Box/Title
@onready var _modal_body: Label = $Root/Modal/Center/Panel/Box/Body
@onready var _primary: Button = $Root/Modal/Center/Panel/Box/Buttons/Primary
@onready var _secondary: Button = $Root/Modal/Center/Panel/Box/Buttons/Secondary


func _ready() -> void:
	_pointer.draw.connect(_draw_pointer)
	_primary.pressed.connect(press_primary)
	_secondary.pressed.connect(press_secondary)
	_skip.pressed.connect(_ask_skip)


## Called by the level once its systems are ready (they are passed down, the
## tutorial never searches the tree for them).
func setup(
	game_state: GameState,
	waves: WaveManager,
	build: BuildManager,
	hero: Hero,
	camera: Camera3D,
	hud: Node
) -> void:
	_game_state = game_state
	_waves = waves
	_build = build
	_hero = hero
	_camera = camera
	_hud = hud
	var cheapest: TowerData = build.tower_types[0]
	for data in build.tower_types:
		if data.cost_gold + data.cost_wood < cheapest.cost_gold + cheapest.cost_wood:
			cheapest = data
	_need_wood = cheapest.cost_wood
	_need_gold = cheapest.cost_gold
	_waves.schedule_next_wave(HOLD_SECONDS)  # no wave until the player is ready
	hero.wood_gathered.connect(_on_resources.unbind(2))
	game_state.gold_changed.connect(_on_resources.unbind(1))
	game_state.wood_changed.connect(_on_resources.unbind(1))
	waves.wave_started.connect(_on_wave_started)
	waves.wave_cleared.connect(_on_wave_cleared)
	build.slot_selected.connect(_on_slot_selected)
	build.selection_cleared.connect(_on_selection_cleared)
	build.tower_built.connect(_on_tower_built)
	build.tower_upgraded.connect(_on_tower_upgraded)
	_enter(Step.WELCOME)


func current_step() -> Step:
	return _step


## Main modal button (welcome: start, skip dialog: skip, finish: to the map).
func press_primary() -> void:
	if not _modal.visible or Time.get_ticks_msec() - _modal_shown_at < MODAL_GUARD_MS:
		return
	match _modal_kind:
		&"welcome":
			_enter(Step.CHOP)
		&"skip":
			Onboarding.complete_tutorial()
			_leave_to_map()
		&"done":
			_leave_to_map()


## Second modal button (welcome: skip, skip dialog: back, finish: keep playing).
func press_secondary() -> void:
	if not _modal.visible or Time.get_ticks_msec() - _modal_shown_at < MODAL_GUARD_MS:
		return
	match _modal_kind:
		&"welcome":
			_ask_skip()
		&"skip":
			_enter(_before_skip)
		&"done":
			_modal.hide()
			_coach.hide()
			_pointer_target = null
			_highlight = null


func _process(_delta: float) -> void:
	var hidden: bool = get_tree().paused or (_game_state != null and _game_state.is_defeated)
	$Root.visible = not hidden
	if hidden or _hero == null:
		return
	match _step:
		Step.MOVE:
			var moved: Vector3 = _hero.global_position - _move_from
			moved.y = 0.0
			if moved.length() >= MOVE_DISTANCE:
				_enter(Step.SPIN)
		Step.SPIN:
			if _hero.spin_cooldown_left() > _spin_seen + 0.01:
				_enter(Step.WAVE)
			_spin_seen = minf(_spin_seen, _hero.spin_cooldown_left())
	_retarget -= 1
	if _retarget <= 0:
		_retarget = RETARGET_FRAMES
		_pointer_target = _find_target()
		_highlight = _find_highlight()
	_pointer.queue_redraw()


func _enter(step: Step) -> void:
	_step = step
	_modal.hide()
	_coach.show()
	_retarget = 0
	match step:
		Step.WELCOME:
			var nick: String = str(PlayerProfile.local()["nickname"])
			_show_modal(
				&"welcome",
				"Добро пожаловать, %s!" % nick if nick != "" else "Добро пожаловать!",
				(
					"Слизни идут волнами по тропе к твоему замку. Не пусти их внутрь!"
					+ "\nСейчас покажу, как защищаться."
				),
				"Начнём!",
				"Пропустить"
			)
		Step.SLIMES:
			if _waves.current_wave == 0:
				_waves.start_next_wave()  # the first slimes, so there is gold to earn
			_waves.schedule_next_wave(HOLD_SECONDS)
		Step.MOVE:
			_move_from = _hero.global_position
		Step.SPIN:
			_spin_seen = _hero.spin_cooldown_left()
		Step.WAVE:
			_wave_target = _waves.current_wave + 1
			_waves.schedule_next_wave(WAVE_DELAY)
		Step.DONE:
			Onboarding.complete_tutorial()
			var nick: String = str(PlayerProfile.local()["nickname"])
			_show_modal(
				&"done",
				"Ты готов, %s!" % nick if nick != "" else "Ты готов!",
				(
					"Волны приходят каждые 30 секунд. Руби деревья, бей слизней,"
					+ " строй и улучшай башни — в любой момент боя. Удачи!"
				),
				"На карту",
				"Играть дальше"
			)
	_refresh_text()
	step_changed.emit(step)
	_check()


## Advances when the current step's goal already holds (e.g. resources from
## perks, a tower built ahead of the instructions).
func _check() -> void:
	match _step:
		Step.CHOP:
			if _game_state.wood >= _need_wood:
				_enter(Step.SLIMES)
		Step.SLIMES:
			if _game_state.gold >= _need_gold:
				_enter(Step.SELECT)
		Step.SELECT:
			if _build.selected_slot != null and _build.selected_slot.is_free():
				_enter(Step.BUILD)
		Step.UPGRADE:
			if _tower_slot != null and _tower_slot.tower != null and _tower_slot.tower.level > 0:
				_enter(Step.DONE)


func _refresh_text() -> void:
	var index: int = COUNTED_STEPS.find(_step)
	_step_label.text = "Шаг %d из %d" % [index + 1, COUNTED_STEPS.size()] if index >= 0 else ""
	var title := ""
	var body := ""
	match _step:
		Step.CHOP:
			title = "Наруби дров"
			body = (
				"Подойди к дереву или нажми на него — рыцарь сам начнёт рубить."
				+ "\nДерево: %d из %d" % [mini(_game_state.wood, _need_wood), _need_wood]
			)
		Step.SLIMES:
			title = "Слизни идут!"
			body = (
				"Подведи рыцаря к слизням — он бьёт мечом сам. За каждого дают золото."
				+ "\nЗолото: %d из %d" % [mini(_game_state.gold, _need_gold), _need_gold]
			)
			if _gift_note != "":
				body = _gift_note
		Step.SELECT:
			title = "Выбери площадку"
			body = "Нажми на каменную площадку у тропы — там встанет башня."
		Step.BUILD:
			title = "Построй башню"
			body = "Выбери башню на панели внизу. Рыцарь подойдёт и построит её."
		Step.MOVE:
			title = "Управляй рыцарем"
			body = "Веди джойстик слева внизу или нажми на землю — рыцарь пойдёт туда."
		Step.SPIN:
			title = "Вихрь!"
			body = "Нажми кнопку вихря: рыцарь крутанётся и ударит всех врагов вокруг."
			if _hero.spin_cooldown_left() > 0.0:
				body += "\nКнопка ещё перезаряжается — подожди пару секунд."
		Step.WAVE:
			title = "Настоящая волна"
			body = "Волна идёт по тропе! Башня и рыцарь защищают замок. Победи всех слизней."
		Step.UPGRADE:
			var cost: Vector2i = _build.upgrade_cost(_tower_slot)
			title = "Улучши башню"
			body = "Нажми на свою башню и выбери «Улучшить». Улучшать можно в любой момент."
			if cost.x >= 0:
				body += (
					"\nНужно: золото %d/%d, дерево %d/%d"
					% [
						mini(_game_state.gold, cost.x),
						cost.x,
						mini(_game_state.wood, cost.y),
						cost.y
					]
				)
	_title.text = title
	_body.text = body


func _show_modal(
	kind: StringName, title: String, body: String, primary: String, secondary: String
) -> void:
	_modal_kind = kind
	_modal_title.text = title
	_modal_body.text = body
	_primary.text = primary
	_secondary.text = secondary
	_modal_shown_at = Time.get_ticks_msec()
	_modal.show()
	_coach.hide()


func _ask_skip() -> void:
	if _step == Step.DONE:
		return
	_before_skip = _step
	_show_modal(
		&"skip",
		"Пропустить обучение?",
		"Его можно пройти заново на карте: Профиль → «Пройти обучение заново».",
		"Пропустить",
		"Назад"
	)


func _leave_to_map() -> void:
	LevelCatalog.tutorial = false
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(Onboarding.MAP_SCENE)


func _on_resources() -> void:
	if _step in [Step.CHOP, Step.SLIMES, Step.UPGRADE]:
		_refresh_text()
		_check()


func _on_wave_started(wave: int, _total: int, _boss: bool) -> void:
	# Waves started by the player (or the tutorial) before the "real wave" step
	# do not restart the normal clock yet.
	if _step < Step.WAVE:
		_waves.schedule_next_wave(HOLD_SECONDS)
	elif _step == Step.WAVE and wave > _wave_target:
		_wave_target = wave


func _on_wave_cleared(wave: int) -> void:
	if _step == Step.WAVE and wave >= _wave_target:
		_enter(Step.UPGRADE)
	elif _step == Step.SLIMES and wave == 1 and _game_state.gold < _need_gold:
		# All first slimes gone and still short: the king pays for the first tower.
		_gift_note = "Король прислал золото на первую башню!"
		_game_state.add_gold(_need_gold - _game_state.gold)


func _on_slot_selected(slot: TowerSlot) -> void:
	if _step == Step.SELECT and slot.is_free():
		_enter(Step.BUILD)
	elif _step == Step.BUILD and not slot.is_free():
		_enter(Step.SELECT)


func _on_selection_cleared() -> void:
	if _step == Step.BUILD:
		_enter(Step.SELECT)


func _on_tower_built(slot: TowerSlot, _tower: Tower) -> void:
	if _tower_slot == null or _tower_slot.tower == null:
		_tower_slot = slot
	if _step < Step.MOVE:
		_enter(Step.MOVE)


func _on_tower_upgraded(slot: TowerSlot, _tower: Tower) -> void:
	_tower_slot = slot
	if _step == Step.UPGRADE:
		_enter(Step.DONE)


## The world object the arrow points at in the current step.
func _find_target() -> Node3D:
	match _step:
		Step.CHOP:
			return _nearest(
				WoodTree.GROUP, func(n: Node) -> bool: return (n as WoodTree).is_choppable()
			)
		Step.SLIMES, Step.WAVE:
			return _nearest(Enemy.GROUP, func(n: Node) -> bool: return (n as Enemy).is_alive())
		Step.SELECT:
			return _nearest(
				TowerSlot.GROUP, func(n: Node) -> bool: return (n as TowerSlot).is_free()
			)
		Step.UPGRADE:
			if _build.selected_slot != _tower_slot:
				return _tower_slot
	return null


## The HUD control to outline in the current step (looked up by name, so a
## reworked HUD only loses the outline, never the tutorial).
func _find_highlight() -> Control:
	var node_name := ""
	match _step:
		Step.BUILD:
			node_name = "CommandCard"
		Step.UPGRADE:
			if _build.selected_slot != null and _build.selected_slot == _tower_slot:
				node_name = "CommandCard"
		Step.SPIN:
			node_name = "SpinButton"
		Step.MOVE:
			node_name = "Joystick"
	if node_name == "" or _hud == null:
		return null
	var found := _hud.find_child(node_name, true, false) as Control
	return found if found != null and found.is_visible_in_tree() else null


func _nearest(group: StringName, accept: Callable) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(group):
		var spot := node as Node3D
		var d: float = spot.global_position.distance_squared_to(_hero.global_position)
		if d < best_distance and accept.call(node):
			best_distance = d
			best = spot
	return best


func _draw_pointer() -> void:
	if _modal.visible:
		return
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	if is_instance_valid(_highlight) and _highlight != null:
		var rect: Rect2 = _highlight.get_global_rect().grow(8.0)
		var color := Color(POINTER_COLOR, 0.55 + 0.45 * pulse)
		_pointer.draw_rect(rect, color, false, 5.0)
		_draw_arrow(Vector2(rect.get_center().x, rect.position.y - 6.0 - 10.0 * pulse))
	if is_instance_valid(_pointer_target) and _pointer_target != null and _camera != null:
		var base: Vector3 = _pointer_target.global_position
		if _camera.is_position_behind(base):
			return
		var ground: Vector2 = _camera.unproject_position(base)
		var height: float = 1.9 if _pointer_target is WoodTree else 1.0
		var top: Vector2 = _camera.unproject_position(base + Vector3.UP * height)
		var radius: float = 34.0 + 6.0 * pulse
		_pointer.draw_arc(ground, radius, 0.0, TAU, 40, OUTLINE_COLOR, 9.0)
		_pointer.draw_arc(ground, radius, 0.0, TAU, 40, POINTER_COLOR, 5.0)
		_draw_arrow(top - Vector2(0.0, 10.0 + 14.0 * pulse))


## A fat downward arrow whose tip is at `tip`.
func _draw_arrow(tip: Vector2) -> void:
	var points := PackedVector2Array(
		[
			tip,
			tip + Vector2(-30, -34),
			tip + Vector2(-13, -34),
			tip + Vector2(-13, -70),
			tip + Vector2(13, -70),
			tip + Vector2(13, -34),
			tip + Vector2(30, -34),
		]
	)
	var outline := points.duplicate()
	outline.append(tip)
	_pointer.draw_polyline(outline, OUTLINE_COLOR, 8.0, true)
	_pointer.draw_colored_polygon(points, POINTER_COLOR)
