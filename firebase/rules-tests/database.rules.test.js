// Realtime Database security rules (co-op rooms) against the local emulator.
// npm test   (in firebase/rules-tests; Java 21 and firebase-tools, see docs/FIREBASE.md)
//
// The tests speak the same REST protocol as scripts/rtdb_client.gd (PUT / PATCH at the
// root / GET with orderBy, ?auth=<token>), not the JS SDK: that is what the game sends,
// and the SDK's websocket does not connect to the emulator on every Node version.
// Tokens are unsigned JWTs, which the emulator accepts.
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { before, beforeEach, describe, test } = require("node:test");

const ROOT = join(__dirname, "..", "..");
const HOST = process.env.FIREBASE_DATABASE_EMULATOR_HOST || "127.0.0.1:9189";
const NS = "demo-bimbleguard-default-rtdb";
const TTL = 7200000;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function token(uid) {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: "https://securetoken.google.com/demo-bimbleguard",
    aud: "demo-bimbleguard",
    sub: uid,
    user_id: uid,
    iat: now,
    exp: now + 3600,
    firebase: { identities: {}, sign_in_provider: "anonymous" },
  };
  return `${b64({ alg: "none", typ: "JWT" })}.${b64(claims)}.`;
}

/** One REST call as `uid` (null = signed out, "__admin" = rules bypassed). */
async function call(method, path, body, uid, query = {}, headers = {}) {
  const params = new URLSearchParams({ ns: NS, print: "silent", ...query });
  if (method === "GET" || headers["if-match"]) params.delete("print"); // not combinable with if-match
  const h = { ...headers };
  if (uid === "__admin") h.Authorization = "Bearer owner";
  else if (uid) params.set("auth", token(uid));
  if (body !== null && body !== undefined) h["Content-Type"] = "application/json";
  const res = await fetch(`http://${HOST}/${path}.json?${params}`, {
    method,
    headers: h,
    body: body === null || body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, ok: res.ok, value: text ? JSON.parse(text) : null };
}

// A tiny SDK-shaped layer so the tests read naturally.
const db = (uid) => ({ uid });
const anon = () => ({ uid: null });
const ref = (d, path = "") => ({ d, path: path.replace(/^\//, ""), query: {} });
const serverTimestamp = () => ({ ".sv": "timestamp" });
const set = (r, value) => call("PUT", r.path, value, r.d.uid);
const setIfAbsent = (r, value) => call("PUT", r.path, value, r.d.uid, {}, { "if-match": "null_etag" });
const update = (r, map) => call("PATCH", r.path, map, r.d.uid);
const remove = (r) => call("DELETE", r.path, null, r.d.uid);
const get = async (r) => {
  const res = await call("GET", r.path, null, r.d.uid, r.query);
  return { ...res, val: () => res.value };
};
const query = (r, ...mods) => ({ ...r, query: Object.assign({}, ...mods) });
const orderByKey = () => ({ orderBy: '"$key"' });
const startAt = (key) => ({ startAt: JSON.stringify(key) });

const assertSucceeds = async (p) => {
  const res = await p;
  assert.ok(res.ok, `expected success, got ${res.status} ${JSON.stringify(res.value)}`);
  return res;
};
const assertFails = async (p) => {
  const res = await p;
  assert.ok(res.status === 401 || res.status === 403, `expected a denial, got ${res.status}`);
  return res;
};

const metaOf = (host, extra = {}) => ({
  host,
  level: 3,
  seed: 12345,
  simv: 7,
  delay: 15,
  rev: 1,
  state: "lobby",
  created: serverTimestamp(),
  expiresAt: Date.now() + TTL,
  pv: 1,
  ...extra,
});

const seq = (n) => String(n).padStart(6, "0");

/** Same two steps as CoopLobby.create(); returns the first failing reply, else the last. */
async function makeRoom(code, host, extra = {}) {
  const d = db(host);
  const meta = await set(ref(d, `rooms/${code}/meta`), metaOf(host, extra));
  if (!meta.ok) return meta;
  return update(ref(d), {
    [`rooms/${code}/players/host`]: { uid: host, name: "Host", ready: 1 },
    [`user_rooms/${host}`]: code,
  });
}

/** Same two steps as CoopLobby.join(). */
async function joinRoom(code, guest) {
  const d = db(guest);
  const slot = await set(ref(d, `rooms/${code}/players/guest`), { uid: guest, name: "Guest", ready: 0 });
  if (!slot.ok) return slot;
  return set(ref(d, `user_rooms/${guest}`), code);
}

/** Writes with the rules bypassed (a room "from the past", a started room...). */
async function admin(fn) {
  return fn({ uid: "__admin" });
}

const msg = (n, extra = {}) => ({ s: n, f: 14 + n, d: "", ...extra });

before(async () => {
  // The emulator loaded database.rules.json from firebase.json; check it is the same file.
  const res = await call("GET", ".settings/rules", null, "__admin");
  assert.ok(res.status === 200, "cannot read the emulator rules");
  readFileSync(join(ROOT, "database.rules.json"), "utf8");
});

beforeEach(async () => {
  await call("DELETE", "", null, "__admin");
});

describe("closed by default", () => {
  test("signed-out users cannot read or write anything", async () => {
    await makeRoom("ABCDE", "host1");
    const d = anon();
    await assertFails(get(ref(d, "rooms/ABCDE/meta")));
    await assertFails(get(ref(d, "rooms/ABCDE/players")));
    await assertFails(set(ref(d, "rooms/FGHJK/meta"), metaOf("x")));
    await assertFails(set(ref(d, "user_rooms/x"), "ABCDE"));
  });

  test("nobody reads the root, rooms, or other users' index", async () => {
    await makeRoom("ABCDE", "host1");
    const d = db("stranger");
    await assertFails(get(ref(d, "/")));
    await assertFails(get(ref(d, "rooms")));
    await assertFails(get(ref(d, "rooms/ABCDE")));
    await assertFails(get(ref(d, "user_rooms")));
    await assertFails(get(ref(d, "user_rooms/host1")));
    await assertSucceeds(get(ref(d, "user_rooms/stranger")));
  });

  test("junk at the top level or inside a room is refused", async () => {
    const d = db("host1");
    await assertFails(set(ref(d, "junk"), { a: 1 }));
    await makeRoom("ABCDE", "host1");
    await assertFails(set(ref(d, "rooms/ABCDE/junk"), 1));
    await assertFails(set(ref(d, "rooms/ABCDE/meta/extra"), 1));
    await assertFails(set(ref(d, "rooms/ABCDE/players/third"), { uid: "host1", name: "x", ready: 0 }));
  });

  test("create-if-absent answers 412 when the node exists (code collisions)", async () => {
    await makeRoom("ABCDE", "host1");
    await admin((d) => set(ref(d, "user_rooms/zzz"), "ABCDE"));
    const again = await setIfAbsent(ref(db("host2"), "rooms/ABCDE/meta"), metaOf("host2"));
    assert.equal(again.status, 412);
    const fresh = await setIfAbsent(ref(db("host2"), "rooms/FGHJK/meta"), metaOf("host2"));
    assert.ok(fresh.ok);
  });

  test("room codes must be 5 symbols without O/0/I/1", async () => {
    const d = db("host1");
    for (const code of ["ABCD", "ABCDEF", "ABCD0", "ABCDO", "abcde", "ABCDI", "ABCD1"]) {
      await assertFails(set(ref(d, `rooms/${code}/meta`), metaOf("host1")));
    }
    await assertSucceeds(set(ref(d, "rooms/ABCDE/meta"), metaOf("host1")));
  });
});

describe("creating a room", () => {
  test("the host creates meta, players/host and the index", async () => {
    await assertSucceeds(makeRoom("ABCDE", "host1"));
  });

  test("meta must name the writer as host", async () => {
    await assertFails(set(ref(db("evil"), "rooms/ABCDE/meta"), metaOf("host1")));
  });

  test("shape and size validation of meta", async () => {
    const d = db("host1");
    const bad = [
      { level: 0 },
      { level: 51 },
      { level: 1.5 },
      { level: "3" },
      { seed: 0 },
      { delay: 5 },
      { delay: 61 },
      { rev: 2 },
      { state: "playing" },
      { pv: 2 },
      { created: 12345 },
      { expiresAt: Date.now() - 1000 },
      { expiresAt: Date.now() + 5 * 3600000 },
      { junk: 1 },
    ];
    for (const extra of bad) {
      await assertFails(set(ref(d, "rooms/ABCDE/meta"), metaOf("host1", extra)));
    }
    const missing = metaOf("host1");
    delete missing.seed;
    await assertFails(set(ref(d, "rooms/ABCDE/meta"), missing));
  });

  test("an existing room cannot be taken over", async () => {
    await makeRoom("ABCDE", "host1");
    await assertFails(set(ref(db("host2"), "rooms/ABCDE/meta"), metaOf("host2")));
  });

  test("one room per user: the index blocks a second one", async () => {
    await makeRoom("ABCDE", "host1");
    await assertFails(set(ref(db("host1"), "rooms/FGHJK/meta"), metaOf("host1")));
    await update(ref(db("host1")), {
      "rooms/ABCDE/meta": null,
      "rooms/ABCDE/players/host": null,
      "user_rooms/host1": null,
    });
    await assertSucceeds(makeRoom("FGHJK", "host1"));
  });

  test("the index holds only a valid code and only the owner's", async () => {
    await assertFails(set(ref(db("u1"), "user_rooms/u1"), "nope"));
    await assertFails(set(ref(db("u1"), "user_rooms/u2"), "ABCDE"));
    await assertSucceeds(set(ref(db("u1"), "user_rooms/u1"), "ABCDE"));
  });

  test("players/host: right uid, name 1..16, no extras", async () => {
    await set(ref(db("host1"), "rooms/ABCDE/meta"), metaOf("host1"));
    const p = ref(db("host1"), "rooms/ABCDE/players/host");
    await assertFails(set(p, { uid: "someone", name: "A", ready: 1 }));
    await assertFails(set(p, { uid: "host1", name: "", ready: 1 }));
    await assertFails(set(p, { uid: "host1", name: "x".repeat(17), ready: 1 }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, junk: 1 }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 9 }));
    await assertSucceeds(set(p, { uid: "host1", name: "Аня", ready: 1 }));
  });

  test("players/host: the cosmetic skin id is a short lower-case id", async () => {
    await set(ref(db("host1"), "rooms/ABCDE/meta"), metaOf("host1"));
    const p = ref(db("host1"), "rooms/ABCDE/players/host");
    await assertSucceeds(set(p, { uid: "host1", name: "A", ready: 1, skin: "hero_ember" }));
    await assertSucceeds(set(p, { uid: "host1", name: "A", ready: 1, skin: "" }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, skin: "x".repeat(33) }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, skin: "Hero Ember" }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, skin: "<b>" }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, skin: 5 }));
    await assertFails(set(p, { uid: "host1", name: "A", ready: 1, skin: { a: 1 } }));
  });
});

