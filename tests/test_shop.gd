extends SceneTree
## The shop: the catalog is valid (prices, translations, no id clashes, cosmetics only),
## buying needs funds and happens once, unknown ids are refused, wearing needs ownership,
## skins reach the models as shared cached materials, a partner's id is validated.
## (That wearing a skin does not change the replay hash: tests/test_replay.gd.)
## godot --headless --path . --script res://tests/test_shop.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_shop.cfg"
	LevelCatalog.erase_all()
	_run.call_deferred()


func _run() -> void:
	_check_catalog()
	_check_buying()
	_check_skins()
	LevelCatalog.erase_all()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_catalog() -> void:
	var items: Array = Cosmetics.items()
	check(items.size() >= 18, "at least 18 items (%d)" % items.size())
	var csv: String = FileAccess.get_file_as_string("res://translations/strings.csv")
	var ids := {}
	var keys := {}
	var ok := true
	var counts := {}
	var rarities := ["common", "rare", "epic"]
	var max_claim: int = Wallet.limit("max_claim")
	for item: Dictionary in items:
		var id: String = str(item["id"])
		ok = ok and not ids.has(id) and not keys.has(item["key"])
		ids[id] = true
		keys[item["key"]] = true
		ok = ok and Wallet.is_valid_id(id) and Cosmetics.categories().has(item["category"])
		ok = ok and int(item["price"]) > 0 and int(item["price"]) <= max_claim
		ok = ok and rarities.has(item["rarity"])
		ok = ok and csv.contains("\n" + str(item["key"]) + ",")
		ok = ok and (item.has("palette") != item.has("tint"))
		ok = ok and id.begins_with(str(item["category"]) + "_")
		counts[item["category"]] = int(counts.get(item["category"], 0)) + 1
		if item.has("palette"):
			ok = ok and FileAccess.file_exists("res://assets/materials/skins/%s.png" % id)
			ok = ok and Cosmetics.material_for(id) != null
		# Cosmetics only: no field that could change the battle.
		for bad in ["gold", "damage", "lives", "hp", "reward", "wood", "bonus"]:
			ok = ok and not item.has(bad)
	check(ok, "ids and keys unique, prices in range, names translated, textures exist")
	check(
		counts.get("hero", 0) >= 6 and counts.get("flag", 0) >= 6,
		"6+ hero skins and 6+ flags: %s" % [counts]
	)
	check(
		counts.get("tower", 0) >= 3 and counts.get("fx", 0) >= 1,
		"tower themes and sparks: %s" % [counts]
	)
	for category in Cosmetics.categories():
		check(
			csv.contains("\nSHOP_CAT_%s," % str(category).to_upper()),
			"category %s is translated" % category
		)
	check(
		Cosmetics.get_item("nope").is_empty() and not Cosmetics.is_valid(""),
		"unknown ids are not items"
	)
	# Events point at real flags.
	for event: Dictionary in Events.all():
		check(
			Cosmetics.sanitize(event.get("flag", ""), Cosmetics.FLAG) != "",
			"event %s has a flag item" % event["id"]
		)


func _check_buying() -> void:
	LevelCatalog.erase_all()
	var cheap: Dictionary = Cosmetics.in_category("flag")[0]
	var id: String = str(cheap["id"])
	check(Shop.state(id) == Shop.State.AVAILABLE, "not owned at the start")
	var r: Dictionary = Shop.buy(id)
	check(not r["ok"] and r["reason"] == "funds", "no gems, no purchase")
	check(
		Economy.balance() == 0 and Shop.state(id) == Shop.State.AVAILABLE,
		"a refused purchase changes nothing"
	)
	check(
		not Shop.buy("no_such_item")["ok"] and Shop.buy("no_such_item")["reason"] == "unknown",
		"an unknown id is refused"
	)
	check(
		not Shop.buy("")["ok"] and not Shop.buy("hero_ember; DROP")["ok"],
		"malformed ids are refused"
	)
	check(not Shop.equip(id) and not Shop.equip("no_such_item"), "cannot wear what is not owned")
	# Earn exactly enough.
	var price: int = int(cheap["price"])
	var p: Dictionary = PlayerProfile.local()
	Wallet.claim(p["wallet"], "test_a", price - 1)
	PlayerProfile.save_local(p)
	check(not Shop.buy(id)["ok"], "one gem short")
	p = PlayerProfile.local()
	Wallet.claim(p["wallet"], "test_b", 1 + 50)
	PlayerProfile.save_local(p)
	r = Shop.buy(id)
	check(r["ok"] and r["gems"] == 50, "enough gems: bought, %d left" % int(r["gems"]))
	check(Shop.state(id) == Shop.State.EQUIPPED, "a bought item is worn at once")
	check(Cosmetics.equipped(Cosmetics.FLAG) == id, "the flag slot shows it")
	check(
		Shop.buy(id)["reason"] == "owned" and Economy.balance() == 50,
		"buying twice is refused and free"
	)
	Shop.unequip(Cosmetics.FLAG)
	check(
		Cosmetics.equipped(Cosmetics.FLAG) == "" and Shop.state(id) == Shop.State.OWNED, "take off"
	)
	check(Shop.equip(id) and Shop.state(id) == Shop.State.EQUIPPED, "wear again")
	# Wearing an item of another category does not push it out.
	var skin: Dictionary = Cosmetics.in_category("hero")[0]
	p = PlayerProfile.local()
	Wallet.claim(p["wallet"], "test_c", int(skin["price"]))
	PlayerProfile.save_local(p)
	check(Shop.buy(str(skin["id"]))["ok"], "a hero skin")
	check(
		(
			Cosmetics.equipped(Cosmetics.FLAG) == id
			and Cosmetics.equipped(Cosmetics.HERO) == skin["id"]
		),
		"slots are independent"
	)
	# The wallet survives a reload, and a tampered "worn" id in the save is ignored.
	LevelCatalog._save = null
	LevelCatalog._save_loaded_from = ""
	Cosmetics.refresh()
	check(Cosmetics.equipped(Cosmetics.HERO) == skin["id"], "worn items survive a reload")
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value("wallet", "equipped", "hero=" + str(id) + ";fx=ghost_item")
	Cosmetics.refresh()
	check(
		Cosmetics.equipped(Cosmetics.HERO) == "" and Cosmetics.equipped(Cosmetics.FX) == "",
		"a wrong or unowned id in the save shows the standard look"
	)
	check(Shop.owned_count() == 2, "owned count")


