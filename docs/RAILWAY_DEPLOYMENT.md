# راهنمای استقرار روی Railway — MAHYAR MUSIC (فاز ۱)

این سند قدم‌به‌قدم توضیح می‌دهد که **شما (مالک پروژه)** چطور بات را روی Railway مستقر کنید. هر جا بین «کارِ کد» و «کارِ دستی در Railway» تفکیک وجود دارد، مشخص شده است.

> ⚠️ تا زمانی که خودتان استقرار واقعی انجام ندهید، «استقرار موفق» ادعا نمی‌شود. مراحل ۹ و ۱۰ برای تأیید نهایی الزامی‌اند.

---

## ۱) ساخت پروژه در Railway

1. وارد <https://railway.com> شوید و **New Project** بزنید.
2. گزینه‌ی **Deploy from GitHub repo** را انتخاب کنید.

## ۲) اتصال مخزن GitHub

1. پروژه هنوز فقط روی کامپیوتر شماست. مخزن را بسازید و push کنید (این کار به عهده‌ی شماست؛ هیچ‌وقت فایل هویت یا `.env` را push نکنید — `.gitignore` جلوی آن را می‌گیرد):

   ```bash
   cd "E:/mahyar music 3"
   git remote add origin https://github.com/<username>/mahyar-music.git
   git push -u origin main
   ```

2. در Railway همان مخزن را انتخاب کنید. Railway خودش `Dockerfile` ریشه را می‌بیند.

## ۳) روش بیلد (Dockerfile)

در تنظیمات سرویس → **Settings → Build** مطمئن شوید:

- Builder = **Dockerfile**
- Config file path = `Dockerfile` (پیش‌فرض؛ در `railway.json` هم ثبت است)

هیچ پورت عمومی (TCP Proxy / Domain) اضافه **نکنید**. بات یک Worker است و اتصال صوتی از داخل کانتینر به سمت سرور TS3 برقرار می‌شود (outbound).

## ۴) ساخت Volume پایدار در `/data`

پروژه → سرویس `mahyar-music-bot` → تب **Storage** → **New Volume**:

- **Mount path:** `/data`
- حجم پیشنهادی: 1 GB (فقط پیکربندی، دیتابیس کوچک و صدای تست)

> Volume در زمان build وجود ندارد و فقط در زمان اجرا mount می‌شود؛ به همین دلیل ایمیج به آن وابسته نیست و entrypoint در هر اجرا ساختار `/data` را می‌سازد.

## ۵) متغیرهای محیطی

سرویس → **Variables** و مطابق `.env.example` (بدون مقادیر ساختگی واقعی):

| متغیر | مقدار شما |
|---|---|
| `TS3_HOST` | آدرس سرور TeamSpeak شما |
| `TS3_VOICE_PORT` | `9987` (یا پورت صوتی سرور شما) |
| `TS3_NICKNAME` | `Mahyar Music` |
| `TS3_CHANNEL_ID` | شناسه‌ی عددی کانال (پیشنهادی) |
| `TS3_CHANNEL_PATH` | فقط اگر ID را ندارید |
| `TS3_SERVER_PASSWORD` / `TS3_CHANNEL_PASSWORD` | فقط در صورت وجود رمز |
| `TS3_IDENTITY_FILE` | `/data/secrets/identity.ini` |
| `DATA_DIR` | `/data` |
| `LOG_LEVEL` | `Information` |
| `MAHYAR_BOOTSTRAP` | `1` فقط برای اولین بوت (بخش ۶) |

## ۶) آپلود امن فایل هویت (مهم‌ترین مرحله)

**هرگز** کلید هویت را در چت، در کد، در issue یا در متغیر عمومی paste نکنید. روش صحیح:

### الف) خروجی گرفتن هویت از کلاینت TeamSpeak (روی سیستم خودتان)

1. کلاینت TeamSpeak → **Tools → Identities**
2. هویت مورد نظر را انتخاب کنید (ترجیحاً یک **هویت اختصاصی بات** — به [`SECURITY.md`](SECURITY.md) توجه کنید)
3. **Export** → ذخیره‌ی فایل ini در محل امن (مثلاً `Documents/secure/`)