describe("reading", () => {
  test("anyone signed in reads meta and players (to join by code), not net", async () => {
    await makeRoom("ABCDE", "host1");
    const d = db("stranger");
    await assertSucceeds(get(ref(d, "rooms/ABCDE/meta")));
    await assertSucceeds(get(ref(d, "rooms/ABCDE/players")));
    await assertFails(get(ref(d, "rooms/ABCDE/net")));
    await assertFails(get(ref(d, "rooms/ABCDE/net/host")));
  });

  test("members read the whole room", async () => {
    await makeRoom("ABCDE", "host1");
    await joinRoom("ABCDE", "guest1");
    await assertSucceeds(get(ref(db("host1"), "rooms/ABCDE")));
    await assertSucceeds(get(ref(db("guest1"), "rooms/ABCDE")));
    await assertFails(get(ref(db("stranger"), "rooms/ABCDE")));
  });
});

describe("joining", () => {
  beforeEach(async () => {
    await makeRoom("ABCDE", "host1");
  });

  test("a guest joins the free slot", async () => {
    await assertSucceeds(joinRoom("ABCDE", "guest1"));
  });

  test("the slot is taken once: no second guest, no takeover", async () => {
    await joinRoom("ABCDE", "guest1");
    await assertFails(set(ref(db("guest2"), "rooms/ABCDE/players/guest"), { uid: "guest2", name: "G2", ready: 0 }));
    await assertFails(set(ref(db("guest2"), "rooms/ABCDE/players/guest/uid"), "guest2"));
  });

  test("writing someone else's uid, or being the host, is refused", async () => {
    const g = ref(db("guest1"), "rooms/ABCDE/players/guest");
    await assertFails(set(g, { uid: "guest2", name: "G", ready: 0 }));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/players/guest"), { uid: "host1", name: "H", ready: 0 }));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/players/guest"), { uid: "ghost", name: "H", ready: 0 }));
  });

  test("not into an expired room", async () => {
    await admin(async (d) => {
      await set(ref(d, "rooms/OLDRM/meta"), metaOf("host2", { expiresAt: Date.now() - 1000, created: Date.now() - TTL }));
    });
    await assertFails(joinRoom("OLDRM", "guest1"));
  });

  test("not into a started room", async () => {
    await joinRoom("ABCDE", "guest1");
    await set(ref(db("guest1"), "rooms/ABCDE/players/guest/ready"), 1);
    await set(ref(db("host1"), "rooms/ABCDE/meta/state"), "playing");
    await update(ref(db("guest1")), { "rooms/ABCDE/players/guest": null, "user_rooms/guest1": null });
    await assertFails(set(ref(db("guest3"), "rooms/ABCDE/players/guest"), { uid: "guest3", name: "G", ready: 0 }));
  });

  test("a user in another room cannot join (one room per user)", async () => {
    await makeRoom("FGHJK", "host2");
    await joinRoom("FGHJK", "guest1");
    await assertFails(set(ref(db("guest1"), "rooms/ABCDE/players/guest"), { uid: "guest1", name: "G", ready: 0 }));
  });
});

