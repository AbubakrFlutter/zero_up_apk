#!/usr/bin/env node
'use strict';

/**
 * zero_up_apk o'rnatuvchisi.
 *
 * MUHIM: bu yerda tayyor .exe yuklab OLINMAYDI. Buning o'rniga zup
 * foydalanuvchining o'z kompyuterida kompilyatsiya qilinadi.
 *
 * Sabab: Windows 11 dagi Smart App Control internetdan kelgan imzolanmagan
 * .exe fayllarni ishga tushirishni taqiqlaydi ("spawn UNKNOWN" yoki
 * "An Application Control policy has blocked this file"). Mahalliy
 * kompilyatsiya qilingan fayl esa bloklanmaydi.
 *
 * Bu ishlaydi, chunki zup faqat Flutter loyihalari uchun kerak, Flutter esa
 * Dart SDK ni o'zi bilan olib keladi — ya'ni har bir foydalanuvchida Dart bor.
 */

const fs = require('fs');
const path = require('path');

const { findDart, buildBinary, zupDir, targetPath } = require('./build.js');

const VERSION = require('../package.json').version;

main();

function main() {
  banner();

  const dart = findDart();
  if (!dart) {
    warnNoDart();
    // npm install ni yiqitmaymiz: Flutter keyinroq o'rnatilsa, `zup`
    // ishga tushganda binary ni o'zi yasab oladi (bin/zup.js).
    process.exit(0);
  }

  console.log('🔨 zup kompyuteringizda yasalmoqda...');
  console.log(`   Dart: ${dart}`);
  console.log('');

  if (!buildBinary(dart, { log: console.log })) {
    console.log('');
    console.log("⚠️  Hozir yasab bo'lmadi.");
    console.log('   Muammo emas — birinchi marta "zup" yozganingizda');
    console.log('   qayta urinib ko\'riladi.');
    console.log('');
    process.exit(0);
  }

  try {
    fs.mkdirSync(zupDir, { recursive: true });
    fs.writeFileSync(path.join(zupDir, 'VERSION'), VERSION);
  } catch (_) {}

  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log("║              ✅ O'RNATISH MUVAFFAQIYATLI!                   ║");
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('📌 ISHLATISH:');
  console.log('');
  console.log('   zup                     # menyu');
  console.log('   zup apk --arm64         # APK yasash');
  console.log('   zup aab                 # App Bundle (Google Play)');
  console.log('   zup config              # fayllar qayerga tushsin');
  console.log('   zup update              # yangilash');
  console.log('');
  console.log("🚀 Flutter loyihangizga kiring va 'zup' yozing!");
  console.log('');
}

function warnNoDart() {
  console.log('⚠️  Dart SDK topilmadi.');
  console.log('');
  console.log("   zup Flutter loyihalarini yig'adi, ya'ni sizda Flutter");
  console.log('   bo\'lishi kerak. Dart Flutter bilan birga keladi —');
  console.log('   alohida o\'rnatish shart emas.');
  console.log('');
  console.log('   O\'rnatish: https://docs.flutter.dev/get-started/install');
  console.log('');
  console.log('   Flutter o\'rnatgach shunchaki "zup" yozing —');
  console.log('   qolganini o\'zi qiladi.');
  console.log('');
}

function banner() {
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║                    ⚡ Zero Up APK                           ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
}

