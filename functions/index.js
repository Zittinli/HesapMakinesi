const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const crypto = require("crypto");
const nodemailer = require("nodemailer");

initializeApp();

function hashCode(uid, code) {
  return crypto.createHash("sha256").update(`${uid}:${code}`).digest("hex");
}

async function sendOtpEmail(to, code) {
  const user = process.env.SMTP_USER || "";
  const pass = process.env.SMTP_PASS || "";
  const db = getFirestore();

  await db.collection("mail").add({
    to,
    message: {
      subject: "HesapMakinesi onay kodu",
      text: `Onay kodun: ${code}\n\nKod 10 dakika gecerlidir. Bu kodu kimseyle paylasma.`,
      html: `<p>Onay kodun: <strong style="font-size:22px;letter-spacing:4px">${code}</strong></p><p>Kod 10 dakika gecerlidir.</p>`,
    },
  });

  if (!user || !pass) {
    return false;
  }

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: { user, pass },
  });
  await transporter.sendMail({
    from: `HesapMakinesi <${user}>`,
    to,
    subject: "HesapMakinesi onay kodu",
    text: `Onay kodun: ${code}\n\nKod 10 dakika gecerlidir.`,
    html: `<p>Onay kodun: <strong style="font-size:22px;letter-spacing:4px">${code}</strong></p><p>Kod 10 dakika gecerlidir.</p>`,
  });
  return true;
}

exports.sendEmailOtp = onCall(
  { region: "europe-west1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giris gerekli.");
    }
    const uid = request.auth.uid;
    const email = request.auth.token.email;
    if (!email) {
      throw new HttpsError("failed-precondition", "E-posta yok.");
    }

    const db = getFirestore();
    const existing = await db.collection("emailOtps").doc(uid).get();
    const lastAt = existing.data()?.sentAtMs || 0;
    if (Date.now() - lastAt < 30000) {
      throw new HttpsError("resource-exhausted", "Biraz bekleyip tekrar dene.");
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    await db.collection("emailOtps").doc(uid).set({
      hash: hashCode(uid, code),
      expiresAtMs: Date.now() + 10 * 60 * 1000,
      sentAtMs: Date.now(),
      attempts: 0,
      createdAt: FieldValue.serverTimestamp(),
    });

    try {
      await sendOtpEmail(email, code);
    } catch (error) {
      console.error("OTP email failed", error);
      throw new HttpsError("internal", "Kod gonderilemedi.");
    }
    return { sent: true };
  },
);

exports.verifyEmailOtp = onCall(
  { region: "europe-west1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Giris gerekli.");
    }
    const uid = request.auth.uid;
    const code = String(request.data?.code || "").replace(/\s/g, "");
    if (!/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Kod 6 haneli olmali.");
    }

    const db = getFirestore();
    const ref = db.collection("emailOtps").doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Once kod iste.");
    }
    const data = snap.data();
    if ((data.attempts || 0) >= 5) {
      throw new HttpsError("permission-denied", "Cok fazla deneme.");
    }
    if (Date.now() > (data.expiresAtMs || 0)) {
      throw new HttpsError("deadline-exceeded", "Kodun suresi doldu.");
    }
    if (data.hash !== hashCode(uid, code)) {
      await ref.update({ attempts: (data.attempts || 0) + 1 });
      throw new HttpsError("permission-denied", "Kod yanlis.");
    }

    await getAuth().updateUser(uid, { emailVerified: true });
    await db.collection("users").doc(uid).set(
      { emailOtpVerified: true },
      { merge: true },
    );
    await ref.delete();
    return { verified: true };
  },
);
