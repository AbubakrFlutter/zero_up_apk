import 'dart:io';

import 'package:zero_up_apk/zero_up_apk.dart';

/// Versiyaning yagona manbasi — lib/src/cli.dart dagi zeroUpApkVersion.
const currentVersion = zeroUpApkVersion;

Future<void> main(List<String> args) async {
  // `update` — bin/zup.js (Node qismi) bajaradi, chunki yangilash zup.exe ni
  // qayta yasaydi, Windows esa ishlab turgan .exe ni almashtirishga ruxsat
  // bermaydi. Bu yerga faqat binary to'g'ridan-to'g'ri chaqirilganda tushadi.
  if (args.isNotEmpty && (args[0] == 'update' || args[0] == '--update')) {
    await _showUpdateInfo();
    return;
  }

  // Argumentsiz — asosiy menyu.
  if (args.isEmpty) {
    exitCode = await ZeroUpApkCli().runMainMenu();
    return;
  }

  // Ma'lumot beruvchi buyruqlar (--version, --help) chiqishi toza va bir xil
  // bo'lishi kerak — fon tekshiruvi tarmoq tezligiga qarab ularning ustiga
  // xabar chiqarib yuborardi.
  if (!_isInfoCommand(args)) {
    _checkUpdateInBackground();
  }

  exitCode = await ZeroUpApkCli().run(args);
}

/// `--version` / `--help` kabi faqat ma'lumot chiqaradigan buyruqmi?
bool _isInfoCommand(List<String> args) {
  const infoFlags = {'--version', '-v', '--help', '-h'};
  return args.any(infoFlags.contains);
}

/// Fonda yangilanishni tekshirib, faqat yangisi bo'lsa xabar beradi.
void _checkUpdateInBackground() {
  Future(() async {
    try {
      final checker = UpdateChecker(currentVersion: currentVersion);
      final latest = await checker.fetchLatestVersion();

      if (latest != null && isNewerVersion(latest, currentVersion)) {
        print('');
        print('╭────────────────────────────────────────────────────────╮');
        print('│  💡 Yangi versiya mavjud!                              │');
        final row =
            '│     Hozirgi: $currentVersion → Yangi: $latest'.padRight(57);
        print('$row│');
        print('│                                                        │');
        print('│     Yangilash: zup update                              │');
        print('╰────────────────────────────────────────────────────────╯');
        print('');
      }
    } catch (_) {
      // Internet yo'q — jim o'tamiz.
    }
  });
}

/// Binary to'g'ridan-to'g'ri `zup.exe update` deb chaqirilganda.
Future<void> _showUpdateInfo() async {
  print('');
  print('╔══════════════════════════════════════════════════════════════╗');
  print('║                    ⚡ Zero Up APK                           ║');
  print('╚══════════════════════════════════════════════════════════════╝');
  print('');
  print('🔍 Yangi versiya qidirilmoqda...');

  final checker = UpdateChecker(currentVersion: currentVersion);
  final latest = await checker.fetchLatestVersion();

  print('');
  if (latest == null) {
    print('⚠️  npm ga ulanib bo\'lmadi.');
    print('   Internet aloqasini tekshirib, qaytadan urinib ko\'ring.');
    print('');
    print('📦 Hozirgi versiya: $currentVersion');
    print('');
    exitCode = 1;
    return;
  }

  if (!isNewerVersion(latest, currentVersion)) {
    print('✅ Siz allaqachon eng so\'nggi versiyadasiz ($currentVersion)');
    print('');
    return;
  }

  print('📦 Yangi versiya mavjud: $latest');
  print('');
  print('   Yangilash uchun quyidagini yozing:');
  print('');
  print('      zup update');
  print('');
}
