'use strict';

/**
 * zup binary sini foydalanuvchi kompyuterida yasash.
 *
 * Bu modulni ikki joy ishlatadi:
 *   - install.js  — npm o'rnatilganda
 *   - bin/zup.js  — binary yo'q bo'lsa, ishga tushganda o'zi yasab oladi
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const platform = os.platform();
const homeDir = os.homedir();

const zupDir = path.join(homeDir, '.zup');
const binaryName = platform === 'win32' ? 'zup.exe' : 'zup';
const targetPath = path.join(zupDir, binaryName);

/// Paket ildizi — bu fayl `node/` ichida, shuning uchun bir daraja yuqori.
///
/// DIQQAT: bu `dart pub get` ishlaydigan papka va `bin/zero_up_apk.dart`
/// yo'li shundan hisoblanadi. `__dirname` deb qoldirilsa kompilyatsiya
/// `node/` papkasida ishlashga urinadi va buziladi.
const packageRoot = path.resolve(__dirname, '..');

/** Dart kirish nuqtasi (paket ildizidan nisbatan). */
const entryPoint = path.join('bin', 'zero_up_apk.dart');

function exeName(name) {
  return platform === 'win32' ? `${name}.exe` : name;
}

/** `where` / `which` natijalari. */
function whichAll(name) {
  try {
    const cmd = platform === 'win32' ? 'where' : 'which';
    const r = spawnSync(cmd, [name], { encoding: 'utf8' });
    if (r.status !== 0 || !r.stdout) return [];
    return r.stdout.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
  } catch (_) {
    return [];
  }
}

/** Shu yo'ldagi dart haqiqatan ishlaydimi? */
function works(dartPath) {
  try {
    const r = spawnSync(dartPath, ['--version'], { encoding: 'utf8' });
    return r.status === 0;
  } catch (_) {
    return false;
  }
}

/**
 * Dart SDK ni topadi, topilmasa `null`.
 *
 * Haqiqiy `dart.exe` afzal ko'riladi: PATH dagi `dart` Windows'da ko'pincha
 * `flutter\bin\dart.bat` bo'ladi, .bat ni esa faqat shell orqali ishga
 * tushirish mumkin — shell bo'lsa argumentlar qalqonlanmaydi va bo'sh joyli
 * yo'llar buziladi.
 */
function findDart() {
  const candidates = [];

  for (const p of whichAll('dart')) {
    if (platform === 'win32' && p.toLowerCase().endsWith('.bat')) {
      // flutter\bin\dart.bat -> flutter\bin\cache\dart-sdk\bin\dart.exe
      candidates.push(
        path.join(path.dirname(p), 'cache', 'dart-sdk', 'bin', 'dart.exe'),
      );
    } else {
      candidates.push(p);
    }
  }

  for (const f of whichAll('flutter')) {
    candidates.push(
      path.join(path.dirname(f), 'cache', 'dart-sdk', 'bin', exeName('dart')),
    );
  }

  const guesses = platform === 'win32'
    ? [
        'C:\\src\\flutter',
        'C:\\flutter',
        path.join(homeDir, 'flutter'),
        process.env.LOCALAPPDATA
          ? path.join(process.env.LOCALAPPDATA, 'flutter')
          : null,
      ]
    : [
        '/opt/flutter',
        '/usr/local/flutter',
        path.join(homeDir, 'flutter'),
        path.join(homeDir, 'development', 'flutter'),
      ];

  for (const g of guesses) {
    if (!g) continue;
    candidates.push(
      path.join(g, 'bin', 'cache', 'dart-sdk', 'bin', exeName('dart')),
    );
  }

  for (const c of candidates) {
    if (c && fs.existsSync(c) && works(c)) return c;
  }

  // Oxirgi chora — PATH dagi nomning o'zi.
  if (works('dart')) return 'dart';

  return null;
}

function run(cmd, args, log) {
  const r = spawnSync(cmd, args, {
    cwd: packageRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  if (r.status === 0) return true;
  const err = (r.stderr || r.stdout || '').trim();
  if (err && log) {
    log('');
    log(err.split('\n').slice(0, 12).join('\n'));
  }
  return false;
}

/**
 * `dart run` ishlashi uchun paketlar hal qilingan bo'lishi kerak.
 * Allaqachon qilingan bo'lsa tegmaymiz — har safar 3-4 soniya yo'qotmaslik
 * uchun.
 */
function ensureDeps(dart, log = () => {}) {
  const marker = path.join(packageRoot, '.dart_tool', 'package_config.json');
  if (fs.existsSync(marker)) return true;

  log('📦 Paketlar yuklanmoqda (bir marta)...');
  return run(dart, ['pub', 'get'], log);
}

/**
 * `dart pub get` + `dart compile exe` bajaradi va binary ni joyiga qo'yadi.
 * Muvaffaqiyatli bo'lsa `true`.
 */
function buildBinary(dart, { log = () => {} } = {}) {
  try {
    fs.mkdirSync(zupDir, { recursive: true });
  } catch (e) {
    log(`❌ ${zupDir} papkasini yaratib bo'lmadi: ${e.message}`);
    return false;
  }

  log('📦 Paketlar yuklanmoqda (dart pub get)...');
  if (!run(dart, ['pub', 'get'], log)) return false;

  log('⚙️  Kompilyatsiya qilinmoqda (bir marta, ~10 soniya)...');

  // Ishlab turgan .exe ni Windows qulflaydi va uning ustiga yozib bo'lmaydi.
  // Shuning uchun avval yonidagi vaqtinchalik faylga yasab, keyin almashtiramiz.
  const tmpPath = `${targetPath}.new`;
  try {
    if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
  } catch (_) {}

  if (!run(dart, ['compile', 'exe', entryPoint, '-o', tmpPath], log)) {
    return false;
  }

  try {
    if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
    fs.renameSync(tmpPath, targetPath);
    if (platform !== 'win32') fs.chmodSync(targetPath, 0o755);
  } catch (e) {
    log(`❌ Faylni joyiga qo'yib bo'lmadi: ${e.message}`);
    log("   Ochiq turgan zup jarayonini yoping va qaytadan urining.");
    try {
      if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath);
    } catch (_) {}
    return false;
  }

  log(`✅ Tayyor: ${targetPath}`);
  return true;
}

module.exports = {
  findDart,
  buildBinary,
  ensureDeps,
  entryPoint,
  zupDir,
  targetPath,
  platform,
  packageRoot,
};
