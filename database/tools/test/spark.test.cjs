const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const {
  Bytes, Timestamp, collection, deleteDoc, doc, getDocFromServer, getDocs, onSnapshot, query, runTransaction,
  serverTimestamp, setDoc, setLogLevel, updateDoc, where, writeBatch,
} = require('firebase/firestore');

setLogLevel('silent');

const owner = 'owner';
const worker = 'worker';
const other = 'other';
const roles = { owner: 'owner', worker: 'worker', other: 'worker' };
const rules = readFileSync(new URL('../../firestore.rules', `file://${__filename}`), 'utf8');
const projectId = process.env.GCLOUD_PROJECT || 'demo-katyuflow';
let env;

function actor(uid, role = roles[uid], testEnv = env) {
  return testEnv.authenticatedContext(uid, { role }).firestore();
}

async function admin(work, testEnv = env) {
  return testEnv.withSecurityRulesDisabled((context) => work(context.firestore()));
}

async function profiles(testEnv = env) {
  await admin(async (db) => {
    for (const [uid, role] of Object.entries(roles)) {
      await setDoc(doc(db, 'users', uid), {
        uid, role, status: 'active', name: uid, email: `${uid}@example.test`,
        points: 0, createdAt: serverTimestamp(),
      });
    }
  }, testEnv);
}

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !projectId.startsWith('demo-')) {
    throw new Error('Run the Spark suite in the Firestore emulator with a demo project.');
  }
  env = await initializeTestEnvironment({ projectId, firestore: { rules } });
  await env.clearFirestore();
  await profiles();
});

after(async () => {
  if (env) await env.cleanup();
});

function audit(db, write, uid, id, action, detail) {
  const ref = doc(collection(db, 'projectActivities'));
  write.set(ref, { projectId: id, actorId: uid, action, timestamp: serverTimestamp(), ...(detail === undefined ? {} : { detail }) });
  return ref.id;
}

function publish(id, { db = actor(owner), extra = {}, extraListing = {}, includeAudit = true,
  includeListing = true, includePrivate = true } = {}) {
  const write = writeBatch(db);
  const listing = {
    projectId: id, title: id, status: 'available', packageType: 'Basic', points: 100,
    deadline: Timestamp.fromMillis(Date.now() + 172800000), createdAt: serverTimestamp(),
  };
  const activityId = includeAudit ? audit(db, write, owner, id, 'published') : 'missingAudit';
  if (includeListing) write.set(doc(db, 'projectListings', id), { ...listing, ...extraListing });
  if (includePrivate) write.set(doc(db, 'projects', id), {
    ...listing, activityId, updatedAt: serverTimestamp(), assignedWorkerId: null,
    createdBy: owner, clientName: 'Private client', brief: 'Private brief', ...extra,
  });
  return write.commit();
}

const day = (value) => Math.floor((value.toMillis() + 7 * 3600000) / 86400000);

async function sample(db, uid) {
  const ref = doc(db, 'serverClocks', uid);
  await setDoc(ref, { at: serverTimestamp() });
  return (await getDocFromServer(ref)).data().at;
}

function claimWrites(db, write, uid, id, count, options = {}) {
  const activityId = options.audit === false ? 'missingAudit' : audit(db, write, uid, id, 'claimed');
  if (options.project !== false) write.update(doc(db, 'projects', id), {
    status: 'claimed', assignedWorkerId: uid, assignedWorkerName: uid, activityId,
    claimedAt: serverTimestamp(), updatedAt: serverTimestamp(), ...options.projectFields,
  });
  if (options.counter !== false) write.set(doc(db, 'claimCounters', uid), {
    workerId: uid, lastProjectId: id, claimCount: count, updatedAt: serverTimestamp(), ...options.counterFields,
  });
  if (options.listing !== false) write.delete(doc(db, 'projectListings', id));
}

function maliciousClaim(db, uid, id, count, options) {
  const write = writeBatch(db);
  claimWrites(db, write, uid, id, count, options);
  return write.commit();
}

async function retryPermissionOnce(operation) {
  try {
    return await operation();
  } catch (error) {
    if (error.code !== 'permission-denied') throw error;
    return operation();
  }
}

