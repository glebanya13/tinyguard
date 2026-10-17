extends SceneTree
## Prints enemies per wave (6..13) of the record-run plan (the daily challenge) per level.
## godot --headless --path . --script res://tools/wave_peaks.gd


func _initialize() -> void:
	for level: Dictionary in LevelCatalog.levels():
		var plan := WavePlan.new(level["waves"], true, true)
		var line := "L%d:" % int(level["id"])
		for w in range(6, 14):
			var list: Array[Dictionary] = plan.spawns(w)
			var bosses := 0
			for s in list:
				if (s["data"] as EnemyData).is_boss:
					bosses += 1
			var extra: String = plan.surprise_key(w)
			if plan.is_elite_wave(w):
				extra += ",E"
			line += " w%d=%d(b%d,%s)" % [w, list.size(), bosses, extra]
		print(line)
	quit()