### ب) اولین Deploy با حالت Bootstrap

1. `MAHYAR_BOOTSTRAP=1` را در Variables بگذارید و Deploy بزنید.
2. چون فایل هویت هنوز وجود ندارد، کانتینر به‌جای exit، در حالت انتظار می‌ماند و راهنما را در لاگ چاپ می‌کند.
3. از خط فرمان (روی سیستم خودتان، با CLI نصب‌شده‌ی Railway و لاگین‌شده):

   ```bash
   railway ssh --service mahyar-music-bot
   ```

4. داخل شل، فایل را روی volume بنویسید (محتوای فایل ini خروجی‌گرفته‌شده):

   ```bash
   mkdir -p /data/secrets
   vi /data/secrets/identity.ini     # یا: cat > /data/secrets/identity.ini
   # محتوا را paste کنید و ذخیره کنید (Ctrl+D برای cat)
   chmod 600 /data/secrets/identity.ini
   exit
   ```

5. `MAHYAR_BOOTSTRAP=0` کنید (یا متغیر را حذف کنید) و **Redeploy** بزنید.
6. entrypoint هویت را اعتبارسنجی می‌کند (بدون چاپ محتوا)، پیکربندی را تولید و بات را اجرا می‌کند.

> اگر از Bootstrap استفاده نمی‌کنید و هویت در اولین بوت موجود نباشد، کانتینر با پیام خطای واضح و exit code غیر صفر متوقف می‌شود (رفتار عمدی و fail-safe است).

## ۷) رفتار Worker و Restart Policy

- بات یک پروسه‌ی دائمی است (نه Cron و نه Job کوتاه).
- `railway.json` سیاست **ON_FAILURE با حداکثر ۱۰ تلاش** را ثبت کرده است؛ می‌توانید در Railway → Settings → Deploy همان مقادیر را تأیید/ویرایش کنید.
- داخل کانتینر هم یک supervisor محدود وجود دارد (حداکثر ۵ ری‌استارت سریع با فاصله‌ی فزاینده ۱۰ تا ۵۰ ثانیه؛ اگر بات مداوم crash کند، کانتینر با exit 1 بیرون می‌آید تا پلتفرم مسئولیت ری‌استارت را بگیرد). این طراحی از «حلقه‌ی بی‌نهایت ری‌استارت سریع» جلوگیری می‌کند.
- ری‌کانکتِ قطعی‌های موقت شبکه، داخل خود TS3AudioBot انجام می‌شود (`reconnect.ontimeout`: ۱ ثانیه تا ۵ دقیقه با تکرار آخرین فاصله).

## ۸) خواندن لاگ‌های بیلد و دیپلوی

- پروژه → سرویس → تب **Deployments** → روی دیپلوی کلیک کنید → **Build Logs** و **Deploy Logs**.
- لاگ‌های اجرای بات با پیشوند `[INFO] / [WARN] / [ERROR]` چاپ می‌شوند و **هرگز شامل رمز یا کلید هویت نیستند**.
- لاگ سالم باید به‌ترتیب این‌ها را نشان دهد:

```
[INFO]  [Mahyar Music] Mahyar Music starting...
[INFO]  [Mahyar Music] Configuration validated (secrets are not printed).
[INFO]  [Mahyar Music] Configuration generated.
[INFO]  [Mahyar Music] Test tone generated: music/test-tone.wav (5 s, 440 Hz sine).
[INFO]  [Mahyar Music] Handing over to the bot process (user 'ts3ab').
[INFO]  [Mahyar Music] Starting TS3AudioBot 0.12.0...
```

## ۹) تأیید اتصال واقعی (بعد از Deploy)

1. در لاگ‌ها دنبال این باشید: بات به سرور وصل شود و پیام پیوستن به کانال ظاهر شود.
2. در کلاینت TeamSpeak، بات با نام **Mahyar Music** باید **داخل کانال تعیین‌شده** دیده شود.
3. آپلود/اجرای صدای تست:

   ```bash
   railway ssh --service mahyar-music-bot
   bash /app/scripts/test-audio.sh
   exit
   ```

   سپس در چت TeamSpeak: `!play test-tone.wav`