async function claimOnce(db, uid, id) {
  const now = await sample(db, uid);
  return runTransaction(db, async (transaction) => {
    const listing = await transaction.get(doc(db, 'projectListings', id));
    if (!listing.exists()) return 'unavailable';
    const counter = (await transaction.get(doc(db, 'claimCounters', uid))).data();
    await transaction.get(doc(db, 'users', uid));
    const count = counter && day(counter.updatedAt) === day(now) ? counter.claimCount : 0;
    if (count >= 3) return 'quota';
    claimWrites(db, transaction, uid, id, count + 1);
    return 'claimed';
  });
}

function claim(db, uid, id) {
  return retryPermissionOnce(() => claimOnce(db, uid, id));
}

const submission = { notes: 'Pekerjaan selesai.', discordUrl: 'https://discord.gg/katyuflow', proofUrl: null };
const revisionDetails = { title: 'Perbaiki roles', description: 'Tinjau kembali permissions.', deadline: null, imageCount: 0 };

function transition(db, write, uid, id, status, extra = {}, detail) {
  const activityId = audit(db, write, uid, id, status, detail);
  write.update(doc(db, 'projects', id), {
    status, activityId, updatedAt: serverTimestamp(), ...extra,
  });
  return activityId;
}

function submit(db, id, detail = submission, extra = {}, uid = worker) {
  const write = writeBatch(db);
  transition(db, write, uid, id, 'waiting_review', { submittedAt: serverTimestamp(), ...extra }, detail);
  return write.commit();
}

async function progress(id, db = actor(worker)) {
  for (const status of ['working', 'almostDone']) {
    const write = writeBatch(db);
    transition(db, write, worker, id, status);
    await assertSucceeds(write.commit());
  }
  await assertSucceeds(submit(db, id));
}

function approvalWrites(db, write, id, { balance = true, ledger = true, change = true, score = true,
  points = 100, total = 100, assignee = worker, completed = 1, onTime = 1, scoreFields = {}, submittedAt } = {}) {
  if (change) transition(db, write, owner, id, 'completed', submittedAt ? { submittedAt } : {});
  if (balance) write.update(doc(db, 'users', assignee), {
    points: total, lastRewardProjectId: id,
  });
  if (ledger) write.set(doc(db, 'pointTransactions', id), {
    projectId: id, workerId: assignee, points, reason: 'project_approved', createdAt: serverTimestamp(),
  });
  if (score) write.set(doc(db, 'workerScores', assignee), {
    name: assignee, points: total, completed, onTime, updatedAt: serverTimestamp(), ...scoreFields,
  });
}

function rawApproval(db, id, options) {
  const write = writeBatch(db);
  approvalWrites(db, write, id, options);
  return write.commit();
}

function approveOnce(db, id) {
  return runTransaction(db, async (transaction) => {
    const project = (await transaction.get(doc(db, 'projects', id))).data();
    const receipt = await transaction.get(doc(db, 'pointTransactions', id));
    if (project.status === 'completed' && receipt.exists()) return 'already-approved';
    assert.ok(['waiting_review', 'waitingReview'].includes(project.status));
    const userRef = doc(db, 'users', project.assignedWorkerId);
    const profile = (await transaction.get(userRef)).data();
    const score = (await transaction.get(doc(db, 'workerScores', project.assignedWorkerId))).data();
    const onTime = (project.submittedAt ?? project.updatedAt).toMillis() <= (project.revisionDeadline ?? project.deadline).toMillis();
    approvalWrites(db, transaction, id, {
      assignee: project.assignedWorkerId, points: project.points, total: profile.points + project.points,
      completed: (score?.completed ?? 0) + 1, onTime: (score?.onTime ?? 0) + Number(onTime),
      submittedAt: project.submittedAt ?? project.updatedAt,
    });
    return 'approved';
  });
}

function approve(db, id) {
  return retryPermissionOnce(() => approveOnce(db, id));
}

