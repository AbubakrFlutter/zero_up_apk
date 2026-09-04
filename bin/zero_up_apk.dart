import 'dart:io';

import 'package:zero_up_apk/zero_up_apk.dart';

// Versiyaning yagona manbasi — lib/src/cli.dart dagi zeroUpApkVersion.
// Ikkita alohida konstanta ikkisi mos kelmay qolishiga olib kelgan edi
// (masalan, banner v1.3.1 ko'rsatib turganda paket allaqachon 1.3.2 edi).
const currentVersion = zeroUpApkVersion;
const repoOwner = 'AbubakrFlutter';
const repoName = 'zero_up_apk';

Future<void> main(List<String> args) async {
  // --install flag → o'rnatish yoki yangilash
  if (args.length == 1 && args[0] == '--install') {
    final installed = await _isInstalled();

    if (!installed) {
      // O'rnatilmagan → o'rnatish
      exitCode = await _autoInstall();
      return;
    }

    // O'rnatilgan - versiyani tekshiramiz
    final needsUpdate = await _checkIfNeedsUpdate();

    if (needsUpdate) {
      // Eski versiya → yangilash
      print('');
      print('✅ zup allaqachon o\'rnatilgan, lekin yangi versiya mavjud.');
      print('🔄 Yangilanmoqda...');
      print('');
      exitCode = await _performUpdate();
      return;
    }

    // Eng so'nggi versiya allaqachon o'rnatilgan
    print('');
    print('╔══════════════════════════════════════════════════════════════╗');
    print('║                    ⚡ Zero Up APK                           ║');
    print('╚══════════════════════════════════════════════════════════════╝');
    print('');
    print('✅ zup allaqachon o\'rnatilgan!');
    print('📦 Versiya: $currentVersion (eng so\'nggi)');
    print('');
    print('💡 Ishlatish: zup apk --arm64');
    print('');
    return;
  }

  // update buyrug'i → yangilash
  if (args.isNotEmpty && args[0] == 'update') {
    exitCode = await _performUpdate();
    return;
  }

  // Argumentsiz ochilgan bo'lsa:
  //   o'rnatilmagan → o'rnatish
  //   o'rnatilgan   → asosiy menyu (hamma amal shu yerdan bajariladi)
  if (args.isEmpty) {
    final installed = await _isInstalled();
    if (!installed) {
      exitCode = await _autoInstall();
      return;
    }
    exitCode = await ZeroUpApkCli().runMainMenu();
    return;
  }

  // Ma'lumot beruvchi buyruqlar (--version, --help) chiqishi toza va
  // bir xil bo'lishi kerak — fon tekshiruvi tarmoq tezligiga qarab
  // ularning ustiga xabar chiqarib yuborardi.
  if (!_isInfoCommand(args)) {
    // Har qanday buyruq ishga tushganda yangilanishni tekshirish (fonda)
    _checkUpdateInBackground();
  }

  // Asosiy buyruqni bajarish
  exitCode = await ZeroUpApkCli().run(args);
}

/// `--version` / `--help` kabi faqat ma'lumot chiqaradigan buyruqmi?
bool _isInfoCommand(List<String> args) {
  const infoFlags = {'--version', '-v', '--help', '-h'};
  return args.any(infoFlags.contains);
}

