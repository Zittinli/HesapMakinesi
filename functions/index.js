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

async function collectTokens(uids, chatId) {
  const db = getFirestore();
  const tokens = [];
  for (const uid of uids) {
    if (chatId) {
      const pref = await db
        .collection("users")
        .doc(uid)
        .collection("chatPrefs")
        .doc(chatId)
        .get();
      if (pref.data()?.muted === true) continue;
    }
    const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
    for (const doc of snap.docs) {
      const token = doc.data().token;
      if (typeof token === "string" && token.length > 10) {
        tokens.push(token);
      }
    }
  }
  return tokens;
}

async function sendChatPush({ recipients, chatId }) {
  const tokens = await collectTokens(recipients, chatId);
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "HesapMakinesi",
      body: "Son işlem kaydedildi",
    },
    data: {
      chatId: String(chatId || ""),
      type: "message",
    },
    android: {
      priority: "high",
      notification: {
        channelId: "hm_alert",
        defaultSound: true,
        defaultVibrateTimings: true,
        tag: `chat-${chatId || "x"}`,
      },
    },
  });
}

async function sendNudgePush({ recipient, chatId, fromId, fromName }) {
  const tokens = await collectTokens([recipient]);
  if (tokens.length === 0) {
    console.warn("nudge skipped: no tokens", recipient);
    return;
  }
  const result = await getMessaging().sendEachForMulticast({
    tokens,
    data: {
      type: "nudge",
      chatId: String(chatId || ""),
      from: String(fromId || ""),
      fromName: String(fromName || "").slice(0, 80),
    },
    android: {
      priority: "high",
    },
  });
  console.log("nudge push", {
    tokens: tokens.length,
    ok: result.successCount,
    fail: result.failureCount,
  });
}

async function sendForceLockPush({ recipient, chatId, fromId }) {
  const tokens = await collectTokens([recipient]);
  if (tokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens,
    data: {
      type: "forceLock",
      chatId: String(chatId || ""),
      from: String(fromId || ""),
    },
    android: {
      priority: "high",
    },
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
    const chatData = chat.data() || {};
    const participants = chatData.participants || [];
    const recipients = participants.filter((id) => id && id !== senderId);
    if (recipients.length === 0) return;
    try {
      await sendChatPush({ recipients, chatId });
    } catch (error) {
      console.error("Push send failed", error);
    }
  },
);

exports.notifyOnNudge = onDocumentCreated(
  {
    region: "europe-west1",
    document: "users/{userId}/incomingNudges/{nudgeId}",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const toId = event.params.userId;
    const fromId = data.from;
    const chatId = data.chatId;
    if (!toId || !fromId || !chatId) return;
    const db = getFirestore();
    const allow = await db
      .collection("users")
      .doc(toId)
      .collection("nudgeAllow")
      .doc(fromId)
      .get();
    if (allow.data()?.allow !== true) return;
    let fromName = "";
    try {
      const fromSnap = await db.collection("users").doc(fromId).get();
      fromName = fromSnap.data()?.displayName || fromSnap.data()?.email || "";
    } catch (_) {}
    try {
      await sendNudgePush({
        recipient: toId,
        chatId,
        fromId,
        fromName,
      });
    } catch (error) {
      console.error("Nudge push send failed", error);
    }
  },
);

exports.notifyOnForceLock = onDocumentCreated(
  {
    region: "europe-west1",
    document: "users/{userId}/incomingForceLocks/{lockId}",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const toId = event.params.userId;
    const fromId = data.from;
    const chatId = data.chatId;
    if (!toId || !fromId || !chatId) return;
    const db = getFirestore();
    const allow = await db
      .collection("users")
      .doc(toId)
      .collection("forceLockAllow")
      .doc(fromId)
      .get();
    if (allow.data()?.allow !== true) return;
    try {
      await sendForceLockPush({ recipient: toId, chatId, fromId });
    } catch (error) {
      console.error("Force lock push failed", error);
    }
  },
);
