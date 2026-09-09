'use strict';

/**
 * Terminal menyusi — ↑↓ tugmalari bilan tanlash.
 *
 * NEGA NODE'DA: Windows konsoli strelka tugmalarini oddiy bayt sifatida
 * yubormaydi. Node (libuv) buni o'zi hal qiladi — konsol tugma hodisalarini
 * o'qib, ularni `ESC [ A` ko'rinishidagi ANSI ketma-ketligiga o'giradi.
 * Dart'da esa bu tarjima yo'q, shuning uchun menyu shu yerda.
 */

const readline = require('readline');

const ESC = '\u001b';

/** Ranglar — terminal qo'llab-quvvatlamasa bo'sh satr. */
function makeColors(enabled) {
  const wrap = (code) => (t) => (enabled ? `${code}${t}${ESC}[0m` : t);
  return {
    bold: wrap(`${ESC}[1m`),
    cyan: wrap(`${ESC}[38;5;80m`),
    grey: wrap(`${ESC}[38;5;245m`),
    green: wrap(`${ESC}[38;5;77m`),
    red: wrap(`${ESC}[38;5;203m`),
    magenta: wrap(`${ESC}[38;5;177m`),
  };
}

const colorsEnabled = Boolean(process.stdout.isTTY);
const c = makeColors(colorsEnabled);

function isInteractive() {
  return Boolean(process.stdin.isTTY && process.stdout.isTTY);
}

/**
 * "Alternativ ekran"ga o'tish — `vim` va `less` shunday ishlaydi.
 *
 * Menyu ekranni vaqtincha egallaydi va terminal tarixini (scrollback)
 * surib yubormaydi. Chiqqanda ekran avvalgi holatiga qaytadi.
 */
function enterAltScreen() {
  if (!colorsEnabled) return;
  process.stdout.write(`${ESC}[?1049h`);
}

/** Alternativ ekrandan chiqish. CHAQIRILISHI SHART — aks holda terminal
 *  menyu ekranida qolib ketadi. */
function leaveAltScreen() {
  if (!colorsEnabled) return;
  process.stdout.write(`${ESC}[?1049l`);
}

/** Ekranni tozalab, kursorni yuqoriga qo'yadi. */
function clearScreen() {
  if (!colorsEnabled) return;
  process.stdout.write(`${ESC}[2J${ESC}[H`);
}

/** Istalgan tugma bosilishini kutadi. */
function pressAnyKey(message = 'Davom etish uchun istalgan tugmani bosing...') {
  if (!isInteractive()) return Promise.resolve();

  return new Promise((resolve) => {
    console.log('');
    process.stdout.write(`  ${c.grey(message)}`);

    const stdin = process.stdin;
    const wasRaw = stdin.isRaw;

    const done = () => {
      stdin.removeListener('data', onData);
      try {
        if (stdin.setRawMode) stdin.setRawMode(Boolean(wasRaw));
      } catch (_) {}
      stdin.pause();
      console.log('');
      resolve();
    };

    const onData = () => done();

    try {
      if (stdin.setRawMode) stdin.setRawMode(true);
      stdin.resume();
      stdin.on('data', onData);
    } catch (_) {
      done();
    }
  });
}

/** Bosilgan tugmani aniqlaydi. Alohida funksiya — sinash uchun. */
function decodeKey(str) {
  if (!str) return 'other';

  // ANSI strelkalar (Node Windows'da ham shu ko'rinishda beradi)
  if (str === `${ESC}[A` || str === `${ESC}OA`) return 'up';
  if (str === `${ESC}[B` || str === `${ESC}OB`) return 'down';

  // Sahifalab aylantirish (uzun matnni ko'rish uchun)
  if (str === `${ESC}[5~`) return 'pageup';
  if (str === `${ESC}[6~`) return 'pagedown';
  if (str === ' ') return 'pagedown';

  // Boshiga / oxiriga
  if (str === `${ESC}[H` || str === `${ESC}[1~`) return 'home';
  if (str === `${ESC}[F` || str === `${ESC}[4~`) return 'end';

  if (str === '\r' || str === '\n') return 'enter';

  // Ctrl+C, Ctrl+D
  if (str === '\u0003' || str === '\u0004') return 'cancel';
  if (str === 'q' || str === 'Q') return 'cancel';
  if (str === ESC) return 'cancel';

  // vim uslubi
  if (str === 'k' || str === 'K') return 'up';
  if (str === 'j' || str === 'J') return 'down';
  if (str === 'g') return 'home';
  if (str === 'G') return 'end';

  return 'other';
}

