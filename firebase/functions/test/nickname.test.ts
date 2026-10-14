// Unit tests of the nickname policy (no Firebase needed): the same table as
// the Godot client (tests/nickname_cases.json), plus server-only behaviour.
// npm test
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { validateNickname, validateRaw } from "../src/nickname";

const tablePath = join(__dirname, "..", "..", "..", "..", "tests", "nickname_cases.json");
const table = JSON.parse(readFileSync(tablePath, "utf8")) as { cases: string[][] };

test("shared table matches the Godot client", () => {
  for (const [input, error, nickname, normalized] of table.cases) {
    const r = validateRaw(input);
    assert.equal(r.nickname, nickname, `cleaned ${JSON.stringify(input)}`);
    if (error === "") {
      assert.ok(r.ok, `valid ${JSON.stringify(input)}`);
      if (r.ok) assert.equal(r.normalized, normalized, `normalized ${JSON.stringify(input)}`);
    } else {
      assert.ok(!r.ok, `invalid ${JSON.stringify(input)}`);
      if (!r.ok) assert.equal(r.error, error, `error ${JSON.stringify(input)}`);
    }
  }
});

test("server applies NFC before the rules", () => {
  const r = validateNickname("éclair");
  assert.ok(r.ok);
  if (r.ok) assert.equal(r.normalized, "éclair");
});

test("non-strings and huge payloads are refused", () => {
  assert.equal(validateNickname(42).ok, false);
  assert.equal(validateNickname(undefined).ok, false);
  assert.equal(validateNickname("a".repeat(10000)).ok, false);
});

test("uniqueness key ignores case, ё/е and space/_", () => {
  const a = validateNickname("Сэр Ёжик");
  const b = validateNickname("сэр_ежик");
  assert.ok(a.ok && b.ok);
  if (a.ok && b.ok) assert.equal(a.normalized, b.normalized);
});
