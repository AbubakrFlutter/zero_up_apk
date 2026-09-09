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
} = require('../node/build.js');

const menu = require('../node/menu.js');
const cfg = require('../node/config.js');
const { buildMainMenu } = require('../node/actions.js');
const { classify } = require('../node/args.js');

const PACKAGE_NAME = 'zero_up_apk';
const currentVersion = require('../package.json').version;
const c = menu.colors;

/// Windows binary ni bloklagani aniqlangach shu belgi qo'yiladi — keyingi
/// safar behuda urinib o'tirmaymiz.
const blockedMarker = path.join(zupDir, 'binary-blocked');

// Terminalni har qanday chiqishda tiklaymiz — Ctrl+C, xato, oddiy chiqish.
menu.installTerminalGuard();

const argv = process.argv.slice(2);

main();

async function main() {
  const a = classify(argv);

  // 1) `zup update` — Node bajaradi, chunki yangilash zup.exe ni qayta
  //    yasaydi, Windows esa ishlab turgan .exe ni almashtirishga ruxsat
  //    bermaydi. `classify` uni argv ning istalgan joyidan topadi —
  //    ilgari faqat yolg'iz kelganda ushlanardi va `zup update apk`
  //    yig'ishga tushib ketardi.
  if (a.command === 'update') {
    update();
    return;
  }

  // 2) Binary versiyasi paket versiyasiga mos kelmasa — qayta yasaymiz.
  //    Aks holda eski binary yangi buyruqlarga javob beraveradi.
  ensureBinaryFresh();

  // 3) Buyruq so'zi yo'q.
  if (a.command === null && !a.flags.help && !a.flags.version) {
    if (!menu.isInteractive()) {
      // Terminal yo'q — Dart aniq xato bersin (chiqish kodi 64).
      runWith(a.argv);
      return;
    }

    const chosen = await menuSession(mainMenuLoop);
    if (chosen === null) return; // foydalanuvchi chiqdi

    // Foydalanuvchi bergan bayroqlarni SAQLAYMIZ: `zup --clean` →
    // menyudan "APK" tanlansa → `apk --clean`.
    runWith([...chosen, ...a.argv]);
    return;
  }

  // 4) `zup config` (qo'shimcha so'z va bayroqsiz) — sozlamalar menyusi.
  //    `zup config --out ...` va `zup config reset` Dart tomonida.
  if (
    a.command === 'config' &&
    a.commandArgs.length === 0 &&
    a.argv.length === 1 &&
    menu.isInteractive()
  ) {
    await menuSession(configLoop);
    return;
  }

  runWith(a.argv);
}

/**
 * O'rnatilgan binary paket versiyasiga mos keladimi?
 *
 * NEGA KERAK: `postinstall` `~/.zup/VERSION` yozadi, lekin uni hech kim
 * o'qimasdi. Agar o'rnatish paytida kompilyatsiya yiqilsa (Dart hali yo'q,
 * yoki exe ishlab turgan zup tomonidan qulflangan), ESKI binary yangi
 * buyruqlarga javob beraverardi. 2.0 da bu — agent JSON o'rniga o'zbekcha
 * matn oladi.
 */
function ensureBinaryFresh() {
  try {
    if (!fs.existsSync(targetPath)) return; // yo'q bo'lsa keyin yasaladi

    const versionFile = path.join(zupDir, 'VERSION');
    const installed = fs.existsSync(versionFile)
      ? fs.readFileSync(versionFile, 'utf8').trim()
      : null;

    if (installed === currentVersion) return;

    const dart = findDart();
    if (!dart) return; // Dart yo'q — eski binary bilan davom etamiz

    console.error(
      `zup yangilandi (${installed ?? 'noma\'lum'} → ${currentVersion}), qayta yasalmoqda...`,
    );
    if (buildBinary(dart, { log: (m) => console.error(m) })) {
      fs.writeFileSync(versionFile, currentVersion);
    }
  } catch (_) {
    // Tekshiruv tufayli zup ishdan chiqmasligi kerak.
  }
}

// ─────────────────────────────  ASOSIY MENYU  ─────────────────────────────

/**
 * Menyuni "alternativ ekran"da ishga tushiradi.
 *
 * Shu tufayli menyu terminal tarixini surib yubormaydi — `vim` va `less`
 * kabi vaqtincha ekranni egallaydi, chiqqanda avvalgi holat qaytadi.
 *
 * Yig'ish buyrug'i tanlansa, alternativ ekrandan CHIQIB, keyin yig'iladi —
 * yig'ish natijasi terminal tarixida qolishi kerak.
 */
