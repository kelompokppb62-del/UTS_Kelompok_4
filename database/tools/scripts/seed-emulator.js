const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

async function main() {
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:29099" ||
      process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:28080") {
    throw new Error("Set both emulator hosts before seeding.");
  }
  const projectId = process.env.GCLOUD_PROJECT || "demo-katyuflow";
  if (!projectId.startsWith("demo-")) throw new Error("Gunakan ID proyek demo-*.");
  const password = process.env.KATYUFLOW_DEMO_PASSWORD;
  if (!password || password.length < 8) {
    throw new Error("Isi KATYUFLOW_DEMO_PASSWORD dengan minimal 8 karakter fiktif.");
  }
  initializeApp({ projectId });
  for (const [uid, role] of [["local-owner", "owner"], ["local-worker", "worker"]]) {
    const email = `${uid}@example.test`;
    const attributes = { email, password, displayName: uid };
    try {
      await getAuth().updateUser(uid, attributes);
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
      await getAuth().createUser({ uid, ...attributes });
    }
    await getAuth().setCustomUserClaims(uid, { role });
    const ref = getFirestore().doc(`users/${uid}`);
    if (!(await ref.get()).exists) {
      await ref.create({ uid, email, name: uid, role, status: "active", points: 0,
        createdAt: FieldValue.serverTimestamp() });
    }
    console.log(`Seeded ${role}: ${email}`);
  }
}
main().catch((error) => { console.error(error.message); process.exitCode = 1; });
