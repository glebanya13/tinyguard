// Firestore security rules tests against the local emulator (no real project).
// npm test   (in firebase/rules-tests; needs firebase-tools and Java, see docs/ACCOUNTS.md)
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { after, before, beforeEach, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} = require("firebase/firestore");

const ROOT = join(__dirname, "..", "..");
let env;

const profile = () => ({
  schemaVersion: 1,
  onboardingCompleted: true,
  tutorialVersionCompleted: 1,
  progression: { unlocked: 2, stars: { 1: 3 }, endless: {}, perks: { axe: 1 } },
  settings: { sound: true },
  updatedAt: serverTimestamp(),
});

/** Same normalization as scripts/nickname_rules.gd. */
const normalize = (name) => name.toLowerCase().replace(/ё/g, "е").replace(/ /g, "_");

/** Reserve (or change to) `name` the way the client does: one atomic batch. */
function reserveBatch(db, uid, name, { old = null, first = true, trace = true } = {}) {
  const key = normalize(name);
  const batch = writeBatch(db);
  if (old) batch.delete(doc(db, `nicknames/${normalize(old)}`));
  batch.set(doc(db, `nicknames/${key}`), { uid, nickname: name, createdAt: serverTimestamp() });
  const fields = { nickname: name, nicknameNormalized: key, nicknameChangedAt: serverTimestamp() };
  // The trace is rewritten in every reservation (set creates or replaces).
  if (trace) batch.set(doc(db, `nicknameTrace/${uid}`), { changedAt: serverTimestamp() });
  if (first) batch.set(doc(db, `publicProfiles/${uid}`), { ...fields, createdAt: serverTimestamp() });
  else batch.update(doc(db, `publicProfiles/${uid}`), fields);
  return batch;
}

/** Reads a document bypassing the rules (withSecurityRulesDisabled returns nothing). */
async function adminGet(path) {
  let snap;
  await env.withSecurityRulesDisabled(async (ctx) => {
    snap = await getDoc(doc(ctx.firestore(), path));
  });
  return snap;
}

/** Seeds an existing reservation, changed `hoursAgo` hours ago, bypassing rules. */
async function seedNickname(uid, name, hoursAgo = 48) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const at = Timestamp.fromMillis(Date.now() - hoursAgo * 3600 * 1000);
    await setDoc(doc(db, `nicknames/${normalize(name)}`), { uid, nickname: name, createdAt: at });
    await setDoc(doc(db, `publicProfiles/${uid}`), {
      nickname: name,
      nicknameNormalized: normalize(name),
      createdAt: at,
      nicknameChangedAt: at,
    });
    await setDoc(doc(db, `nicknameTrace/${uid}`), { changedAt: at });
  });
}

/** Seeds the run document as if the run started `secondsAgo` seconds ago. */
async function seedRun(uid, level, secondsAgo) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const at = Timestamp.fromMillis(Date.now() - secondsAgo * 1000);
    await setDoc(doc(ctx.firestore(), `runs/${uid}`), { level, startedAt: at });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bimbleguard",
    firestore: { rules: readFileSync(join(ROOT, "firestore.rules"), "utf8") },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

// ---- users ---------------------------------------------------------------

test("users: owner creates, reads, updates and deletes the private profile", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "users/alice");
  await assertSucceeds(setDoc(ref, { ...profile(), createdAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(updateDoc(ref, { settings: { sound: false }, updatedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(ref));
});

test("users: nobody else reads, writes or deletes it", async () => {
  const bob = env.authenticatedContext("bob").firestore();
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(bob, "users/alice"), { ...profile(), createdAt: serverTimestamp() }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), { schemaVersion: 1 });
  });
  await assertFails(getDoc(doc(bob, "users/alice")));
  await assertFails(getDoc(doc(anon, "users/alice")));
  await assertFails(deleteDoc(doc(bob, "users/alice")));
  await assertFails(deleteDoc(doc(anon, "users/alice")));
  await assertFails(setDoc(doc(anon, "users/alice"), { ...profile(), createdAt: serverTimestamp() }));
});

