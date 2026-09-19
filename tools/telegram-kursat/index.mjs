import { createServer } from "node:net";
import os from "node:os";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadEnv } from "dotenv";
import { Bot } from "grammy";
import { Agent, CursorAgentError } from "@cursor/sdk";

const here = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: resolve(here, ".env") });

const LOCK_PORT = Number(process.env.KURSAT_LOCK_PORT || 47231);
const IDLE_MS = Number(process.env.KURSAT_IDLE_MS || 10 * 60 * 1000);
const TELEGRAM_BOT_TOKEN = required("TELEGRAM_BOT_TOKEN");
const TELEGRAM_USER_ID = Number((process.env.TELEGRAM_USER_ID || "").trim());
const CURSOR_API_KEY = required("CURSOR_API_KEY");
const WORKSPACE = resolve(
  process.env.CURSOR_WORKSPACE || resolve(here, "../.."),
);
const MODEL = process.env.CURSOR_MODEL || "composer-2.5";
const TELEGRAM_LIMIT = 3900;

const IDENTITY = [
  "Senin adın Kürşat. Kullanıcı sana Telegram üzerinden yazıyor.",
  "Türkçe yanıt ver. Kısa ve net ol.",
  "Bu oturum HesapMakinesi projesinde, kullanıcının kendi bilgisayarında çalışıyor.",
  "Gizli anahtarları, tokenları ve .env içeriğini asla mesaja yazma.",
  "İstenmedikçe commit veya push yapma.",
].join(" ");

const ownerReady = Number.isFinite(TELEGRAM_USER_ID) && TELEGRAM_USER_ID > 0;

try {
  os.setPriority(os.constants.priority.PRIORITY_BELOW_NORMAL);
} catch {
  // öncelik ayarlanamazsa sessizce devam
}

await claimSingleInstance();

const bot = new Bot(TELEGRAM_BOT_TOKEN);
/** @type {Awaited<ReturnType<typeof Agent.create>> | null} */
let agent = null;
let agentPrimed = false;
let busy = false;
let idleTimer = null;
/** @type {Array<{ chatId: number, text: string }>} */
const queue = [];

function required(name) {
  const value = (process.env[name] || "").trim();
  if (!value) {
    throw new Error(`${name} .env içinde boş. env.example dosyasına bak.`);
  }
  return value;
}

function claimSingleInstance() {
  return new Promise((resolve) => {
    const server = createServer();
    server.on("error", () => {
      console.log("Kürşat köprüsü zaten açık, ikinci kopya kapanıyor.");
      process.exit(0);
    });
    server.listen(LOCK_PORT, "127.0.0.1", () => resolve(server));
  });
}

function isOwner(ctx) {
  return ownerReady && ctx.from?.id === TELEGRAM_USER_ID;
}

async function rejectStranger(ctx) {
  const id = ctx.from?.id;
  await ctx.reply(
    id
      ? `Bu kumanda kilitli. Senin Telegram ID'n: ${id}`
      : "Bu kumanda kilitli.",
  );
}

function scheduleIdleClose() {
  if (idleTimer) clearTimeout(idleTimer);
  if (!agent) return;
  idleTimer = setTimeout(() => {
    void closeAgent();
  }, IDLE_MS);
}

async function ensureAgent() {
  if (agent) return agent;
  agent = await Agent.create({
    apiKey: CURSOR_API_KEY,
    model: { id: MODEL },
    local: { cwd: WORKSPACE },
  });
  agentPrimed = false;
  return agent;
}

async function closeAgent() {
  if (idleTimer) {
    clearTimeout(idleTimer);
    idleTimer = null;
  }
  if (!agent) return;
  const current = agent;
  agent = null;
  agentPrimed = false;
  try {
    await current[Symbol.asyncDispose]();
  } catch {
    // kapanış hatası köprüyü durdurmasın
  }
}

