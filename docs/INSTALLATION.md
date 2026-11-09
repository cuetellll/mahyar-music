# نصب و راه‌اندازی محلی — MAHYAR MUSIC (فاز ۱)

این سند نحوه‌ی اجرای بات را **به‌صورت محلی با Docker** توضیح می‌دهد. برای استقرار نهایی روی Railway به [`RAILWAY_DEPLOYMENT.md`](RAILWAY_DEPLOYMENT.md) مراجعه کنید.

> ⚠️ **نکته‌ی مهم:** در ساخت این پروژه هیچ نرم‌افزاری روی کامپیوتر شما نصب نشده است. اگر می‌خواهید ایمیج را روی سیستم خودتان بیلد و اجرا کنید، باید خودتان **Docker Desktop** را نصب کنید. تا آن زمان همه‌ی تست‌های بیلد/اجرا با وضعیت **BLOCKED** در [`PHASE1_TEST_PLAN.md`](PHASE1_TEST_PLAN.md) ثبت شده‌اند.

---

## ۱. پیش‌نیازها

| نیازمندی | توضیح |
|---|---|
| Docker (محلی، اختیاری) | فقط برای تست محلی؛ روی Railway نیازی به آن نیست |
| اکانت GitHub | برای push کردن مخزن (توسط خودتان انجام می‌شود) |
| اکانت Railway | برای استقرار |
| یک هویت TeamSpeak 3 | ترجیحاً **هویت اختصاصی بات**، نه هویت شخصی روزمره (بخش ۴) |
| آدرس سرور TS3 + شناسه‌ی کانال | از مدیر سرور یا از داخل کلاینت TS3 (بخش «پیدا کردن Channel ID» در [`TEAMSPEAK_CONFIGURATION.md`](TEAMSPEAK_CONFIGURATION.md)) |

## ۲. ساخت ایمیج (پس از نصب Docker توسط خودتان)

```bash
cd "E:/mahyar music 3"
docker build -t mahyar-music-bot .
```

- بیلد، نسخه‌ی پین‌شده‌ی `TS3AudioBot 0.12.0` (باینری self-contained لینوکس x64) را دانلود و **sha256 آن را بررسی** می‌کند.
- نیازی به نصب .NET ندارید؛ runtime داخل باینری است.

## ۳. آماده‌سازی فایل‌های پایدار محلی

```bash
mkdir -p data/secrets data/bot
cp /path/to/exported_identity.ini data/secrets/identity.ini
```

فایل `.env` را از روی `.env.example` بسازید و مقادیر واقعی را پر کنید:

```bash
cp .env.example .env
# .env را ویرایش کنید: TS3_HOST, TS3_CHANNEL_ID یا TS3_CHANNEL_PATH, ...
```

> فایل `.env` و پوشه‌ی `data/` در `.gitignore` هستند و هرگز commit نمی‌شوند.

## ۴. اجرا

```bash
docker run -d --name mahyar-music-bot \
  --env-file .env \
  -v "$(pwd)/data:/data" \
  mahyar-music-bot
```

- کانتینر ابتدا پیکربندی را از env تولید می‌کند و بعد پروسه‌ی بات را با کاربر غیر root اجرا می‌کند.
- لاگ‌ها: `docker logs -f mahyar-music-bot`

## ۵. تست صدا و اتصال (داخل کانتینر)

```bash
docker exec mahyar-music-bot bash /app/scripts/test-connection.sh   # تشخیص شبکه
docker exec mahyar-music-bot bash /app/scripts/test-audio.sh        # ساخت صدای تست
```

سپس در چت TeamSpeak به بات بفرستید:

```
!play test-tone.wav
```

یک نفر باید در کانال، صدای بوق ۵ ثانیه‌ای ۴۴۰ هرتز را **واقعاً بشنود**. این تنها اثبات واقعی مسیر صدا است.

## ۶. متغیرهای محیطی

همه‌ی متغیرها با توضیح کامل در [`../.env.example`](../.env.example) آمده‌اند. خلاصه:

| متغیر | الزامی | پیش‌فرض | توضیح |
|---|---|---|---|
| `TS3_HOST` | ✅ | — | آدرس سرور TS3 |
| `TS3_VOICE_PORT` | ✅ | `9987` | **پورت UDP صدا** (نه پورت 10011 کوئری!) |
| `TS3_NICKNAME` | ✅ | `Mahyar Music` | نام نمایشی بات |
| `TS3_CHANNEL_ID` | ✅ (یا PATH) | — | شناسه‌ی عددی کانال (قالب `"/<id>"`) |
| `TS3_CHANNEL_PATH` | ✅ (یا ID) | — | مسیر کانال مثل `Lobby/Afk` |
| `TS3_SERVER_PASSWORD` | — | خالی | رمز سرور |
| `TS3_CHANNEL_PASSWORD` | — | خالی | رمز کانال |
| `TS3_IDENTITY_FILE` | ✅ | `/data/secrets/identity.ini` | مسیر فایل هویت روی volume |
| `DATA_DIR` | ✅ | `/data` | محل ذخیره‌ی پایدار |
| `LOG_LEVEL` | — | `Information` | `Trace` تا `Fatal` |
| `MAHYAR_BOOTSTRAP` | — | `0` | فقط برای اولین بوت Railway (بخش ۶ راهنمای Railway) |

## ۷. توقف و حذف

```bash
docker stop mahyar-music-bot    # خاموشی نرم (SIGTERM → SIGINT به بات)
docker rm mahyar-music-bot
```

پیکربندی تولیدشده در `data/bot/` می‌ماند و با تغییر env فقط در صورت تغییر مقادیرِ مدیریت‌شده دوباره تولید می‌شود؛ بنابراین مقادیری که بات در زمان اجرا بازنویسی می‌کند (مثل offset هویت یا رمز هش‌شده) بین ری‌استارت‌ها حفظ می‌شوند.
