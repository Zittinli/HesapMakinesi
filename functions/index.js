const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const dns = require("dns").promises;
const disposableDomains = require("disposable-email-domains");

initializeApp();

const DISPOSABLE = new Set(disposableDomains);
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[a-zA-Z]{2,}$/;

async function inspectEmail(rawEmail) {
  const email = String(rawEmail || "").trim().toLowerCase();

  if (email.length < 5 || email.length > 320 || !EMAIL_PATTERN.test(email)) {
    return { valid: false, reason: "format" };
  }

  const domain = email.slice(email.lastIndexOf("@") + 1);
  if (DISPOSABLE.has(domain)) {
    return { valid: false, reason: "disposable" };
  }

  let records = [];
  try {
    records = await dns.resolveMx(domain);
  } catch (error) {
    if (error.code === "ENOTFOUND" || error.code === "ENODATA") {
      return { valid: false, reason: "no_mx" };
    }
    throw error;
  }

  const usable = records.filter((item) => item.exchange && item.exchange !== ".");
  if (usable.length === 0) {
    return { valid: false, reason: "no_mx" };
  }

  return { valid: true, reason: "" };
}

exports.validateEmailAddress = onCall(
  { region: "europe-west1" },
  async (request) => {
    let result;
    try {
      result = await inspectEmail(request.data?.email);
    } catch (error) {
      console.error("Email validation failed", error);
      throw new HttpsError("unavailable", "E-posta dogrulanamadi.");
    }
    return result;
  },
);

async function sendChatPush({ recipients, title, body, chatId }) {
  const db = getFirestore();
  const tokens = [];
  for (const uid of recipients) {
    const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
    for (const doc of snap.docs) {
      const token = doc.data().token;
      if (typeof token === "string" && token.length > 10) {
        tokens.push(token);
      }
    }
  }
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: {
      chatId: String(chatId || ""),
      sender: String(title || ""),
      preview: String(body || ""),
    },
    android: { priority: "high" },
  });
}

exports.notifyOnChatMessage = onDocumentCreated(
  {
    region: "europe-west1",
    document: "chats/{chatId}/messages/{messageId}",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const senderId = data.senderId;
    const chatId = event.params.chatId;
    const db = getFirestore();
    const chat = await db.collection("chats").doc(chatId).get();
    const participants = chat.data()?.participants || [];
    const recipients = participants.filter((id) => id && id !== senderId);
    if (recipients.length === 0) return;
    const sender = await db.collection("users").doc(senderId).get();
    const senderData = sender.data() || {};
    const title =
      senderData.displayName || senderData.email || "Kayit";
    const body = data.text || (data.type === "video" ? "Video" : data.type === "image" ? "Fotograf" : "Yeni mesaj");
    try {
      await sendChatPush({ recipients, title, body, chatId });
    } catch (error) {
      console.error("Push send failed", error);
    }
  },
);