function observe(target, predicate) {
  return new Promise((resolve, reject) => {
    let stop;
    const timer = setTimeout(() => finish(new Error('Timed out waiting for Firestore stream')), 20000);
    function finish(error) {
      clearTimeout(timer);
      stop?.();
      if (error) reject(error); else resolve();
    }
    stop = onSnapshot(target, (snapshot) => {
      if (!snapshot.metadata.fromCache && !snapshot.metadata.hasPendingWrites && predicate(snapshot)) finish();
    }, finish);
  });
}

test('publication is atomic, and two Worker streams see only the safe listing', async () => {
  const db = actor(owner);
  const workerDb = actor(worker);
  const otherSession = actor(worker);
  await assertFails(publish('missing-listing', { db, includeListing: false }));
  await assertFails(publish('orphan-listing', { db, includePrivate: false }));
  await assertFails(publish('missing-audit', { db, includeAudit: false }));
  await assertFails(publish('private-listing', { db, extraListing: { brief: 'leak' } }));
  await assertFails(publish('extra-field', { db, extra: { admin: true } }));
  await assertFails(publish('invalid-reward', { db, extra: { points: 500 } }));
  const streamed = [workerDb, otherSession].map((session) =>
    observe(doc(session, 'projectListings', 'published'), (snapshot) => snapshot.exists()));
  await assertSucceeds(publish('published', { db }));
  await Promise.all(streamed);
  const listing = (await getDocFromServer(doc(workerDb, 'projectListings', 'published'))).data();
  assert.equal(listing.brief, undefined);
  assert.equal(listing.clientName, undefined);
  await assertFails(getDocFromServer(doc(workerDb, 'projects', 'published')));
  const full = await assertSucceeds(getDocFromServer(doc(db, 'projects', 'published')));
  assert.equal(full.data().brief, 'Private brief');
});

test('one of two concurrent Workers wins, loses no quota, and alone sees private details', { timeout: 60000 }, async () => {
  await publish('race');
  const results = await Promise.all([claim(actor(worker), worker, 'race'), claim(actor(other), other, 'race')]);
  assert.deepEqual(results.sort(), ['claimed', 'unavailable']);
  const record = (await getDocFromServer(doc(actor(owner), 'projects', 'race'))).data();
  const winner = record.assignedWorkerId;
  const loser = winner === worker ? other : worker;
  assert.equal((await getDocFromServer(doc(actor(winner), 'projects', 'race'))).data().clientName, 'Private client');
  await assertFails(getDocFromServer(doc(actor(loser), 'projects', 'race')));
  assert.equal((await getDocFromServer(doc(actor(winner), 'claimCounters', winner))).data().claimCount, 1);
  assert.equal((await getDocFromServer(doc(actor(loser), 'claimCounters', loser))).exists(), false);
  await assertFails(maliciousClaim(actor(loser), loser, 'race', 1));
  assert.equal((await getDocFromServer(doc(actor(loser), 'claimCounters', loser))).exists(), false);
  await assertFails(getDocs(collection(actor(worker), 'projects')));
  await assertSucceeds(getDocs(query(collection(actor(winner), 'projects'), where('assignedWorkerId', '==', winner))));
});

test('quota counts server day and rejects fourth claim at the API without side effects', { timeout: 60000 }, async () => {
  const db = actor(worker);
  const now = await sample(db, worker);
  await admin((store) => setDoc(doc(store, 'claimCounters', worker), {
    workerId: worker, dateKey: 'legacy-counter', claimCount: 3,
    updatedAt: Timestamp.fromMillis(now.toMillis() - 86400000),
  }));
  for (const id of ['quota1', 'quota2', 'quota3', 'quota4']) await publish(id);
  for (const id of ['quota1', 'quota2', 'quota3']) assert.equal(await claim(db, worker, id), 'claimed');
  assert.equal(await claim(db, worker, 'quota4'), 'quota');
  await assertFails(maliciousClaim(db, worker, 'quota4', 4));
  await assertFails(maliciousClaim(db, worker, 'quota4', 1));
  assert.equal((await getDocFromServer(doc(db, 'projectListings', 'quota4'))).exists(), true);
  assert.equal((await getDocFromServer(doc(db, 'claimCounters', worker))).data().claimCount, 3);
});