test("users: no nickname, extra keys, bad types, huge maps or fake timestamps", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "users/alice");
  const create = (extra) => setDoc(ref, { ...profile(), createdAt: serverTimestamp(), ...extra });
  await assertFails(create({ nickname: "Me" }));
  await assertFails(create({ email: "x@y.z" }));
  await assertFails(create({ tutorialVersionCompleted: "1" }));
  await assertFails(create({ updatedAt: 5 }));
  await assertFails(create({ createdAt: Timestamp.fromMillis(0) }));
  await assertFails(create({ onboardingCompleted: "yes" }));
  await assertFails(create({ schemaVersion: 0 }));
  await assertFails(create({ settings: { sound: true, volume: 3 } }));
  await assertFails(create({ settings: { sound: "loud" } }));
  const big = Object.fromEntries(Array.from({ length: 101 }, (_, i) => [String(i), 1]));
  await assertFails(create({ progression: { ...profile().progression, stars: big } }));
  await assertFails(create({ progression: { ...profile().progression, extra: 1 } }));
  await assertFails(create({ progression: { ...profile().progression, unlocked: 0 } }));
  await assertSucceeds(create({}));
  await assertFails(updateDoc(ref, { nickname: "Me", updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { settings: { sound: false } })); // updatedAt not server time
});

test("users: an older schema never overwrites a newer document", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), {
      ...profile(),
      schemaVersion: 2,
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(updateDoc(doc(db, "users/alice"), { schemaVersion: 1, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db, "users/alice"), { schemaVersion: 3, updatedAt: serverTimestamp() }));
});

test("users: list is forbidden", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const { getDocs, collection } = require("firebase/firestore");
  await assertFails(getDocs(collection(db, "users")));
});

// ---- nicknames -----------------------------------------------------------

test("nickname: first reservation succeeds (atomic batch)", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertSucceeds(reserveBatch(db, "alice", "Сэр Ёжик").commit());
  const snap = await adminGet("nicknames/сэр_ежик");
  assert.equal(snap.data().uid, "alice");
  await assertSucceeds(getDoc(doc(db, "publicProfiles/alice")));
});

test("nickname: a taken name cannot be created again, in any case or spelling", async () => {
  await seedNickname("alice", "Сова");
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(reserveBatch(bob, "bob", "Сова").commit());
  await assertFails(reserveBatch(bob, "bob", "сова").commit());
  await assertFails(reserveBatch(bob, "bob", "СОВА").commit());
  await seedNickname("carol", "Ёжик Ё");
  await assertFails(reserveBatch(bob, "bob", "Ежик Е").commit());
  await assertSucceeds(reserveBatch(bob, "bob", "Сова2").commit());
});

