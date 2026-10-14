// reserveNickname / deleteAccount on the local emulators (Auth, Firestore,
// Functions), called exactly like the Godot client does: anonymous sign-up via
// the Identity Toolkit REST API, then the callable protocol over HTTP.
// npm run test:functions   (needs firebase-tools and Java; nothing reaches a real project)
const assert = require("node:assert/strict");
const { test } = require("node:test");

const PROJECT = "demo-tinyguard";
const REGION = "europe-west1";
const AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1";
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/${REGION}`;
const FIRESTORE = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;

async function signUp() {
  const res = await fetch(`${AUTH}/accounts:signUp?key=fake-key`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const json = await res.json();
  return { uid: json.localId, token: json.idToken };
}

async function call(name, token, data) {
  const res = await fetch(`${FUNCTIONS}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify({ data }),
  });
  return { status: res.status, json: await res.json() };
}

// Reads with the emulator's admin bypass ("Bearer owner").
async function adminGet(path) {
  const res = await fetch(`${FIRESTORE}/${path}`, { headers: { Authorization: "Bearer owner" } });
  return res.status === 200 ? res.json() : null;
}

test("reserve, idempotent repeat, taken, rate limit, case-insensitive", async () => {
  const alice = await signUp();
  const bob = await signUp();
  let r = await call("reserveNickname", alice.token, { nickname: "  Сэр   Ёжик " });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.deepEqual(r.json.result, { nickname: "Сэр Ёжик", normalized: "сэр_ежик" });
  r = await call("reserveNickname", alice.token, { nickname: "Сэр Ёжик" });
  assert.equal(r.status, 200, "same name again is fine");
  r = await call("reserveNickname", bob.token, { nickname: "сэр_ежик" });
  assert.equal(r.json.error.details.reason, "taken");
  r = await call("reserveNickname", bob.token, { nickname: "a!" });
  assert.equal(r.json.error.details.reason, "invalid");
  r = await call("reserveNickname", bob.token, { nickname: "Admin" });
  assert.equal(r.json.error.details.reason, "taken");
  r = await call("reserveNickname", alice.token, { nickname: "Другое Имя" });
  assert.equal(r.json.error.details.reason, "rate_limited", "a change right away is limited");

  const pub = await adminGet(`publicProfiles/${alice.uid}`);
  assert.equal(pub.fields.nickname.stringValue, "Сэр Ёжик");
  assert.deepEqual(Object.keys(pub.fields).sort(), ["createdAt", "nickname"]);
  const user = await adminGet(`users/${alice.uid}`);
  assert.equal(user.fields.nicknameNormalized.stringValue, "сэр_ежик");
  const index = await adminGet("nicknames/сэр_ежик");
  assert.equal(index.fields.uid.stringValue, alice.uid);
});

test("unauthenticated calls are refused", async () => {
  const r = await call("reserveNickname", "not-a-token", { nickname: "Гость" });
  assert.notEqual(r.status, 200);
});

test("deleteAccount removes data, reservation and the auth user", async () => {
  const carol = await signUp();
  let r = await call("reserveNickname", carol.token, { nickname: "Кэрол" });
  assert.equal(r.status, 200, JSON.stringify(r.json));
  r = await call("deleteAccount", carol.token, {});
  assert.equal(r.status, 200, JSON.stringify(r.json));
  assert.equal(await adminGet(`users/${carol.uid}`), null);
  assert.equal(await adminGet(`publicProfiles/${carol.uid}`), null);
  assert.equal(await adminGet("nicknames/кэрол"), null);
  const dave = await signUp();
  r = await call("reserveNickname", dave.token, { nickname: "Кэрол" });
  assert.equal(r.status, 200, "the released name can be taken again");
});
