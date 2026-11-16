const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');

function summarize(profiles, projects, rewards) {
  const scores = new Map(profiles.docs.map((profile) => {
    const { name, points } = profile.data();
    if (typeof name !== 'string' || !name.trim() ||
        !Number.isSafeInteger(points) || points < 0) {
      throw new Error('Ada profil Worker dengan nama atau saldo yang tidak valid.');
    }
    return [profile.id, { name, points: 0, completed: 0, onTime: 0, balance: points }];
  }));
  const completed = new Map(projects.docs.map((project) => [project.id, project.data()]));

  for (const receipt of rewards.docs) {
    const { workerId, points, projectId, reason } = receipt.data();
    const project = completed.get(receipt.id);
    const worker = scores.get(workerId);
    if (!worker || !project || receipt.id !== projectId ||
        reason !== 'project_approved' || project.assignedWorkerId !== workerId ||
        !Number.isSafeInteger(points) || points <= 0 || project.points !== points) {
      throw new Error('Ada reward yang tidak cocok dengan project selesai atau profil Worker.');
    }

    const deadline = project.revisionDeadline ?? project.deadline;
    const finished = project.submittedAt ?? project.updatedAt;
    if (!(deadline instanceof Timestamp) || !(finished instanceof Timestamp)) {
      throw new Error('Ada project berhadiah yang belum memiliki timestamp untuk statistik.');
    }
    worker.points += points;
    worker.completed += 1;
    if (finished.valueOf() <= deadline.valueOf()) worker.onTime += 1;
    completed.delete(receipt.id);
  }

  if (completed.size > 0) throw new Error('Ada project selesai tanpa transaksi poin.');
  for (const score of scores.values()) {
    if (score.points !== score.balance) throw new Error('Saldo Worker dan ledger berbeda.');
    delete score.balance;
  }
  return scores;
}

async function main() {
  const [projectId, mode, confirmation, ...extra] = process.argv.slice(2);
  const local = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:28080';
  if (extra.length || !projectId ||
      (!local || !projectId.startsWith('demo-')) ||
      !(mode === '--dry-run' && !confirmation || mode === '--apply' && confirmation === projectId)) {
    throw new Error('Pemakaian: node database/tools/scripts/seed-worker-scores.js PROJECT_ID --dry-run | PROJECT_ID --apply PROJECT_ID');
  }
  initializeApp({ projectId });
  const db = getFirestore();
  const result = await db.runTransaction(async (transaction) => {
    const [profiles, projects, rewards, rankings] = await Promise.all([
      transaction.get(db.collection('users').where('role', '==', 'worker')),
      transaction.get(db.collection('projects').where('status', '==', 'completed')),
      transaction.get(db.collection('pointTransactions')),
      transaction.get(db.collection('workerScores')),
    ]);
    const scores = summarize(profiles, projects, rewards);
    const existing = new Map(rankings.docs.map((entry) => [entry.id, entry.data()]));
    if ([...existing.keys()].some((uid) => !scores.has(uid))) {
      throw new Error('Leaderboard memuat akun tanpa profil Worker.');
    }
    let changes = 0;
    for (const [uid, score] of scores) {
      const current = existing.get(uid);
      if (current && Object.entries(score).every(([key, value]) => current[key] === value)) continue;
      changes += 1;
      if (mode === '--apply') {
        transaction.set(db.collection('workerScores').doc(uid), {
          ...score,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
    return { workers: scores.size, completed: projects.size, changes };
  });
  console.log(JSON.stringify({ project: projectId, mode, ...result }));
}

if (require.main === module) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}

module.exports = { summarize };