test("nickname: two players racing for one name, exactly one wins", async () => {
  const a = env.authenticatedContext("alice").firestore();
  const b = env.authenticatedContext("bob").firestore();
  const results = await Promise.allSettled([
    reserveBatch(a, "alice", "Racer").commit(),
    reserveBatch(b, "bob", "racer").commit(),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const owner = (await adminGet("nicknames/racer")).data().uid;
  const winner = results[0].status === "fulfilled" ? "alice" : "bob";
  assert.equal(owner, winner);
});

test("nickname: cannot take over, update or squat names for another uid", async () => {
  await seedNickname("alice", "Сова");
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(bob, "nicknames/сова"), { uid: "bob", nickname: "Сова", createdAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(bob, "nicknames/сова"), { uid: "bob" }));
  await assertFails(deleteDoc(doc(bob, "nicknames/сова")));
  // Creating a name for someone else.
  await assertFails(setDoc(doc(bob, "nicknames/mallory"), { uid: "alice", nickname: "Mallory", createdAt: serverTimestamp() }));
  // The owner cannot overwrite her own (update is never allowed).
  const alice = env.authenticatedContext("alice").firestore();
  await assertFails(updateDoc(doc(alice, "nicknames/сова"), { nickname: "СОВА" }));
});

test("nickname: one name per player (no hoarding, no orphans)", async () => {
  const db = env.authenticatedContext("alice").firestore();
  // An index document without a profile that points at it.
  await assertFails(setDoc(doc(db, "nicknames/hoard"), { uid: "alice", nickname: "Hoard", createdAt: serverTimestamp() }));
  await assertSucceeds(reserveBatch(db, "alice", "First").commit());
  // A second name without releasing the first.
  const batch = writeBatch(db);
  batch.set(doc(db, "nicknames/second"), { uid: "alice", nickname: "Second", createdAt: serverTimestamp() });
  batch.update(doc(db, "publicProfiles/alice"), {
    nickname: "Second",
    nicknameNormalized: "second",
    nicknameChangedAt: serverTimestamp(),
  });
  await assertFails(batch.commit());
  // Deleting the index document alone leaves a profile pointing nowhere.
  await assertFails(deleteDoc(doc(db, "nicknames/first")));
  // Profile alone, without an index document.
  await assertFails(setDoc(doc(db, "publicProfiles/alice"), { nickname: "Ghost", nicknameNormalized: "ghost", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() }));
});

test("nickname: change = delete old + create new in one batch, once per 24 hours", async () => {
  await seedNickname("alice", "Старое", 48);
  const db = env.authenticatedContext("alice").firestore();
  await assertSucceeds(reserveBatch(db, "alice", "Новое", { old: "Старое", first: false }).commit());
  const gone = await adminGet("nicknames/старое");
  assert.equal(gone.exists(), false);
  // Immediately again: refused by the 24 hour limit.
  await assertFails(reserveBatch(db, "alice", "Третье", { old: "Новое", first: false }).commit());
});

test("nickname: change without releasing the old name or inside 24 hours fails", async () => {
  await seedNickname("alice", "Старое", 1);
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(reserveBatch(db, "alice", "Новое", { old: "Старое", first: false }).commit());
  await env.clearFirestore();
  await seedNickname("alice", "Старое", 48);
  await assertFails(reserveBatch(db, "alice", "Новое", { first: false }).commit());
  // The old name is released but the profile was not updated.
  const batch = writeBatch(db);
  batch.delete(doc(db, "nicknames/старое"));
  await assertFails(batch.commit());
});

test("nickname: another player's profile cannot be written or deleted", async () => {
  await seedNickname("alice", "Alice", 48);
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(updateDoc(doc(bob, "publicProfiles/alice"), { nickname: "Pwned", nicknameNormalized: "pwned", nicknameChangedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(bob, "publicProfiles/alice")));
  await assertFails(reserveBatch(bob, "alice", "Pwned", { first: false }).commit());
});

test("nickname: policy is enforced (length, characters, reserved, key, extra fields)", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const bad = [
    "ab", // too short
    "Abcdefghijklmnopq", // 17
    "Рыцарь!",
    "Bob😀",
    "a  b", // double space
    "_ab", // leading underscore
    "ab_", // trailing underscore
    "a__b",
    " ab c", // leading space
    "tab\tname",
    "ab cd", // NBSP
    "ab​cd", // zero width
    "Admin",
    "Bimbleguard",
    "Рыцарь",
    "ПОДДЕРЖКА",
    "mix日本語",
    "Ω-omega",
  ];
  for (const name of bad) {
    await assertFails(reserveBatch(db, "alice", name).commit());
  }
  // Wrong key for a valid name.
  const wrongKey = writeBatch(db);
  wrongKey.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
  wrongKey.set(doc(db, "nicknames/other"), { uid: "alice", nickname: "Valid", createdAt: serverTimestamp() });
  wrongKey.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "other", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(wrongKey.commit());
  // Extra fields.
  const extra = writeBatch(db);
  extra.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
  extra.set(doc(db, "nicknames/valid"), { uid: "alice", nickname: "Valid", createdAt: serverTimestamp(), email: "a@b.c" });
  extra.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "valid", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(extra.commit());
  // Fake timestamps.
  const fake = writeBatch(db);
  fake.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
  fake.set(doc(db, "nicknames/valid"), { uid: "alice", nickname: "Valid", createdAt: Timestamp.fromMillis(0) });
  fake.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "valid", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(fake.commit());
  // A key that is not the lower-case form (would allow duplicates differing in case).
  for (const key of ["Valid", "VALID", "valid_", "val id", "vаlid"]) {
    const b = writeBatch(db);
    b.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
    b.set(doc(db, `nicknames/${key}`), { uid: "alice", nickname: "Valid", createdAt: serverTimestamp() });
    b.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: key, createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
    await assertFails(b.commit());
  }
  // And the good ones.
  for (const name of ["Аня", "Knight_42", "José Müller", "Їжак 2", "Abcdefghijklmnop"]) {
    await env.clearFirestore();
    await assertSucceeds(reserveBatch(db, "alice", name).commit());
  }
});

test("nickname: rules agree with tests/nickname_cases.json (the Godot policy table)", async () => {
  const table = JSON.parse(readFileSync(join(ROOT, "tests", "nickname_cases.json"), "utf8"));
  let checked = 0;
  for (const [raw, error, nickname, normalized] of table.cases) {
    await env.clearFirestore();
    const db = env.authenticatedContext("alice").firestore();
    if (error === "") {
      // `nickname` is the cleaned form the client sends.
      assert.equal(normalize(nickname), normalized, `normalization of ${JSON.stringify(raw)}`);
      await assertSucceeds(reserveBatch(db, "alice", nickname).commit());
    } else if (error !== "reserved") {
      // The client would never send the raw text, but if it did the rules refuse it.
      const guess = normalize(raw);
      const key = /^__.*__$|\//.test(guess) || guess === "" ? "zzz" : guess;
      const batch = writeBatch(db);
      batch.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
      batch.set(doc(db, `nicknames/${key}`), { uid: "alice", nickname: raw, createdAt: serverTimestamp() });
      batch.set(doc(db, "publicProfiles/alice"), { nickname: raw, nicknameNormalized: key, createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
      await assertFails(batch.commit());
    } else {
      await assertFails(reserveBatch(db, "alice", nickname).commit());
    }
    checked++;
  }
  assert.ok(checked > 10);
});

test("nickname: every character the client accepts gets the same key in the rules", async () => {
  // tests/nickname_letters.json is generated by tools/gen_nickname_letters.gd from
  // NicknameRules (Godot to_lower); the rules verify the key with RE2 case folding.
  const { letters } = JSON.parse(readFileSync(join(ROOT, "tests", "nickname_letters.json"), "utf8"));
  assert.ok(letters.length > 300);
  const db = env.authenticatedContext("alice").firestore();
  const mismatches = [];
  for (const [ch, lower] of letters) {
    await env.clearFirestore();
    // Pad with a letter of the same alphabet (a nickname may not mix Latin and Cyrillic).
    const pad = /[\u0400-\u045f]/.test(ch) ? "\u0436" : "x";
    const name = `${pad}${ch}${pad}`;
    const key = `${pad}${lower}${pad}`;
    const batch = writeBatch(db);
    batch.set(doc(db, `nicknames/${key}`), { uid: "alice", nickname: name, createdAt: serverTimestamp() });
    batch.set(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() });
    batch.set(doc(db, "publicProfiles/alice"), { nickname: name, nicknameNormalized: key, createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
    try {
      await assertSucceeds(batch.commit());
    } catch {
      mismatches.push(`U+${ch.codePointAt(0).toString(16)} ${ch} -> ${lower}`);
    }
  }
  assert.deepEqual(mismatches, []);
});

test("nickname: signed-out users can do nothing; signed-in may only get", async () => {
  await seedNickname("alice", "Alice");
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "nicknames/alice")));
  await assertFails(getDoc(doc(anon, "publicProfiles/alice")));
  await assertFails(reserveBatch(anon, "alice", "Hacker").commit());
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "nicknames/alice")));
  await assertSucceeds(getDoc(doc(bob, "publicProfiles/alice")));
  const { getDocs, collection } = require("firebase/firestore");
  await assertFails(getDocs(collection(bob, "nicknames")));
  await assertFails(getDocs(collection(bob, "publicProfiles")));
});