async function menuSession(loop) {
  menu.enterAltScreen();
  try {
    return await loop();
  } finally {
    menu.restoreTerminal();
  }
}

/**
 * Asosiy menyu halqasi.
 *
 * Yordam yoki sozlamalardan keyin menyuga QAYTADI — ilgari CLI butunlay
 * chiqib ketardi. Faqat yig'ish tanlansa yoki "Chiqish" bosilsa tugaydi.
 */
async function mainMenuLoop() {
  for (;;) {
    menu.clearScreen();

    const config = cfg.load();
    const project = readProject(process.cwd());

    // Ixcham sarlavha: to'liq banner + holat jadvali 13 qator edi va menyu
    // bilan birga oynaga sig'masdi.
    compactHeader(project, config);

    const { items, actions, buildable } = buildMainMenu(project);
    const picked = await menu.select({ title: 'Nima qilamiz?', items });

    if (picked === null) return null; // q yoki Ctrl+C

    const action = actions[picked];

    switch (action.type) {
      case 'exit':
        return null;

      case 'config':
        await configLoop();
        continue; // menyuga qaytamiz

      case 'build':
        if (!buildable) {
          console.log('');
          explainNotBuildable(project);
          await menu.pressAnyKey('Menyuga qaytish uchun tugma bosing...');
          continue;
        }
        return action.args; // alternativ ekrandan chiqib yig'amiz

      case 'passthrough': {
        // Yordam uzun — SAHIFALAB ko'rsatamiz. Oddiy chiqarilsa terminal
        // darhol eng pastga tushib qolardi va matnning boshi ko'rinmasdi.
        const text = await runAndCapture(action.args);
        await menu.pager(text, { title: '' });
        continue;
      }

      default:
        return null;
    }
  }
}

/**
 * Menyu uchun ixcham sarlavha — 3 qator.
 *
 * To'liq banner (6 qator) + holat jadvali (7 qator) menyu bilan qo'shilib
 * 25 qator bo'lardi va oddiy terminal oynasiga sig'masdi.
 */
function compactHeader(project, config) {
  console.log('');
  console.log(
    `  ${c.bold(c.magenta('⚡ ZERO UP APK'))} ${c.grey(`v${currentVersion}`)}`,
  );

  if (!project) {
    console.log(`  ${c.grey("Loyiha topilmadi — bu papkada pubspec.yaml yo'q")}`);
  } else {
    const version = project.version ? ` ${c.grey(`· ${project.version}`)}` : '';
    console.log(`  ${project.name}${version}`);
    if (!project.hasAndroid) {
      console.log(`  ${c.grey("'android' papkasi yo'q — APK yig'ib bo'lmaydi")}`);
    }
  }

  console.log(
    `  ${c.grey('Fayllar tushadi:')} ${config.out || 'Ish stoli (Desktop)'}`,
  );
  console.log('');
}

/** pubspec.yaml dan ilova nomi va versiyasini oladi (oddiy o'qish). */
function readProject(dir) {
  const pubspec = path.join(dir, 'pubspec.yaml');
  try {
    if (!fs.existsSync(pubspec)) return null;
    const text = fs.readFileSync(pubspec, 'utf8');

    const nameMatch = text.match(/^name:\s*(.+)$/m);
    const versionMatch = text.match(/^version:\s*(.+)$/m);

    return {
      name: nameMatch ? nameMatch[1].trim() : path.basename(dir),
      version: versionMatch ? versionMatch[1].trim() : null,
      hasAndroid: fs.existsSync(path.join(dir, 'android')),
    };
  } catch (_) {
    return null;
  }
}

function explainNotBuildable(project) {
  if (!project) {
    console.log(`  ${c.red('✖')} Bu papkada Flutter loyihasi topilmadi.`);
    console.log(`    ${c.grey(process.cwd())}`);
    console.log('');
    console.log("    Flutter loyihangizga kiring va qaytadan urinib ko'ring:");
    console.log(`      ${c.cyan('cd C:\\mening_loyiham')}`);
    console.log(`      ${c.cyan('zup')}`);
  } else {
    console.log(
      `  ${c.red('✖')} Loyihada 'android' papkasi yo'q — APK yig'ib bo'lmaydi.`,
    );
  }
  console.log('');
}

// ─────────────────────────────  SOZLAMALAR  ─────────────────────────────