test('the Jakarta rollover uses 17:00 UTC exactly in Rules', { timeout: 60000 }, async () => {
  // Firestore supplies request.time. Evaluate the same rule helper against fixed
  // instants in a separate emulator project to exercise both sides of midnight.
  const midnightUtc = 17 * 60 * 60 * 1000;
  for (const [label, millis, allowed] of [
    ['before', midnightUtc - 1, false], ['after', midnightUtc, true],
  ]) {
    const probe = rules.replace('return jakartaDay(request.time);',
      `return jakartaDay(timestamp.date(2025, 12, 31) + duration.value(${millis}, 'ms'));`);
    const fixedEnv = await initializeTestEnvironment({
      projectId: `demo-katyuflow-wib-${label}`, firestore: { rules: probe },
    });
    try {
      await profiles(fixedEnv);
      await admin((db) => setDoc(doc(db, 'claimCounters', worker), {
        workerId: worker, claimCount: 3, updatedAt: Timestamp.fromMillis(Date.parse('2025-12-31T16:59:59.999Z')),
      }), fixedEnv);
      await publish('midnight', { db: actor(owner, 'owner', fixedEnv) });
      const commit = maliciousClaim(actor(worker, 'worker', fixedEnv), worker, 'midnight', 1);
      if (allowed) await assertSucceeds(commit); else await assertFails(commit);
    } finally {
      await fixedEnv.clearFirestore();
      await fixedEnv.cleanup();
    }
  }
});

test('direct API cannot tamper with counters, assignment, fields or partial writes', async () => {
  const db = actor(other);
  await admin((store) => setDoc(doc(store, 'claimCounters', other), {
    workerId: other, lastProjectId: 'historical', claimCount: 1, updatedAt: serverTimestamp(),
  }));
  await publish('integrity');
  await publish('integrity2');
  await assertFails(updateDoc(doc(db, 'claimCounters', other), { claimCount: 0 }));
  await assertFails(setDoc(doc(db, 'serverClocks', other), { at: Timestamp.fromMillis(0) }));
  await assertFails(setDoc(doc(db, 'serverClocks', worker), { at: serverTimestamp() }));
  for (const options of [
    { counter: false }, { project: false }, { listing: false }, { audit: false },
    { projectFields: { assignedWorkerId: worker } }, { projectFields: { assignedWorkerName: 'fake' } },
    { projectFields: { brief: 'overwrite' } }, { projectFields: { points: 9000 } },
    { counterFields: { updatedAt: Timestamp.fromMillis(0) } },
    { counterFields: { lastProjectId: 'integrity2' } },
    { counterFields: { workerId: worker } },
  ]) {
    await assertFails(maliciousClaim(db, other, 'integrity', 2, options));
  }
  const both = writeBatch(db);
  claimWrites(db, both, other, 'integrity', 2);
  claimWrites(db, both, other, 'integrity2', 2, {counter: false});
  await assertFails(both.commit());
  assert.equal((await getDocFromServer(doc(db, 'claimCounters', other))).data().claimCount, 1);
  assert.equal((await getDocFromServer(doc(db, 'projectListings', 'integrity'))).exists(), true);
  assert.equal(await claim(db, other, 'integrity'), 'claimed');
});

test('role and assignment are enforced for reads, progress, points and audit', async () => {
  const db = actor(worker);
  await assertFails(updateDoc(doc(db, 'users', worker), { role: 'owner' }));
  await assertFails(updateDoc(doc(db, 'users', worker), { points: 5000 }));
  await assertFails(getDocs(collection(actor(worker, 'owner'), 'projects')));
  await assertFails(publish('forged-owner', { db: actor(worker, 'owner') }));
  await assertFails(getDocFromServer(doc(env.unauthenticatedContext().firestore(), 'projects', 'published')));
  await assertFails(getDocFromServer(doc(db, 'projects', 'integrity')));
  const wrongWorker = writeBatch(db);
  transition(db, wrongWorker, worker, 'integrity', 'working');
  await assertFails(wrongWorker.commit());
  for (const [status, changes] of [['completed', {}], ['waitingReview', {}], ['working', { title: 'new' }]]) {
    const malicious = writeBatch(db);
    transition(db, malicious, worker, 'quota1', status, changes);
    await assertFails(malicious.commit());
  }
  await assertFails(setDoc(doc(db, 'pointTransactions', 'quota1'), {
    projectId: 'quota1', workerId: worker, points: 100, createdAt: serverTimestamp(),
  }));
  const orphanAudit = writeBatch(db);
  audit(db, orphanAudit, worker, 'quota1', 'working');
  await assertFails(orphanAudit.commit());
  await admin((store) => updateDoc(doc(store, 'users', worker), { status: 'suspended' }));
  try { await assertFails(getDocFromServer(doc(db, 'projects', 'quota1'))); }
  finally { await admin((store) => updateDoc(doc(store, 'users', worker), { status: 'active' })); }
});