// ---- account deletion ----------------------------------------------------

test("delete account: owner can delete profile + nickname + records in one batch", async () => {
  await seedNickname("alice", "Alice");
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { schemaVersion: 1 });
    await setDoc(doc(db, "saves/alice"), { progress: "x" });
    await setDoc(doc(db, "leaderboards/level_1/scores/alice"), { name: "Alice", wave: 3, updated: new Date() });
  });
  const db = env.authenticatedContext("alice").firestore();
  const batch = writeBatch(db);
  for (const path of [
    "users/alice",
    "publicProfiles/alice",
    "nicknames/alice",
    "saves/alice",
    "nicknameTrace/alice",
    "runs/alice",
    "leaderboards/level_1/scores/alice",
    "leaderboards/level_2/scores/alice", // never existed: deleting a missing record is fine
  ]) {
    batch.delete(doc(db, path));
  }
  await assertSucceeds(batch.commit());
  for (const path of ["nicknames/alice", "publicProfiles/alice", "users/alice", "nicknameTrace/alice", "leaderboards/level_1/scores/alice"]) {
    const snap = await adminGet(path);
    assert.equal(snap.exists(), false, path);
  }
});

test("delete account: nobody can delete another player's data", async () => {
  await seedNickname("alice", "Alice");
  const bob = env.authenticatedContext("bob").firestore();
  for (const path of ["users/alice", "publicProfiles/alice", "nicknames/alice", "saves/alice", "leaderboards/level_1/scores/alice"]) {
    await assertFails(deleteDoc(doc(bob, path)));
  }
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(deleteDoc(doc(anon, "leaderboards/level_1/scores/alice")));
});

// ---- nickname trace (24 hour clock that survives profile deletion) --------

