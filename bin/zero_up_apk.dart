import 'dart:io';

import 'package:zero_up_apk/zero_up_apk.dart';

/// Versiyaning yagona manbasi — lib/src/cli.dart dagi zeroUpApkVersion.
const currentVersion = zeroUpApkVersion;

/// Dart kirish nuqtasi — YIG'ISH DVIGATELI.
///
/// Bu yerda menyu, savol yoki fonda ishlaydigan chiqish YO'Q:
///   * Interaktiv UI faqat Node tomonida (`node/menu.js`)
///   * `zup update` ni Node bajaradi (Windows ishlab turgan .exe ni
///     almashtirishga ruxsat bermaydi)
///   * Fonda yangilanish tekshiruvi olib tashlandi — u `print()` bilan
///     stdout'ga yozib, jonli progress bar ustiga tushardi va JSON
///     chiqishini buzardi
Future<void> main(List<String> args) async {
  // Binary to'g'ridan-to'g'ri `zup.exe update` deb chaqirilgan holat.
  if (args.isNotEmpty && (args[0] == 'update' || args[0] == '--update')) {
    await _showUpdateInfo();
    return;
  }

  // Argumentsiz — qisqa yo'riqnoma. MENYU OCHILMAYDI.
  if (args.isEmpty) {
    _showQuickHelp();
    // Terminal bo'lsa foydalanuvchi ko'rmoqchi bo'lgan — xato emas.
    // Terminal bo'lmasa (quvurdan chaqirilgan) — buyruq berilmagan, xato.
    exitCode = stdout.hasTerminal ? 0 : 64;
    return;
  }

  exitCode = await ZeroUpApkCli().run(args);
}

void _showQuickHelp() {
  final ui = Ui();
  ui.banner(zeroUpApkVersion);
  ui.line('  ${ui.bold("TEZ BOSHLASH")}');
  ui.line();
  ui.line('    ${ui.cyan("zup apk")}          ${ui.grey("APK yig'ish")}');
  ui.line('    ${ui.cyan("zup apk --arm64")}  ${ui.grey("eng tez rejim")}');
  ui.line('    ${ui.cyan("zup aab")}          ${ui.grey("Google Play uchun")}');
  ui.line('    ${ui.cyan("zup config")}       ${ui.grey("fayllar qayerga tushsin")}');
  ui.line('    ${ui.cyan("zup --help")}       ${ui.grey("to'liq yordam")}');
  ui.line();
}

/// Binary to'g'ridan-to'g'ri `zup.exe update` deb chaqirilganda.
///
/// Yangilashning o'zini Node bajaradi — bu yerda faqat holat ko'rsatiladi.
Future<void> _showUpdateInfo() async {
  final ui = Ui();
  ui.banner(zeroUpApkVersion);
  ui.step('Yangi versiya qidirilmoqda...');

  final checker = UpdateChecker(currentVersion: currentVersion);
  final latest = await checker.fetchLatestVersion();

  ui.line();
  if (latest == null) {
    ui.warn("npm ga ulanib bo'lmadi.");
    ui.detail("Internet aloqasini tekshirib, qaytadan urinib ko'ring.");
    ui.detail('Hozirgi versiya: $currentVersion');
    ui.line();
    exitCode = 1;
    return;
  }

  if (!isNewerVersion(latest, currentVersion)) {
    ui.ok("Siz allaqachon eng so'nggi versiyadasiz ($currentVersion)");
    ui.line();
    return;
  }

  ui.step('Yangi versiya mavjud: $latest');
  ui.line();
  ui.detail('Yangilash uchun:  zup update');
  ui.line();
}