/**
 * Uzun matnni sahifalab ko'rsatadi (`less` kabi).
 *
 * NEGA KERAK: uzun matn oddiy chiqarilganda terminal darhol eng pastga
 * tushib qoladi va matnning BOSHI ko'rinmay qoladi. Sahifalab ko'rsatilsa,
 * foydalanuvchi boshidan o'qiydi va o'zi kerakli joyga aylantiradi.
 */
function pager(text, { title = '' } = {}) {
  const allLines = String(text).replace(/\s+$/, '').split('\n');

  if (!isInteractive()) {
    console.log(allLines.join('\n'));
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    const stdin = process.stdin;
    const wasRaw = stdin.isRaw;
    let top = 0;

    // Sarlavha va pastdagi izoh uchun joy qoldiramiz.
    const pageSize = () => Math.max((process.stdout.rows || 24) - 3, 5);
    const maxTop = () => Math.max(allLines.length - pageSize(), 0);

    const draw = () => {
      clearScreen();
      const size = pageSize();
      const visible = allLines.slice(top, top + size);

      if (title) console.log(`  ${c.bold(title)}`);
      console.log(visible.join('\n'));

      // Qolgan joyni to'ldiramiz — pastdagi izoh sakramasligi uchun.
      for (let i = 0; i < size - visible.length; i++) console.log('');

      const fits = allLines.length <= size;
      const position = fits
        ? ''
        : `   ${c.grey(
            `${top + 1}-${Math.min(top + size, allLines.length)} / ${allLines.length}`,
          )}`;
      const hint = fits
        ? 'q yoki Enter — qaytish'
        : '↑↓ aylantirish  ·  probel — sahifa  ·  q qaytish';

      process.stdout.write(`  ${c.grey(hint)}${position}`);
    };

    const finish = () => {
      stdin.removeListener('data', onData);
      try {
        if (stdin.setRawMode) stdin.setRawMode(Boolean(wasRaw));
      } catch (_) {}
      stdin.pause();
      if (colorsEnabled) process.stdout.write(`${ESC}[?25h`);
      resolve();
    };

    const onData = (chunk) => {
      const key = decodeKey(chunk.toString());
      const size = pageSize();
      const limit = maxTop();

      switch (key) {
        case 'down':
          if (top < limit) {
            top++;
            draw();
          }
          break;
        case 'up':
          if (top > 0) {
            top--;
            draw();
          }
          break;
        case 'pagedown':
          if (top < limit) {
            top = Math.min(top + size, limit);
            draw();
          }
          break;
        case 'pageup':
          if (top > 0) {
            top = Math.max(top - size, 0);
            draw();
          }
          break;
        case 'home':
          if (top !== 0) {
            top = 0;
            draw();
          }
          break;
        case 'end':
          if (top !== limit) {
            top = limit;
            draw();
          }
          break;
        case 'enter':
        case 'cancel':
          finish();
          break;
        default:
          break;
      }
    };

    try {
      if (stdin.setRawMode) stdin.setRawMode(true);
      stdin.resume();
      stdin.on('data', onData);
      if (colorsEnabled) process.stdout.write(`${ESC}[?25l`);
      draw();
    } catch (_) {
      console.log(allLines.join('\n'));
      finish();
    }
  });
}

/**
 * ↑↓ bilan tanlash menyusi.
 *
 * items: [{ label, hint, separatorBefore }]
 * Tanlangan indeksni qaytaradi, bekor qilinsa `null`.
 */
