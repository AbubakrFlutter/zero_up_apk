import 'dart:io';

import 'package:zero_up_apk/zero_up_apk.dart';

const currentVersion = '1.3.2';
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

  // Agar argumentsiz ochilgan bo'lsa → yo'riqnoma
  if (args.isEmpty) {
    final installed = await _isInstalled();
    if (!installed) {
      // O'rnatilmagan → o'rnatish
      exitCode = await _autoInstall();
      return;
    } else {
      // Allaqachon o'rnatilgan → yo'riqnoma
      _showQuickStart();
      return;
    }
  }

  // Har qanday buyruq ishga tushganda yangilanishni tekshirish (fonda)
  // 24 soat cooldown yo'q - har safar tekshiriladi
  _checkUpdateInBackground();

  // Asosiy buyruqni bajarish
  exitCode = await ZeroUpApkCli().run(args);
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

      if (latestVersion != null && latestVersion != currentVersion) {
        print('');
        print('╭────────────────────────────────────────────────────────╮');
        print('│  💡 Yangi versiya mavjud!                             │');
        print('│     Hozirgi: $currentVersion → Yangi: $latestVersion'.padRight(57) + '│');
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

    if (latestVersion == currentVersion) {
      print('✅ Siz allaqachon eng so\'nggi versiyada ($currentVersion)');
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

/// Allaqachon o'rnatilgan bo'lganda ko'rsatiladigan qisqa yo'riqnoma
void _showQuickStart() {
  print('');
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║                    ⚡ Zero Up APK                           ║');
  print('╚══════════════════════════════════════════════════════════════╝');
  print('');
  print('✅ zup allaqachon o\'rnatilgan!');
  print('');
  print('📌 QANDAY ISHLATISH:');
  print('');
  print('   1. Flutter loyihangizga kiring:');
  print('      cd C:\\mening_loyiham');
  print('');
  print('   2. APK yasash:');
  print('      zup apk');
  print('');
  print('   3. Faqat arm64 (tezroq):');
  print('      zup apk --arm64');
  print('');
  print('   4. App Bundle (Google Play):');
  print('      zup aab');
  print('');
  print('   5. Yordam:');
  print('      zup --help');
  print('');
  print('💡 MASLAHAT: Telefonga o\'rnatish uchun arm64 faylini oling.');
  print('');
  print('🚀 Hozir terminaldan chiqib, Flutter loyihangizga kiring!');
  print('');
}

/// O'rnatilgan joyda ekanligini yoki PATH da borligini tekshiradi
Future<bool> _isInstalled() async {
  // PATH da zup.exe borligini tekshirish
  try {
    final result = await Process.run(
      'where',
      ['zup', 'zup.exe'],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      final output = result.stdout.toString();
      return output.trim().isNotEmpty && output.contains('.exe');
    }
  } catch (_) {}

  return false;
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
          final installedVersion = versionMatch.group(1);
          return installedVersion != currentVersion;
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
        return installedVersion != currentVersion;
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
    if (exePath != targetExe.path) {
      final exeFile = File(exePath);
      exeFile.copySync(targetExe.path);
      print('✅ zup.exe ko\'chirildi');
    }

    // 3. VERSION faylini yozish
    final versionFile = File('${installDir.path}\\VERSION');
    versionFile.writeAsStringSync(currentVersion);

    // 4. PATH ga qo'shish
    print('🔧 PATH ga qo\'shilmoqda...');

    final installPathForPs = installDir.path.replaceAll('/', '\\');

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

    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psScript],
      runInShell: true,
    );

    final output = result.stdout.toString().trim();

    if (output.startsWith('ERROR:')) {
      print('❌ PATH ga qo\'shib bo\'lmadi');
      print('   Xato: ${output.substring(6)}');
      print('');
      print('⚠️  zup.exe ko\'chirildi, lekin PATH ga qo\'shilmadi.');
      print('   Qo\'lda qo\'shing: ${installDir.path}');
      print('');
      return 1;
    } else if (output == 'OK') {
      print('✅ PATH ga qo\'shildi!');
    } else if (output == 'ALREADY') {
      print('ℹ️  PATH da allaqachon mavjud');
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