/// Semantik versiyalarni solishtiradi: [candidate] > [current] bo'lsa `true`.
///
/// Oddiy `!=` bilan solishtirish xato edi: mahalliy versiya GitHub dagidan
/// yangiroq bo'lsa ham "yangi versiya bor" deb ko'rsatardi va `zup update`
/// foydalanuvchini eskiroq versiyaga tushirib yuborishi mumkin edi.
bool isNewerVersion(String candidate, String current) {
  List<int> parse(String v) {
    final cleaned = v.trim().replaceFirst(RegExp('^v'), '');
    // "1.3.3+2" yoki "1.3.3-beta" — faqat raqamli qismni olamiz.
    final core = cleaned.split(RegExp('[+-]')).first;
    return core
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }

  final a = parse(candidate);
  final b = parse(current);
  final length = a.length > b.length ? a.length : b.length;

  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// Fonda yangilanish tekshirish va xabar berish (har safar)
void _checkUpdateInBackground() {
  Future(() async {
    try {
      final checker = UpdateChecker(
        currentVersion: currentVersion,
        repoOwner: repoOwner,
        repoName: repoName,
      );

      // Har safar tekshirish (24 soat cooldown yo'q)
      final latestVersion = await checker.fetchLatestVersion();

      if (latestVersion != null && isNewerVersion(latestVersion, currentVersion)) {
        print('');
        print('╭────────────────────────────────────────────────────────╮');
        print('│  💡 Yangi versiya mavjud!                             │');
        final row =
            '│     Hozirgi: $currentVersion → Yangi: $latestVersion'.padRight(57);
        print('$row│');
        print('│                                                        │');
        print('│     Yangilash: zup update                             │');
        print('╰────────────────────────────────────────────────────────╯');
        print('');
      }
    } catch (_) {
      // Xato bo'lsa, indamay o'tamiz (internet yo'q yoki GitHub muammosi)
    }
  });
}

/// Yangilashni amalga oshirish
Future<int> _performUpdate() async {
  print('');
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║                    ⚡ Zero Up APK                           ║');
  print('╚══════════════════════════════════════════════════════════════╝');
  print('');
  print('🔄 Yangilash boshlanmoqda...');
  print('');

  try {
    final checker = UpdateChecker(
      currentVersion: currentVersion,
      repoOwner: repoOwner,
      repoName: repoName,
    );

    // 1. Yangi versiya borligini tekshirish
    print('🔍 Yangi versiya qidirilmoqda...');
    final latestVersion = await checker.fetchLatestVersion();

    if (latestVersion == null) {
      print('⚠️  GitHub Releases ga ulanib bo\'lmadi.');
      print('');
      print('💡 Mumkin bo\'lgan sabablar:');
      print('   • Internet aloqasi yo\'q');
      print('   • GitHub Releases da yangilanish yo\'q');
      print('   • GitHub vaqtincha band');
      print('');
      print('📦 Hozirgi versiya: $currentVersion');
      print('');
      return 1;
    }

    if (!isNewerVersion(latestVersion, currentVersion)) {
      print('✅ Siz allaqachon eng so\'nggi versiyada ($currentVersion)');
      if (latestVersion != currentVersion) {
        print('   (GitHub dagi so\'nggi reliz: $latestVersion)');
      }
      print('');
      return 0;
    }

    print('📦 Yangi versiya topildi: $latestVersion');
    print('');

    // 2. Yangi versiyani yuklab olish
    final downloadedFile = await checker.downloadLatestRelease();

    if (downloadedFile == null) {
      print('❌ Faylni yuklab olishda xato.');
      print('');
      return 1;
    }

    // 3. PATH dagi barcha zup.exe fayllarni topish
    print('');
    print('🔍 O\'rnatilgan zup fayllar qidirilmoqda...');
    final allZupPaths = await _findAllZupInPath();

    if (allZupPaths.isEmpty) {
      print('❌ Birorta ham zup.exe topilmadi.');
      print('');
      print('💡 O\'rnatish uchun: zup.exe --install');
      print('');
      return 1;
    }

    print('📍 ${allZupPaths.length} ta zup.exe topildi');
    print('');

    // 4. Har bir zup.exe ni yangilash
    print('🔄 Fayllar yangilanmoqda...');
    print('');

    final updatedPaths = <String>[];
    final exePath = Platform.resolvedExecutable;

    for (final zupPath in allZupPaths) {
      // O'zimizni o'zimizga ko'chirmaymiz
      if (zupPath.toLowerCase() == exePath.toLowerCase()) {
        print('⏭  ${_shortenPath(zupPath)} (hozirgi fayl)');
        continue;
      }

      try {
        downloadedFile.copySync(zupPath);
        updatedPaths.add(zupPath);
        print('✅ ${_shortenPath(zupPath)}');
      } catch (e) {
        print('⚠️  ${_shortenPath(zupPath)} - xato: $e');
      }
    }

    // 5. VERSION faylini yangilash
    final homeDir = Platform.environment['USERPROFILE'] ??
                    Platform.environment['HOME'] ??
                    '';
    if (homeDir.isNotEmpty) {
      try {
        final versionFile = File('$homeDir\\.zup\\VERSION');
        if (versionFile.parent.existsSync()) {
          versionFile.writeAsStringSync(latestVersion);
        }
      } catch (_) {}
    }

    // 6. Vaqtinchalik faylni o'chirish
    try {
      downloadedFile.parent.deleteSync(recursive: true);
    } catch (_) {}

    print('');
    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              ✅ YANGILASH MUVAFFAQIYATLI!                   ║');
    print('╚══════════════════════════════════════════════════════════════╝');
    print('');
    print('📊 NATIJA:');
    print('   • Yangi versiya: $latestVersion');
    print('   • Yangilangan fayllar: ${updatedPaths.length}');
    print('');
    print('🚀 Endi barcha joyda yangi versiya ishlaydi!');
    print('');
    print('💡 Tekshirish: zup --version');
    print('');

    return 0;
  } catch (e) {
    print('');
    print('❌ XATO: Yangilab bo\'lmadi');
    print('   Sabab: $e');
    print('');
    return 1;
  }
}

/// O'rnatilgan joyda ekanligini yoki PATH da borligini tekshiradi.
///
/// MUHIM: faqat `where` ga tayanib bo'lmaydi. Ochiq turgan terminal PATH
/// nusxasini o'zi ochilganda bir marta o'qiydi — o'rnatuvchi registry ni
/// yangilagan bo'lsa ham, eski terminal buni ko'rmaydi. Shu sababli
/// hammasi joyida bo'lsa ham "o'rnatilmagan" deb hisoblanib, har safar
/// o'rnatish ekrani qayta-qayta chiqardi.
Future<bool> _isInstalled() async {
  final targetExe = _installedExe();

  // Fayl umuman yo'q bo'lsa — aniq o'rnatilmagan.
  if (targetExe != null && targetExe.existsSync()) {
    // Fayl bor. Doimiy (registry) PATH da ham bormi?
    if (await _zupDirInPersistentPath()) return true;
  }

  // Zaxira: joriy jarayonning PATH i bo'yicha tekshiramiz.
  try {
    final result = await Process.run(
      'where',
      ['zup', 'zup.exe'],
      runInShell: true,
    ).timeout(const Duration(seconds: 10));

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      return output.trim().isNotEmpty && output.contains('.exe');
    }
  } catch (_) {}

  return false;
}