function select({ title, items, initial = 0 }) {
  if (!items || items.length === 0) return Promise.resolve(null);

  if (!isInteractive()) {
    return numberedFallback({ title, items });
  }

  return new Promise((resolve) => {
    let index = Math.min(Math.max(initial, 0), items.length - 1);
    let drawnLines = 0;
    let finished = false;

    const stdin = process.stdin;
    const wasRaw = stdin.isRaw;

    const cleanup = () => {
      stdin.removeListener('data', onData);
      try {
        if (stdin.setRawMode) stdin.setRawMode(Boolean(wasRaw));
      } catch (_) {}
      stdin.pause();
      // Kursorni qaytarish SHART — aks holda u ko'rinmay qoladi.
      if (colorsEnabled) process.stdout.write(`${ESC}[?25h`);
    };

    const draw = () => {
      if (drawnLines > 0 && colorsEnabled) {
        process.stdout.write(`${ESC}[${drawnLines}A`);
      }
      drawnLines = render(title, items, index);
    };

    const onData = (chunk) => {
      if (finished) return;
      const key = decodeKey(chunk.toString());

      if (key === 'up') {
        index = (index - 1 + items.length) % items.length;
        draw();
      } else if (key === 'down') {
        index = (index + 1) % items.length;
        draw();
      } else if (key === 'enter') {
        finished = true;
        cleanup();
        resolve(index);
      } else if (key === 'cancel') {
        finished = true;
        cleanup();
        resolve(null);
      }
    };

    try {
      if (stdin.setRawMode) stdin.setRawMode(true);
      stdin.resume();
      stdin.on('data', onData);
      if (colorsEnabled) process.stdout.write(`${ESC}[?25l`);
      draw();
    } catch (_) {
      cleanup();
      numberedFallback({ title, items }).then(resolve);
    }
  });
}

/** Menyuni chizadi, chizilgan qatorlar sonini qaytaradi. */
function render(title, items, index) {
  let lines = 0;
  const out = [];

  out.push(`  ${c.bold(title)}`);
  out.push('');
  lines += 2;

  // Izohlar bir ustunda turishi uchun yorliqlarni tekislaymiz.
  const hasHints = items.some((it) => it.hint);
  const labelWidth = hasHints
    ? Math.max(...items.map((it) => it.label.length))
    : 0;

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (item.separatorBefore) {
      out.push('');
      lines++;
    }
    const selected = i === index;
    const pointer = selected ? c.cyan('❯') : ' ';
    // Rang kodlari uzunlikni buzadi, shuning uchun avval tekislab,
    // keyin rang beramiz.
    const padded = item.hint ? item.label.padEnd(labelWidth) : item.label;
    const label = selected ? c.cyan(c.bold(padded)) : padded;
    const hint = item.hint ? `   ${c.grey(item.hint)}` : '';
    out.push(`   ${pointer} ${label}${hint}`);
    lines++;
  }

  out.push('');
  out.push(`  ${c.grey('↑↓ tanlang  ·  Enter tasdiqlash  ·  q chiqish')}`);
  lines += 2;

  // Har bir qatorni tozalab yozamiz — eski, uzunroq matn qolib ketmasligi uchun.
  const clear = colorsEnabled ? `${ESC}[2K` : '';
  process.stdout.write(out.map((l) => `${clear}${l}`).join('\n') + '\n');

  return lines;
}

/** Terminal bo'lmasa — raqamli ro'yxat. */
function numberedFallback({ title, items }) {
  console.log(`  ${title}`);
  console.log('');
  items.forEach((item, i) => {
    if (item.separatorBefore) console.log('');
    const hint = item.hint ? `  ${item.hint}` : '';
    console.log(`    ${i + 1}  ${item.label}${hint}`);
  });
  console.log('');

  if (!process.stdin.isTTY) return Promise.resolve(null);

  return ask('Tanlang [1]:').then((answer) => {
    const n = parseInt(answer || '1', 10);
    if (!n || n < 1 || n > items.length) return null;
    return n - 1;
  });
}

/** Bir qatorli matn so'rash. */
function ask(prompt) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });
    rl.question(`  ${prompt} `, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

module.exports = {
  select,
  ask,
  decodeKey,
  isInteractive,
  enterAltScreen,
  leaveAltScreen,
  clearScreen,
  pressAnyKey,
  pager,
  colors: c,
};
