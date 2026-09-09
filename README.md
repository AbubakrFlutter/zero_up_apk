# ⚡ zero_up_apk

Flutter ilovalarining **APK** va **App Bundle (AAB)** fayllarini oddiy
`flutter build apk` ga qaraganda ancha tez yig'adigan, **to'liq o'zbekcha**
buyruq qatori vositasi.

- 📊 Jarayon **foizlarda** ko'rinadi — qaysi bosqichda ekani o'zbekcha yoziladi
- 🚀 Kompyuter quvvatiga (RAM / yadro soni) qarab Gradle **avtomat sozlanadi**
- 📁 Tayyor APK **ish stoliga (Desktop)** — ilova nomi va versiyasi bilan atalgan yangi papkaga tushadi (`zup config` bilan boshqa papkani tanlash mumkin)
- 🧠 Xatolar **o'zbekcha tushuntiriladi** va yechimi ko'rsatiladi
- 🤖 **AI rejimi** — Claude Code kabi agentlar uchun JSON chiqish
- 🩺 **zup doctor** — muhitdagi muammolarni topib, yechimini aytadi

```
  ▕████████████████░░░░░░░░░░▏  63%  Kotlin kodi kompilyatsiya qilinmoqda  01:12
```

---

## O'rnatish

### ⚡ npm orqali (eng oddiy)

```bash
npm install -g zero_up_apk
```

Tayyor! Endi istalgan Flutter loyihangizda:

```bash
cd C:\mening_loyiham
zup apk --arm64
```

Birinchi ishga tushirishda zup o'zini kompyuteringizda tayyorlaydi
(~15 soniya, bir marta). Undan keyin darhol ishlaydi.

**Talab:** Flutter o'rnatilgan bo'lishi. Boshqa hech narsa kerak emas —
Dart Flutter bilan birga keladi.

---

## Ishlatish

```bash
zup                  # Menyu — ↑↓ bilan tanlang (eng oson yo'l)

zup apk              # Release APK (ABI bo'yicha bo'lingan)
zup apk --arm64      # Eng tez: faqat arm64
zup apk -i           # Yig'ib telefonga o'rnatish
zup aab              # Google Play uchun App Bundle
zup hammasi          # APK + AAB
```

### Boshqa buyruqlar

| Buyruq | Vazifasi |
|--------|----------|
| `zup doctor` | Flutter, SDK, Java, adb — hammasini tekshiradi |
| `zup info` | Loyiha, sozlamalar, kompyuter holati |
| `zup last` | Oxirgi yig'ishlar tarixi |
| `zup devices` | Ulangan qurilmalar |
| `zup config` | Fayllar qayerga tushsin |
| `zup update` | Yangilash |

### Foydali parametrlar

| Parametr | Ta'rif |
|----------|--------|
| `--arm64` | Faqat arm64 — 2-3x tezroq |
| `-i`, `--install` | Yig'ilgach qurilmaga o'rnatadi (mos APK ni o'zi tanlaydi) |
| `-t lib/main_dev.dart` | Boshqa kirish fayli (dev/prod uchun) |
| `--clean` | Avval `flutter clean` |
| `--obfuscate` | Dart kodini yashirish |
| `-o`, `--out C:\papka` | Boshqa papkaga chiqarish (faqat shu safar) |
| `--save` | Berilgan sozlamalarni doimiy qilib saqlash |
| `--open` | Tugagach papkani ochish |
| `-q`, `--quiet` | Faqat ogohlantirish va xatolar |
| `--json` | Natijani JSON qaytarish |
| `-v` | Versiyani ko'rsatish |
| `-V` | Batafsil log |

---

## 🤖 AI rejimi

Claude Code kabi kodlash agentlari zup'ni ishonchli boshqarishi uchun:

```bash
zup ai apk           # Yig'ib, natijani JSON qaytaradi
zup ai info          # Loyiha va muhit holati
zup ai doctor        # Muhit tekshiruvi
```

`stdout` da **faqat bitta JSON obyekt** bo'ladi — odamlarga mo'ljallangan
matn `stderr` ga ketadi, shuning uchun `JSON.parse` saralashsiz ishlaydi.
Savol berilmaydi, xatolar barqaror kod bilan qaytadi.

Agent harness'i uchun: `ZUP_OUTPUT=json` o'rnatilsa, har bir chaqiruv JSON
qaytaradi — `--json` yozish shart emas.

To'liq shartnoma: **[docs/AI.md](docs/AI.md)**

---

## 📁 Fayllar qayerga tushadi?

Standart holatda tayyor APK **ish stoliga (Desktop)** tushadi. Buni bir marta
sozlab qo'ysangiz, keyin har safar `--out` yozib o'tirish shart emas:

```bash
zup config                    # sozlamalar menyusi (eng oson yo'l)
zup config --out D:\APK       # papkani darhol o'rnatish
zup config reset              # ish stoliga qaytarish

zup apk --out D:\APK          # faqat shu safar boshqa papkaga
zup apk --out D:\APK --save   # shu papkani doimiy qilib saqlash
```

`zup config` menyusi orqali quyidagilarni sozlash mumkin:

- Fayllar tushadigan papka
- Yig'ish tugagach papkani avtomatik ochish
- Doim faqat arm64 yig'ish (eng tez rejim)

Sozlamalar `~/.zup/config.json` faylida saqlanadi.

---

## Yangilanish

```bash
zup update
```

Boshqa hech narsa yozish kerak emas — zup npm dan yangi versiya bor-yo'qligini
tekshiradi, bo'lsa o'rnatadi va o'zini qayta tayyorlaydi.

Tool har safar ishga tushganda ham tekshirib turadi:

```
╭────────────────────────────────────────────────────────╮
│  💡 Yangi versiya mavjud!                              │
│     Hozirgi: 2.0.0 → Yangi: 2.1.0                      │
│                                                        │
│     Yangilash: zup update                              │
╰────────────────────────────────────────────────────────╯
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

- Flutter SDK (PATH da) — Dart u bilan birga keladi
- Android SDK + JDK
- Node.js 18+ (npm uchun)

Alohida Dart SDK o'rnatish shart emas.

---

## Qanday ishlaydi?

npm paketida tayyor `.exe` yo'q — zup sizning kompyuteringizda, sizning
Dart SDK ingiz bilan yasaladi.

Sabab: Windows 11 dagi **Smart App Control** internetdan kelgan imzolanmagan
`.exe` fayllarni ishga tushirishga ruxsat bermaydi. Mahalliy yasalgan fayl
esa bu muammoga duch kelmaydi.

Agar Windows baribir bloklasa, zup buni o'zi sezadi va manba koddan ishga
tushadi — hech narsa qilishingiz shart emas, faqat boshlanishi bir necha
soniya sekinroq bo'ladi.

---

## Litsenziya

MIT License - [LICENSE](LICENSE)
