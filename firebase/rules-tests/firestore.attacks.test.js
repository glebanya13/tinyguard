// Security audit: attack cases against firestore.rules (docs/SECURITY_AUDIT.md).
// Every test here is an attack that must FAIL (or a limit that must hold).
// npm test   (in firebase/rules-tests; Firebase emulator, Java 21)
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
  collectionGroup,
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
const userDoc = (extra = {}) => ({ ...profile(), createdAt: serverTimestamp(), ...extra });
const prog = (extra) => ({ ...profile().progression, ...extra });
const score = (extra = {}) => ({ name: "Рыцарь", wave: 5, updated: serverTimestamp(), ...extra });

/** Same normalization as scripts/nickname_rules.gd. */
const normalize = (name) => name.toLowerCase().replace(/ё/g, "е").replace(/ /g, "_");

function reserveBatch(db, uid, name) {
  const key = normalize(name);
  const batch = writeBatch(db);
  batch.set(doc(db, `nicknames/${key}`), { uid, nickname: name, createdAt: serverTimestamp() });
  batch.set(doc(db, `nicknameTrace/${uid}`), { changedAt: serverTimestamp() });
  batch.set(doc(db, `publicProfiles/${uid}`), {
    nickname: name,
    nicknameNormalized: key,
    nicknameChangedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });
  return batch;
}

/** Reservation with a hand-made key (the attacker does not use the client's normalize()). */
function rawReserve(db, uid, name, key) {
  const batch = writeBatch(db);
  batch.set(doc(db, `nicknames/${key}`), { uid, nickname: name, createdAt: serverTimestamp() });
  batch.set(doc(db, `nicknameTrace/${uid}`), { changedAt: serverTimestamp() });
  batch.set(doc(db, `publicProfiles/${uid}`), {
    nickname: name,
    nicknameNormalized: key,
    nicknameChangedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  });
  return batch;
}

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

async function seedRun(uid, level, secondsAgo) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const at = Timestamp.fromMillis(Date.now() - secondsAgo * 1000);
    await setDoc(doc(ctx.firestore(), `runs/${uid}`), { level, startedAt: at });
  });
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bimbleguard-attacks",
    firestore: { rules: readFileSync(join(ROOT, "firestore.rules"), "utf8") },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
});
after(async () => {
  await env.cleanup();
});

// ---- nicknames -----------------------------------------------------------

test("attack: homoglyph / mixed-script nicknames cannot imitate reserved names", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  // Cyrillic letters inside Latin reserved words (А, а, о, і, е look like Latin ones).
  for (const name of ["Аdmin", "аdmin", "Moderatоr", "Tіnyguard", "Systеm"]) {
    await assertFails(reserveBatch(db, "mallory", name).commit());
  }
  // A pure Cyrillic name stays fine.
  await assertSucceeds(reserveBatch(db, "mallory", "Сэр Ёжик").commit());
});

test("attack: invisible, combining, bidi, emoji, path-like and oversized nicknames", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  const bad = [
    "ab​cd", // zero width space
    "ábc", // combining acute
    "ab‮cd", // right-to-left override
    "😀😀😀", // emoji
    "ab cd", // no-break space
    "ab\tcd",
    "ab\ncd",
    "x".repeat(17),
    "ab",
    "ＡＢＣ", // fullwidth Latin
    "ab\u0000cd",
    "a/b/c",
    "abc%2Fdef",
    "ab cd",
    "abc.def",
    "abc  def", // two spaces
    "_abc",
    "abc_",
  ];
  for (const name of bad) {
    await assertFails(rawReserve(db, "mallory", name, name.toLowerCase().replace(/ /g, "_")).commit());
  }
});

test("attack: the index key cannot be forged (other name, upper case, regex characters)", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  await assertFails(rawReserve(db, "mallory", "Alice", "bob_the").commit()); // a victim's key
  await assertFails(rawReserve(db, "mallory", "ALICE", "ALICE").commit()); // upper-case key
  await assertFails(rawReserve(db, "mallory", "Alice", ".+").commit()); // regex wildcard
  await assertFails(rawReserve(db, "mallory", "Alice", "al(ice)").commit());
  await assertFails(rawReserve(db, "mallory", "Alice", "alice|bob").commit());
});

test("attack: one account cannot hold two names or squat a spare index document", async () => {
  await seedNickname("mallory", "Mallory");
  const db = env.authenticatedContext("mallory").firestore();
  await assertFails(
    setDoc(doc(db, "nicknames/spare"), { uid: "mallory", nickname: "Spare", createdAt: serverTimestamp() }),
  );
  await assertFails(
    setDoc(doc(db, "nicknames/other"), { uid: "victim", nickname: "Other", createdAt: serverTimestamp() }),
  );
  await assertFails(deleteDoc(doc(db, "nicknames/mallory"))); // profile still uses it
  await assertFails(updateDoc(doc(db, "publicProfiles/mallory"), { nickname: "MALLORY" }));
});

test("attack: a taken name cannot be stolen by delete + create in one commit", async () => {
  await seedNickname("victim", "Victim");
  const db = env.authenticatedContext("mallory").firestore();
  const b = rawReserve(db, "mallory", "Victim", "victim");
  b.delete(doc(db, "nicknames/victim"));
  await assertFails(b.commit());
  const c = writeBatch(db);
  c.delete(doc(db, "nicknames/victim"));
  await assertFails(c.commit());
});

