'use strict';

/**
 * Sozlamalar — `~/.zup/config.json`.
 *
 * Dart tomoni ham shu faylni o'qiydi (lib/src/config.dart), shuning uchun
 * maydon nomlari MOS BO'LISHI SHART: out, open, arm64, copy.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const zupDir = path.join(os.homedir(), '.zup');
const configPath = path.join(zupDir, 'config.json');

/** Sozlamalarni o'qiydi. Fayl yo'q yoki buzuq bo'lsa — bo'sh obyekt. */
function load() {
  try {
    if (!fs.existsSync(configPath)) return {};
    const raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    return raw && typeof raw === 'object' ? raw : {};
  } catch (_) {
    // Buzuq JSON — sozlamasiz davom etamiz.
    return {};
  }
}

/** Saqlaydi. Xato bo'lsa xato matnini qaytaradi, aks holda null. */
function save(config) {
  try {
    fs.mkdirSync(zupDir, { recursive: true });
    // undefined maydonlarni tashlab yuboramiz.
    const clean = {};
    for (const [k, v] of Object.entries(config)) {
      if (v !== undefined && v !== null) clean[k] = v;
    }
    fs.writeFileSync(configPath, JSON.stringify(clean, null, 2) + '\n');
    return null;
  } catch (e) {
    return e.message;
  }
}

/** Sozlamalarni butunlay o'chiradi. */
function reset() {
  try {
    if (fs.existsSync(configPath)) fs.unlinkSync(configPath);
    return null;
  } catch (e) {
    return e.message;
  }
}

/**
 * Papkaga yozib bo'ladimi? Yo'q bo'lsa yaratib ko'radi.
 * Hammasi joyida bo'lsa null, aks holda xato matni.
 */
function validateDir(dir) {
  const target = String(dir || '').trim();
  if (!target) return "Papka yo'li bo'sh";

  try {
    if (!fs.existsSync(target)) fs.mkdirSync(target, { recursive: true });

    // Mavjudligi yetarli emas — haqiqatan yozib ko'ramiz
    // (masalan C:\Windows ga yozib bo'lmaydi).
    const probe = path.join(target, `.zup_test_${Date.now()}`);
    fs.writeFileSync(probe, 'test');
    fs.unlinkSync(probe);
    return null;
  } catch (e) {
    return e.code === 'EACCES' || e.code === 'EPERM'
      ? 'Ruxsat yo\'q (Access denied)'
      : e.message;
  }
}

/** Tirnoqlarni olib tashlaydi — nusxa ko'chirilgan yo'llar uchun. */
function cleanPath(input) {
  let s = String(input || '').trim();
  if (
    s.length > 1 &&
    ((s.startsWith('"') && s.endsWith('"')) ||
      (s.startsWith("'") && s.endsWith("'")))
  ) {
    s = s.slice(1, -1).trim();
  }
  return s;
}

module.exports = { load, save, reset, validateDir, cleanPath, configPath, zupDir };
