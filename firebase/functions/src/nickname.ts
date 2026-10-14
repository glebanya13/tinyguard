/**
 * Nickname policy — the server-side twin of scripts/nickname_rules.gd.
 * Both are checked against tests/nickname_cases.json; change them together.
 *
 * - Trim, collapse runs of whitespace (space, tab, CR, LF, NBSP) to one space.
 * - 3..16 characters (code points) after that.
 * - Latin letters (A-Z, a-z, U+00C0..U+017F without U+00D7, U+00F7, U+0130),
 *   Cyrillic (U+0401..U+045F without U+040D), digits 0-9; a single space or
 *   underscore only between two letters/digits.
 *   (Only ranges where Godot's String.to_lower() and JS toLowerCase() agree.)
 * - Uniqueness key: lower case, "ё" -> "е", space -> "_".
 * - Reserved names are refused.
 *
 * The client never normalizes Unicode; the server applies NFC first, so a
 * decomposed "й" typed on an odd keyboard still validates here — but the
 * client would refuse it earlier, which is fine (stricter client).
 */

export const MIN_LENGTH = 3;
export const MAX_LENGTH = 16;

export const RESERVED: ReadonlySet<string> = new Set([
  "admin",
  "administrator",
  "moderator",
  "support",
  "system",
  "tinyguard",
  "bimbleguard",
  "рыцарь",
  "админ",
  "администратор",
  "модератор",
  "поддержка",
]);

export type NicknameError =
  | "too_short"
  | "too_long"
  | "bad_char"
  | "bad_separator"
  | "reserved";

export type NicknameCheck =
  | { ok: true; nickname: string; normalized: string }
  | { ok: false; nickname: string; error: NicknameError };

const WHITESPACE = new Set([0x20, 0x09, 0x0a, 0x0d, 0xa0]);

/** Godot's String.strip_edges(): drops characters <= U+0020 at both ends. */
function stripEdges(raw: string): string {
  const chars = Array.from(raw);
  let start = 0;
  let end = chars.length;
  while (start < end && chars[start].codePointAt(0)! <= 0x20) start++;
  while (end > start && chars[end - 1].codePointAt(0)! <= 0x20) end--;
  return chars.slice(start, end).join("");
}

export function clean(raw: string): string {
  let out = "";
  let gap = false;
  for (const ch of stripEdges(raw)) {
    if (WHITESPACE.has(ch.codePointAt(0)!)) {
      gap = true;
      continue;
    }
    if (gap && out !== "") out += " ";
    gap = false;
    out += ch;
  }
  return out;
}

export function isLetterOrDigit(code: number): boolean {
  return (
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a) ||
    (code >= 0xc0 && code <= 0x17f && code !== 0xd7 && code !== 0xf7 && code !== 0x130) ||
    (code >= 0x401 && code <= 0x45f && code !== 0x40d)
  );
}

export function normalize(name: string): string {
  return name.toLowerCase().replace(/ё/g, "е").replace(/ /g, "_");
}

function errorCode(name: string): NicknameError | null {
  const chars = Array.from(name);
  if (chars.length < MIN_LENGTH) return "too_short";
  if (chars.length > MAX_LENGTH) return "too_long";
  let badSeparator = false;
  let previousSeparator = true;
  for (const ch of chars) {
    const code = ch.codePointAt(0)!;
    const separator = code === 0x20 || code === 0x5f;
    if (!separator && !isLetterOrDigit(code)) return "bad_char";
    if (separator && previousSeparator) badSeparator = true;
    previousSeparator = separator;
  }
  if (badSeparator || previousSeparator) return "bad_separator";
  return null;
}

/** Validates without NFC (exactly what the Godot client does). */
export function validateRaw(raw: string): NicknameCheck {
  const nickname = clean(raw);
  const error = errorCode(nickname);
  if (error) return { ok: false, nickname, error };
  const normalized = normalize(nickname);
  if (RESERVED.has(normalized)) return { ok: false, nickname, error: "reserved" };
  return { ok: true, nickname, normalized };
}

/** Server entry point: NFC first, then the shared rules. */
export function validateNickname(raw: unknown): NicknameCheck {
  if (typeof raw !== "string") return { ok: false, nickname: "", error: "too_short" };
  if (raw.length > 200) return { ok: false, nickname: "", error: "too_long" };
  return validateRaw(raw.normalize("NFC"));
}
