class_name Cosmetics
extends RefCounted
## The catalog of cosmetics (resources/shop.json) and how a worn item reaches the
## screen. A skin is the shared palette material with a recoloured atlas
## (assets/materials/skins/<id>.png, made by tools/make_palette_variants.py): one cached
## material per skin, set as `material_override` on the meshes of a model. Nothing is
## rebuilt and no draw call is added. COSMETICS NEVER TOUCH THE SIMULATION: no function
## here is called from Sim or reads its state, nothing goes into the command journal
## or the replay hash (tests/test_cosmetics.gd checks it).

const DATA_PATH := "res://resources/shop.json"
const BASE_MATERIAL_PATH := "res://assets/materials/tg_palette.tres"
const SKIN_DIR := "res://assets/materials/skins/"
## The category of an item is also the slot it is worn in.
const HERO := "hero"
const TOWER := "tower"
const FLAG := "flag"
const FX := "fx"

static var _items: Array = []
static var _data_categories: Array = []
static var _by_id: Dictionary = {}
static var _materials: Dictionary = {}
## Worn item per slot, read from the wallet; see refresh().
static var _worn: Dictionary = {}
static var _worn_loaded: bool = false
## Tests and the shop preview can wear items without owning them: slot -> item id.
static var preview: Dictionary = {}


static func items() -> Array:
	_load()
	return _items


static func categories() -> Array:
	_load()
	return _data_categories


static func get_item(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})


static func is_valid(id: String) -> bool:
	_load()
	return _by_id.has(id)


## Items of a category in catalog order.
static func in_category(category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in items():
		if str(item["category"]) == category:
			out.append(item)
	return out


## An id from outside (the co-op partner, the cloud) made safe: the id if it names an
## item of that category, else "" (the standard look).
static func sanitize(id: Variant, category: String) -> String:
	if not id is String:
		return ""
	var item: Dictionary = get_item(id)
	return id if not item.is_empty() and str(item["category"]) == category else ""


## Reloads the worn items from the wallet (after buying, equipping, a sync, a new scene).
static func refresh() -> void:
	_worn.clear()
	var wallet: Dictionary = Wallet.local()
	for category: String in categories():
		_worn[category] = sanitize(Wallet.equipped(wallet, category), category)
	_worn_loaded = true


## The item worn in a slot ("" = standard).
static func equipped(category: String) -> String:
	if preview.has(category):
		return sanitize(preview[category], category)
	if not _worn_loaded:
		refresh()
	return str(_worn.get(category, ""))


## The skin material of an item (null for "" or an item without a palette).
static func material_for(id: String) -> Material:
	var item: Dictionary = get_item(id)
	if item.is_empty() or not item.has("palette"):
		return null
	if _materials.has(id):
		return _materials[id]
	var base: StandardMaterial3D = load(BASE_MATERIAL_PATH)
	var texture: Texture2D = load(SKIN_DIR + id + ".png") as Texture2D
	if base == null or texture == null:
		return null
	var material := base.duplicate() as StandardMaterial3D
	material.resource_name = "Skin_" + id
	material.albedo_texture = texture
	_materials[id] = material
	return material


## Puts the skin `id` on every mesh under `root` ("" or unknown = the standard material).
static func apply(root: Node, id: String) -> void:
	var material: Material = material_for(id)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = material


## Wears what the player has on in `category` on the model `root`.
static func apply_worn(root: Node, category: String) -> void:
	apply(root, equipped(category))


## The castle's banner: the worn flag, else the flag of the running seasonal event.
static func castle_flag() -> String:
	var worn: String = equipped(FLAG)
	if worn != "":
		return worn
	var event: Dictionary = Events.active(Daily.today_key())
	return sanitize(event.get("flag", ""), FLAG)


## The colour of the hit sparks: the worn "fx" item's tint over the default.
static func fx_tint(default: Color) -> Color:
	var item: Dictionary = get_item(equipped(FX))
	if item.is_empty() or not item.has("tint"):
		return default
	return Color.html(str(item["tint"]))


## Colours shown on a card: the first palette colours or the tint.
static func swatches(item: Dictionary, count: int = 3) -> Array[Color]:
	var out: Array[Color] = []
	if item.has("tint"):
		out.append(Color.html(str(item["tint"])))
	elif item.has("palette"):
		for swatch: String in item["palette"]:
			if out.size() < count:
				out.append(Color.html(str(item["palette"][swatch])))
	return out


static func _load() -> void:
	if not _items.is_empty():
		return
	var json: JSON = load(DATA_PATH)
	_items = json.data["items"]
	_data_categories = json.data["categories"]
	for item: Dictionary in _items:
		_by_id[str(item["id"])] = item
