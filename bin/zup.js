#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');
const { spawn } = require('child_process');

const {
  findDart,
  buildBinary,
  ensureDeps,
  entryPoint,
  packageRoot,
  targetPath,
  zupDir,
  platform,
} = require('../zup-build.js');

const PACKAGE_NAME = 'zero_up_apk';
const currentVersion = require('../package.json').version;

/// Windows binary ni bloklagani aniqlangach shu belgi qo'yiladi — keyingi
/// safar behuda urinib o'tirmaymiz.
const blockedMarker = path.join(zupDir, 'binary-blocked');

const args = process.argv.slice(2);

// `zup update` ni AYNAN SHU YERDA bajaramiz — Dart binary sida emas.
//
// Sabab: yangilash zup.exe ni qayta yasaydi, lekin Windows ishlab turgan
// .exe ni almashtirishga ruxsat bermaydi. Node qismi esa uni ushlab turmaydi.
if (args.length === 1 && (args[0] === 'update' || args[0] === '--update')) {
  update();
} else {
  run();
}

function run() {
  const dart = findDart();

  // Tezkor yo'l: kompilyatsiya qilingan binary.
  // U yo'q bo'lsa va Windows ilgari bloklamagan bo'lsa — yasab ko'ramiz.
  if (!fs.existsSync(targetPath) && !isMarkedBlocked() && dart) {
    console.log('');
    console.log('🔨 zup birinchi marta ishga tushmoqda — tayyorlanmoqda...');
    console.log('');
    buildBinary(dart, { log: console.log });
    console.log('');
  }

  if (fs.existsSync(targetPath) && !isMarkedBlocked()) {
    spawnBinary(dart);
    return;
  }

  runViaDart(dart);
}

/** Kompilyatsiya qilingan binary ni ishga tushiradi. */
function spawnBinary(dart) {
  // Windows Smart App Control imzolanmagan .exe ni bloklashi mumkin.
  // Bunda spawn() 'error' hodisasini KUTMASDAN, o'sha zahoti istisno
  // tashlaydi ("spawn UNKNOWN") — shuning uchun try/catch ham kerak,
  // faqat child.on('error') yetarli emas.
  let child;
  try {
    // shell ISHLATILMAYDI: u argumentlarni qalqonlamasdan qo'shib yuboradi,
    // ya'ni bo'sh joyli yo'llar buziladi (--out "D:\Mening APK").
    child = spawn(targetPath, args, { stdio: 'inherit' });
  } catch (err) {
    handleSpawnFailure(err, dart);
    return;
  }

  child.on('exit', (code, signal) => {
    if (signal) process.exit(1);
    process.exit(code === null ? 0 : code);
  });

  child.on('error', (err) => handleSpawnFailure(err, dart));
}

/**
 * Binary ni ishga tushirib bo'lmadi. Windows bloklagan bo'lsa — dastur
 * ishdan chiqmaydi, manba koddan ishga tushiramiz (Dart VM bloklanmaydi).
 */
function handleSpawnFailure(err, dart) {
  const blocked =
    err.code === 'UNKNOWN' || err.code === 'EACCES' || err.code === 'EPERM';

  if (blocked && dart) {
    markBlocked();
    runViaDart(dart);
    return;
  }

  console.error(`❌ Xato: ${err.message}`);
  process.exit(1);
}

/**
 * Manba koddan ishga tushirish — kompilyatsiya qilingan fayl bloklanganda
 * yoki uni yasab bo'lmaganda. Biroz sekinroq, lekin har doim ishlaydi.
 */
function runViaDart(dart) {
  if (!dart) {
    console.error('❌ Dart SDK topilmadi.');
    console.error('');
    console.error("   zup Flutter loyihalarini yig'adi — sizda Flutter");
    console.error("   bo'lishi kerak. Dart Flutter bilan birga keladi.");
    console.error('');
    console.error('   https://docs.flutter.dev/get-started/install');
    console.error('');
    process.exit(1);
  }

  ensureDeps(dart);

  // MUHIM: cwd ni O'ZGARTIRMAYMIZ. zup joriy papkadagi Flutter loyihasini
  // qidiradi — agar bu yerda cwd ni npm paketiga o'zgartirsak, u foydalanuvchi
  // loyihasi o'rniga npm papkasini "loyiha" deb qabul qiladi.
  //
  // Dart kirish faylining yonidan .dart_tool/package_config.json ni o'zi
  // topadi, shuning uchun to'liq yo'l berish kifoya.
  const absoluteEntry = path.join(packageRoot, entryPoint);
  const child = spawn(dart, ['run', absoluteEntry, ...args], {
    stdio: 'inherit',
  });

  child.on('exit', (code, signal) => {
    if (signal) process.exit(1);
    process.exit(code === null ? 0 : code);
  });

  child.on('error', (err) => {
    console.error(`❌ zup ni ishga tushirib bo'lmadi: ${err.message}`);
    process.exit(1);
  });
}

