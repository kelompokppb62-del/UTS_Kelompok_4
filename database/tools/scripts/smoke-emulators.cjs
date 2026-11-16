const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { initializeApp: initializeClient, deleteApp: deleteClient } = require('firebase/app');
const {
  connectAuthEmulator, getAuth: getClientAuth, signInWithEmailAndPassword, signOut,
} = require('firebase/auth');
const {
  connectFirestoreEmulator, doc, getDocFromServer, getFirestore: getClientStore, terminate,
} = require('firebase/firestore');

const projectId = 'demo-katyuflow';
const authHost = '127.0.0.1:29099';
const firestoreHost = '127.0.0.1:28080';
const uid = 'docker-smoke-owner';
const email = 'docker-smoke-owner@example.test';
const profileName = 'Owner Fiktif Docker';

async function main() {
  const mode = process.argv[2];
  assert.ok(['create', 'restore'].includes(mode), 'Pilih mode create atau restore.');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, authHost);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, firestoreHost);

  const admin = initializeApp({ projectId });
  try {
    const auth = getAuth(admin);
    const profile = getFirestore(admin).doc('users/' + uid);
    if (mode === 'restore') {
      const [account, document] = await Promise.all([auth.getUser(uid), profile.get()]);
      assert.equal(account.email, email);
      assert.equal(account.customClaims.role, 'owner');
      assert.equal(document.get('name'), profileName);
      assert.equal(document.get('points'), 0);
      console.log('Pemulihan akun, claim Owner, dan profil Firestore lulus.');
      return;
    }

    const password = randomBytes(24).toString('hex');
    await auth.createUser({ uid, email, password });
    await auth.setCustomUserClaims(uid, { role: 'owner' });
    await profile.create({ uid, email, name: profileName, role: 'owner', status: 'active', points: 0 });

    const client = initializeClient({ projectId, apiKey: 'fixture-only' });
    const clientAuth = getClientAuth(client);
    const clientStore = getClientStore(client);
    connectAuthEmulator(clientAuth, 'http://' + authHost, { disableWarnings: true });
    connectFirestoreEmulator(clientStore, '127.0.0.1', 28080);
    try {
      const session = await signInWithEmailAndPassword(clientAuth, email, password);
      assert.equal((await session.user.getIdTokenResult()).claims.role, 'owner');
      const document = await getDocFromServer(doc(clientStore, 'users', uid));
      assert.equal(document.get('status'), 'active');
      assert.equal(document.get('points'), 0);
      console.log('Login Auth Emulator, claim Owner, dan pembacaan profil via SDK client lulus.');
    } finally {
      await signOut(clientAuth);
      await terminate(clientStore);
      await deleteClient(client);
    }
  } finally {
    await deleteApp(admin);
  }
}

main().catch(error => {
  console.error('Smoke test gagal (' + (error.code || error.name) + ').');
  process.exitCode = 1;
});