/**
 * Sozlamalar halqasi — bir necha sozlamani ketma-ket o'zgartirish mumkin.
 * "Chiqish" bosilganda asosiy menyuga qaytadi.
 */
async function configLoop() {
  for (;;) {
    screenHeader('sozlamalar');

    const done = await configMenu();
    if (done) return;
  }
}

/**
 * Ekranni tozalab, sarlavha chizadi.
 *
 * HAR BIR menyu (pastki menyular ham) buni chaqirishi shart — aks holda
 * yangi menyu eskisining ustiga qo'shilib chiqadi va ikkitasi birga
 * ko'rinib qoladi.
 */
function screenHeader(subtitle) {
  menu.clearScreen();
  console.log('');
  console.log(
    `  ${c.bold(c.magenta('⚡ ZERO UP APK'))} ${c.grey(`· ${subtitle}`)}`,
  );
  console.log('');
}

/** Bitta sozlama qadamini bajaradi. `true` qaytarsa — chiqish. */
async function configMenu() {
  const config = cfg.load();

  // Hozirgi holat menyudagi izohlarda ko'rinadi ("hozir: ha"), shuning
  // uchun alohida jadval chizmaymiz — ekranga sig'ishi muhimroq.
  const picked = await menu.select({
    title: "Nimani o'zgartiramiz?",
    items: [
      {
        label: 'Fayllar tushadigan papka',
        hint: config.out || 'hozir: Ish stoli',
      },
      {
        label: 'Tugagach papkani avtomatik ochish',
        hint: config.open ? 'hozir: ha' : "hozir: yo'q",
      },
      {
        label: "Doim faqat arm64 yig'ish",
        hint: config.arm64 ? 'hozir: ha' : "hozir: yo'q",
      },
      { label: 'Hammasini standart holatga qaytarish', separatorBefore: true },
      { label: 'Chiqish' },
    ],
  });
  console.log('');

  // null (q / Ctrl+C) yoki "Chiqish" — sozlamalardan chiqamiz.
  if (picked === null || picked === 4) return true;

  // Natija xabarlari uchun toza ekran — menyu ustiga yozilmasin.
  // (0-variant o'z ekranlarini o'zi boshqaradi.)
  if (picked !== 0) screenHeader('sozlamalar');

  switch (picked) {
    case 0:
      await chooseOutputDir(config);
      break;

    case 1: {
      const updated = { ...config, open: !config.open };
      saveAndReport(
        updated,
        updated.open
          ? "Endi yig'ish tugagach papka avtomatik ochiladi."
          : 'Endi papka avtomatik ochilmaydi.',
      );
      break;
    }

    case 2: {
      const updated = { ...config, arm64: !config.arm64 };
      saveAndReport(
        updated,
        updated.arm64
          ? "Endi doim faqat arm64 uchun yig'iladi (eng tez rejim)."
          : "Endi barcha protsessorlar uchun yig'iladi.",
      );
      break;
    }

    case 3: {
      const error = cfg.reset();
      if (error) {
        console.log(`  ${c.red('✖')} Tozalab bo'lmadi: ${error}`);
      } else {
        console.log(
          `  ${c.green('✔')} Sozlamalar tozalandi — hammasi standart holatga qaytdi.`,
        );
        console.log(`    ${c.grey('Fayllar yana ish stoliga (Desktop) tushadi.')}`);
      }
      break;
    }
  }

  await menu.pressAnyKey('Sozlamalarga qaytish uchun tugma bosing...');
  return false; // sozlamalar menyusiga qaytamiz
}