test("attack: the 24 hour nickname clock cannot be reset or backdated", async () => {
  await seedNickname("mallory", "Mallory", 1);
  const db = env.authenticatedContext("mallory").firestore();
  const b = writeBatch(db);
  b.delete(doc(db, "nicknameTrace/mallory"));
  b.delete(doc(db, "publicProfiles/mallory"));
  b.delete(doc(db, "nicknames/mallory"));
  await assertFails(b.commit());
  await assertFails(setDoc(doc(db, "nicknameTrace/mallory"), { changedAt: Timestamp.fromMillis(0) }));
  const c = writeBatch(db);
  c.delete(doc(db, "nicknames/mallory"));
  c.set(doc(db, "nicknames/mallory2"), { uid: "mallory", nickname: "Mallory2", createdAt: serverTimestamp() });
  c.update(doc(db, "publicProfiles/mallory"), {
    nickname: "Mallory2",
    nicknameNormalized: "mallory2",
    nicknameChangedAt: Timestamp.fromMillis(0),
  });
  await assertFails(c.commit());
});

// ---- private profile as storage ------------------------------------------

test("attack: users/{uid} cannot be used as free storage (types, sizes, ranges)", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  const ref = doc(db, "users/mallory");
  const fat = "x".repeat(900000);
  await assertFails(setDoc(ref, userDoc({ progression: prog({ stars: { 1: fat } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ endless: { 1: fat } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ perks: { axe: fat } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ perks: { [fat.slice(0, 1400)]: 1 } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ stars: { 1: { a: { b: fat } } } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ stars: { 1: -5 } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ stars: { 1: 99999 } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ perks: { axe: -1 } }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ unlocked: 1.5 }) })));
  await assertFails(setDoc(ref, userDoc({ progression: prog({ unlocked: "2" }) })));
  await assertFails(setDoc(ref, userDoc({ schemaVersion: 1.0001 })));
  await assertSucceeds(
    setDoc(ref, userDoc({ progression: prog({ stars: { 1: 3, 2: 2 }, endless: { 1: 25 }, perks: { axe: 2 } }) })),
  );
});

// ---- leaderboards, runs, saves --------------------------------------------

test("attack: leaderboard reads are bounded (no unlimited scans)", async () => {
  await seedRun("alice", "level_1", 3600);
  const db = env.authenticatedContext("alice").firestore();
  await assertSucceeds(setDoc(doc(db, "leaderboards/level_1/scores/alice"), score()));
  const anon = env.unauthenticatedContext().firestore();
  const col = collection(anon, "leaderboards/level_1/scores");
  await assertSucceeds(getDocs(query(col, orderBy("wave", "desc"), limit(10))));
  await assertFails(getDocs(query(col, orderBy("wave", "desc"), limit(100000))));
  await assertFails(getDocs(col));
});

test("attack: leaderboard numbers, shapes and timing", async () => {
  await seedRun("alice", "level_1", 100000);
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  for (const wave of [0, -1, 5000, 4999.5, "7", null, 1e30, NaN]) {
    await assertFails(setDoc(ref, score({ wave })));
  }
  await assertFails(setDoc(ref, score({ updated: Timestamp.fromMillis(Date.now() + 1e9) })));
  await assertFails(setDoc(ref, score({ name: "x".repeat(17) })));
  await assertFails(setDoc(doc(db, "leaderboards/not_a_level/scores/alice"), score()));
  await assertFails(setDoc(doc(db, "leaderboards/level_1/other/alice"), score()));
  await seedRun("bob", "level_1", 100000);
  await assertFails(setDoc(doc(db, "leaderboards/level_1/scores/bob"), score())); // someone else's entry
  await assertSucceeds(setDoc(ref, score({ wave: 50 })));
  await assertFails(deleteDoc(doc(env.authenticatedContext("bob").firestore(), "leaderboards/level_1/scores/alice")));
});

test("attack: leaderboard name must be the player's own nickname", async () => {
  await seedRun("alice", "level_1", 100000);
  await seedNickname("bob", "Bobby");
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  await assertFails(setDoc(ref, score({ name: "Bobby" }))); // impersonation of another player
  await assertFails(setDoc(ref, score({ name: "Admin" })));
  await assertFails(setDoc(ref, score({ name: "рыцарь" }))); // only the exact anonymous name
});

test("attack: runs and saves abuse", async () => {
  const db = env.authenticatedContext("mallory").firestore();
  await assertFails(setDoc(doc(db, "runs/mallory"), { level: "level_12345", startedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, "runs/mallory"), { level: "level_1\n", startedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, "runs/mallory"), { level: "LEVEL_1", startedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, "runs/mallory"), { startedAt: serverTimestamp() }));
  await assertFails(setDoc(doc(db, "saves/mallory"), { progress: "ж".repeat(20000) }));
});

// ---- reading other people's data -------------------------------------------

test("attack: strangers cannot read private data or list anything", async () => {
  await seedNickname("alice", "Alice");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), { schemaVersion: 1 });
    await setDoc(doc(ctx.firestore(), "runs/alice"), { level: "level_1" });
    await setDoc(doc(ctx.firestore(), "saves/alice"), { progress: "x" });
  });
  const mal = env.authenticatedContext("mallory").firestore();
  for (const path of ["users/alice", "runs/alice", "nicknameTrace/alice", "saves/alice"]) {
    await assertFails(getDoc(doc(mal, path)));
  }
  await assertFails(getDocs(collection(mal, "users")));
  await assertFails(getDocs(collection(mal, "publicProfiles")));
  await assertFails(getDocs(collection(mal, "nicknames")));
  await assertFails(getDocs(query(collectionGroup(mal, "scores"))));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "publicProfiles/alice")));
  await assertFails(getDoc(doc(anon, "nicknames/alice")));
});