test("nickname trace: deleting the profile and recreating it does not reset the 24 hour limit", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertSucceeds(reserveBatch(db, "alice", "Первый").commit());
  // Delete profile + index (allowed: part of account deletion), keep the trace.
  const del = writeBatch(db);
  del.delete(doc(db, "nicknames/первый"));
  del.delete(doc(db, "publicProfiles/alice"));
  await assertSucceeds(del.commit());
  assert.equal((await adminGet("nicknameTrace/alice")).exists(), true);
  // "First reservation" again: refused, the trace says the name changed minutes ago.
  await assertFails(reserveBatch(db, "alice", "Второй").commit());
  // Without stamping the trace the profile cannot be created at all.
  await assertFails(reserveBatch(db, "alice", "Второй", { trace: false }).commit());
});

test("nickname trace: recreation is possible once 24 hours have passed", async () => {
  await seedNickname("alice", "Старое", 25);
  const db = env.authenticatedContext("alice").firestore();
  const del = writeBatch(db);
  del.delete(doc(db, "nicknames/старое"));
  del.delete(doc(db, "publicProfiles/alice"));
  await assertSucceeds(del.commit());
  await assertSucceeds(reserveBatch(db, "alice", "Новое").commit());
});

test("nickname trace: cannot be deleted, rewritten or forged within 24 hours", async () => {
  await seedNickname("alice", "Alice", 1);
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(deleteDoc(doc(db, "nicknameTrace/alice")));
  await assertFails(setDoc(doc(db, "nicknameTrace/alice"), { changedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, "nicknameTrace/alice"), { changedAt: Timestamp.fromMillis(0) }));
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(getDoc(doc(bob, "nicknameTrace/alice")));
  await assertFails(deleteDoc(doc(bob, "nicknameTrace/alice")));
  await assertSucceeds(getDoc(doc(db, "nicknameTrace/alice")));
  // A first trace: only for yourself, only server time, no extra keys.
  await assertFails(setDoc(doc(db, "nicknameTrace/carol"), { changedAt: serverTimestamp() }));
  const carol = env.authenticatedContext("carol").firestore();
  await assertFails(setDoc(doc(carol, "nicknameTrace/carol"), { changedAt: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(doc(carol, "nicknameTrace/carol"), { changedAt: serverTimestamp(), x: 1 }));
  await assertSucceeds(setDoc(doc(carol, "nicknameTrace/carol"), { changedAt: serverTimestamp() }));
});

test("nickname trace: deleting the whole account stays possible", async () => {
  // Old trace: deleted together with everything else.
  await seedNickname("alice", "Alice", 48);
  const db = env.authenticatedContext("alice").firestore();
  const batch = writeBatch(db);
  for (const path of ["nicknames/alice", "publicProfiles/alice", "nicknameTrace/alice", "runs/alice", "users/alice"]) {
    batch.delete(doc(db, path));
  }
  await assertSucceeds(batch.commit());
  assert.equal((await adminGet("nicknameTrace/alice")).exists(), false);
  // Recent trace: the trace delete is refused, the rest of the data can go
  // (the client leaves the trace out of the batch).
  await seedNickname("bob", "Bob", 1);
  const bobDb = env.authenticatedContext("bob").firestore();
  const withTrace = writeBatch(bobDb);
  withTrace.delete(doc(bobDb, "nicknames/bob"));
  withTrace.delete(doc(bobDb, "publicProfiles/bob"));
  withTrace.delete(doc(bobDb, "nicknameTrace/bob"));
  await assertFails(withTrace.commit());
  const without = writeBatch(bobDb);
  without.delete(doc(bobDb, "nicknames/bob"));
  without.delete(doc(bobDb, "publicProfiles/bob"));
  await assertSucceeds(without.commit());
});

// ---- runs ----------------------------------------------------------------

test("runs: owner writes the start with server time, nobody backdates it", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "runs/alice");
  await assertSucceeds(setDoc(ref, { level: "level_1", startedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(ref, { level: "level_2", startedAt: serverTimestamp() })); // new run
  await assertFails(setDoc(ref, { level: "level_1", startedAt: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(ref, { level: "level_1", startedAt: Timestamp.now() })); // client clock
  await assertFails(setDoc(ref, { level: "level_1", startedAt: serverTimestamp(), x: 1 }));
  await assertFails(setDoc(ref, { level: 1, startedAt: serverTimestamp() }));
  await assertFails(setDoc(ref, { level: "levels", startedAt: serverTimestamp() }));
  const bob = env.authenticatedContext("bob").firestore();
  await assertFails(setDoc(doc(bob, "runs/alice"), { level: "level_1", startedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(bob, "runs/alice")));
  await assertSucceeds(deleteDoc(ref));
});

// ---- leaderboard ---------------------------------------------------------

const score = (extra = {}) => ({ name: "Рыцарь", wave: 5, updated: serverTimestamp(), ...extra });

test("leaderboard: own entry, reserved name or the anonymous name, only upwards", async () => {
  await seedRun("alice", "level_1", 3600);
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  await assertFails(setDoc(ref, score({ name: "Самозванец" })));
  await assertSucceeds(setDoc(ref, score()));
  await seedNickname("alice", "Alice");
  await assertSucceeds(setDoc(ref, score({ name: "Alice", wave: 7 })));
  await assertFails(setDoc(ref, score({ name: "Alice", wave: 6 })));
  await assertFails(setDoc(ref, score({ name: "Alice", wave: 7 }))); // not higher
  await assertFails(setDoc(doc(db, "leaderboards/level_1/scores/bob"), score({ wave: 9 })));
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "leaderboards/level_1/scores/alice")));
});

test("leaderboard: renaming the entry keeps wave and time", async () => {
  await seedRun("alice", "level_1", 3600);
  await seedNickname("alice", "Alice");
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  await assertSucceeds(setDoc(ref, score({ wave: 7 })));
  // The client updates only the name (updateMask); wave and time stay as they were.
  await assertSucceeds(updateDoc(ref, { name: "Alice" }));
  await assertFails(updateDoc(ref, { name: "Самозванец" }));
  await assertFails(updateDoc(ref, { name: "Рыцарь", wave: 6 })); // downwards
  await assertFails(updateDoc(ref, { name: "Рыцарь", updated: serverTimestamp() }));
  // The rename still works after a newer run replaced the run document.
  await seedRun("alice", "level_1", 1);
  await assertSucceeds(updateDoc(ref, { name: "Рыцарь" }));
  // ...but a higher wave still needs the clock.
  await assertFails(updateDoc(ref, { wave: 8, updated: serverTimestamp() }));
});

test("leaderboard: a record cannot be faster than the wave clock (anti-cheat)", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  // No run document at all.
  await assertFails(setDoc(ref, score({ wave: 1 })));
  // Run started 100 s ago: wave N needs (N-1)*15 s -> up to wave 7 (90 s).
  await seedRun("alice", "level_1", 100);
  await assertFails(setDoc(ref, score({ wave: 50 })));
  await assertFails(setDoc(ref, score({ wave: 8 })));
  await assertSucceeds(setDoc(ref, score({ wave: 7 })));
  // Higher again only once more time has passed.
  await assertFails(setDoc(ref, score({ wave: 20 })));
  await seedRun("alice", "level_1", 400);
  await assertSucceeds(setDoc(ref, score({ wave: 20 })));
  await assertFails(setDoc(ref, score({ wave: 4999 })));
});

test("leaderboard: the run must be for the same level and the time must be the server's", async () => {
  await seedRun("alice", "level_2", 3600);
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(db, "leaderboards/level_1/scores/alice"), score()));
  const ref = doc(db, "leaderboards/level_2/scores/alice");
  await assertSucceeds(setDoc(ref, score()));
  // Client clocks / old timestamps / missing time are refused.
  await assertFails(setDoc(ref, score({ wave: 6, updated: new Date(Date.now() - 60000) })));
  await assertFails(setDoc(ref, score({ wave: 6, updated: Timestamp.fromMillis(0) })));
  await assertFails(setDoc(ref, { name: "Рыцарь", wave: 6 }));
  // Someone else's run does not help.
  await seedRun("bob", "level_2", 3600);
  await assertFails(setDoc(doc(db, "leaderboards/level_2/scores/bob"), score()));
});

