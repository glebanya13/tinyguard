extends SceneTree


## Lists, for the next 120 days from DAILY_FROM, the first date of every (level, preset) pair.
func _initialize() -> void:
	var seen := {}
	var t: int = int(Time.get_unix_time_from_system()) - 86400 * 60
	for d in 400:
		var key: String = Daily.key_for(t + d * 86400)
		var pair := "%d/%s" % [Daily.level_for(key), Daily.preset_for(key)["id"]]
		if not seen.has(pair):
			seen[pair] = key
	var pairs: Array = seen.keys()
	pairs.sort()
	for p in pairs:
		print(p, " ", seen[p])
	quit()