async function chooseOutputDir(config) {
  // Pastki menyu — ekranni tozalamasa, yuqoridagi sozlamalar menyusi
  // ekranda qolib, ikkitasi birga ko'rinadi.
  screenHeader('chiqish papkasi');

  const picked = await menu.select({
    title: 'Fayllar qayerga tushsin?',
    items: [
      { label: 'Ish stoli', hint: 'Desktop — standart' },
      { label: 'Boshqa papka', hint: "yo'lini yozasiz" },
      { label: 'Bekor qilish', separatorBefore: true },
    ],
  });
  console.log('');

  if (picked === null || picked === 2) {
    console.log('  Bekor qilindi.');
    console.log('');
    return;
  }

  if (picked === 0) {
    const updated = { ...config };
    delete updated.out;
    return saveAndReport(updated, 'Fayllar ish stoliga (Desktop) tushadi.');
  }

  // Yo'l so'rash uchun ham toza ekran — menyu ustiga yozilmasligi kerak.
  screenHeader('chiqish papkasi');
  console.log(`  ${c.grey('Masalan: D:\\APK  yoki  C:\\Users\\Ali\\Downloads')}`);
  console.log('');
  const answer = await menu.ask("Papka yo'li:");
  console.log('');

  const dir = cfg.cleanPath(answer);
  if (!dir) {
    console.log('  Bekor qilindi.');
    console.log('');
    return;
  }

  const error = cfg.validateDir(dir);
  if (error) {
    console.log(`  ${c.red('✖')} Bu papkaga yozib bo'lmaydi: ${dir}`);
    console.log(`    ${c.grey(`Sabab: ${error}`)}`);
    console.log('');
    return;
  }

  const absolute = path.resolve(dir);
  return saveAndReport(
    { ...config, out: absolute },
    `Saqlandi! Endi fayllar shu yerga tushadi:\n    ${absolute}`,
  );
}

function saveAndReport(config, message) {
  const error = cfg.save(config);
  if (error) {
    console.log(`  ${c.red('✖')} Saqlanmadi: ${error}`);
  } else {
    console.log(`  ${c.green('✔')} ${message}`);
  }
  console.log('');
}


/**
 * Dart'ga uzatiladigan muhit o'zgaruvchilari.
 *
 * Dart bu faktlarni O'ZI TO'G'RI BILA OLMAYDI:
 *   * stdin terminalmi — Dart faqat stdout ni tekshirardi, shu sababli
 *     `echo | zup` da "terminal bor" deb menyu ochib yuborardi
 *   * stdout quvurga yo'naltirilgani "terminal yo'q" degani emas —
 *     Node yordamni sahifalash uchun uni ataylab ushlab oladi
 *   * terminal kengligi — Node stdout ni ushlaganda Dart uni bilmaydi
 */
function dartEnv(extra) {
  return {
    ...process.env,
    ZUP_STDIN_TTY: process.stdin.isTTY ? '1' : '0',
    ZUP_STDOUT_TTY: process.stdout.isTTY ? '1' : '0',
    ZUP_COLUMNS: String(process.stdout.columns || 80),
    ZUP_FROM: 'node',
    ZUP_RUN_MODE:
      fs.existsSync(targetPath) && !isMarkedBlocked() ? 'binary' : 'source',
    ...(extra || {}),
  };
}
// ─────────────────────────  DART NI ISHGA TUSHIRISH  ─────────────────────────

/**
 * Dart'ni ishga tushirib, chiqishini MATN sifatida qaytaradi.
 *
 * Sahifalab ko'rsatish uchun kerak: matnni oldin to'liq olib, keyin
 * ekranga sig'adigan qismlarga bo'lib chiqaramiz.
 */
function runAndCapture(args) {
  return new Promise((resolve) => {
    const dart = findDart();
    const useBinary = fs.existsSync(targetPath) && !isMarkedBlocked();

    const collect = (cmd, cmdArgs) =>
      new Promise((done) => {
        let out = '';
        let child;
        try {
          child = spawn(cmd, cmdArgs, {
            stdio: ['ignore', 'pipe', 'pipe'],
            // Sahifalovchi rangli matnni ko'rsata oladi, shuning uchun
            // Dart'ga "terminal bor" deb bildiramiz.
            env: dartEnv({ ZUP_STDOUT_TTY: '1' }),
          });
        } catch (err) {
          return done({ text: '', failed: true });
        }
        child.stdout.on('data', (d) => {
          out += d.toString();
        });
        child.stderr.on('data', (d) => {
          out += d.toString();
        });
        child.on('exit', () => done({ text: out, failed: false }));
        child.on('error', () => done({ text: out, failed: true }));
        return undefined;
      });

    const viaDart = () => {
      if (!dart) return resolve('Dart SDK topilmadi.');
      ensureDeps(dart);
      const absoluteEntry = path.join(packageRoot, entryPoint);
      collect(dart, ['run', absoluteEntry, ...args]).then((r) =>
        resolve(r.text),
      );
    };

    if (useBinary) {
      collect(targetPath, args).then((r) => {
        // Windows bloklagan bo'lsa — manba koddan qayta urinamiz.
        if (r.failed && dart) {
          markBlocked();
          viaDart();
        } else {
          resolve(r.text);
        }
      });
      return;
    }

    viaDart();
  });
}

