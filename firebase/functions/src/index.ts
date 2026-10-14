/**
 * Tinyguard callable Cloud Functions (Firebase Functions v2, Admin SDK).
 *
 * reserveNickname — the only writer of nicknames/* and publicProfiles/*.
 * deleteAccount   — deletes everything stored for the caller, then the Auth user.
 *
 * Called from Godot over HTTPS with the callable protocol:
 *   POST https://<region>-<project>.cloudfunctions.net/<name>
 *   Authorization: Bearer <Firebase id token>
 *   {"data": {...}}  ->  {"result": {...}} | {"error": {status, message, details}}
 * Errors carry details.reason: unauthenticated, invalid, taken, rate_limited.
 *
 * NOT DEPLOYED / NOT RUN against a real project from this repository:
 * see docs/ACCOUNTS.md ("Cloud Functions: deploy and test plan").
 */
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import {
  DocumentReference,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { validateNickname } from "./nickname";

/** Must match functions_region in firebase.cfg (client side). */
export const REGION = "europe-west1";
/** Minimum time between nickname changes (the first reservation is free). */
export const NICKNAME_CHANGE_INTERVAL_MS = 24 * 60 * 60 * 1000;
export const SCHEMA_VERSION = 1;

setGlobalOptions({ region: REGION, maxInstances: 10 });
initializeApp();

function requireUid(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in first.", { reason: "unauthenticated" });
  }
  return uid;
}

/**
 * Reserves data.nickname for the caller in one transaction:
 * nicknames/{normalized} -> {uid}; publicProfiles/{uid}.nickname;
 * users/{uid}.nickname/nicknameNormalized/lastNicknameChangeAt; releases the
 * caller's previous reservation. Idempotent for the same name.
 */
export const reserveNickname = onCall(async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as { nickname?: unknown };
  const check = validateNickname(data.nickname);
  if (!check.ok) {
    throw new HttpsError("invalid-argument", "Invalid nickname.", {
      reason: check.error === "reserved" ? "taken" : "invalid",
      code: check.error,
    });
  }
  const { nickname, normalized } = check;
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const publicRef = db.doc(`publicProfiles/${uid}`);
  const nameRef = db.doc(`nicknames/${normalized}`);

  const result = await db.runTransaction(async (tx) => {
    // All reads before any write (Firestore transactions require it).
    const [userSnap, publicSnap, nameSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(publicRef),
      tx.get(nameRef),
    ]);
    const owner = nameSnap.exists ? (nameSnap.get("uid") as string | undefined) : undefined;
    if (owner && owner !== uid) {
      throw new HttpsError("already-exists", "Nickname taken.", { reason: "taken" });
    }
    const previous = userSnap.get("nicknameNormalized") as string | undefined;
    if (owner === uid && previous === normalized && userSnap.get("nickname") === nickname) {
      return { nickname, normalized, changed: false };
    }
    const last = userSnap.get("lastNicknameChangeAt") as Timestamp | undefined;
    if (previous && last) {
      const wait = last.toMillis() + NICKNAME_CHANGE_INTERVAL_MS - Date.now();
      if (wait > 0) {
        throw new HttpsError("resource-exhausted", "Nickname changed too recently.", {
          reason: "rate_limited",
          retryAfterSeconds: Math.ceil(wait / 1000),
        });
      }
    }
    let previousRef: DocumentReference | null = null;
    if (previous && previous !== normalized) {
      previousRef = db.doc(`nicknames/${previous}`);
      const previousSnap = await tx.get(previousRef);
      if (!previousSnap.exists || previousSnap.get("uid") !== uid) previousRef = null;
    }
    const now = FieldValue.serverTimestamp();
    if (previousRef) tx.delete(previousRef);
    tx.set(nameRef, { uid, nickname, createdAt: now });
    tx.set(
      publicRef,
      publicSnap.exists ? { nickname } : { nickname, createdAt: now },
      { merge: true },
    );
    tx.set(
      userRef,
      userSnap.exists
        ? { nickname, nicknameNormalized: normalized, lastNicknameChangeAt: now }
        : {
            nickname,
            nicknameNormalized: normalized,
            lastNicknameChangeAt: now,
            schemaVersion: SCHEMA_VERSION,
            createdAt: now,
            updatedAt: now,
          },
      { merge: true },
    );
    return { nickname, normalized, changed: true };
  });

  if (result.changed) {
    await renameLeaderboardEntries(uid, nickname);
  }
  return { nickname: result.nickname, normalized: result.normalized };
});

/** Best effort, outside the transaction: old records show the new name. */
async function renameLeaderboardEntries(uid: string, nickname: string): Promise<void> {
  const db = getFirestore();
  const levels = await db.collection("leaderboards").listDocuments();
  await Promise.all(
    levels.map(async (level) => {
      const score = level.collection("scores").doc(uid);
      const snap = await score.get();
      if (snap.exists) await score.update({ name: nickname });
    }),
  );
}

/**
 * Deletes the caller's data: users/{uid}, publicProfiles/{uid}, the nickname
 * reservation(s), saves/{uid}, leaderboard entries, reports they filed —
 * then the Firebase Auth user. Safe to call again after a partial failure.
 */
export const deleteAccount = onCall(async (request) => {
  const uid = requireUid(request);
  const db = getFirestore();
  const refs: DocumentReference[] = [
    db.doc(`users/${uid}`),
    db.doc(`publicProfiles/${uid}`),
    db.doc(`saves/${uid}`),
  ];
  const names = await db.collection("nicknames").where("uid", "==", uid).get();
  names.forEach((doc) => refs.push(doc.ref));
  const levels = await db.collection("leaderboards").listDocuments();
  levels.forEach((level) => refs.push(level.collection("scores").doc(uid)));
  const reports = await db.collection("reports").where("reporter", "==", uid).get();
  reports.forEach((doc) => refs.push(doc.ref));

  // Batches of up to 500 deletes (deleting a missing document is fine).
  for (let i = 0; i < refs.length; i += 450) {
    const batch = db.batch();
    refs.slice(i, i + 450).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
  try {
    await getAuth().deleteUser(uid);
  } catch (error: unknown) {
    const code = (error as { code?: string }).code;
    if (code !== "auth/user-not-found") throw error;
  }
  return { deleted: true };
});
