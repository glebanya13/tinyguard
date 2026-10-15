class_name CoopHooks
extends RefCounted
## What the level scene does for a co-op match (docs/MULTIPLAYER.md, "Co-op in the
## game"; the work itself is in CoopBattle): creates the CoopBattle, shows the
## "waiting for partner" notice and ends the battle when the match is closed.

var battle: CoopBattle = null

var _hud: Hud = null
var _battle_end: BattleEnd = null


func attach(
	host: Node3D,
	config: Dictionary,
	transport: CoopTransport,
	lobby: CoopLobby,
	sim: Sim,
	commands: GameCommands,
	hero: Hero,
	level_root: Node3D,
	hud: Hud,
	battle_end: BattleEnd
) -> CoopBattle:
	_hud = hud
	_battle_end = battle_end
	battle = CoopBattle.new()
	battle.name = "CoopBattle"
	host.add_child(battle)
	battle.setup(config, transport, lobby, sim, commands, hero, level_root)
	battle.partner_waiting.connect(_on_partner_waiting)
	battle.match_over.connect(battle_end.on_coop_match_over)
	battle_end.coop = battle
	hud.set_coop_mode(true)
	return battle


func _on_partner_waiting(waiting: bool) -> void:
	if _battle_end.ended:
		return
	if waiting:
		_hud.show_coop_notice(TranslationServer.translate("COOP_WAITING_PARTNER"))
	else:
		_hud.hide_coop_notice()