describe("lobby: ready, level, start", () => {
  beforeEach(async () => {
    await makeRoom("ABCDE", "host1");
    await joinRoom("ABCDE", "guest1");
  });

  test("a guest sets ready to the current revision or 0, nothing else", async () => {
    const r = ref(db("guest1"), "rooms/ABCDE/players/guest/ready");
    await assertSucceeds(set(r, 1));
    await assertSucceeds(set(r, 0));
    await assertFails(set(r, 2));
    await assertFails(set(r, 1.5));
    await assertFails(set(r, "1"));
  });

  test("the host cannot change the guest's readiness, nor the guest the host's", async () => {
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/players/guest/ready"), 1));
    await assertFails(set(ref(db("guest1"), "rooms/ABCDE/players/host/ready"), 0));
  });

  test("the host changes level with rev+1 in one update", async () => {
    await assertSucceeds(
      update(ref(db("host1")), {
        "rooms/ABCDE/meta/level": 5,
        "rooms/ABCDE/meta/rev": 2,
        "rooms/ABCDE/players/host/ready": 2,
      }),
    );
    await assertFails(update(ref(db("host1")), { "rooms/ABCDE/meta/rev": 9 }));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/meta/level"), 99));
  });

  test("a guest cannot change meta", async () => {
    await assertFails(set(ref(db("guest1"), "rooms/ABCDE/meta/level"), 4));
    await assertFails(set(ref(db("guest1"), "rooms/ABCDE/meta/state"), "playing"));
    await assertFails(set(ref(db("stranger"), "rooms/ABCDE/meta/level"), 4));
  });

  test("immutable fields stay", async () => {
    const d = db("host1");
    await assertFails(set(ref(d, "rooms/ABCDE/meta/seed"), 999));
    await assertFails(set(ref(d, "rooms/ABCDE/meta/host"), "guest1"));
    await assertFails(set(ref(d, "rooms/ABCDE/meta/delay"), 20));
    await assertFails(set(ref(d, "rooms/ABCDE/meta/created"), 1));
    await assertFails(set(ref(d, "rooms/ABCDE/meta/expiresAt"), Date.now() + 1000));
  });

  test("start needs both players ready for the current revision", async () => {
    const state = ref(db("host1"), "rooms/ABCDE/meta/state");
    await assertFails(set(state, "playing")); // guest not ready
    await set(ref(db("guest1"), "rooms/ABCDE/players/guest/ready"), 1);
    await assertSucceeds(set(state, "playing"));
    await assertFails(set(state, "lobby")); // no way back
  });

  test("a stale ready does not start the match after a level change", async () => {
    await set(ref(db("guest1"), "rooms/ABCDE/players/guest/ready"), 1);
    await update(ref(db("host1")), {
      "rooms/ABCDE/meta/level": 4,
      "rooms/ABCDE/meta/rev": 2,
      "rooms/ABCDE/players/host/ready": 2,
    });
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/meta/state"), "playing"));
  });
});

