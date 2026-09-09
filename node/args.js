'use strict';

/**
 * Argumentlarni TASNIFLASH — sof mantiq, terminalsiz sinaladi.
 *
 * MUHIM XAVFSIZLIK XUSUSIYATI: bu modul faqat ikki narsani hal qiladi —
 * menyu ko'rsatilsinmi yoki argumentlar Dart'ga uzatilsinmi. U hech qachon
 * yig'ish argumentlarini O'ZI yasamaydi.
 *
 * Shu sababli Node xato tasniflasa, natija "keraksiz menyu" yoki "toza Dart
 * xatosi" bo'ladi — HECH QACHON "jim-jimgina noto'g'ri yig'ish" emas.
 * Dart argumentlarni noldan qayta parslaydi va yagona hakam bo'lib qoladi.
 */

/// Buyruq so'zlari. Dart tomonidagi `commandAliases` bilan MOS BO'LISHI SHART —
/// `test/node/args.test.js` ikkalasini solishtiradi.
const COMMANDS = new Set([
  'apk',
  'aab',
  'appbundle',
  'bundle',
  'hammasi',
  'both',
  'all',
  'ikkalasi',
  'config',
  'sozlama',
  'doctor',
  'tekshir',
  'last',
  'oxirgi',
  'info',
  'malumot',
  'devices',
  'qurilmalar',
  'install',
  'ornat',
  'restore-gradle',
  'help',
  'yordam',
  'version',
  // Node'ning o'zi bajaradigan buyruqlar:
  'update',
  'ai',
]);

/// Qiymat qabul qiladigan opsiyalar.
///
/// NEGA KERAK: `zup -p C:\loyiha apk` da `C:\loyiha` — bu buyruq emas,
/// `-p` ning qiymati. Buni bilmasak, uni buyruq deb o'ylab qolamiz.
const VALUE_OPTIONS = new Set([
  '-p',
  '--path',
  '-m',
  '--mode',
  '-o',
  '--out',
  '-t',
  '--target',
  '--flavor',
  '--dart-define',
  '--dart-define-from-file',
  '--build-name',
  '--build-number',
  '--extra',
  '--device',
]);

/**
 * `zup ai` / `-m ai` / `--mode ai` / `--mode=ai`  →  `--ai`
 *
 * `-m` allaqachon yig'ish rejimi uchun band (`release|profile|debug`),
 * shuning uchun AI ni o'sha ro'yxatga qo'shish ikki xil tushunchani bitta
 * joyga tiqish bo'lardi. O'rniga hammasi bitta `--ai` bayrog'iga
 * normallashtiriladi — parser umuman bilmaydi ham.
 *
 * `zup ai` yolg'iz kelsa — `--ai apk` ga aylanadi.
 */
function normalize(argv) {
  const out = [];
  let sawAi = false;
  let sawCommand = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    // `-m ai` yoki `--mode ai`
    if ((arg === '-m' || arg === '--mode') && argv[i + 1] === 'ai') {
      sawAi = true;
      i++; // qiymatni ham o'tkazib yuboramiz
      continue;
    }

    // `--mode=ai`
    if (arg === '--mode=ai' || arg === '-m=ai') {
      sawAi = true;
      continue;
    }

    // Birinchi pozitsion so'z sifatida `ai`
    if (arg === 'ai' && !arg.startsWith('-')) {
      sawAi = true;
      continue;
    }

    if (!arg.startsWith('-') && COMMANDS.has(arg.toLowerCase())) {
      sawCommand = true;
    }

    out.push(arg);
  }

  if (!sawAi) return out;

  // `zup ai` yolg'iz — standart maqsad APK.
  if (!sawCommand) out.push('apk');
  return ['--ai', ...out];
}

/**
 * argv ni tasniflaydi.
 *
 * Qaytaradi:
 *   command        — topilgan buyruq so'zi (kichik harfda) yoki null
 *   commandArgs    — buyruqdan keyingi pozitsion so'zlar
 *   flags          — Node uchun muhim bayroqlar
 *   argv           — normallashtirilgan argumentlar (Dart'ga uzatiladi)
 */
function classify(rawArgv) {
  const argv = normalize(rawArgv);

  let command = null;
  const commandArgs = [];
  const flags = {
    ai: false,
    json: false,
    help: false,
    version: false,
    install: false,
    device: null,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    if (arg === '--') {
      // Bundan keyingisi hammasi Dart'ga tegishli.
      break;
    }

    if (arg.startsWith('-')) {
      if (arg === '--ai') flags.ai = true;
      else if (arg === '--json') flags.json = true;
      else if (arg === '--help' || arg === '-h') flags.help = true;
      else if (arg === '--version' || arg === '-v') flags.version = true;
      else if (arg === '--install' || arg === '-i') flags.install = true;
      else if (arg.startsWith('--device=')) flags.device = arg.slice(9);
      else if (arg === '--device') flags.device = argv[i + 1] ?? null;

      // Qiymat qabul qiladigan opsiya bo'lsa — keyingi so'zni o'tkazamiz,
      // aks holda uni buyruq deb o'ylab qolamiz.
      if (VALUE_OPTIONS.has(arg)) i++;
      continue;
    }

    const lower = arg.toLowerCase();
    if (command === null && COMMANDS.has(lower)) {
      command = lower;
    } else {
      commandArgs.push(arg);
    }
  }

  return { command, commandArgs, flags, argv };
}

module.exports = { classify, normalize, COMMANDS, VALUE_OPTIONS };
