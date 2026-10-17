# gdlint:disable=max-public-methods,max-returns
extends RefCounted
## Fake HTTP layer and fake Firebase project shared by the account tests
## (tests/test_accounts.gd, tests/test_email_accounts.gd). Never touches the network.


## Answers requests from `handler` (method, url, body) -> [code, json]; code 0 = no reply.
class FakeTransport:
	extends HttpTransport
	var handler: Callable
	var calls: Array[Dictionary] = []

	func send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		calls.append({"method": method, "url": url, "headers": headers, "body": body})
		await get_tree().process_frame  # replies arrive later, like real ones
		var answer: Array = handler.call(method, url, body)
		var code: int = answer[0]
		return {
			"ok": code >= 200 and code < 300,
			"code": code,
			"json": answer[1],
			"network": code == 0,
		}

	func count(fragment: String) -> int:
		var n: int = 0
		for call in calls:
			if fragment in str(call["url"]):
				n += 1
		return n


## Fake Firebase project: auth, users/{uid}, saves/{uid} and a generic document
## store for publicProfiles / nicknames / leaderboards. It mimics the rules that
## matter: creating an existing nickname document is refused (403), a taken name
## belongs to another uid.
class FakeFirebase:
	extends RefCounted
	var users_doc: Variant = null  # Dictionary of decoded fields or null
	var update_time: String = "2026-10-14T10:00:00.000001Z"
	var legacy_text: String = ""
	var fail_commits: int = 0
	var offline: bool = false
	var taken: Array[String] = []
	## users/{uid} commits only.
	var commits: Array[Dictionary] = []
	## Every commit body, in order.
	var all_commits: Array[Array] = []
	## Other documents by path ("publicProfiles/uid1" -> decoded fields).
	var docs: Dictionary = {}
	var auth_deleted: bool = false
	var auth_delete_error: String = ""
	var refuse_commits: int = 0
	## Unix time the fake server believes it is (0 = the real clock): the daily board rules
	## compare the day in the path with it.
	var server_time: int = 0
	## uid of the next anonymous sign-up (a second "device").
	var guest_uid: String = "uid1"
	## Email accounts (lower-case email -> {"password", "uid"}).
	var accounts: Dictionary = {}
	## users/{uid} of every uid but "uid1" (that one is users_doc).
	var other_users: Dictionary = {}
	## Server-side minimum password length.
	var min_password: int = 6
	## URL fragment -> Firebase error message to answer with instead of working.
	var forced: Dictionary = {}
	## URL fragment -> a whole reply [code, json] (code 0 = timeout), see the make_* helpers.
	var forced_raw: Dictionary = {}
	## Bodies of the email requests: {"url", "body"} (accounts:update, signInWithPassword, ...).
	var email_requests: Array[Dictionary] = []
	## Password reset mails that were "sent".
	var oob: Array[Dictionary] = []
	## Verification mails (VERIFY_EMAIL) that were "sent": the email of the account.
	var verify_mails: Array[String] = []
	## Emails confirmed by a click on the link (lower case).
	var verified: Array[String] = []

	func handle(method: int, url: String, body: String) -> Array:
		if offline:
			return [0, null]
		if "accounts:" in url or "securetoken" in url:
			return auth_reply(url, body)
		if url.ends_with(":commit"):
			return commit(body)
		if url.ends_with(":runQuery"):
			return run_query(url)
		return document(method, url)

	func auth_reply(url: String, body: String) -> Array:
		var parsed: Variant = JSON.parse_string(body) if body.begins_with("{") else null
		var data: Dictionary = parsed if parsed is Dictionary else {}
		var is_verify: bool = data.get("requestType", "") == "VERIFY_EMAIL"
		if "accounts:update" in url or "signInWithPassword" in url or "sendOobCode" in url:
			if not is_verify:
				email_requests.append({"url": url, "body": data})
		if "signUp" in url and data.has("email"):
			email_requests.append({"url": url, "body": data})
		for fragment: String in forced_raw:
			if fragment in url:
				return forced_raw[fragment]
		for fragment: String in forced:
			if fragment in url:
				return [400, {"error": {"code": 400, "message": forced[fragment]}}]
		return route(url, body, data)

	## Failure modes of the Identity Toolkit as the real server answers them.
	static func err_operation_not_allowed() -> Array:
		return [400, {"error": {"code": 400, "message": "OPERATION_NOT_ALLOWED"}}]

	static func err_admin_only() -> Array:
		return [400, {"error": {"code": 400, "message": "ADMIN_ONLY_OPERATION"}}]

	## 403 PERMISSION_DENIED with reason API_KEY_SERVICE_BLOCKED (key restricted).
	static func err_key_blocked() -> Array:
		return [
			403,
			{
				"error":
				{
					"code": 403,
					"message": "Requests to this API identitytoolkit method are blocked.",
					"status": "PERMISSION_DENIED",
					"details":
					[
						{
							"@type": "type.googleapis.com/google.rpc.ErrorInfo",
							"reason": "API_KEY_SERVICE_BLOCKED",
							"domain": "googleapis.com"
						}
					]
				}
			}
		]

	static func err_no_body() -> Array:
		return [400, null]

	static func err_timeout() -> Array:
		return [0, null]

	func route(url: String, body: String, data: Dictionary) -> Array:
		if "signUp" in url:
			if data.has("email"):
				return sign_up(data)
			return tokens(guest_uid)
		if "accounts:lookup" in url:
			return lookup(data)
		if "securetoken" in url:
			return refresh(body)
		if "accounts:update" in url:
			return link(data)
		if "signInWithPassword" in url:
			return sign_in(data)
		if "sendOobCode" in url:
			return send_oob(data)
		return delete_user()

	func delete_user() -> Array:
		if auth_delete_error != "":
			return [400, {"error": {"message": auth_delete_error}}]
		auth_deleted = true
		return [200, {}]

	func refresh(body: String) -> Array:
		var token: String = body.get_slice("refresh_token=", 1).uri_decode()
		var uid: String = token.trim_prefix("RT:") if token.begins_with("RT:") else "uid1"
		return [
			200,
			{
				"id_token": "ID:" + uid,
				"refresh_token": "RT:" + uid,
				"user_id": uid,
				"expires_in": "3600"
			}
		]

	func sign_in(data: Dictionary) -> Array:
		var key: String = str(data.get("email", "")).to_lower()
		if not accounts.has(key) or accounts[key]["password"] != data.get("password", ""):
			return [400, {"error": {"message": "INVALID_LOGIN_CREDENTIALS"}}]
		return tokens(str(accounts[key]["uid"]))

	## accounts:signUp with email + password: a fresh account (uid = guest_uid).
	func sign_up(data: Dictionary) -> Array:
		var key: String = str(data.get("email", "")).to_lower()
		if accounts.has(key):
			return [400, {"error": {"message": "EMAIL_EXISTS"}}]
		if str(data.get("password", "")).length() < min_password:
			return [400, {"error": {"message": "WEAK_PASSWORD : Password should be longer"}}]
		accounts[key] = {"password": data["password"], "uid": guest_uid}
		return tokens(guest_uid)

	## accounts:lookup for the account the idToken belongs to.
	func lookup(data: Dictionary) -> Array:
		var uid: String = str(data.get("idToken", "")).trim_prefix("ID:")
		for key: String in accounts:
			if accounts[key]["uid"] == uid:
				return [
					200,
					{"users": [{"localId": uid, "email": key, "emailVerified": key in verified}]}
				]
		return [200, {"users": [{"localId": uid}]}]

	func send_oob(data: Dictionary) -> Array:
		if data.get("requestType", "") == "VERIFY_EMAIL":
			var uid: String = str(data.get("idToken", "")).trim_prefix("ID:")
			for key: String in accounts:
				if accounts[key]["uid"] == uid:
					verify_mails.append(key)
					return [200, {"email": key}]
			return [400, {"error": {"message": "INVALID_ID_TOKEN"}}]
		oob.append(data)
		if not accounts.has(str(data.get("email", "")).to_lower()):
			return [400, {"error": {"message": "EMAIL_NOT_FOUND"}}]
		return [200, {"email": data.get("email", "")}]

	func tokens(uid: String) -> Array:
		return [
			200,
			{
				"idToken": "ID:" + uid,
				"refreshToken": "RT:" + uid,
				"localId": uid,
				"expiresIn": "3600"
			}
		]

	## accounts:update with email + password on the guest the idToken belongs to.
	func link(data: Dictionary) -> Array:
		var key: String = str(data.get("email", "")).to_lower()
		if accounts.has(key):
			return [400, {"error": {"message": "EMAIL_EXISTS"}}]
		if str(data.get("password", "")).length() < min_password:
			return [400, {"error": {"message": "WEAK_PASSWORD : Password should be longer"}}]
		var uid: String = str(data.get("idToken", "")).trim_prefix("ID:")
		accounts[key] = {"password": data["password"], "uid": uid if uid != "ID" else "uid1"}
		return tokens(str(accounts[key]["uid"]))

	func path_of(name: String) -> String:
		return name.get_slice("/documents/", 1)

	func exists(path: String) -> bool:
		if path.begins_with("nicknames/") and path.trim_prefix("nicknames/") in taken:
			return true
		return docs.has(path)

	func fields_of(path: String) -> Dictionary:
		if path.begins_with("nicknames/") and path.trim_prefix("nicknames/") in taken:
			return {"uid": "someone-else"}
		return docs.get(path, {})

	func commit(body: String) -> Array:
		var writes: Array = JSON.parse_string(body)["writes"]
		all_commits.append(writes)
		if refuse_commits > 0:
			refuse_commits -= 1
			return [403, {"error": {"status": "PERMISSION_DENIED"}}]
		var touches_users := false
		for write: Dictionary in writes:
			var name: String = str(
				write["update"]["name"] if write.has("update") else write["delete"]
			)
			if path_of(name).begins_with("users/"):
				touches_users = true
		if touches_users and writes.size() == 1 and writes[0].has("update"):
			return commit_users(writes[0])
		# Generic documents: validate every write first (all or nothing).
		var refusal: Array = validate_writes(writes)
		if not refusal.is_empty():
			return refusal
		for write: Dictionary in writes:
			if write.has("delete"):
				var gone: String = path_of(write["delete"])
				docs.erase(gone)
				if gone == "users/uid1":
					users_doc = null
				elif gone.begins_with("users/"):
					other_users.erase(gone.trim_prefix("users/"))
			else:
				var path: String = path_of(write["update"]["name"])
				var fields: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
				for transform: Dictionary in write.get("updateTransforms", []):
					fields[str(transform["fieldPath"])] = int(Time.get_unix_time_from_system())
				var merged: Dictionary = docs.get(path, {})
				merged.merge(fields, true)
				docs[path] = merged
		return [200, {"writeResults": [{}]}]

	## [] if every write passes the preconditions and the trace rules, else the error reply.
	func validate_writes(writes: Array) -> Array:
		var denied := [403, {"error": {"status": "PERMISSION_DENIED"}}]
		for write: Dictionary in writes:
			if write.has("update"):
				var path: String = path_of(write["update"]["name"])
				var precondition: Dictionary = write.get("currentDocument", {})
				if precondition.get("exists", true) == false and exists(path):
					return denied
				if precondition.get("exists", false) == true and not exists(path):
					return [404, {"error": {"status": "NOT_FOUND"}}]
				if path.begins_with("nicknameTrace/") and exists(path) and trace_recent(path):
					return denied  # rules: rewritten at most every 24 hours
				if path.begins_with("leaderboards/") and not run_allows(path):
					return denied  # rules: runs/{uid} must exist with the same level
				if path.begins_with("daily/") and not daily_allows(path, write):
					return denied
			if write.has("delete"):
				var gone_path: String = path_of(write["delete"])
				var is_trace: bool = gone_path.begins_with("nicknameTrace/")
				if is_trace and exists(gone_path) and trace_recent(gone_path):
					return denied
		return []

	## firestore.rules runAllows (the time bound is not modelled): a record needs runs/{uid}
	## of the same level.
	func run_allows(path: String) -> bool:
		var parts: PackedStringArray = path.split("/")  # leaderboards/level_N/scores/uid
		var run: String = "runs/" + parts[3]
		return docs.has(run) and docs[run].get("level", "") == parts[1]

	## firestore.rules daily/{day}/scores/{uid}: the day is today by the server clock (one hour
	## of grace after midnight), the wave is 1..499 and above the stored one.
	func daily_allows(path: String, write: Dictionary) -> bool:
		var parts: PackedStringArray = path.split("/")  # daily/day/scores/uid
		if parts.size() != 4 or parts[2] != "scores":
			return false
		var now: int = server_time if server_time > 0 else int(Time.get_unix_time_from_system())
		var days: Array[String] = [Daily.key_for(now), Daily.key_for(now - 3600)]
		if not parts[1] in days:
			return false
		var fields: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
		var wave: Variant = fields.get("wave", 0)
		if not wave is int or wave < 1 or wave > 499:
			return false
		return not docs.has(path) or wave > int(docs[path].get("wave", 0))

	## runQuery under "<parent>": the documents of the collection "scores" below it, best wave first.
	func run_query(url: String) -> Array:
		var parent: String = url.get_slice("/documents/", 1).trim_suffix(":runQuery").uri_decode()
		var rows: Array = []
		for path: String in docs:
			if path.begins_with(parent + "/scores/"):
				rows.append(docs[path])
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["wave"] > b["wave"])
		var out: Array = []
		for fields: Dictionary in rows:
			out.append({"document": {"fields": FirestoreClient.encode_fields(fields)}})
		return [200, out if not out.is_empty() else [{}]]

	## firestore.rules: nicknameTrace/{uid} may only be rewritten or deleted after 24 hours.
	func trace_recent(path: String) -> bool:
		return Time.get_unix_time_from_system() < int(docs[path]["changedAt"]) + 86400

	func commit_users(write: Dictionary) -> Array:
		var uid: String = path_of(write["update"]["name"]).trim_prefix("users/")
		if uid != "uid1":
			var other: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
			other["updatedAt"] = 2000000000
			other_users[uid] = other
			return [200, {"writeResults": [{}]}]
		if fail_commits > 0:
			# Another device wrote first: the precondition fails.
			fail_commits -= 1
			users_doc = {"schemaVersion": 1, "progression": {"unlocked": 5, "stars": {"4": 3}}}
			update_time = "2026-10-14T11:00:00.000001Z"
			return [400, {"error": {"status": "FAILED_PRECONDITION"}}]
		commits.append(write)
		var fields: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
		fields["updatedAt"] = 2000000000
		users_doc = fields
		return [200, {"writeResults": [{}]}]

	func document(method: int, url: String) -> Array:
		var missing := [404, {"error": {"status": "NOT_FOUND"}}]
		if "/users/" in url and method == HTTPClient.METHOD_GET:
			var uid: String = url.get_slice("/users/", 1)
			var doc: Variant = users_doc if uid == "uid1" else other_users.get(uid)
			if doc == null:
				return missing
			return [200, {"fields": FirestoreClient.encode_fields(doc), "updateTime": update_time}]
		if "/saves/" in url:
			return saves(method)
		var path: String = url.get_slice("/documents/", 1).uri_decode()  # segments are encoded
		if method == HTTPClient.METHOD_GET and exists(path):
			return [200, {"fields": FirestoreClient.encode_fields(fields_of(path))}]
		return missing

	func saves(method: int) -> Array:
		if method == HTTPClient.METHOD_DELETE:
			legacy_text = ""
			return [200, {}]
		if legacy_text == "":
			return [404, {"error": {"status": "NOT_FOUND"}}]
		return [200, {"fields": {"progress": {"stringValue": legacy_text}}}]