test('review, revision and concurrent approval credit one immutable reward', { timeout: 60000 }, async () => {
  const id = 'quota1';
  await progress(id);
  const db = actor(owner);
  const revision = writeBatch(db);
  transition(db, revision, owner, id, 'revision_required', { revisionDeadline: null }, revisionDetails);
  await assertSucceeds(revision.commit());
  await progress(id);
  for (const options of [
    { balance: false }, { ledger: false }, { change: false }, { score: false }, { points: 999, total: 999 },
    { completed: 99 }, { onTime: 99 }, { scoreFields: { email: 'private@example.test' } },
    { total: 999 }, { assignee: other },
  ]) {
    await assertFails(rawApproval(db, id, options));
  }
  await assertFails(updateDoc(doc(db, 'users', worker), { points: 100 }));
  const workerDb = actor(worker);
  const streamed = observe(doc(workerDb, 'users', worker), (snapshot) => snapshot.data()?.points === 100);
  const result = await Promise.all([approve(db, id), approve(actor(owner), id)]);
  assert.deepEqual(result.sort(), ['already-approved', 'approved']);
  await streamed;
  await assertFails(rawApproval(db, id, { total: 200 }));
  await assertFails(updateDoc(doc(db, 'pointTransactions', id), { points: 200 }));
  await assertFails(getDocFromServer(doc(actor(other), 'pointTransactions', id)));
  const receipt = (await getDocFromServer(doc(workerDb, 'pointTransactions', id))).data();
  assert.equal(receipt.points, 100);
  assert.equal((await getDocFromServer(doc(workerDb, 'users', worker))).data().points, 100);
  const history = await getDocs(query(collection(db, 'projectActivities'), where('projectId', '==', id)));
  assert.equal(history.docs.filter((entry) => entry.data().action === 'completed').length, 1);
});

test('records written in Phase 2 can finish and earn their original reward', async () => {
  const id = 'legacy';
  await admin((db) => setDoc(doc(db, 'projects', id), {
    projectId: id, title: 'Legacy project', status: 'almostDone', packageType: 'Premium',
    points: 150, deadline: Timestamp.now(), createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(), claimedAt: Timestamp.now(), assignedWorkerId: other,
    assignedWorkerName: other, createdBy: owner, clientName: 'Private', brief: 'Legacy brief',
  }));
  const workerDb = actor(other);
  await assertSucceeds(submit(workerDb, id, submission, {}, other));
  assert.equal(await approve(actor(owner), id), 'approved');
  assert.equal((await getDocFromServer(doc(workerDb, 'users', other))).data().points, 150);
  assert.equal((await getDocFromServer(doc(workerDb, 'pointTransactions', id))).data().points, 150);
  assert.equal((await getDocFromServer(doc(actor(worker), 'workerScores', other))).data().onTime, 0);
});

test('only an active Owner can query the Worker directory', async () => {
  const directory = (db) => query(collection(db, 'users'), where('role', '==', 'worker'));
  const rows = await assertSucceeds(getDocs(directory(actor(owner))));
  assert.deepEqual(rows.docs.map((row) => row.id).sort(), [other, worker].sort());
  await assertFails(getDocs(directory(actor(worker))));
  await assertFails(getDocs(directory(actor(worker, 'owner'))));
  await assertFails(getDocs(directory(env.unauthenticatedContext().firestore())));
});

