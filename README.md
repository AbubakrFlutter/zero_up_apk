# ⚡ zero_up_apk

Flutter ilovalarining **APK** va **App Bundle (AAB)** fayllarini oddiy
`flutter build apk` ga qaraganda ancha tez yig'adigan, **to'liq o'zbekcha**
buyruq qatori vositasi.

- 📊 Jarayon **foizlarda** ko'rinadi — qaysi bosqichda ekani o'zbekcha yoziladi
- 🚀 Kompyuter quvvatiga (RAM / yadro soni) qarab Gradle **avtomat sozlanadi**
- 📁 Tayyor APK **ish stoliga (Desktop)** — ilova nomi va versiyasi bilan atalgan yangi papkaga tushadi
- 🧠 Xatolar **o'zbekcha tushuntiriladi** va yechimi ko'rsatiladi
- 🔄 **GitHub orqali avtomatik yangilanish** - npm uslubida

```
  ▕████████████████░░░░░░░░░░▏  63%  Kotlin kodi kompilyatsiya qilinmoqda  01:12
```

---

## O'rnatish

### ⚡ npm orqali (eng oddiy)

```bash
npm install -g github:zero_up_team/zero_up_apk
```

Tayyor! Endi istalgan Flutter loyihangizda:

```bash
cd C:\mening_loyiham
zup apk --arm64
```

---

### 📦 Yoki .exe yuklab olish

1. **[Releases](../../releases) dan `zup.exe` ni yuklab oling**
2. **Ikki marta bosib oching** 🖱️ yoki `zup.exe --install`
3. **Yangi terminal oching**
4. **Flutter loyihangizga kiring va ishlatish:**
   ```powershell
   zup apk --arm64
   ```

---

## Ishlatish

```bash
zup apk              # Release APK (ABI bo'yicha bo'lingan)
zup apk --arm64      # Eng tez: faqat arm64
zup aab              # Google Play uchun App Bundle
zup hammasi          # APK + AAB
zup update           # Yangilash
zup --help           # Yordam
```

### Foydali parametrlar

| Parametr | Ta'rif |
|----------|--------|
| `--arm64` | Faqat arm64 — 2-3x tezroq |
| `--clean` | Avval `flutter clean` |
| `--obfuscate` | Dart kodini yashirish |
| `--out C:\papka` | Boshqa papkaga chiqarish |
| `--open` | Tugagach papkani ochish |
| `-v` | Batafsil log |

---

## Yangilanish

```bash
# Avtomatik yangilanish (tavsiya)
zup update

# Yoki npm orqali
npm update -g github:zero_up_team/zero_up_apk
```

Tool har 24 soatda yangilanish borligini tekshiradi:

```
╭────────────────────────────────────────╮
│  💡 Yangi versiya mavjud!             │
│     Hozirgi: 1.2.0 → Yangi: 1.3.0    │
│                                       │
│     Yangilash: zup update            │
╰────────────────────────────────────────╯
```

---

## Nima uchun tezroq?

| Usul | Foyda |
|------|-------|
| **Inkremental build** | `flutter clean` qilinmaydi |
| **Gradle optimization** | daemon + parallel + cache |
| **Kotlin incremental** | Minimal qayta kompilyatsiya |
| **RAM tuning** | GC va swap muammolarini oldini oladi |
| **`--arm64`** | AOT 1 marta (3 ta emas) |

---

## Talablar

- Flutter SDK (PATH da)
- Android SDK + JDK
- Node.js 14+ (npm uchun)

---

## Litsenziya

MIT License - [LICENSE](LICENSE)
