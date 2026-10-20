// The records tables as the GAME asks for them: Firestore REST runQuery without a login
// (scripts/online_records.gd top_query + FirestoreClient.run_query, signed = false), checked
// against firestore.rules in the emulator. The other tests use the web SDK; this one sends the
// exact JSON body of the client, so a mismatch between the query shape and the rules shows up here.
// npm test   (in firebase/rules-tests; Firebase emulator, Java 21)
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { after, before, beforeEach, test } = require("node:test");
const assert = require("node:assert");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const { Timestamp, doc, setDoc } = require("firebase/firestore");

const ROOT = join(__dirname, "..", "..");
const PROJECT = "demo-bimbleguard-rest";
let env;

/** FirestoreClient.run_query body of OnlineRecords.top_query(): the 10 best waves. */
const topQuery = (limit = 10) => ({
  structuredQuery: {
    from: [{ collectionId: "scores" }],
    orderBy: [{ field: { fieldPath: "wave" }, direction: "DESCENDING" }],
    limit,
  },
});

/** The same URL the game builds: HOST/projects/<id>/databases/(default)/documents/<parent>:runQuery */
async function runQuery(parent, body) {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const url = `http://${host}/v1/projects/${PROJECT}/databases/(default)/documents/${parent}:runQuery`;
  const reply = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" }, // no Authorization: the table is public
    body: JSON.stringify(body),
  });
  return { code: reply.status, json: await reply.json().catch(() => null) };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync(join(ROOT, "firestore.rules"), "utf8") },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
});
after(async () => {
  await env.cleanup();
});

async function seedScores(parent, waves) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [i, wave] of waves.entries()) {
      await setDoc(doc(ctx.firestore(), `${parent}/scores/u${i}`), {
        name: `Рыцарь${i}`,
        wave,
        updated: Timestamp.now(),
      });
    }
  });
}

test("REST runQuery of the records table (client query) passes the rules", async () => {
  await seedScores("leaderboards/level_1", [5, 30, 12]);
  const { code, json } = await runQuery("leaderboards/level_1", topQuery());
  assert.strictEqual(code, 200, JSON.stringify(json));
  const waves = json.filter((r) => r.document).map((r) => Number(r.document.fields.wave.integerValue));
  assert.deepStrictEqual(waves, [30, 12, 5], "best first");
});

test("REST runQuery of an empty table is a 200 without documents", async () => {
  const { code, json } = await runQuery("leaderboards/level_2", topQuery());
  assert.strictEqual(code, 200, JSON.stringify(json));
  assert.strictEqual(json.filter((r) => r.document).length, 0);
});

test("REST runQuery of the daily table passes the rules", async () => {
  await seedScores("daily/2026-10-17", [4, 9]);
  const { code, json } = await runQuery("daily/2026-10-17", topQuery());
  assert.strictEqual(code, 200, JSON.stringify(json));
  assert.strictEqual(json.filter((r) => r.document).length, 2);
});

test("REST runQuery stays bounded: a limit above 100 and no limit are refused", async () => {
  const big = await runQuery("leaderboards/level_1", topQuery(101));
  assert.strictEqual(big.code, 403);
  const body = topQuery();
  delete body.structuredQuery.limit;
  const unbounded = await runQuery("leaderboards/level_1", body);
  assert.strictEqual(unbounded.code, 403);
});

test("REST runQuery cannot scan every table (collection group is refused)", async () => {
  const body = topQuery();
  body.structuredQuery.from = [{ collectionId: "scores", allDescendants: true }];
  const { code } = await runQuery("", body);
  assert.ok(code >= 400, `a collection-group scan must not succeed (got ${code})`);
});
