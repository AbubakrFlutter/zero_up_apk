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
