## 1.4.0 - 2026-09-08

### 🛠 Endi tayyor .exe yuklab olinmaydi — u sizning kompyuteringizda yasaladi

Windows 11 dagi **Smart App Control** internetdan kelgan imzolanmagan `.exe`
fayllarni ishga tushirishga ruxsat bermaydi. Natijada `zup` deyilganda
tushunarsiz xato chiqardi:

```
Error: spawn UNKNOWN    errno: -4094
```

Endi npm paketida `.exe` umuman yo'q — zup o'rnatish paytida foydalanuvchining
o'z Dart SDK si bilan kompilyatsiya qilinadi. Bu ishlaydi, chunki zup faqat
Flutter loyihalari uchun kerak, Flutter esa Dart ni o'zi bilan olib keladi.

**Ikki bosqichli himoya.** Agar Windows kompilyatsiya qilingan faylni ham
bloklasa, zup buni sezadi va avtomatik ravishda manba koddan ishga tushadi
(Dart VM bloklanmaydi). Foydalanuvchi hech narsa qilishi shart emas —
faqat boshlanishi ~3 soniya sekinroq bo'ladi.

Qo'shimcha yutuqlar:

* npm paketi **3.4 MB → 45 KB** (76 barobar kichik)
* macOS va Linux ham ishlaydi — avval ular uchun tayyor fayl umuman yo'q edi
* Sertifikat sotib olish shart emas

### 🔄 `zup update` endi npm orqali

Avval yangilanish GitHub Releases dan olinardi. Endi manba — **npm registry**,
ya'ni odamlar zup ni qayerdan o'rnatsa, o'sha yer. `npm publish` qilingan
zahoti versiya o'zi yangilanadi.

Foydalanuvchi faqat `zup update` yozadi — qolganini zup o'zi qiladi:
npm dan versiyani tekshiradi, yangisi bo'lsa o'rnatadi va yangi binary yasaydi.

Yangilashni Node qismi bajaradi, Dart binary si emas — chunki Windows ishlab
turgan `.exe` ni almashtirishga ruxsat bermaydi.

### 🐞 Tuzatishlar

* **npm postinstall bloklansa ham ishlaydi.** npm 11 xavfsizlik sababli
  o'rnatish skriptlarini bloklashi mumkin. Bunday holatda zup birinchi ishga
  tushganda o'zini o'zi tayyorlaydi.
* **`dart run` yo'lida joriy papka noto'g'ri edi** — zup foydalanuvchi
  loyihasi o'rniga npm paketini "loyiha" deb qabul qilardi.
* **`spawn` xatosi ushlanmasdi** — Windows bloklaganda `spawn()` `error`
  hodisasini kutmasdan darhol istisno tashlaydi, shuning uchun `try/catch`
  ham qo'shildi.

### 🧹 Soddalashtirish

O'rnatish va yangilash mantiqi Node tomoniga o'tgani uchun Dart kodidan ~400
qator olib tashlandi: PATH ni registry orqali sozlash, o'zini nusxalash,
GitHub Releases dan yuklab olish. Bu bilan birga o'sha kodga tegishli
xatolar sinfi ham yo'qoldi.

## 1.3.3 - 2026-09-04

### ✨ Yangi imkoniyatlar

* **`zup config` — fayllar qayerga tushishini sozlash!** Endi har safar `--out` yozib o'tirish shart emas:
  * `zup config` — sozlamalar menyusi (papka, avtomatik ochish, doimiy arm64)
  * `zup config --out D:\APK` — papkani darhol o'rnatish
  * `zup config reset` — ish stoliga qaytarish
  * `zup apk --out D:\APK --save` — shu yig'ishdagi sozlamani doimiy qilish
  * Sozlamalar `~/.zup/config.json` da saqlanadi
* **`-o`** — `--out` ning qisqa shakli

### 🐞 Bug tuzatishlar

