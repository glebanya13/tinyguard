// Firestore security rules tests against the local emulator (no real project).
// npm run test:rules   (needs firebase-tools and Java; see docs/ACCOUNTS.md)
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
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require("firebase/firestore");

let env;

const profile = () => ({
  schemaVersion: 1,
  onboardingCompleted: true,
  tutorialVersionCompleted: 1,
  progression: { unlocked: 2, stars: { 1: 3 }, endless: {}, perks: { axe: 1 } },
  settings: { sound: true },
  updatedAt: serverTimestamp(),
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-tinyguard",
    firestore: { rules: readFileSync(join(__dirname, "..", "..", "..", "firestore.rules"), "utf8") },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
});

after(async () => {
  await env.cleanup();
});

test("users: owner creates and updates the private profile", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "users/alice");
  await assertSucceeds(setDoc(ref, { ...profile(), createdAt: serverTimestamp() }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(updateDoc(ref, { settings: { sound: false }, updatedAt: serverTimestamp() }));
});

test("users: nobody else reads or writes it", async () => {
  const bob = env.authenticatedContext("bob").firestore();
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(bob, "users/alice"), { ...profile(), createdAt: serverTimestamp() }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/alice"), { schemaVersion: 1 });
  });
  await assertFails(getDoc(doc(bob, "users/alice")));
  await assertFails(getDoc(doc(anon, "users/alice")));
});

test("users: client cannot set nickname fields, bad types or extra keys", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "users/alice");
  await assertFails(setDoc(ref, { ...profile(), createdAt: serverTimestamp(), nickname: "Me" }));
  await assertFails(setDoc(ref, { ...profile(), createdAt: serverTimestamp(), email: "x@y.z" }));
  await assertFails(
    setDoc(ref, { ...profile(), createdAt: serverTimestamp(), tutorialVersionCompleted: "1" }),
  );
  await assertFails(setDoc(ref, { ...profile(), createdAt: serverTimestamp(), updatedAt: 5 }));
  await assertSucceeds(setDoc(ref, { ...profile(), createdAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { nickname: "Me", updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(ref, { createdAt: serverTimestamp(), updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(ref));
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
});

test("nicknames and publicProfiles are server-only", async () => {
  const db = env.authenticatedContext("alice").firestore();
  await assertFails(setDoc(doc(db, "nicknames/alice"), { uid: "alice" }));
  await assertFails(getDoc(doc(db, "nicknames/alice")));
  await assertFails(setDoc(doc(db, "publicProfiles/alice"), { nickname: "Alice" }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "publicProfiles/bob"), { nickname: "Bob" });
    await setDoc(doc(ctx.firestore(), "publicProfiles/eve"), {
      nickname: "Eve",
      moderation: { hidden: true },
    });
  });
  await assertSucceeds(getDoc(doc(db, "publicProfiles/bob")));
  await assertFails(getDoc(doc(db, "publicProfiles/eve")));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "publicProfiles/bob")));
});

test("leaderboard: own entry, reserved name or the anonymous name, only upwards", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "leaderboards/level_1/scores/alice");
  await assertFails(setDoc(ref, { name: "Самозванец", wave: 5, updated: new Date() }));
  await assertSucceeds(setDoc(ref, { name: "Рыцарь", wave: 5, updated: new Date() }));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "publicProfiles/alice"), { nickname: "Alice" });
  });
  await assertSucceeds(setDoc(ref, { name: "Alice", wave: 7, updated: new Date() }));
  await assertFails(setDoc(ref, { name: "Alice", wave: 6, updated: new Date() }));
  await assertFails(
    setDoc(doc(db, "leaderboards/level_1/scores/bob"), { name: "Рыцарь", wave: 9, updated: new Date() }),
  );
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), "leaderboards/level_1/scores/alice")));
});

test("legacy saves: owner may read and delete", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const ref = doc(db, "saves/alice");
  await assertSucceeds(setDoc(ref, { progress: "[progress]\nunlocked=2\n" }));
  await assertFails(getDoc(doc(env.authenticatedContext("bob").firestore(), "saves/alice")));
  await assertSucceeds(deleteDoc(ref));
});

test("reports: create-only, about someone else, by the reporter", async () => {
  const db = env.authenticatedContext("alice").firestore();
  const report = { reporter: "alice", target: "bob", reason: "name", createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(db, "reports/r1"), report));
  await assertFails(getDoc(doc(db, "reports/r1")));
  await assertFails(setDoc(doc(db, "reports/r2"), { ...report, reporter: "bob" }));
  await assertFails(setDoc(doc(db, "reports/r3"), { ...report, target: "alice" }));
  await assertFails(setDoc(doc(db, "reports/r4"), { ...report, reason: "spam!!" }));
  assert.ok(true);
});