test("leaderboard: wave, name size, extra keys and level id are validated", async () => {
  await seedRun("alice", "level_1", 100000);
  const db = env.authenticatedContext("alice").firestore();
  const path = (level) => `leaderboards/${level}/scores/alice`;
  await assertFails(setDoc(doc(db, path("level_1")), score({ wave: 0 })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ wave: 5000 })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ wave: 5.5 })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ wave: "5" })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ extra: 1 })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ updated: "yesterday" })));
  await assertFails(setDoc(doc(db, path("level_1")), score({ name: "x".repeat(17) })));
  await assertFails(setDoc(doc(db, path("levels")), score()));
  await assertFails(setDoc(doc(db, path("level_x")), score()));
  await seedRun("alice", "level_6", 100000);
  await assertSucceeds(setDoc(doc(db, path("level_6")), score()));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), path("level_1")), score()));
});

// ---- legacy saves, default deny -------------------------------------------

test("legacy saves: owner may read, write and delete", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "saves/alice");
  await assertSucceeds(setDoc(ref, { progress: "[progress]\nunlocked=2\n" }));
  await assertFails(setDoc(ref, { progress: "x", extra: 1 }));
  await assertFails(setDoc(ref, { progress: "x".repeat(20000) }));
  await assertFails(getDoc(doc(env.authenticatedContext("bob").firestore(), "saves/alice")));
  await assertSucceeds(deleteDoc(ref));
});