* **PATH ga qo'shilmasdan "muvaffaqiyatli" deb xabar berardi** — o'rnatuvchi PowerShell skriptini `runInShell` orqali chaqirar, bu esa skript ichidagi qo'shtirnoqlarni buzar edi. Xato jim yutilib, PATH hech qachon yozilmasdi va `zup` har safar qaytadan "o'rnatish" jarayonini boshlardi. Skript endi vaqtinchalik `.ps1` faylga yozilib ishga tushiriladi va har qanday xato aniq ko'rsatiladi.
* **`-v` versiyani ko'rsatmasdi** — `-v` `--verbose` ga bog'langani uchun versiya o'rniga interaktiv menyu ochilardi. Endi `-v` = versiya, `-V` = verbose.
* **Qayta o'rnatishda qulab tushardi** — mavjud `zup.exe` ustiga ko'chirishda `PathExistsException` chiqib, PATH bosqichiga umuman yetib borilmasdi.
* **Bo'sh joyli papka yo'llari buzilardi** — `bin/zup.js` `shell:true` bilan argumentlarni qalqonlamasdan uzatardi (`--out "D:\Mening APK"` ishlamasdi). Bu Node'ning har safargi DEP0190 ogohlantirishini ham keltirib chiqarardi.
* **Versiyalar noto'g'ri solishtirilardi** — oddiy `!=` ishlatilgani uchun mahalliy versiya yangiroq bo'lsa ham "yangi versiya bor" deb ko'rsatardi va `zup update` eskiroq versiyaga tushirib yuborishi mumkin edi. Endi to'g'ri semantik solishtirish ishlatiladi.
* **Versiya raqami 3 joyda mos kelmasdi** — banner `v1.3.1` ko'rsatib turganda paket 1.3.2 edi. Endi yagona manba: `zeroUpApkVersion`.
* **`zup -v` chiqishi beqaror edi** — fondagi yangilanish tekshiruvi tarmoq tezligiga qarab versiya chiqishiga aralashib qolardi. `--version` va `--help` uchun fon tekshiruvi o'chirildi.

### 🛡 Xatolarni oldindan ushlash

Endi quyidagilar **yig'ish boshlanishidan oldin** tekshiriladi (avval 5 daqiqa kutib, oxirida xato chiqardi):

* `--build-number` butun son ekanligi
* `--dart-define` `KEY=VALUE` ko'rinishida ekanligi
* Chiqish papkasiga haqiqatan yozib bo'lishi

Jim-jimgina e'tiborsiz qoladigan bayroqlar uchun ogohlantirish qo'shildi: `--no-copy` bilan `--out`/`--open`, release bo'lmagan rejimda `--obfuscate`, `--arm64` bilan `--split`, `--no-tune` bilan `--aggressive`.

## 1.3.2 - 2026-08-22

### 🐞 Bug tuzatishlar

* **npm install muammosi tuzatildi** - `install.js` da binary nomi mos kelmasligi sababli npm orqali o'rnatib bo'lmaydigan xato hal qilindi
* **`--dart-define` hujjati yaxshilandi** - CLI yordamida misol va batafsil tavsif qo'shildi

### ♻️ Ichki yaxshilanishlar

* `install.js` platformaga mos binary nomlarini to'g'ri ishlatadi (`zup_windows_x64.exe`, `zup_macos_<arch>`, `zup_linux_<arch>`)
* `package.json` ga `files` massivi qo'shildi - to'g'ri fayllar paketlenadi

## 1.3.1 - 2026-08-11

### 🔧 Yaxshilanishlar

* **Har safar yangilanish tekshirish** - 24 soatlik cooldown olib tashlandi, har safar `zup apk` yoki `zup aab` ishlatganda yangilanish tekshiriladi
* **Yaxshiroq xabar berish** - Agar GitHub ga ulanib bo'lmasa, aniq va tushunarli xabar ko'rsatiladi
* **To'g'ri feedback** - `zup update` ishlatganda:
  * Agar allaqachon eng so'nggi versiyada bo'lsa: "✅ Siz allaqachon eng so'nggi versiyada"
  * Agar GitHub ga ulanib bo'lmasa: Batafsil sabablari bilan xabar
  * Agar yangi versiya bo'lsa: Yangilanadi

### Foydalanuvchi tajribasi

* Faqat yangi versiya bo'lganda xabar ko'rsatiladi - ortiqcha bezovta qilmaydi
* Internet muammosi va "yangilanish yo'q" holatini aniq ajratish
* Har safar eng so'nggi versiya mavjudligini tekshirish

## 1.3.0 - 2026-08-11

### 🎉 Katta yangiliklar