/// `~/.zup/zup.exe` fayli (o'rnatilgan nusxa).
File? _installedExe() {
  final homeDir = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  if (homeDir.isEmpty) return null;
  return File('$homeDir\\.zup\\zup.exe');
}

/// `.zup` papkasi foydalanuvchining doimiy (registry) PATH ida bormi?
///
/// Joriy terminalning eskirgan PATH nusxasidan farqli o'laroq, bu
/// haqiqiy holatni ko'rsatadi.
Future<bool> _zupDirInPersistentPath() async {
  if (!Platform.isWindows) return false;

  final homeDir = Platform.environment['USERPROFILE'] ?? '';
  if (homeDir.isEmpty) return false;
  final zupDir = '$homeDir\\.zup'.toLowerCase();

  try {
    final result = await Process.run(
      'reg',
      ['query', 'HKCU\\Environment', '/v', 'Path'],
      runInShell: true,
    ).timeout(const Duration(seconds: 10));

    if (result.exitCode != 0) return false;
    return result.stdout.toString().toLowerCase().contains(zupDir);
  } catch (_) {
    return false;
  }
}

/// O'rnatilgan versiya eski bo'lsa yangilash kerakligini tekshirish
Future<bool> _checkIfNeedsUpdate() async {
  try {
    // 1. PATH dagi birinchi zup.exe versiyasini olish
    final zupPaths = await _findAllZupInPath();
    if (zupPaths.isEmpty) return false;

    // 2. Versiyani tekshirish
    try {
      final result = await Process.run(
        zupPaths.first,
        ['--version'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        // "zero_up_apk 1.2.0" → "1.2.0"
        final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);
        if (versionMatch != null) {
          final installedVersion = versionMatch.group(1)!;
          // Faqat o'rnatilgani eskiroq bo'lsa yangilash kerak.
          return isNewerVersion(currentVersion, installedVersion);
        }
      }
    } catch (_) {}

    // 3. Agar versiyani aniqlab bo'lmasa, VERSION faylini tekshiramiz
    final homeDir = Platform.environment['USERPROFILE'] ??
                    Platform.environment['HOME'] ??
                    '';

    if (homeDir.isNotEmpty) {
      final versionFile = File('$homeDir\\.zup\\VERSION');
      if (versionFile.existsSync()) {
        final installedVersion = versionFile.readAsStringSync().trim();
        return isNewerVersion(currentVersion, installedVersion);
      }
    }
  } catch (_) {}

  return false;
}