test("everything else is denied by default", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(db, "reports/r1"), { reporter: "alice" }));
  await assertFails(setDoc(doc(db, "anything/alice"), { a: 1 }));
  await assertFails(getDoc(doc(db, "anything/alice")));
});

// ---- daily challenge board ---------------------------------------------------

const dayKey = (offsetDays = 0) =>
  new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10);
const dailyScore = (extra = {}) => ({ name: "Рыцарь", wave: 5, updated: serverTimestamp(), ...extra });
const dailyPath = (day = dayKey(), uid = "alice") => `daily/${day}/scores/${uid}`;

test("daily: own entry for today, reserved or anonymous name, only upwards", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, dailyPath());
  await assertFails(setDoc(ref, dailyScore({ name: "Самозванец" })));
  await assertSucceeds(setDoc(ref, dailyScore()));
  await seedNickname("alice", "Alice");
  await assertSucceeds(setDoc(ref, dailyScore({ name: "Alice", wave: 7 })));
  await assertFails(setDoc(ref, dailyScore({ name: "Alice", wave: 6 })));
  await assertFails(setDoc(ref, dailyScore({ name: "Alice", wave: 7 }))); // not higher
  await assertFails(setDoc(doc(db, dailyPath(dayKey(), "bob")), dailyScore())); // not yours
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(anon, dailyPath())));
  await assertFails(setDoc(doc(anon, dailyPath()), dailyScore({ wave: 9 })));
});

test("daily: only today's date by the server clock (no past or future boards)", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(db, dailyPath(dayKey(-2))), dailyScore()));
  await assertFails(setDoc(doc(db, dailyPath(dayKey(1))), dailyScore()));
  await assertFails(setDoc(doc(db, dailyPath(dayKey(-400))), dailyScore()));
  await assertFails(setDoc(doc(db, dailyPath("2026-1-5")), dailyScore())); // not zero padded
  await assertFails(setDoc(doc(db, dailyPath("today")), dailyScore()));
  // Yesterday is open only in the first hour after midnight (grace for a run in progress).
  const justAfterMidnight = new Date().getUTCHours() < 1;
  const yesterday = setDoc(doc(db, dailyPath(dayKey(-1))), dailyScore());
  await (justAfterMidnight ? assertSucceeds(yesterday) : assertFails(yesterday));
  await assertSucceeds(setDoc(doc(db, dailyPath(dayKey())), dailyScore()));
});

test("daily: time must be the server's, wave and name and keys are validated", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, dailyPath());
  await assertFails(setDoc(ref, dailyScore({ updated: new Date() }))); // client clock
  await assertFails(setDoc(ref, dailyScore({ updated: Timestamp.fromMillis(0) })));
  await assertFails(setDoc(ref, { name: "Рыцарь", wave: 5 }));
  await assertFails(setDoc(ref, dailyScore({ wave: 0 })));
  await assertFails(setDoc(ref, dailyScore({ wave: 500 })));
  await assertFails(setDoc(ref, dailyScore({ wave: 5.5 })));
  await assertFails(setDoc(ref, dailyScore({ wave: "5" })));
  await assertFails(setDoc(ref, dailyScore({ extra: 1 })));
  await assertFails(setDoc(ref, dailyScore({ name: "x".repeat(17) })));
  await assertSucceeds(setDoc(ref, dailyScore({ wave: 499 })));
});

test("daily: a rename-only write is refused (wave must grow), delete is owner only", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, dailyPath());
  await assertSucceeds(setDoc(ref, dailyScore({ wave: 8 })));
  await assertFails(updateDoc(ref, { name: "Рыцарь", updated: serverTimestamp() }));
  await assertFails(deleteDoc(doc(env.authenticatedContext("bob").firestore(), dailyPath())));
  await assertFails(deleteDoc(doc(env.unauthenticatedContext().firestore(), dailyPath())));
  await assertSucceeds(deleteDoc(ref));
  // Account deletion removes entries of earlier days too (missing ones are fine).
  await assertSucceeds(deleteDoc(doc(db, dailyPath(dayKey(-3)))));
});