function splitTelegram(text) {
  const clean = (text || "").trim() || "(boş yanıt)";
  if (clean.length <= TELEGRAM_LIMIT) return [clean];
  const parts = [];
  let rest = clean;
  while (rest.length > TELEGRAM_LIMIT) {
    let cut = rest.lastIndexOf("\n", TELEGRAM_LIMIT);
    if (cut < 800) cut = TELEGRAM_LIMIT;
    parts.push(rest.slice(0, cut));
    rest = rest.slice(cut).trimStart();
  }
  if (rest) parts.push(rest);
  return parts;
}

async function handlePrompt(text) {
  const session = await ensureAgent();
  const prompt = agentPrimed ? text : `${IDENTITY}\n\n${text}`;
  agentPrimed = true;
  const run = await session.send(prompt);
  const result = await run.wait();
  scheduleIdleClose();
  if (result.status === "error") {
    return `İş yarıda kaldı (run ${result.id}). Tekrar dene veya /yeni yaz.`;
  }
  const answer = (result.result || "").trim();
  return answer || "Tamam, işi bitirdim.";
}

async function drainQueue() {
  if (busy) return;
  busy = true;
  while (queue.length > 0) {
    const job = queue.shift();
    try {
      await bot.api.sendChatAction(job.chatId, "typing");
      const answer = await handlePrompt(job.text);
      for (const part of splitTelegram(answer)) {
        await bot.api.sendMessage(job.chatId, part);
      }
    } catch (err) {
      const startup = err instanceof CursorAgentError;
      const detail = err instanceof Error ? err.message : String(err);
      await bot.api.sendMessage(
        job.chatId,
        startup ? `Kürşat açılamadı: ${detail}` : `Hata: ${detail}`,
      );
      if (startup) await closeAgent();
    }
  }
  busy = false;
  scheduleIdleClose();
}

bot.command("id", async (ctx) => {
  await ctx.reply(`Telegram ID'n: ${ctx.from?.id ?? "?"}`);
});

bot.command("start", async (ctx) => {
  if (!isOwner(ctx)) return rejectStranger(ctx);
  await ctx.reply(
    "Kürşat hazır. Telegram'dan yaz, bu bilgisayardaki ajan işi yapsın.\n\n/yeni — sohbeti sıfırla\n/durum — köprü bilgisi\n/id — Telegram ID",
  );
});

bot.command("durum", async (ctx) => {
  if (!isOwner(ctx)) return rejectStranger(ctx);
  await ctx.reply(
    [
      agent ? "Oturum: açık" : "Oturum: ilk mesajda açılacak",
      busy || queue.length
        ? `Sıra: ${queue.length + (busy ? 1 : 0)}`
        : "Sıra: boş",
      `Klasör: ${WORKSPACE}`,
      `Model: ${MODEL}`,
    ].join("\n"),
  );
});

bot.command("yeni", async (ctx) => {
  if (!isOwner(ctx)) return rejectStranger(ctx);
  await closeAgent();
  await ctx.reply("Yeni oturum. Bir sonraki mesaj temiz başlar.");
});

bot.on("message:text", async (ctx) => {
  if (!isOwner(ctx)) return rejectStranger(ctx);
  if (ctx.message.text.startsWith("/")) return;
  queue.push({ chatId: ctx.chat.id, text: ctx.message.text });
  if (busy || queue.length > 1) {
    await ctx.reply(`Sıraya alındı (${queue.length}).`);
  }
  void drainQueue();
});

process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);

async function shutdown() {
  await closeAgent();
  bot.stop();
  process.exit(0);
}

await bot.start({
  drop_pending_updates: true,
  allowed_updates: ["message"],
  onStart: (info) => {
    console.log(`Kürşat Telegram köprüsü açık: @${info.username}`);
    console.log(`Çalışma klasörü: ${WORKSPACE}`);
    console.log(
      ownerReady
        ? `İzinli kullanıcı: ${TELEGRAM_USER_ID}`
        : "TELEGRAM_USER_ID boş. Telegram'da /id yaz, numarayı .env'e koy, scripti yeniden başlat.",
    );
  },
});
