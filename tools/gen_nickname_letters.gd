extends SceneTree
## Writes tests/nickname_letters.json: every character NicknameRules accepts and
## its uniqueness key (what the client sends). firebase/rules-tests checks that
## firestore.rules accept exactly these keys (the rules fold case with RE2,
## the client with String.to_lower()). Run after changing NicknameRules:
##   godot --headless --path . --script res://tools/gen_nickname_letters.gd

const OUT := "res://tests/nickname_letters.json"


func _initialize() -> void:
	var letters: Array = []
	for code in range(0x20, 0x500):
		if NicknameRules.is_letter_or_digit(code):
			var ch: String = char(code)
			# "x?x": the character is surrounded by plain letters, so it is a valid name.
			var check: Dictionary = NicknameRules.validate("x" + ch + "x")
			if check["ok"]:
				letters.append([ch, str(check["normalized"]).substr(1, 1)])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	var lines: PackedStringArray = []
	for pair: Array in letters:
		lines.append("\t" + JSON.stringify(pair))
	f.store_string('{"letters": [\n' + ",\n".join(lines) + "\n]}\n")
	f.close()
	print("wrote %d letters" % letters.size())
	quit()