test("daily: a list is capped at 100 and ordered queries work for everybody", async () => {
  const anon = env.unauthenticatedContext().firestore();
  const col = collection(anon, `daily/${dayKey()}/scores`);
  await assertSucceeds(getDocs(query(col, orderBy("wave", "desc"), limit(100))));
  await assertFails(getDocs(query(col, limit(101))));
  await assertFails(getDocs(col)); // unbounded
});

test("users: difficulty crowns are 0..2 per known level (optional, schemaVersion 2)", async () => {
  let n = 0;
  const create = (crowns) => {
    const uid = `crown${n++}`;
    const db = env.authenticatedContext(uid).firestore();
    return setDoc(doc(db, `users/${uid}`), {
      ...profile(),
      schemaVersion: 2,
      createdAt: serverTimestamp(),
      progression: { ...profile().progression, crowns },
    });
  };
  await assertSucceeds(create({}));
  await assertSucceeds(create({ 1: 1, 2: 2, 6: 2 }));
  await assertFails(create({ 1: 3 }));
  await assertFails(create({ 1: -1 }));
  await assertFails(create({ 1: 1.5 }));
  await assertFails(create({ 1: "2" }));
  await assertFails(create({ 99: 1 }));
  await assertFails(create({ abc: 1 }));
  await assertFails(create([1, 2]));
  await assertFails(create("all"));
  // The fullest honest profile (6 levels of stars, records and crowns, every perk) fits the
  // rules' expression budget.
  const six = { 1: 3, 2: 3, 3: 3, 4: 3, 5: 3, 6: 3 };
  const full = env.authenticatedContext("crownFull").firestore();
  await assertSucceeds(
    setDoc(doc(full, "users/crownFull"), {
      ...profile(),
      schemaVersion: 2,
      createdAt: serverTimestamp(),
      achievements: 65535,
      progression: {
        unlocked: 6,
        stars: six,
        endless: { 1: 80, 2: 80, 3: 80, 4: 80, 5: 80, 6: 80 },
        perks: { axe: 1, walls: 2, sword: 2, gold_start: 3, towers: 3, wood_start: 3 },
        dailyStars: 10,
        crowns: { 1: 2, 2: 2, 3: 2, 4: 2, 5: 2, 6: 2 },
      },
    }),
  );
  // Unknown keys next to the crowns stay refused.
  const evil = env.authenticatedContext("crownEvil").firestore();
  await assertFails(
    setDoc(doc(evil, "users/crownEvil"), {
      ...profile(),
      createdAt: serverTimestamp(),
      progression: { ...profile().progression, crowns: {}, medals: {} },
    }),
  );
  // A document without crowns (older client) stays valid.
  const old = env.authenticatedContext("crownOld").firestore();
  await assertSucceeds(setDoc(doc(old, "users/crownOld"), { ...profile(), createdAt: serverTimestamp() }));
});

test("users: achievements are a bit mask integer (optional, bounded)", async () => {
  let n = 0; // a fresh user each time: a second setDoc on one would be an update
  const create = (achievements) => {
    const uid = `ach${n++}`;
    const db = env.authenticatedContext(uid).firestore();
    return setDoc(doc(db, `users/${uid}`), { ...profile(), createdAt: serverTimestamp(), achievements });
  };
  await assertSucceeds(create(0));
  await assertSucceeds(create(65535));
  await assertFails(create(-1));
  await assertFails(create(2147483648));
  await assertFails(create(1.5));
  await assertFails(create("all"));
  await assertFails(create({ first_win: 1 }));
  await assertFails(create(true));
  // Bonus stars of the daily challenge ride in progression.
  const withStars = (dailyStars) => {
    const uid = `ach${n++}`;
    const db = env.authenticatedContext(uid).firestore();
    return setDoc(doc(db, `users/${uid}`), {
      ...profile(),
      createdAt: serverTimestamp(),
      progression: { ...profile().progression, dailyStars },
    });
  };
  await assertSucceeds(withStars(0));
  await assertSucceeds(withStars(10));
  await assertFails(withStars(11));
  await assertFails(withStars(-1));
  await assertFails(withStars("3"));
  // An older client does not know the field: a document without it stays valid.
  const bob = env.authenticatedContext("bob").firestore();
  await assertSucceeds(setDoc(doc(bob, "users/bob"), { ...profile(), createdAt: serverTimestamp() }));
});
