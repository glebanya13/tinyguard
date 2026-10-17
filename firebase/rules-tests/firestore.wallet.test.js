// Firestore rules for the gem wallet and the day streak (users/{uid}.wallet / .streak,
// schemaVersion 3), against the local emulator. Own project id: the files run in parallel and
// every file clears its own Firestore data. Run through `npm test`.
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { after, before, beforeEach, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { Timestamp, doc, serverTimestamp, setDoc, updateDoc } = require("firebase/firestore");

const ROOT = join(__dirname, "..", "..");
let env;

const profile = () => ({
  schemaVersion: 3,
  onboardingCompleted: true,
  tutorialVersionCompleted: 1,
  progression: { unlocked: 2, stars: { 1: 3 }, endless: {}, perks: { axe: 1 } },
  settings: { sound: true },
  updatedAt: serverTimestamp(),
});

const wallet = (extra = {}) => ({
  gems: 90,
  earned: 150,
  spent: 60,
  claims: "ach:hunter=25;lv1s1=15;lv1s2=25;lv1s3=40;streak:2026-10-17=5;old:2026-09=40",
  buys: "hero_ember=60",
  equipped: "hero=hero_ember",
  ...extra,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-bimbleguard-wallet",
    firestore: { rules: readFileSync(join(ROOT, "firestore.rules"), "utf8") },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

test("wallet: an honest wallet is accepted, an empty one too, and a document without one", async () => {
  const db = env.authenticatedContext("w1").firestore();
  await assertSucceeds(setDoc(doc(db, "users/w1"), { ...profile(), createdAt: serverTimestamp(), wallet: wallet() }));
  const db2 = env.authenticatedContext("w2").firestore();
  await assertSucceeds(
    setDoc(doc(db2, "users/w2"), {
      ...profile(),
      createdAt: serverTimestamp(),
      wallet: { gems: 0, earned: 0, spent: 0, claims: "", buys: "", equipped: "" },
    }),
  );
  // Spending more than was earned (after a merge) clamps the balance at 0.
  const db3 = env.authenticatedContext("w3").firestore();
  await assertSucceeds(
    setDoc(doc(db3, "users/w3"), {
      ...profile(),
      createdAt: serverTimestamp(),
      wallet: wallet({ gems: 0, earned: 50, spent: 80 }),
    }),
  );
  // An older client without a wallet stays valid.
  const db4 = env.authenticatedContext("w4").firestore();
  const old = { ...profile(), schemaVersion: 1, createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(db4, "users/w4"), old));
});

test("wallet: attacks on numbers, keys, text and the allowance are refused", async () => {
  let n = 0;
  const create = (w) => {
    const uid = `wa${n++}`;
    const db = env.authenticatedContext(uid).firestore();
    return setDoc(doc(db, `users/${uid}`), { ...profile(), createdAt: serverTimestamp(), wallet: w });
  };
  await assertFails(create(wallet({ gems: -1 })));
  await assertFails(create(wallet({ gems: 100 }))); // not earned - spent
  await assertFails(create(wallet({ gems: 151, spent: 0 }))); // more gems than ever earned
  await assertSucceeds(create(wallet({ gems: 150, spent: 0 })));
  await assertFails(create(wallet({ gems: 1.5 })));
  await assertFails(create(wallet({ gems: "90" })));
  await assertFails(create(wallet({ earned: -5, gems: 0, spent: 0 })));
  await assertFails(create(wallet({ spent: -1, gems: 151 })));
  await assertFails(create(wallet({ gems: 9999999, earned: 9999999, spent: 0 })));
  // A new account cannot already own 30000 gems; 20000 is the one-time lump.
  await assertFails(create(wallet({ gems: 30000, earned: 30000, spent: 0 })));
  await assertSucceeds(create(wallet({ gems: 20000, earned: 20000, spent: 0 })));
  await assertFails(create(wallet({ coins: 5 }))); // unknown key
  await assertFails(create({ gems: 1, earned: 1, spent: 0, claims: "", buys: "" })); // missing key
  await assertFails(create(wallet({ claims: "A=1" }))); // upper case
  await assertFails(create(wallet({ claims: "<script>=1" })));
  await assertFails(create(wallet({ claims: "a=1\nb=2" })));
  await assertFails(create(wallet({ claims: "k=1;".repeat(4000) }))); // over 12000 characters
  await assertFails(create(wallet({ buys: "x=1;".repeat(1000) })));
  await assertFails(create(wallet({ equipped: "s=i;".repeat(200) })));
  await assertFails(create(wallet({ claims: 5 })));
  await assertFails(create(wallet({ claims: { a: 1 } })));
  await assertFails(create([1, 2, 3]));
  await assertFails(create("rich"));
  await assertFails(create(null));
});

test("wallet: the lifetime total grows only by the daily allowance", async () => {
  const old = Timestamp.fromMillis(Date.now() - 100 * 86400 * 1000);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/vet"), { ...profile(), createdAt: old, updatedAt: new Date() });
  });
  const db = env.authenticatedContext("vet").firestore();
  const ref = doc(db, "users/vet");
  const total = (earned) => ({ gems: earned, earned, spent: 0, claims: "", buys: "", equipped: "" });
  const update = (earned) => updateDoc(ref, { wallet: total(earned), updatedAt: serverTimestamp(), schemaVersion: 3 });
  // 100 days old: 20000 + 700 * 101 = 90700.
  await assertSucceeds(update(60000));
  await assertFails(update(95000));
  await assertFails(update(2000001));
});

test("streak: shape and ranges", async () => {
  let n = 0;
  const create = (streak) => {
    const uid = `st${n++}`;
    const db = env.authenticatedContext(uid).firestore();
    return setDoc(doc(db, `users/${uid}`), { ...profile(), createdAt: serverTimestamp(), streak });
  };
  await assertSucceeds(create({ last: "2026-10-17", len: 3, best: 5, grace: 12345 }));
  await assertSucceeds(create({ last: "", len: 0, best: 0, grace: -1 }));
  await assertFails(create({ last: "2026-10-17", len: 6, best: 5, grace: 0 })); // best < len
  await assertFails(create({ last: "2026-10-17", len: 1001, best: 1001, grace: 0 }));
  await assertFails(create({ last: "yesterday", len: 1, best: 1, grace: 0 }));
  await assertFails(create({ last: "2026-10-17", len: 1.5, best: 2, grace: 0 }));
  await assertFails(create({ last: "2026-10-17", len: 1, best: 1, grace: 0, gift: 1 }));
  await assertFails(create({ last: "2026-10-17", len: -1, best: 1, grace: 0 }));
  await assertFails(create("7"));
});
