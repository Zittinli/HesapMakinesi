const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
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