* **GitHub Releases integratsiyasi** - Yangilanishlar avtomatik GitHub orqali tekshiriladi
* **`zup update` buyrug'i** - Oddiy yangilash, npm uslubida
* **Fonda yangilanish tekshirish** - Har safar tool ishlatganda avtomatik tekshiriladi (24 soatda 1 marta)
* **Ogohlantirish tizimi** - Yangi versiya bo'lsa chiroyli xabar ko'rsatiladi
* **Ko'p joylarni yangilash** - Barcha PATH dagi zup.exe fayllar bir vaqtda yangilanadi

### Yangi buyruqlar

* `zup update` - Eng so'nggi versiyaga yangilash
* Yangilanish avtomatik GitHub Releases dan yuklab olinadi

### Yaxshilanishlar

* GitHub API bilan ishlash - ishonchli va tez
* 24 soatlik cooldown - ortiqcha so'rovlarni oldini oladi
* Oddiy va tushunarli yangilash jarayoni
* Internet yo'q bo'lsa ham tool ishlaydi (faqat yangilanish tekshirilmaydi)

## 1.2.1 - 2026-08-11

### Yaxshilanishlar

* Versiya aniqlash yaxshilandi

## 1.2.0 - 2026-08-11

### Yaxshilanishlar

* **Avtomatik yangilash** - Yangi versiyani ochganda PATH dagi barcha zup.exe fayllar avtomatik yangilanadi
* **Ko'p joylarni yangilash** - `C:\bin\zup.exe`, `.zup\zup.exe` va boshqa barcha PATH joylari bir vaqtda yangilanadi
* **Yangilash hisoboti** - Nechta fayl yangilangani ko'rsatiladi

### Tuzatilgan xatolar

* Faqat bitta joy yangilanib, boshqalari eski qolishi muammosi hal qilindi

## 1.1.0 - 2026-08-11

### Yaxshilanishlar

* **Terminal holati tiklash** - Progress bar tugaganda yoki Ctrl+C bosilganda terminal kursorini va holatini to'g'ri tiklaydi
* **Xato aniqlash yaxshilandi** - Build aslida muvaffaqiyatsiz bo'lsa ham "muvaffaqiyatli" deb ko'rsatilmaydigan qilingan (exit code + "Built" xabari + log tahlili)
* **Xato xabarlar batafsil** - Xato chiqishida "Nima sodir bo'ldi" va "Qanday tuzatish" bo'limlari qo'shildi
* **20+ yangi xato turi** - Signing config, keystore parol, Gradle task, build.gradle, native kod, Java/Kotlin import, plugin versiya va boshqa xatolar aniqlanyapti
* **Rangli log chiqishi** - Xato qatorlar qizil, oddiy qatorlar kulrang rangda ko'rsatiladi
* **Ko'proq log qatorlari** - Xato tahlilida 15 ta muhim qator ko'rsatiladi (oldin 12 ta edi)
* **Qo'shimcha maslahatlar** - Har bir xato holatida 3 ta foydali maslahat beriladi

### Tuzatilgan xatolar

* Terminal kursorining yo'qolib qolishi muammosi hal qilindi
* Xato bo'lsa ham "muvaffaqiyatli" deb ko'rsatish muammosi bartaraf etildi
* Progress bar "qotib qolish" muammosi tuzatildi

## 1.0.0

Birinchi to'liq versiya.

* `zup apk` / `zup aab` / `zup hammasi` buyruqlari va interaktiv menyu
* Jarayonni foizlarda ko'rsatuvchi o'zbekcha progress-bar (bosqich nomlari
  bilan): Gradle, Kotlin, Java, Dart AOT, R8, paketlash
* Foiz statistikasi `.dart_tool/zero_up_apk/stats.json` da saqlanadi —
  ikkinchi yig'ishdan boshlab taxminiy vaqt ko'rsatiladi
* Kompyuter quvvatiga (yadro / RAM) qarab `gradle.properties` ni avtomatik
  optimallashtirish; asl fayl zaxiralanadi (`--restore-gradle`)
* Inkremental yig'ish, keraksiz `pub get` ni o'tkazib yuborish,
  `--arm64` tezkor rejimi, ikonka tree-shaking
* Natija ish stoliga — ilova nomi va versiyasi bilan atalgan papkaga,
  ichida o'zbekcha `MALUMOT.txt` hisoboti
* Xatolarni o'zbekcha tushuntirish va yechim taklif qilish (xotira, SDK,
  internet, keystore, JDK, duplicate class, R8, lint va boshqalar)