async function assignForTest(id, status = 'almostDone', patch = {}) {
  await admin((db) => setDoc(doc(db, 'projects', id), {
    projectId: id, title: id, status, packageType: 'Basic',
    points: 100, deadline: Timestamp.fromMillis(Date.now() + 3600000),
    createdAt: Timestamp.now(), updatedAt: Timestamp.now(), assignedWorkerId: worker,
    assignedWorkerName: worker, createdBy: owner, clientName: 'Private', brief: 'Private',
    ...patch,
  }));
}

const activity = (db, id) => query(collection(db, 'projectActivities'), where('projectId', '==', id));

test('submissions validate notes and HTTPS, require atomic history and preserve all review rounds', async () => {
  const id = 'submission';
  const db = actor(worker);
  await assignForTest(id);
  await assertFails(submit(actor(other), id, submission, {}, other));
  for (const detail of [
    { ...submission, notes: '   ' }, { ...submission, notes: 'a'.repeat(4001) },
    { ...submission, discordUrl: 'https://discord.gg.evil.test/valid' },
    { ...submission, discordUrl: 'https://discord.gg@evil.test/valid' },
    { ...submission, proofUrl: 'javascript:alert(1)' },
    { ...submission, proofUrl: 'https://test.example@alternate.example/path' },
    { ...submission, proofUrl: 'https://test.example/path' + String.fromCharCode(92) + 'windows' },
    { ...submission, points: 1000 },
  ]) await assertFails(submit(db, id, detail));
  await assertFails(submit(db, id, submission, { submittedAt: Timestamp.fromMillis(0) }));
  await assertFails(submit(db, id, undefined, { points: 1200 }));
  const bare = writeBatch(db);
  transition(db, bare, worker, id, 'waitingReview');
  await assertFails(bare.commit());
  const observed = observe(activity(actor(owner), id), (result) =>
    result.docs.some((event) => event.data().detail?.notes === submission.notes));
  await assertSucceeds(submit(db, id, { ...submission, proofUrl: 'https://example.test/proof?id=1' }));
  await observed;
  assert.equal((await getDocFromServer(doc(db, 'users', worker))).data().points, 100);
  await assertFails(getDocs(activity(actor(other), id)));
  await assertFails(getDocs(collection(db, 'projectActivities')));
  const ownerDb = actor(owner);
  for (const number of [1, 2]) {
    const write = writeBatch(ownerDb);
    transition(ownerDb, write, owner, id, 'revision_required',
      { revisionDeadline: null }, { ...revisionDetails, title: 'Revision ' + number });
    await assertSucceeds(write.commit());
    await assertSucceeds(submit(db, id, { ...submission, notes: 'Kiriman ' + number }));
  }
  const history = await assertSucceeds(getDocs(activity(db, id)));
  assert.equal(history.size, 5);
  assert.equal(history.docs.filter((entry) => entry.data().action === 'waiting_review').length, 3);
  assert.equal(history.docs.filter((entry) => entry.data().action === 'revision_required').length, 2);
  await assertFails(updateDoc(history.docs[0].ref, { 'detail.notes': 'forged' }));
  await assertFails(deleteDoc(history.docs[0].ref));
});

