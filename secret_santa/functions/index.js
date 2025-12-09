// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();

const sgMail = require('@sendgrid/mail');

// Load SendGrid and superadmin config from functions config
const SENDGRID_KEY = functions.config().sendgrid?.key;
const SENDGRID_FROM = functions.config().sendgrid?.from;
const SUPERADMIN_USERNAME = functions.config().superadmin?.username;
const SUPERADMIN_PASSWORD = functions.config().superadmin?.password;
const ADMIN_EMAIL = functions.config().app?.admin_email || "bhaskark301@gmail.com";

if (SENDGRID_KEY) sgMail.setApiKey(SENDGRID_KEY);

// Helper: generate a derangement (no one gets themselves)
function assignSecret(ids) {
  const receivers = ids.slice();
  let attempts = 0;
  do {
    for (let i = receivers.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [receivers[i], receivers[j]] = [receivers[j], receivers[i]];
    }
    attempts++;
    if (attempts > 2000) throw new Error("Failed to generate valid assignments");
  } while (receivers.some((r, i) => r === ids[i]));
  const map = {};
  for (let i = 0; i < ids.length; i++) map[ids[i]] = receivers[i];
  return map;
}

// Admin callable: shuffle and send emails
exports.shuffleAndSend = functions.https.onCall(async (data, context) => {
  // Require authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Sign-in required');
  }
  const callerEmail = context.auth.token.email;
  if (callerEmail !== ADMIN_EMAIL) {
    throw new functions.https.HttpsError('permission-denied', 'Only admin may shuffle');
  }

  // Read users who have done == true
  const snapshot = await db.collection('users').where('done', '==', true).get();
  if (snapshot.empty) {
    throw new functions.https.HttpsError('failed-precondition', 'No users ready for shuffle');
  }

  const users = [];
  snapshot.forEach(doc => {
    const d = doc.data();
    users.push({
      uid: doc.id,
      name: d.name || (d.email ? d.email.split('@')[0] : doc.id),
      email: d.email,
      wishlist: d.wishlist || ''
    });
  });

  if (users.length < 2) {
    throw new functions.https.HttpsError('failed-precondition', 'Need at least 2 users to shuffle');
  }

  const uids = users.map(u => u.uid);
  const assignment = assignSecret(uids); // giverUid -> receiverUid

  // Build uid->user map
  const userMap = {};
  users.forEach(u => userMap[u.uid] = u);

  // Write assignments & send emails
  const batch = db.batch();
  const emailPromises = [];
  for (const giverUid of Object.keys(assignment)) {
    const receiverUid = assignment[giverUid];
    const giver = userMap[giverUid];
    const receiver = userMap[receiverUid];

    // Write assignment doc: assignments/{giverUid}
    const assignRef = db.collection('assignments').doc(giverUid);
    batch.set(assignRef, {
      giverUid,
      giverName: giver.name,
      giverEmail: giver.email,
      receiverUid,
      receiverName: receiver.name,
      receiverWishlist: receiver.wishlist || '',
      createdAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Send email to giver (if SendGrid configured)
    if (SENDGRID_KEY && SENDGRID_FROM) {
      const msg = {
        to: giver.email,
        from: SENDGRID_FROM,
        subject: `Your Secret Santa assignment`,
        text: `Hello ${giver.name},\n\nYou are Secret Santa for: ${receiver.name}.\n\nTheir wishlist:\n${receiver.wishlist || "(no wishlist)"}\n\nHappy gifting!`,
        html: `<p>Hello ${giver.name},</p>
               <p><strong>You are Secret Santa for: ${receiver.name}</strong></p>
               <p><strong>Their wishlist:</strong><br>${(receiver.wishlist || '(no wishlist)').replace(/\n/g,'<br>')}</p>
               <p>Happy gifting!</p>`
      };
      emailPromises.push(sgMail.send(msg));
    }
  }

  // Commit DB writes then wait for email sends
  await batch.commit();
  if (emailPromises.length) await Promise.all(emailPromises);

  return { success: true, count: users.length };
});


// Super Admin Callable: returns all assignments after validating credentials
exports.getAssignmentsForSuperAdmin = functions.https.onCall(async (data, context) => {
  const { username, password } = data || {};
  if (!username || !password) {
    throw new functions.https.HttpsError('invalid-argument', 'username & password required');
  }
  if (username !== SUPERADMIN_USERNAME || password !== SUPERADMIN_PASSWORD) {
    throw new functions.https.HttpsError('permission-denied', 'Invalid super admin credentials');
  }

  // Read assignments collection and return simplified list
  const snap = await db.collection('assignments').orderBy('createdAt', 'asc').get();
  const list = [];
  snap.forEach(doc => {
    const d = doc.data();
    list.push({
      giverUid: d.giverUid,
      giverName: d.giverName,
      receiverUid: d.receiverUid,
      receiverName: d.receiverName,
      receiverWishlist: d.receiverWishlist || ''
    });
  });
  return { assignments: list };
});