function runViaDartAndWait(args, dart) {
  return new Promise((resolve) => {
    ensureDeps(dart);
    const absoluteEntry = path.join(packageRoot, entryPoint);
    const child = spawn(dart, ['run', absoluteEntry, ...args], {
    stdio: 'inherit',
    env: dartEnv(),
  });
    child.on('exit', () => resolve());
    child.on('error', () => resolve());
  });
}

function printNoDart() {
  console.error('❌ Dart SDK topilmadi.');
  console.error('');
  console.error("   zup Flutter loyihalarini yig'adi — sizda Flutter");
  console.error("   bo'lishi kerak. Dart Flutter bilan birga keladi.");
  console.error('');
  console.error('   https://docs.flutter.dev/get-started/install');
  console.error('');
}

function runWith(args) {
  const dart = findDart();

  // Tezkor yo'l: kompilyatsiya qilingan binary.
  if (!fs.existsSync(targetPath) && !isMarkedBlocked() && dart) {
    console.log('');
    console.log('🔨 zup birinchi marta ishga tushmoqda — tayyorlanmoqda...');
    console.log('');
    buildBinary(dart, { log: console.log });
    console.log('');
  }

  if (fs.existsSync(targetPath) && !isMarkedBlocked()) {
    spawnBinary(args, dart);
    return;
  }

  runViaDart(args, dart);
}

function spawnBinary(args, dart) {
  // Windows Smart App Control imzolanmagan .exe ni bloklashi mumkin. Bunda
  // spawn() 'error' hodisasini KUTMASDAN o'sha zahoti istisno tashlaydi
  // ("spawn UNKNOWN") — shuning uchun try/catch ham kerak.
  let child;
  try {
    // shell ISHLATILMAYDI: u argumentlarni qalqonlamasdan qo'shib yuboradi,
    // ya'ni bo'sh joyli yo'llar buziladi (--out "D:\Mening APK").
    child = spawn(targetPath, args, { stdio: 'inherit', env: dartEnv() });
  } catch (err) {
    handleSpawnFailure(err, args, dart);
    return;
  }

  child.on('exit', (code, signal) => {
    if (signal) process.exit(1);
    process.exit(code === null ? 0 : code);
  });

  child.on('error', (err) => handleSpawnFailure(err, args, dart));
}

function handleSpawnFailure(err, args, dart) {
  const blocked =
    err.code === 'UNKNOWN' || err.code === 'EACCES' || err.code === 'EPERM';

  if (blocked && dart) {
    markBlocked();
    runViaDart(args, dart);
    return;
  }

  console.error(`❌ Xato: ${err.message}`);
  process.exit(1);
}

/**
 * Manba koddan ishga tushirish — binary bloklanganda yoki yasab
 * bo'lmaganda. Biroz sekinroq, lekin har doim ishlaydi.
 */
function runViaDart(args, dart) {
  if (!dart) {
    printNoDart();
    process.exit(1);
  }

  ensureDeps(dart);

  // MUHIM: cwd ni O'ZGARTIRMAYMIZ. zup joriy papkadagi Flutter loyihasini
  // qidiradi — cwd ni npm paketiga o'zgartirsak, u foydalanuvchi loyihasi
  // o'rniga npm papkasini "loyiha" deb qabul qiladi.
  const absoluteEntry = path.join(packageRoot, entryPoint);
  const child = spawn(dart, ['run', absoluteEntry, ...args], {
    stdio: 'inherit',
    env: dartEnv(),
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
        'zup manba koddan ishga tushmoqda — hammasi ishlaydi, faqat\n' +
        'boshlanishi bir necha soniya sekinroq.\n',
    );
    if (fs.existsSync(targetPath)) fs.unlinkSync(targetPath);
  } catch (_) {}
}

// ─────────────────────────────  YANGILASH  ─────────────────────────────

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
  const child = spawn('npm', ['install', '-g', `${PACKAGE_NAME}@latest`], {
    stdio: 'inherit',
    shell: platform === 'win32',
  });

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
    if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) > (b[i] || 0);
  }
  return false;
}

function banner() {
  const bar = '─'.repeat(58);
  console.log('');
  console.log(`  ${c.cyan(bar)}`);
  console.log(
    `  ${c.bold(c.magenta('⚡ ZERO UP APK'))}  ${c.grey(`v${currentVersion}`)}`,
  );
  console.log(`  ${c.grey("Flutter APK / App Bundle tezkor yig'uvchi")}`);
  console.log(`  ${c.cyan(bar)}`);
  console.log('');
}
