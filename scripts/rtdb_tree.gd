class_name RtdbTree
extends RefCounted
## Local mirror of a streamed location: applies the put/patch events of a
## Realtime Database stream (paths relative to the listened node) and answers
## reads. Like the database, it never keeps empty nodes (null removes).

var value: Variant = null


## Applies one event. Returns false for a malformed one.
func apply(kind: String, path: String, data: Variant) -> bool:
	if kind == "put":
		_assign(_segments(path), data)
		return true
	if kind == "patch":
		if not data is Dictionary:
			return false
		var base: Array[String] = _segments(path)
		for key in (data as Dictionary).keys():
			_assign(base + _segments(str(key)), (data as Dictionary)[key])
		return true
	return false


## Value at `path` ("a/b"; "" or "/" = the root) or `fallback`.
func get_at(path: String, fallback: Variant = null) -> Variant:
	var node: Variant = value
	for key in _segments(path):
		if not node is Dictionary or not (node as Dictionary).has(key):
			return fallback
		node = (node as Dictionary)[key]
	return node


func clear() -> void:
	value = null


func _assign(segments: Array[String], data: Variant) -> void:
	var pruned: Variant = _prune(data)
	if segments.is_empty():
		value = pruned
		return
	if not value is Dictionary:
		if pruned == null:
			return
		value = {}
	var node: Dictionary = value
	var trail: Array[Dictionary] = [node]
	for i in range(segments.size() - 1):
		var next: Variant = node.get(segments[i])
		if not next is Dictionary:
			if pruned == null:
				return
			next = {}
			node[segments[i]] = next
		node = next
		trail.append(node)
	var leaf: String = segments[segments.size() - 1]
	if pruned == null:
		node.erase(leaf)
	else:
		node[leaf] = pruned
	# Remove emptied parents bottom-up.
	for i in range(trail.size() - 1, 0, -1):
		if trail[i].is_empty():
			trail[i - 1].erase(segments[i - 1])
	if (value as Dictionary).is_empty():
		value = null


func _prune(data: Variant) -> Variant:
	if data is Dictionary:
		var out: Dictionary = {}
		for key in (data as Dictionary).keys():
			var child: Variant = _prune((data as Dictionary)[key])
			if child != null:
				out[key] = child
		return out if not out.is_empty() else null
	return data


func _segments(path: String) -> Array[String]:
	var out: Array[String] = []
	for part in path.split("/"):
		if part != "":
			out.append(part)
	return out
