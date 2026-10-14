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
  deleteDoc,
  doc,
  getDoc,
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
function reserveBatch(db, uid, name, { old = null, first = true } = {}) {
  const key = normalize(name);
  const batch = writeBatch(db);
  if (old) batch.delete(doc(db, `nicknames/${normalize(old)}`));
  batch.set(doc(db, `nicknames/${key}`), { uid, nickname: name, createdAt: serverTimestamp() });
  const fields = { nickname: name, nicknameNormalized: key, nicknameChangedAt: serverTimestamp() };
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
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-tinyguard",
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
    "Tinyguard",
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
  wrongKey.set(doc(db, "nicknames/other"), { uid: "alice", nickname: "Valid", createdAt: serverTimestamp() });
  wrongKey.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "other", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(wrongKey.commit());
  // Extra fields.
  const extra = writeBatch(db);
  extra.set(doc(db, "nicknames/valid"), { uid: "alice", nickname: "Valid", createdAt: serverTimestamp(), email: "a@b.c" });
  extra.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "valid", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(extra.commit());
  // Fake timestamps.
  const fake = writeBatch(db);
  fake.set(doc(db, "nicknames/valid"), { uid: "alice", nickname: "Valid", createdAt: Timestamp.fromMillis(0) });
  fake.set(doc(db, "publicProfiles/alice"), { nickname: "Valid", nicknameNormalized: "valid", createdAt: serverTimestamp(), nicknameChangedAt: serverTimestamp() });
  await assertFails(fake.commit());
  // A key that is not the lower-case form (would allow duplicates differing in case).
  for (const key of ["Valid", "VALID", "valid_", "val id", "vаlid"]) {
    const b = writeBatch(db);
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
    "leaderboards/level_1/scores/alice",
    "leaderboards/level_2/scores/alice", // never existed: deleting a missing record is fine
  ]) {
    batch.delete(doc(db, path));
  }
  await assertSucceeds(batch.commit());
  for (const path of ["nicknames/alice", "publicProfiles/alice", "users/alice", "leaderboards/level_1/scores/alice"]) {
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

// ---- leaderboard ---------------------------------------------------------

test("leaderboard: own entry, reserved name or the anonymous name, only upwards", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  await assertFails(setDoc(ref, { name: "Самозванец", wave: 5, updated: new Date() }));
  await assertSucceeds(setDoc(ref, { name: "Рыцарь", wave: 5, updated: new Date() }));
  await seedNickname("alice", "Alice");
  await assertSucceeds(setDoc(ref, { name: "Alice", wave: 7, updated: new Date() }));
  await assertFails(setDoc(ref, { name: "Alice", wave: 6, updated: new Date() }));
  // The same wave is allowed (renaming the entry after a nickname change).
  await assertSucceeds(setDoc(ref, { name: "Рыцарь", wave: 7, updated: new Date() }));
  await assertFails(
    setDoc(doc(db, "leaderboards/level_1/scores/bob"), { name: "Рыцарь", wave: 9, updated: new Date() }),
  );
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "leaderboards/level_1/scores/alice")));
});

test("leaderboard: wave, name size, extra keys and level id are validated", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const path = (level) => `leaderboards/${level}/scores/alice`;
  const ok = { name: "Рыцарь", wave: 5, updated: new Date() };
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, wave: 0 }));
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, wave: 5000 }));
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, wave: 5.5 }));
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, wave: "5" }));
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, extra: 1 }));
  await assertFails(setDoc(doc(db, path("level_1")), { ...ok, updated: "yesterday" }));
  await assertFails(setDoc(doc(db, path("level_1")), { name: "Рыцарь", wave: 5 }));
  await assertFails(setDoc(doc(db, path("levels")), ok));
  await assertFails(setDoc(doc(db, path("level_x")), ok));
  await assertSucceeds(setDoc(doc(db, path("level_6")), ok));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), path("level_1")), ok));
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