describe("match messages", () => {
  beforeEach(async () => {
    await makeRoom("ABCDE", "host1");
    await joinRoom("ABCDE", "guest1");
  });
  const host = (n) => ref(db("host1"), `rooms/ABCDE/net/host/${seq(n)}`);
  const guest = (n) => ref(db("guest1"), `rooms/ABCDE/net/guest/${seq(n)}`);

  test("members write their own stream, in order, with their s", async () => {
    await assertSucceeds(set(host(1), msg(1)));
    await assertSucceeds(set(host(2), msg(2, { d: '{"c":[[20,"sell",[1]]]}' })));
    await assertSucceeds(set(guest(1), msg(1)));
  });

  test("a batch of consecutive messages in one update is accepted, a batch with a gap is not", async () => {
    const base = "rooms/ABCDE/net/host/";
    await assertSucceeds(
      update(ref(db("host1")), { [base + seq(1)]: msg(1), [base + seq(2)]: msg(2), [base + seq(3)]: msg(3) }),
    );
    await assertFails(update(ref(db("host1")), { [base + seq(5)]: msg(5), [base + seq(6)]: msg(6) }));
  });

  test("no gaps: a message needs its predecessor", async () => {
    await assertFails(set(host(2), msg(2)));
    await set(host(1), msg(1));
    await assertFails(set(host(3), msg(3)));
  });

  test("the key must match s; s in range", async () => {
    await assertFails(set(host(1), msg(2)));
    await assertFails(set(host(1), msg(0)));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/net/host/1"), msg(1)));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/net/host/0000001"), msg(1)));
  });

  test("a message is write-once (the same data again is fine)", async () => {
    await set(host(1), msg(1));
    await assertSucceeds(set(host(1), msg(1)));
    await assertFails(set(host(1), msg(1, { f: 99 })));
    await assertFails(set(host(1), msg(1, { d: "x" })));
  });

  test("size and type limits", async () => {
    await assertSucceeds(set(host(1), msg(1, { d: "x".repeat(900) })));
    await assertFails(set(host(2), msg(2, { d: "x".repeat(901) })));
    await assertFails(set(host(2), msg(2, { f: -1 })));
    await assertFails(set(host(2), msg(2, { f: 1.5 })));
    await assertFails(set(host(2), msg(2, { d: 5 })));
    await assertFails(set(host(2), msg(2, { junk: 1 })));
    await assertFails(set(host(2), { s: 2, f: 3 }));
  });

  test("only your own stream", async () => {
    await assertFails(set(ref(db("guest1"), `rooms/ABCDE/net/host/${seq(1)}`), msg(1)));
    await assertFails(set(ref(db("host1"), `rooms/ABCDE/net/guest/${seq(1)}`), msg(1)));
    await assertFails(set(ref(db("stranger"), `rooms/ABCDE/net/host/${seq(1)}`), msg(1)));
    await assertFails(set(ref(db("stranger"), `rooms/ABCDE/net/guest/${seq(1)}`), msg(1)));
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/net/other/000001"), msg(1)));
  });

  test("members read the partner's stream with the key filter; strangers cannot", async () => {
    await set(host(1), msg(1));
    await set(host(2), msg(2));
    const q = query(ref(db("guest1"), "rooms/ABCDE/net/host"), orderByKey(), startAt(seq(2)));
    const snap = await assertSucceeds(get(q));
    if (Object.keys(snap.value).join() !== seq(2)) throw new Error("filter did not apply");
    await assertFails(get(query(ref(db("stranger"), "rooms/ABCDE/net/host"), orderByKey(), startAt(seq(1)))));
  });

  test("no writes after the room expired", async () => {
    await admin(async (d) => {
      await set(ref(d, "rooms/OLDRM/meta"), metaOf("host2", { expiresAt: Date.now() - 1000, created: Date.now() - TTL }));
      await set(ref(d, "rooms/OLDRM/players/host"), { uid: "host2", name: "H", ready: 1 });
    });
    await assertFails(set(ref(db("host2"), `rooms/OLDRM/net/host/${seq(1)}`), msg(1)));
  });

  test("the host cannot forge the guest's messages but can delete them", async () => {
    await set(guest(1), msg(1));
    await assertSucceeds(remove(ref(db("host1"), "rooms/ABCDE/net/guest")));
  });
});

