# Telegram → Kürşat

Bilgisayar açıkken bu script çalışır. Telegram'dan yazdığın mesaj, bu klasördeki Cursor ajanına gider; yanıt Telegram'a döner.

## 1. Telegram botu

1. Telegram'da [@BotFather](https://t.me/BotFather) → `/newbot`
2. Gelen token'ı kopyala
3. Kendi ID'ni öğren: [@userinfobot](https://t.me/userinfobot)

## 2. Cursor anahtarı

[Cursor Dashboard → Integrations](https://cursor.com/dashboard/integrations) üzerinden bir API key al.

## 3. Çalıştır

```powershell
cd "C:\Users\zttnl\Yazilim projeleri\Cursor\HesapMakinesi\tools\telegram-kursat"
copy env.example .env
notepad .env
npm install
npm start
```

`.env` örneği:

```
TELEGRAM_BOT_TOKEN=123456:ABC...
TELEGRAM_USER_ID=123456789
CURSOR_API_KEY=cursor_...
```

Telegram'da botunu aç, `/start` yaz, sonra normal mesaj gönder.

- `/yeni` — sohbeti sıfırlar
- `/durum` — oturum ve kuyruk
- `/id` — Telegram kullanıcı ID'n

Bilgisayar uykuya geçerse veya `npm start` kapanırsa kumanda kesilir. Sadece `TELEGRAM_USER_ID` komut verebilir.