function isMarkedBlocked() {
  try {
    return fs.existsSync(blockedMarker);
  } catch (_) {
    return false;
  }
}

function markBlocked() {
  try {
    fs.mkdirSync(zupDir, { recursive: true });
    fs.writeFileSync(
      blockedMarker,
      'Windows Smart App Control kompilyatsiya qilingan zup.exe ni bloklagan.\n' +
        "zup manba koddan ishga tushmoqda — hammasi ishlaydi, faqat\n" +
        'boshlanishi bir necha soniya sekinroq.\n',
    );
    // Bloklangan faylni saqlab o'tirishning ma'nosi yo'q.
    if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
  } catch (_) {}
}

function update() {
  banner();
  console.log('🔍 Yangi versiya qidirilmoqda...');

  fetchLatestVersion((latest) => {
    if (!latest) {
      console.log('');
      console.log("⚠️  npm ga ulanib bo'lmadi.");
      console.log("   Internet aloqasini tekshirib, qaytadan urinib ko'ring.");
      console.log('');
      console.log(`📦 Hozirgi versiya: ${currentVersion}`);
      console.log('');
      process.exit(1);
    }

    if (!isNewer(latest, currentVersion)) {
      console.log('');
      console.log(`✅ Siz allaqachon eng so'nggi versiyadasiz (${currentVersion})`);
      console.log('');
      process.exit(0);
    }

    console.log(`📦 Yangi versiya topildi: ${latest}`);
    console.log('');
    console.log('⬇️  Yangilanmoqda...');
    console.log('');

    // Eski belgini olib tashlaymiz — yangi versiyada qayta sinab ko'riladi.
    try {
      if (fs.existsSync(blockedMarker)) fs.unlinkSync(blockedMarker);
    } catch (_) {}

    runNpmInstall((ok) => {
      console.log('');
      if (!ok) {
        console.log("❌ Yangilab bo'lmadi.");
        console.log('');
        console.log("   Qo'lda urinib ko'ring:");
        console.log(`   npm install -g ${PACKAGE_NAME}@latest`);
        console.log('');
        process.exit(1);
      }
      console.log('╔══════════════════════════════════════════════════════════════╗');
      console.log("║              ✅ YANGILASH MUVAFFAQIYATLI!                   ║");
      console.log('╚══════════════════════════════════════════════════════════════╝');
      console.log('');
      console.log(`   ${currentVersion} → ${latest}`);
      console.log('');
      process.exit(0);
    });
  });
}

/** npm registry dan oxirgi versiyani oladi. */
function fetchLatestVersion(callback) {
  const req = https.get(
    `https://registry.npmjs.org/${PACKAGE_NAME}/latest`,
    { headers: { accept: 'application/json' }, timeout: 10000 },
    (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        return callback(null);
      }
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        body += chunk;
      });
      res.on('end', () => {
        try {
          const version = JSON.parse(body).version;
          callback(typeof version === 'string' ? version : null);
        } catch (_) {
          callback(null);
        }
      });
    },
  );

  req.on('timeout', () => req.destroy());
  req.on('error', () => callback(null));
}

function runNpmInstall(callback) {
  // Windows'da npm — bu npm.cmd. Node 18.20+/20.12+ .cmd ni shell'siz ishga
  // tushirmaydi, shuning uchun bu yerda shell kerak. Argumentlar qat'iy
  // (foydalanuvchi kiritmaydi), ya'ni qalqonlash muammosi yo'q.
  const child = spawn(
    'npm',
    ['install', '-g', `${PACKAGE_NAME}@latest`],
    { stdio: 'inherit', shell: platform === 'win32' },
  );

  child.on('exit', (code) => callback(code === 0));
  child.on('error', () => callback(false));
}

/** Semantik solishtirish: candidate > current bo'lsa true. */
function isNewer(candidate, current) {
  const parse = (v) =>
    String(v)
      .trim()
      .replace(/^v/, '')
      .split(/[+-]/)[0]
      .split('.')
      .map((n) => parseInt(n, 10) || 0);

  const a = parse(candidate);
  const b = parse(current);
  const len = Math.max(a.length, b.length);

  for (let i = 0; i < len; i++) {
    const x = a[i] || 0;
    const y = b[i] || 0;
    if (x !== y) return x > y;
  }
  return false;
}

function banner() {
  console.log('');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║                    ⚡ Zero Up APK                           ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
}