/// PATH dagi barcha zup.exe fayllarni topish
Future<List<String>> _findAllZupInPath() async {
  final paths = <String>[];

  try {
    final result = await Process.run(
      'where',
      ['zup', 'zup.exe'],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      for (final line in output.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty &&
            trimmed.toLowerCase().endsWith('.exe') &&
            File(trimmed).existsSync()) {
          paths.add(trimmed);
        }
      }
    }
  } catch (_) {}

  return paths;
}

/// Yo'lni qisqartirish (ekranda chiroyli ko'rinishi uchun)
String _shortenPath(String path) {
  if (path.length <= 50) return path;
  final parts = path.split('\\');
  if (parts.length > 3) {
    return '...\\${parts[parts.length - 2]}\\${parts[parts.length - 1]}';
  }
  return path;
}

/// Avtomatik o'rnatish
Future<int> _autoInstall() async {
  final exePath = Platform.resolvedExecutable;
  final homeDir = Platform.environment['USERPROFILE'] ??
                  Platform.environment['HOME'] ??
                  '';

  if (homeDir.isEmpty) {
    print('❌ USERPROFILE topilmadi — o\'rnatib bo\'lmadi.');
    print('   zup.exe ni qo\'lda PATH ga qo\'shing.');
    return 1;
  }

  final installDir = Directory('$homeDir\\.zup');
  final targetExe = File('${installDir.path}\\zup.exe');

  // `dart run bin/zero_up_apk.dart` bilan ishga tushirilganda
  // Platform.resolvedExecutable Dart SDK ning dart.exe sini qaytaradi.
  // Uni zup.exe deb ko'chirsak, o'rnatilgan "zup" umuman ishlamaydi
  // ("Unable to find snapshot: dartdev_aot.dart.snapshot").
  final exeName = exePath.split(RegExp(r'[\\/]')).last.toLowerCase();
  if (exeName == 'dart.exe' || exeName == 'dart') {
    print('');
    print('⚠️  Bu buyruq manba koddan (dart run) ishga tushirilgan —');
    print('   o\'rnatish uchun avval kompilyatsiya qilish kerak:');
    print('');
    print('   dart compile exe bin/zero_up_apk.dart -o bin/zup.exe');
    print('   bin\\zup.exe');
    print('');
    return 1;
  }

  print('');
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║                    ⚡ Zero Up APK                           ║');
  print('╚══════════════════════════════════════════════════════════════╝');
  print('');
  print('🔍 PATH da zup topilmadi — avtomatik o\'rnatish boshlanmoqda...');
  print('');

  try {
    // 1. .zup papkani yaratish
    if (!installDir.existsSync()) {
      installDir.createSync(recursive: true);
      print('✅ Papka yaratildi: ${installDir.path}');
    } else {
      print('📁 Papka mavjud: ${installDir.path}');
    }

    // 2. exe ni ko'chirish
    if (exePath.toLowerCase() != targetExe.path.toLowerCase()) {
      // Windows'da mavjud fayl ustiga copySync xato beradi
      // (ERROR_ALREADY_EXISTS) — avval eskisini olib tashlaymiz.
      // Aks holda qayta o'rnatishda dastur shu yerda qulab tushib,
      // PATH ga qo'shish bosqichiga umuman yetib bormasdi.
      if (targetExe.existsSync()) {
        try {
          targetExe.deleteSync();
        } on FileSystemException catch (e) {
          print('❌ Eski zup.exe ni almashtirib bo\'lmadi');
          print('   Sabab: ${e.osError?.message ?? e.message}');
          print('');
          print('💡 Ochiq turgan zup jarayonini yoping va qaytadan urining.');
          print('');
          return 1;
        }
      }
      File(exePath).copySync(targetExe.path);
      print('✅ zup.exe ko\'chirildi');
    }

    // 3. VERSION faylini yozish
    final versionFile = File('${installDir.path}\\VERSION');
    versionFile.writeAsStringSync(currentVersion);

    // 4. PATH ga qo'shish
    print('🔧 PATH ga qo\'shilmoqda...');

    final installPathForPs = installDir.path.replaceAll('/', '\\');

    // Skriptni vaqtinchalik .ps1 faylga yozib -File bilan ishga tushiramiz.
    // -Command orqali ko'p qatorli skript yuborilsa, runInShell:true cmd.exe
    // orqali argumentlarni qayta parslaydi va ichidagi qo'shtirnoqlarni
    // yeb qo'yishi mumkin — bu esa skriptni jim-jimgina buzib, PATH hech
    // qachon yozilmagan holda "muvaffaqiyatli" deb noto'g'ri xabar berardi.
    final psScript = '''
\$ErrorActionPreference = "Stop"
try {
    \$ZupPath = "$installPathForPs"
    \$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (\$null -eq \$UserPath) {
        \$UserPath = ""
    }
    if (\$UserPath -notlike "*\$ZupPath*") {
        if (\$UserPath -eq "") {
            \$NewPath = \$ZupPath
        } else {
            \$NewPath = "\$UserPath;\$ZupPath"
        }
        [Environment]::SetEnvironmentVariable("Path", \$NewPath, "User")
        Write-Host "OK"
    } else {
        Write-Host "ALREADY"
    }
} catch {
    Write-Host "ERROR:\$_"
    exit 1
}
''';

    final scriptFile = File(
      '${Directory.systemTemp.path}\\zup_addpath_${DateTime.now().microsecondsSinceEpoch}.ps1',
    );
    scriptFile.writeAsStringSync(psScript);

    ProcessResult result;
    try {
      result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
        ],
      );
    } finally {
      try {
        scriptFile.deleteSync();
      } catch (_) {}
    }

    final output = result.stdout.toString().trim();
    final stderrOutput = result.stderr.toString().trim();

    if (result.exitCode != 0 || output.startsWith('ERROR:')) {
      print('❌ PATH ga qo\'shib bo\'lmadi');
      if (output.startsWith('ERROR:')) {
        print('   Xato: ${output.substring(6)}');
      } else if (stderrOutput.isNotEmpty) {
        print('   Xato: $stderrOutput');
      } else {
        print('   Xato: kutilmagan holat (exit code: ${result.exitCode})');
      }
      print('');
      print('⚠️  zup.exe ko\'chirildi, lekin PATH ga qo\'shilmadi.');
      print('   Qo\'lda qo\'shing: ${installDir.path}');
      print('');
      return 1;
    } else if (output == 'OK') {
      print('✅ PATH ga qo\'shildi!');
    } else if (output == 'ALREADY') {
      print('ℹ️  PATH da allaqachon mavjud');
    } else {
      // Kutilmagan chiqish — muvaffaqiyat deb noto'g'ri e'lon qilmaymiz.
      print('❌ PATH ga qo\'shib bo\'lmadi');
      print('   Kutilmagan javob: $output');
      print('');
      print('⚠️  zup.exe ko\'chirildi, lekin PATH ga qo\'shilmadi.');
      print('   Qo\'lda qo\'shing: ${installDir.path}');
      print('');
      return 1;
    }

    print('');
    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              ✅ O\'RNATISH MUVAFFAQIYATLI!                   ║');
    print('╚══════════════════════════════════════════════════════════════╝');
    print('');
    print('📌 KEYINGI QADAM:');
    print('   1. Hozirgi terminal/cmd ni YOPING');
    print('   2. YANGI terminal/cmd oching');
    print('   3. Flutter loyihangizga kiring');
    print('   4. Shunchaki yozing: zup apk');
    print('');
    print('💡 MASALAN:');
    print('   cd C:\\mening_loyiham');
    print('   zup apk --arm64');
    print('');
    print('🚀 Endi istalgan Flutter loyihasida "zup" buyrug\'i ishlaydi!');
    print('');

    return 0;
  } catch (e) {
    print('');
    print('❌ XATO: O\'rnatib bo\'lmadi');
    print('   Sabab: $e');
    print('');
    print('📝 QO\'LDA O\'RNATISH:');
    print('   1. zup.exe ni ${installDir.path} ga ko\'chiring');
    print('   2. O\'sha papkani PATH ga qo\'shing');
    print('');
    return 1;
  }
}