4. یک نفر در کانال باید صدای بوق را **بشنود**. شنیدن صدا = اثبات نهایی مسیر UDP صدا.

## ۱۰) عیب‌یابی مشکلات اتصال

| نشانه در لاگ | علت احتمالی | اقدام |
|---|---|---|
| `Identity file not found` | فایل هویت آپلود نشده | بخش ۶ همین سند |
| خطای فرمت هویت | فایل ini ناقص یا خراب Export شده | دوباره Export کنید؛ خط `identity=` باید `عددVرشته‌base64` باشد |
| DNS resolution failure | نام سرور اشتباه | `TS3_HOST` را بررسی کنید؛ `bash /app/scripts/test-connection.sh` |
| بات start می‌شود ولی به سرور وصل نمی‌شود و خطای timeout می‌دهد | مسدود بودن UDP خروجی در زیرساخت | ادامه‌ی همین بخش |
| `Process terminated. Couldn't find a valid ICU package...` | runtime قدیمی .NET Core 3.1 نسخه‌های ICU جدید را نمی‌شناسد | از نسخه‌ی فعلی مخزن استفاده کنید: entrypoint حالت `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` را ست می‌کند و ایمیج دیگر libicu ندارد (کامیت مربوطه را push و Redeploy کنید) |
| `No usable version of libssl was found` هنگام استارت | runtime قدیمی .NET Core 3.1 فقط OpenSSL 1.1 را می‌شناسد و Debian 12 فقط OpenSSL 3 دارد | از نسخه‌ی فعلی مخزن استفاده کنید: Dockerfile بسته‌ی `libssl1.1 1.1.1w-0+deb11u1` را از آرشیو رسمی Debian با checksum پین‌شده نصب می‌کند (کامیت مربوطه را push و Redeploy کنید) |
| بات وصل است ولی صدای کسی شنیده نمی‌شود | صدا در حالت whisper یا رمز/دسترسی کانال | `!volume 50`؛ در فاز ۱ `send_mode = "voice"` از قبل تنظیم است |

### اگر Railway مانع UDP صوتی شد (سناریوی جایگزین VPS)

پیاده‌سازی فعلی تمام تلاش اتصال را **خروجی (outbound)** از کانتینر انجام می‌دهد و به TCP Proxy نیازی ندارد؛ به‌طور معمول Railway مانع UDP خروجی نیست، اما تا وقتی «شنیدن صدای تست» تأیید نشود، موفقیت ادعا نمی‌شود.

اگر تست واقعی نشان داد UDP صوتی روی Railway کار نمی‌کند:

- فقط همین سرویس بات را روی یک **VPS لینوکسی کوچک** اجرا کنید (دستور docker run بخش ۴ سند [`INSTALLATION.md`](INSTALLATION.md) عیناً قابل استفاده است) و فازهای بعدی (داشبورد وب) همچنان روی Railway بمانند.
- برای این سناریو تغییری در کد لازم نیست؛ همان ایمیج روی هر Docker 호ستی اجرا می‌شود.

## نکات تکمیلی

- پیکربندی TS3AudioBot در `/data/bot/` تولید می‌شود؛ فایل `bots/mahyar-music/bot.toml` شامل کلید خصوصی هویت است و دسترسی آن `600` نگه داشته می‌شود. این فایل را هیچ‌وقت خارج از volume کپی نکنید.
- وب‌اینتردیس و Web API در فاز ۱ **غیرفعال** هستند (`[web.api] enabled = false`)؛ فاز ۴ آن‌ها را عمدی و با احراز هویت فعال می‌کند.
- برای دیدن کلیدهای پیکربندی و معنی هرکدام: [`../bot/config/ts3audiobot.example.toml`](../bot/config/ts3audiobot.example.toml) و [`TEAMSPEAK_CONFIGURATION.md`](TEAMSPEAK_CONFIGURATION.md).