func _check_skins() -> void:
	check(Cosmetics.sanitize("hero_ember", "hero") == "hero_ember", "partner id: known")
	check(Cosmetics.sanitize("hero_ember", "flag") == "", "partner id: wrong slot")
	check(
		Cosmetics.sanitize("zzz", "hero") == "" and Cosmetics.sanitize(5, "hero") == "",
		"partner id: unknown or not text"
	)
	check(Cosmetics.sanitize("x".repeat(500), "hero") == "", "partner id: huge")
	var a: Material = Cosmetics.material_for("hero_ember")
	check(a != null and a == Cosmetics.material_for("hero_ember"), "one cached material per skin")
	check(a != Cosmetics.material_for("hero_frost"), "different skins, different materials")
	var base: StandardMaterial3D = load(Cosmetics.BASE_MATERIAL_PATH)
	var skin := a as StandardMaterial3D
	check(
		(
			skin.albedo_texture != base.albedo_texture
			and skin.metallic_texture == base.metallic_texture
		),
		"only the colour atlas differs"
	)
	check(skin.vertex_color_use_as_albedo, "baked occlusion (vertex colours) is kept")
	# Skins reach a model; "" restores it.
	var scene: PackedScene = load("res://scenes/hero.tscn")
	var hero: Node = scene.instantiate()
	root.add_child(hero)
	var model: Node = hero.get_node("Model")
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty(), "the knight has %d meshes" % meshes.size())
	Cosmetics.apply(model, "hero_royal")
	var all_skinned := true
	for mesh in meshes:
		all_skinned = (
			all_skinned
			and (mesh as MeshInstance3D).material_override == Cosmetics.material_for("hero_royal")
		)
	check(all_skinned, "a skin covers the whole model")
	Cosmetics.apply(model, "")
	check((meshes[0] as MeshInstance3D).material_override == null, "the standard look comes back")
	hero.queue_free()
	# A ghost (the partner's knight) wears the partner's validated id, not ours.
	var ghost: Hero = scene.instantiate() as Hero
	ghost.is_ghost = true
	ghost.skin_id = Cosmetics.sanitize("hero_shadow", "hero")
	root.add_child(ghost)
	var gm: Node = ghost.get_node("Model").find_children("*", "MeshInstance3D", true, false)[0]
	check(
		(gm as MeshInstance3D).material_override == Cosmetics.material_for("hero_shadow"),
		"the ghost wears the partner's skin"
	)
	ghost.queue_free()
	# The spark tint.
	Cosmetics.preview = {"fx": "fx_pink"}
	check(Cosmetics.fx_tint(Color.WHITE) != Color.WHITE, "a spark tint changes the colour")
	Cosmetics.preview = {}
	check(
		Cosmetics.fx_tint(Color.WHITE) == Color.WHITE or Cosmetics.equipped("fx") != "",
		"no tint, no change"
	)
	# Two textures of different skins really differ in the recoloured cells only.
	var img_a: Image = (
		(load("res://assets/materials/skins/hero_ember.png") as Texture2D).get_image()
	)
	var img_b: Image = (
		(load("res://assets/materials/tg_palette_albedo.png") as Texture2D).get_image()
	)
	var diff: int = 0
	for y in 256:
		for x in 256:
			if img_a.get_pixel(x, y) != img_b.get_pixel(x, y):
				diff += 1
	check(
		diff > 0 and diff < 256 * 256 / 4,
		"the skin atlas differs from the base in a few cells (%d px)" % diff
	)
