class_name SessionStore
extends RefCounted
## The Firebase session (uid, refresh token, account type) in its own file,
## encrypted with FileAccess.open_encrypted_with_pass. The key is derived from
## OS.get_unique_id() and an app salt, so a copied file does not open on
## another device. This is obfuscation, not hardware-backed security: Godot 4.3
## has no Android Keystore API, and anyone with root access to the device (or
## the APK, which contains the salt) can rebuild the key. See docs/ACCOUNTS.md.
## The refresh token never goes into progress.cfg or the cloud save.

## Not a secret: it only makes the key specific to this app.
const APP_SALT := "tinyguard/session/v1/7d1f3a9c"
## Tests point this at a scratch file.
static var path: String = "user://session.dat"


## The stored session, {} when there is none, or {"unreadable": true} when a
## file exists but cannot be decrypted (other device id, damaged file). A damaged
## main file falls back to the .bak copy of the previous good session.
static func load_session() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Dictionary = _read(path)
	if data.is_empty() and FileAccess.file_exists(path + ".bak"):
		data = _read(path + ".bak")
	if data.is_empty():
		return {"unreadable": true}
	return data


## Writes atomically (temp file, read back, previous good file kept as .bak, then
## rename). Returns false on failure; the old session stays then.
static func save_session(session: Dictionary) -> bool:
	var tmp: String = path + ".tmp"
	var file := FileAccess.open_encrypted_with_pass(tmp, FileAccess.WRITE, _key())
	if file == null:
		return false
	file.store_string(JSON.stringify(session))
	file.close()
	if _read(tmp).is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	var real: String = ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) and not _read(path).is_empty():
		DirAccess.copy_absolute(real, real + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real) == OK


static func clear() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var real: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(real)


static func _read(file_path: String) -> Dictionary:
	var file := FileAccess.open_encrypted_with_pass(file_path, FileAccess.READ, _key())
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data is Dictionary else {}


static func _key() -> String:
	return (OS.get_unique_id() + "|" + APP_SALT).sha256_text()