describe("leaving and cleanup", () => {
  beforeEach(async () => {
    await makeRoom("ABCDE", "host1");
    await joinRoom("ABCDE", "guest1");
    await set(ref(db("guest1"), `rooms/ABCDE/net/guest/${seq(1)}`), msg(1));
    await set(ref(db("host1"), `rooms/ABCDE/net/host/${seq(1)}`), msg(1));
  });

  test("a guest removes only its own entries", async () => {
    await assertSucceeds(
      update(ref(db("guest1")), {
        "rooms/ABCDE/players/guest": null,
        "rooms/ABCDE/net/guest": null,
        "user_rooms/guest1": null,
      }),
    );
    await assertFails(remove(ref(db("guest1"), "rooms/ABCDE/meta")));
    await assertFails(remove(ref(db("guest1"), "rooms/ABCDE/players/host")));
    await assertFails(remove(ref(db("guest1"), "rooms/ABCDE/net/host")));
  });

  test("the host removes the whole room (what account deletion does)", async () => {
    await assertSucceeds(
      update(ref(db("host1")), {
        "rooms/ABCDE/net/host": null,
        "rooms/ABCDE/net/guest": null,
        "rooms/ABCDE/players/guest": null,
        "rooms/ABCDE/players/host": null,
        "rooms/ABCDE/meta": null,
        "user_rooms/host1": null,
      }),
    );
    const left = await admin(async (d) => (await get(ref(d, "rooms"))).val());
    if (left) throw new Error("something was left behind");
  });

  test("a stranger deletes nothing", async () => {
    const d = db("stranger");
    await assertFails(remove(ref(d, "rooms/ABCDE/meta")));
    await assertFails(remove(ref(d, "rooms/ABCDE/players/guest")));
    await assertFails(remove(ref(d, "rooms/ABCDE/net/host")));
    await assertFails(remove(ref(d, "user_rooms/host1")));
  });

  test("the host can remove a guest entry, but not edit it", async () => {
    await assertFails(set(ref(db("host1"), "rooms/ABCDE/players/guest/name"), "Hacked"));
    await assertSucceeds(remove(ref(db("host1"), "rooms/ABCDE/players/guest")));
  });
});