test('revision attachments enforce atomic linkage, byte limits, JPEG format, roles and privacy', async () => {
  const id = 'revision-photos';
  await assignForTest(id, 'waitingReview');
  const db = actor(owner);
  const jpeg = Bytes.fromUint8Array(Uint8Array.from([0xff, 0xd8, 0xff, ...Array(13).fill(1), 0xff, 0xd9]));
  function revise({ writer = db, uid = owner, images = [jpeg, jpeg], count = images.length,
    attach = true, encoding = 'image/jpeg', deadline = null, detail = {} } = {}) {
    const write = writeBatch(writer);
    const event = transition(writer, write, uid, id, 'revision_required', { revisionDeadline: deadline },
      { ...revisionDetails, imageCount: count, deadline, ...detail });
    if (attach) write.set(doc(writer, 'revisionImages', event), { encoding, images });
    return [write.commit(), event];
  }
  await assertFails(revise({ attach: false })[0]);
  await assertFails(revise({ count: 1 })[0]);
  await assertFails(revise({ images: [jpeg, jpeg, jpeg] })[0]);
  await assertFails(revise({ encoding: 'image/png' })[0]);
  await assertFails(revise({ images: ['encoded'] })[0]);
  await assertFails(revise({ images: [Bytes.fromUint8Array(new Uint8Array(16))] })[0]);
  const large = new Uint8Array(150001);
  large.set([0xff, 0xd8, 0xff]);
  await assertFails(revise({ images: [Bytes.fromUint8Array(large)] })[0]);
  await assertFails(revise({ deadline: Timestamp.fromMillis(1) })[0]);
  await assertFails(revise({ detail: { title: ' ' } })[0]);
  await assertFails(revise({ writer: actor(worker), uid: worker })[0]);
  await assertFails(setDoc(doc(db, 'revisionImages', 'orphan'), { encoding: 'image/jpeg', images: [jpeg] }));
  const max = new Uint8Array(150000);
  max.set([0xff, 0xd8, 0xff]);
  max.set([0xff, 0xd9], max.length - 2);
  const deadline = Timestamp.fromMillis(Date.now() + 3600000);
  const [commit, event] = revise({ deadline, images: [Bytes.fromUint8Array(max), Bytes.fromUint8Array(max)] });
  await assertSucceeds(commit);
  assert.equal((await getDocFromServer(doc(actor(worker), 'revisionImages', event))).data().images.length, 2);
  assert.equal((await getDocFromServer(doc(db, 'projects', id))).data().revisionDeadline.toMillis(), deadline.toMillis());
  await assertFails(getDocFromServer(doc(actor(other), 'revisionImages', event)));
  await assertFails(getDocs(collection(actor(worker), 'revisionImages')));
  await assertFails(updateDoc(doc(db, 'revisionImages', event), { images: [jpeg] }));
});

