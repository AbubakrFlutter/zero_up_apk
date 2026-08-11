/// Yig'ish xatosining o'zbekcha tushuntirishi va yechimi.
class TranslatedError {
  TranslatedError({
    required this.title,
    required this.reason,
    required this.solutions,
    this.rawLine,
  });

  final String title;
  final String reason;
  final List<String> solutions;
  final String? rawLine;
}

/// Gradle/Flutter log qatorlaridan xatoni topib, o'zbekchaga o'giradi.
class ErrorTranslator {
  static final List<_Rule> _rules = [
    _Rule(
      RegExp(r"flutter buyrug'ini ishga tushirib bo'lmadi"),
      'Flutter topilmadi',
      "'flutter' buyrug'i tizimda topilmadi.",
      [
        "Flutter SDK o'rnatilganini tekshiring: 'flutter --version'",
        "Flutter'ning bin papkasini PATH ga qo'shing",
        "PATH o'zgartirilgan bo'lsa, terminalni qayta oching",
      ],
    ),
    _Rule(
      RegExp(r'BUILD FAILED|build failed|Gradle build failed', caseSensitive: false),
      "Gradle build xatosi",
      "Gradle loyihani yig'a olmadi - umumiy xato.",
      [
        "To'liq logni tekshiring: yuqorida aniq sabab yozilgan",
        "'--verbose' flag bilan batafsil ma'lumot oling",
        "'flutter clean' so'ng qayta urinib ko'ring",
      ],
    ),
    _Rule(
      RegExp(r'FAILURE: Build failed with an exception', caseSensitive: false),
      "Build jarayoni muvaffaqiyatsiz tugadi",
      "Gradle yoki Flutter build jarayonida kritik xato yuz berdi.",
      [
        "Logdagi 'What went wrong:' qismini o'qing",
        "Agar kerak bo'lsa, '--clean' bilan tozalab qayta yig'ing",
        "Oxirgi o'zgarishlarni tekshiring - nima yangi qo'shilgan?",
      ],
    ),
    _Rule(
      RegExp(r'Signing config .* is not configured|signingConfig', caseSensitive: false),
      "Imzolash sozlamalari noto'g'ri",
      "Release build uchun signing config kerak, lekin topilmadi yoki xato.",
      [
        "android/app/build.gradle da signingConfigs to'g'ri yozilganini tekshiring",
        "android/key.properties fayli mavjud va to'g'ri yo'llar ko'rsatilganini tasdiqlang",
        "Debug rejimda sinab ko'ring: zup apk --mode debug",
      ],
    ),
    _Rule(
      RegExp(r'storePassword|keyPassword|keyAlias', caseSensitive: false),
      "Keystore parol yoki alias xatosi",
      "Keystore paroli, key alias yoki key paroli noto'g'ri ko'rsatilgan.",
      [
        "android/key.properties dagi parollarni tekshiring",
        "Keystore faylini to'g'ri ko'rsatyapsizmi: keystore yo'lini qayta tekshiring",
        "Alias nomi to'g'ri yozilganligiga ishonch hosil qiling",
      ],
    ),
    _Rule(
      RegExp(r'Task .* FAILED|Execution failed for task', caseSensitive: false),
      "Gradle vazifasi bajarilmadi",
      "Biror Gradle task muvaffaqiyatsiz tugadi.",
      [
        "Logda qaysi task xato berganini toping (masalan: ':app:lintVital')",
        "O'sha task bilan bog'liq sozlamalarni tekshiring",
        "Agar lint xatosi bo'lsa: android/app/build.gradle da lint { checkReleaseBuilds false } qo'shing",
      ],
    ),
    _Rule(
      RegExp(r'Could not find .* in build\.gradle', caseSensitive: false),
      "build.gradle da xato",
      "Gradle build fayllari noto'g'ri yoki buzilgan.",
      [
        "android/build.gradle va android/app/build.gradle fayllarini tekshiring",
        "Oxirgi o'zgarishlarni bekor qiling yoki asl nusxani tiklang",
        "Sintaksis xatosi yo'qligiga ishonch hosil qiling",
      ],
    ),
    _Rule(
      RegExp(r"Error:.* undefined|Error:.* doesn't name a type|Error:.* undeclared identifier", caseSensitive: false),
      "C++/Native kod xatosi",
      "Native kod (C++ yoki JNI) kompilyatsiya qilinmadi.",
      [
        "Native plugin'larni yangilang: flutter pub upgrade",
        "CMakeLists.txt yoki build fayllari buzilgan bo'lishi mumkin",
        "Plugin hujjatlarini o'qib, qo'shimcha sozlamalar kerakmi tekshiring",
      ],
    ),
    _Rule(
      RegExp(r'unresolved reference|cannot find symbol|package .* does not exist', caseSensitive: false),
      "Java/Kotlin import xatosi",
      "Java yoki Kotlin kodida import qilingan paket topilmadi.",
      [
        "android/app/build.gradle da dependencies to'g'ri qo'shilganini tekshiring",
        "Gradle sync qiling: Android Studio da 'Sync Project with Gradle Files'",
        "'flutter pub get' va 'flutter clean' bajaring",
      ],
    ),
    _Rule(
      RegExp(
        r'not enough space on the disk|No space left on device|'
        r'errno = 112|There is not enough space',
      ),
      "Diskda joy yo'q",
      "Yig'ish uchun diskda bo'sh joy qolmadi.",
      [
        "Kamida 5 GB bo'sh joy kerak",
        "'gradlew --stop' so'ng .gradle\\caches\\build-cache-1 ni o'chiring",
        "Eski loyihalarning build papkalarini tozalang",
      ],
    ),
    _Rule(
      RegExp(r'OutOfMemoryError|Java heap space|GC overhead limit'),
      'Xotira yetishmadi',
      'Gradle uchun ajratilgan operativ xotira (RAM) yetmadi.',
      [
        "android/gradle.properties da org.gradle.jvmargs dagi -Xmx qiymatini kamaytiring",
        "Ochiq dasturlarni (brauzer, emulator) yopib qayta urinib ko'ring",
        "--no-aggressive bilan ishga tushiring",
      ],
    ),
    _Rule(
      RegExp(r'SDK location not found|ANDROID_HOME|sdk\.dir'),
      'Android SDK topilmadi',
      "Loyihada Android SDK yo'li ko'rsatilmagan.",
      [
        "android/local.properties fayliga sdk.dir=C\\:\\\\Users\\\\<siz>\\\\AppData\\\\Local\\\\Android\\\\Sdk qatorini qo'shing",
        "Yoki 'flutter doctor --android-licenses' buyrug'ini bajaring",
      ],
    ),
    _Rule(
      RegExp(
        r'Could not (resolve|download|find) .*|Connection (timed out|refused)|UnknownHostException',
      ),
      "Internet yoki kutubxona xatosi",
      "Gradle kerakli kutubxonani yuklab ololmadi.",
      [
        "Internet aloqasini tekshiring",
        "VPN/proxy ishlatayotgan bo'lsangiz, uni o'chirib ko'ring",
        "Qaytadan urinib ko'ring — ko'pincha vaqtinchalik muammo",
      ],
    ),
    _Rule(
      RegExp(r'Keystore file .* not found|keystore password was incorrect|key\.properties'),
      'Imzolash kaliti (keystore) muammosi',
      "Release uchun imzolash sozlamalari topilmadi yoki noto'g'ri.",
      [
        "android/key.properties faylini va keystore yo'lini tekshiring",
        "Parollar to'g'riligiga ishonch hosil qiling",
        "Sinov uchun --mode debug bilan yig'ib ko'ring",
      ],
    ),
    _Rule(
      RegExp(
        r'Android resource linking failed|AAPT: error:|Aapt2Exception|'
        r'resource (style|mipmap|drawable|color|string)/',
      ),
      'Resurs (aapt2) xatosi',
      'Android resurslari bog\'lanmadi — biror resurs topilmadi yoki '
          'XML fayl noto\'g\'ri.',
      [
        "Logdagi 'AAPT: error:' qatorida qaysi resurs yetishmayotgani yozilgan",
        "android/app/src/main/res papkasi joyida ekanini tekshiring",
        "Ikonka o'zgartirgan bo'lsangiz, mipmap fayllari borligiga ishonch hosil qiling",
        "'--clean' bilan qayta yig'ib ko'ring",
      ],
    ),
    _Rule(
      RegExp(r'Manifest merger failed|uses-sdk:.*minSdkVersion'),
      'AndroidManifest birlashtirilmadi',
      "Pluginlar manifestlari bir-biriga zid — ko'pincha minSdk past.",
      [
        "android/app/build.gradle da minSdk qiymatini oshiring",
        "Logdagi 'Manifest merger failed' qatoridagi tavsiyaga amal qiling",
      ],
    ),
    _Rule(
      RegExp(r'lintVitalRelease|Lint found'),
      'Lint tekshiruvi to\'xtatdi',
      "Android lint jiddiy ogohlantirish topdi.",
      [
        "android/app/build.gradle ichida android { lint { checkReleaseBuilds false } } qo'shing",
        "Yoki logdagi lint xatosini to'g'rilang",
      ],
    ),
    _Rule(
      RegExp(r'Unsupported class file major version|Unsupported Java|invalid source release|jvmTarget'),
      'Java/JDK versiyasi mos emas',
      "Loyiha talab qiladigan JDK versiyasi o'rnatilganidan farq qiladi.",
      [
        "'flutter doctor -v' bilan JDK versiyasini tekshiring",
        "'flutter config --jdk-dir=<JDK 17 yo'li>' bilan JDK ni ko'rsating",
        "android/gradle/wrapper/gradle-wrapper.properties dagi Gradle versiyasini yangilang",
      ],
    ),
    _Rule(
      RegExp(r'Duplicate class|Program type already present'),
      'Takrorlangan kutubxona (duplicate class)',
      "Ikki xil paket bir xil sinfni olib kelgan.",
      [
        "'flutter pub deps' bilan qaysi paketlar to'qnashayotganini toping",
        "pubspec.yaml da paket versiyalarini moslang",
        "'flutter pub upgrade' ni bajaring",
      ],
    ),
    _Rule(
      // Diqqat: shunchaki "proguard" so'zi emas — u oddiy logda ham uchraydi.
      RegExp(
        r"Execution failed for task '[^']*:(minify|r8)[^']*'|"
        r'com\.android\.tools\.r8|R8: |Missing class ',
        caseSensitive: false,
      ),
      'Kod siqishda (R8/ProGuard) xato',
      "Kod obfuskatsiya/siqish bosqichida muammo yuz berdi.",
      [
        "android/app/proguard-rules.pro ga kerakli -keep qoidalarini qo'shing",
        "--no-obfuscate bilan yig'ib ko'ring",
      ],
    ),
    _Rule(
      RegExp(r"Target of URI doesn't exist|Error: .*\.dart:\d+|error: .*\.dart:|Expected to find|Undefined name|Undefined class"),
      'Dart kodida xato',
      "Loyiha kodida kompilyatsiya xatosi bor.",
      [
        "'flutter analyze' ni ishga tushiring va xatolarni to'g'rilang",
        "Yuqoridagi logda fayl nomi va qator raqami ko'rsatilgan",
        "Import qilish kerak bo'lgan paketlar to'g'ri qo'shilganini tekshiring",
        "Sintaksis xatolari yo'qligiga ishonch hosil qiling",
      ],
    ),
    _Rule(
      RegExp(r'Gradle sync failed|Configuration .* could not be resolved', caseSensitive: false),
      "Gradle konfiguratsiyasi xato",
      "Gradle loyiha strukturasini to'g'ri o'qiy olmadi.",
      [
        "android/build.gradle va android/app/build.gradle sintaksisini tekshiring",
        "Gradle versiyasini yangilang: gradle-wrapper.properties da",
        "Android Studio da 'Invalidate Caches / Restart' qiling",
      ],
    ),
    _Rule(
      RegExp(r'Exception: Gradle task .* failed with exit code \d+', caseSensitive: false),
      "Gradle task muvaffaqiyatsiz",
      "Gradle task ishlamadi.",
      [
        "Logdagi batafsil xato xabarini o'qing",
        "--verbose flag bilan ko'proq ma'lumot oling",
        "Gradle keshlari buzilgan bo'lishi mumkin: 'gradlew clean' bajaring",
      ],
    ),
    _Rule(
      RegExp(r'The binary version of its metadata is|This version .* requires plugin'),
      "Plugin versiya moslashtirmasi kerak",
      "Flutter yoki Gradle versiyasi plugin'lar bilan mos kelmayapti.",
      [
        "flutter pub upgrade qiling - barcha paketlarni yangilang",
        "pubspec.yaml da plugin versiyalarini eng yangilari bilan almashtiring",
        "Flutter SDK ni yangilash kerak bo'lishi mumkin: flutter upgrade",
      ],
    ),
    _Rule(
      RegExp(
        r'requires Android SDK|'
        r'(compileSdk|minSdk|targetSdk)\w*\s*\(?\d*\)?[^\n]{0,40}'
        r'(required|is greater|but|cannot be)',
      ),
      'Android SDK versiyasi mos emas',
      "Biror plugin yuqoriroq compileSdk/minSdk talab qilmoqda.",
      [
        "android/app/build.gradle da compileSdk va minSdk qiymatlarini oshiring",
        "Android Studio > SDK Manager orqali kerakli SDK ni o'rnating",
      ],
    ),
    _Rule(
      RegExp(r'Could not (delete|create|move)|being used by another process|Access is denied'),
      'Fayl band yoki ruxsat yo\'q',
      "Boshqa dastur build papkasidagi faylni ushlab turibdi.",
      [
        "Antivirus yoki Windows Defender build papkasini skanerlayotgan bo'lishi mumkin",
        "Android Studio / VS Code dagi ishlab turgan buildni to'xtating",
        "'--clean' bilan qayta urinib ko'ring",
      ],
    ),
    _Rule(
      RegExp(r'No Android SDK found|cmdline-tools component is missing'),
      'Android buyruq qatori vositalari yo\'q',
      "Android SDK cmdline-tools o'rnatilmagan.",
      [
        "Android Studio > SDK Manager > SDK Tools > 'Android SDK Command-line Tools' ni o'rnating",
        "So'ng 'flutter doctor' ni qayta bajaring",
      ],
    ),
  ];

