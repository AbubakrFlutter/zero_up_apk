'use strict';

/**
 * Menyu tuzilishi va amallar — sof mantiq, terminaldan mustaqil.
 *
 * Alohida modulda: bu yerda mantiqiy xato bo'lgan edi (Yordam yig'ish
 * buyrug'i deb hisoblanib qolgan), shuning uchun sinovdan o'tkazish
 * mumkin bo'lishi kerak.
 */

/**
 * Asosiy menyu variantlari va ularga mos amallar.
 *
 * project: null yoki { name, version, hasAndroid }
 * Qaytaradi: { items, actions, buildable }
 *
 * Amal turlari:
 *   build       — loyiha talab qiladi, Dart'ga argument uzatiladi
 *   passthrough — loyiha talab qilmaydi (masalan --help)
 *   config      — Node dagi sozlamalar menyusi
 *   exit        — chiqish
 */
function buildMainMenu(project) {
  const buildable = Boolean(project && project.hasAndroid);
  const items = [];
  const actions = [];

  if (buildable) {
    items.push({ label: "APK yig'ish", hint: '(tavsiya etiladi)' });
    actions.push({ type: 'build', args: ['apk'] });

    items.push({ label: 'App Bundle (AAB)', hint: 'Google Play uchun' });
    actions.push({ type: 'build', args: ['aab'] });

    items.push({ label: 'Ikkalasi ham' });
    actions.push({ type: 'build', args: ['hammasi'] });

    items.push({ label: 'Faqat arm64 APK', hint: 'eng tez rejim' });
    actions.push({ type: 'build', args: ['apk', '--arm64'] });
  }

  items.push({
    label: 'Sozlamalar',
    hint: 'fayllar qayerga tushadi',
    separatorBefore: buildable,
  });
  actions.push({ type: 'config' });

  // Yordam loyihaga bog'liq emas — istalgan papkada ishlaydi.
  items.push({ label: 'Yordam' });
  actions.push({ type: 'passthrough', args: ['--help'] });

  items.push({ label: 'Chiqish' });
  actions.push({ type: 'exit' });

  return { items, actions, buildable };
}

module.exports = { buildMainMenu };