test('checklist is editable by Owner, completed only by assigned Worker, and logged atomically', async () => {
  const id = 'checklist';
  await assignForTest(id, 'working');
  const item = (db) => doc(db, 'projects', id, 'checklist', 'roles');
  const db = actor(owner);
  const person = actor(worker);
  await assertFails(setDoc(item(person), { title: 'roles', done: false, updatedAt: serverTimestamp() }));
  await assertFails(setDoc(item(db), { title: 'roles', done: true, updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(item(db), { title: 'roles', done: false, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(item(db), { title: 'Roles and permissions', updatedAt: serverTimestamp() }));
  await assertFails(updateDoc(item(person), { title: 'overwrite' }));
  await assertFails(deleteDoc(item(person)));
  await assertFails(getDocFromServer(item(actor(other))));
  await assertFails(updateDoc(item(person), { done: true, updatedAt: serverTimestamp() }));
  function complete(writer, uid, { itemId = 'roles', title = 'Roles and permissions', change = {} } = {}) {
    const write = writeBatch(writer);
    const activityId = audit(writer, write, uid, id, 'checklist_done', { itemId, title });
    write.update(item(writer), { done: true, activityId, updatedAt: serverTimestamp(), ...change });
    return write.commit();
  }
  await assertFails(complete(actor(other), other));
  await assertFails(complete(db, owner));
  await assertFails(complete(person, worker, { title: 'fake' }));
  await assertFails(complete(person, worker, { change: { title: 'overwrite' } }));
  await assertSucceeds(complete(person, worker));
  await assertFails(complete(person, worker));
  assert.equal((await getDocFromServer(item(db))).data().done, true);
  const history = await assertSucceeds(getDocs(activity(person, id)));
  assert.equal(history.docs[0].data().detail.title, 'Roles and permissions');
});

test('discussion streams only to participants and enforces identity, length and per-sender throttling', async () => {
  const id = 'discussion';
  await assignForTest(id, 'working');
  const db = actor(worker);
  const ownerDb = actor(owner);
  const messages = (store) => collection(store, 'projects', id, 'messages');
  const clock = (store, uid) => doc(store, 'projects', id, 'chatClocks', uid);
  function send(store, uid, text, { throttle = true, extra = {} } = {}) {
    const write = writeBatch(store);
    const ref = doc(messages(store));
    write.set(ref, { authorId: uid, authorName: uid, text, timestamp: serverTimestamp(), ...extra });
    if (throttle) write.set(clock(store, uid), { at: serverTimestamp(), messageId: ref.id });
    return write.commit();
  }
  await assertFails(getDocs(messages(actor(other))));
  await assertFails(send(actor(other), other, 'Hi'));
  await assertFails(send(db, worker, ' ', {}));
  await assertFails(send(db, worker, 'a'.repeat(1001)));
  await assertFails(send(db, worker, 'Hi', { extra: { authorName: owner } }));
  await assertFails(send(db, worker, 'Hi', { throttle: false }));
  await assertFails(setDoc(clock(db, worker), { at: serverTimestamp(), messageId: 'orphan' }));
  const live = observe(messages(ownerDb), (result) => result.docs.some((message) => message.data().text === 'Selesai.'));
  await assertSucceeds(send(db, worker, 'Selesai.'));
  await live;
  await assertFails(send(db, worker, 'Too fast'));
  await assertSucceeds(send(ownerDb, owner, 'Terima kasih.'));
  await admin((store) => updateDoc(clock(store, worker), { at: Timestamp.fromMillis(0) }));
  await assertSucceeds(send(db, worker, 'Siap.'));
  const rows = await assertSucceeds(getDocs(messages(db)));
  assert.equal(rows.size, 3);
  await assertFails(deleteDoc(rows.docs[0].ref));
});

test('leaderboard exposes only approved totals and blocks standalone credits or project references', async () => {
  const score = (db) => doc(db, 'workerScores', worker);
  const db = actor(worker);
  const rankings = await assertSucceeds(getDocs(collection(db, 'workerScores')));
  assert.ok(rankings.size > 0);
  const first = (await getDocFromServer(score(db))).data();
  assert.deepEqual(Object.keys(first).sort(), ['completed', 'name', 'onTime', 'points', 'updatedAt'].sort());
  await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), 'workerScores')));
  await assertFails(updateDoc(score(db), { points: 9000 }));
  await assertFails(updateDoc(score(actor(owner)), { points: 9000 }));
  await assertFails(deleteDoc(score(actor(owner))));
  const id = 'historic-waiting';
  await assignForTest(id, 'waitingReview', {
    deadline: Timestamp.fromMillis(Date.now() - 100000),
    updatedAt: Timestamp.fromMillis(Date.now() - 200000),
  });
  assert.equal(await approve(actor(owner), id), 'approved');
  const after = (await getDocFromServer(score(db))).data();
  assert.equal(after.points, first.points + 100);
  assert.equal(after.completed, first.completed + 1);
  assert.equal(after.onTime, first.onTime + 1);
  await assertFails(publish('expired-deadline', {
    extra: { deadline: Timestamp.fromMillis(1) }, extraListing: { deadline: Timestamp.fromMillis(1) },
  }));
});

test('leaderboard seed validates legacy credits and can be previewed and safely repeated', async () => {
  const id = 'zero-worker';
  await admin((db) => setDoc(doc(db, 'users', id), { name: 'Zero', role: 'worker', status: 'active', points: 0 }));
  const run = async (...args) => {
    const script = new URL('../scripts/seed-worker-scores.js', `file://${__filename}`);
    const { stdout } = await promisify(execFile)(process.execPath, [script.pathname, projectId, ...args]);
    return JSON.parse(stdout);
  };
  const zero = doc(actor(worker), 'workerScores', id);
  assert.equal((await run('--dry-run')).changes, 1);
  assert.equal((await getDocFromServer(zero)).exists(), false);
  assert.equal((await run('--apply', projectId)).changes, 1);
  assert.equal((await getDocFromServer(zero)).data().points, 0);
  assert.equal((await run('--apply', projectId)).changes, 0);
  await admin((db) => updateDoc(doc(db, 'users', id), { points: 1 }));
  await assert.rejects(run('--apply', projectId), /Saldo Worker dan ledger berbeda/);
  assert.equal((await getDocFromServer(zero)).data().points, 0);
});