  /// Log qatorlari ichidan eng mos xatoni topadi.
  static TranslatedError? translate(List<String> logLines) {
    // Oxiridan boshlab qidiramiz — asosiy sabab odatda oxirida bo'ladi.
    for (final rule in _rules) {
      for (var i = logLines.length - 1; i >= 0; i--) {
        final line = logLines[i];
        if (rule.pattern.hasMatch(line)) {
          return TranslatedError(
            title: rule.title,
            reason: rule.reason,
            solutions: rule.solutions,
            rawLine: line.trim(),
          );
        }
      }
    }
    return null;
  }

  /// Logdan foydalanuvchiga ko'rsatish uchun eng muhim qatorlarni ajratadi.
  static List<String> highlights(List<String> logLines, {int max = 12}) {
    final interesting = <String>[];
    final seen = <String>{};

    // Xato belgisi bo'lgan qatorlarni topish uchun kengaytirilgan regex
    final re = RegExp(
      r'(FAILURE:|BUILD FAILED|What went wrong|Execution failed|'
      r'error:|Error:|Exception|Caused by:|\* Try:|'
      r'Task .* FAILED|BUILD FAILED with an exception|'
      r'Could not resolve|Could not find|'
      r'Signing config|signingConfig|keystore|'
      r'Dart Error:|Target of URI|'
      r'Undefined name|Undefined class|'
      r'unresolved reference|cannot find symbol|'
      r'OutOfMemoryError|No space left|'
      r'Manifest merger failed|uses-sdk:|'
      r'lintVitalRelease|Lint found|'
      r'Duplicate class|Program type already present)',
      caseSensitive: false,
    );

    // Oxiridan boshlab qidiramiz - eng so'nggi xatolar muhimroq
    for (var i = logLines.length - 1; i >= 0; i--) {
      final line = logLines[i];
      final clean = _clean(line);
      if (clean.isEmpty) continue;
      if (re.hasMatch(clean) && seen.add(clean)) {
        interesting.insert(0, clean); // Boshiga qo'shamiz (tartib saqlansin)
        if (interesting.length >= max) break;
      }
    }

    // Hech narsa topilmasa - oxirgi 'max' ta qatorni qaytaramiz
    if (interesting.isEmpty) {
      return logLines
          .map(_clean)
          .where((l) => l.isNotEmpty)
          .toList()
          .reversed
          .take(max)
          .toList()
          .reversed
          .toList();
    }
    return interesting;
  }

  static String _clean(String line) =>
      shortenPaths(_stripVerbosePrefix(line).trim());

  static String _stripVerbosePrefix(String line) =>
      line.replaceFirst(RegExp(r'^\[\s*[+\-]?\s*\d+\s*(ms|s)?\s*\]\s?'), '');

  /// Uzun absolyut yo'llarni faqat fayl nomiga qisqartiradi —
  /// xato matni qatorga sig'ishi uchun.
  static String shortenPaths(String text) => text
      .replaceAllMapped(
        RegExp(r'[A-Za-z]:\\(?:[^\\\s:]+\\){2,}([^\\\s:]+)'),
        (m) => '…\\${m[1]}',
      )
      .replaceAllMapped(
        RegExp(r'(?<![\w.])/(?:[^/\s:]+/){2,}([^/\s:]+)'),
        (m) => '…/${m[1]}',
      );
}

class _Rule {
  _Rule(this.pattern, this.title, this.reason, this.solutions);

  final RegExp pattern;
  final String title;
  final String reason;
  final List<String> solutions;
}
