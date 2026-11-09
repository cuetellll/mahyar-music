# MAHYAR MUSIC 🎧

**بات موسیقی حرفه‌ای برای TeamSpeak 3 — فاز ۱: زیرساخت هسته، اتصال TS3 و استقرار Railway**

> Professional · Reliable · Lightweight · Modular · Production-oriented

---

## این مخزن چیست؟

فاز ۱ از پروژه‌ی **Mahyar Music**: یک بات صوتی دائمی برای TeamSpeak 3 که به یک کانال مشخص وصل می‌شود، با نام **Mahyar Music** دیده می‌شود و برای فازهای بعدی (رادیو، موسیقی درخواستی، داشبورد وب) آماده می‌شود.

- **موتور صوتی:** [TS3AudioBot 0.12.0](https://github.com/Splamy/TS3AudioBot) — آخرین نسخه‌ی پایدار رسمی، باینری self-contained لینوکس x64 با checksum پین‌شده (runtime دات‌نت داخل باینری است؛ نیازی به نصب .NET نیست)
- **میزبان:** [Railway](https://railway.com) — Worker دائمی مبتنی بر Docker از طریق GitHub
- **ذخیره‌ی پایدار:** Volume در `/data` (پیکربندی + هویت + دیتابیس)
- **امنیت:** هویت TeamSpeak فقط روی volume، دسترسی 600، بدون commit/لاگ/بیمج، بدون پورت عمومی

## ساختار پروژه

```
mahyar-music/
├── bot/
│   └── config/
│       └── ts3audiobot.example.toml   # مرجع کلیدهای پیکربندی تولیدی (0.12.0)
├── docker/
│   ├── entrypoint.sh                  # آماده‌سازی /data، اعتبارسنجی، تولید پیکربندی، اجرای غیر root
│   └── nlog.config.template           # قالب لاگ [INFO]/[WARN]/[ERROR]
├── scripts/
│   ├── validate-config.sh             # اعتبارسنجی env + هویت (بدون چاپ سکرت)
│   ├── test-connection.sh             # تشخیص شبکه (DNS/TCP) با تفسیر صادقانه
│   └── test-audio.sh                  # ساخت صدای تست اورجینال (۴۴۰Hz، ۵ ثانیه)
├── docs/                              # مستندات فارسی
│   ├── INSTALLATION.md
│   ├── RAILWAY_DEPLOYMENT.md
│   ├── TEAMSPEAK_CONFIGURATION.md
│   ├── SECURITY.md
│   └── PHASE1_TEST_PLAN.md
├── Dockerfile                         # Debian slim + ffmpeg + libopus + TS3AudioBot پین‌شده
├── .env.example                       # همه‌ی متغیرهای محیطی
├── railway.json                       # بیلد Dockerfile + restart policy
└── README.md
```

## شروع سریع (Railway)

خلاصه؛ راهنمای کامل و تصویری: [`docs/RAILWAY_DEPLOYMENT.md`](docs/RAILWAY_DEPLOYMENT.md)

1. مخزن را به GitHub push کنید (خودتان؛ هیچ سکرتی commit نشود)
2. Railway → New Project → Deploy from GitHub repo
3. Volume با mount path `/data` بسازید
4. متغیرها را از `.env.example` پر کنید (`TS3_HOST`، `TS3_CHANNEL_ID` یا `TS3_CHANNEL_PATH`، ...)
5. هویت TS3 را Export کنید و با `railway ssh` روی volume بگذارید (`MAHYAR_BOOTSTRAP=1` برای اولین بوت)
6. Deploy → لاگ‌ها را ببینید → در کانال: `!help` و `!play test-tone.wav`
7. **یک نفر باید صدای تست را بشنود** — این اثبات نهایی مسیر UDP صدا است

## متغیرهای محیطی

| متغیر | الزامی | پیش‌فرض | توضیح |
|---|---|---|---|
| `TS3_HOST` | ✅ | — | آدرس سرور TeamSpeak |
| `TS3_VOICE_PORT` | ✅ | `9987` | پورت **UDP صدا** (نه ServerQuery!) |
| `TS3_NICKNAME` | ✅ | `Mahyar Music` | نام نمایشی |
| `TS3_CHANNEL_ID` | ✅* | — | شناسه‌ی عددی کانال (پایدارترین) |
| `TS3_CHANNEL_PATH` | ✅* | — | مسیر کانال، جایگزین ID |
| `TS3_SERVER_PASSWORD` | — | خالی | رمز سرور |
| `TS3_CHANNEL_PASSWORD` | — | خالی | رمز کانال |
| `TS3_IDENTITY_FILE` | ✅ | `/data/secrets/identity.ini` | فایل هویت روی volume |
| `DATA_DIR` | ✅ | `/data` | مسیر volume |
| `LOG_LEVEL` | — | `Information` | سطح لاگ |
| `MAHYAR_BOOTSTRAP` | — | `0` | فقط اولین بوت Railway برای آپلود هویت |

\* یکی از ID یا Path الزامی است.

## وضعیت فاز ۱ (صادقانه)

- ✅ ۱۰ مورد تست در محیط توسعه تأیید شد (پیکربندی، اعتبارسنجی هویت، TOML، checksum موتور، ...)
- ⛔ ۱۳ مورد BLOCKED است تا منابع واقعی فراهم شود: بیلد Docker (Docker روی سیستم شما نصب نیست و چیزی نصب نشد)، سرور/کانال واقعی، فایل هویت واقعی، و **شنیدن صدای تست توسط انسان**
- جزئیات هر مورد و این‌که دقیقاً چه باید بدهید: [`docs/PHASE1_TEST_PLAN.md`](docs/PHASE1_TEST_PLAN.md)

## نقشه‌ی راه

| فاز | محتوا | وضعیت |
|---|---|---|
| 1 | زیرساخت، اتصال TS3، Railway | 🔨 همین مخزن |
| 2 | موتور رادیو (ایستگاه‌های زنده، دستور انتخاب، health check) | آینده |
| 3 | موتور موسیقی (جست‌وجو، صف، pause/resume، کنترل صدا) | آینده |
| 4 | داشبورد وب (برندینگ MAHYAR MUSIC، تیره، مدیریت) | آینده |
| 5 | یکپارچگی دستورات چت ↔ داشبورد | آینده |

نقاط توسعه در پیکربندی از قبل در نظر گرفته شده‌اند (وب‌API/اینترفیس غیرفعال ولی مستند؛ `[factories].media` برای منابع محلی؛ `[events]` برای خودکارسازی).

## لایسنس و اطلاعیه‌ها

- **TS3AudioBot** © مشارکت‌کنندگان پروژه — لایسنس **Open Software License v3.0 (OSL-3.0)**: <https://github.com/Splamy/TS3AudioBot/blob/master/LICENSE>. این پروژه فقط باینری رسمی انتشارشده را با checksum پین‌شده اجرا می‌کند.
- پخش هر رسانه‌ی خارجی در فازهای بعدی باید مطابق محدودیت‌های فنی و مجوزهای ارائه‌دهنده باشد؛ دورزدن محدودیت‌ها در دستور کار نیست.
- کد و مستندات این مخزن متعلق به مالک پروژه‌ی Mahyar Music است.
