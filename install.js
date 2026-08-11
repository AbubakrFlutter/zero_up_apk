#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const { execSync } = require('child_process');

const VERSION = '1.3.0';
const REPO_OWNER = 'AbubakrFlutter';
const REPO_NAME = 'zero_up_apk';

// Platform aniqlash
const platform = os.platform();
const arch = os.arch();

console.log('');
console.log('╔══════════════════════════════════════════════════════════════╗');
console.log('║                    ⚡ Zero Up APK                           ║');
console.log('╚══════════════════════════════════════════════════════════════╝');
console.log('');
console.log('📦 O\'rnatilmoqda...');
console.log('');

// Home directory
const homeDir = os.homedir();
const zupDir = path.join(homeDir, '.zup');

// Papkani yaratish
if (!fs.existsSync(zupDir)) {
  fs.mkdirSync(zupDir, { recursive: true });
  console.log('✅ Papka yaratildi:', zupDir);
}

// Platform bo'yicha binary nomi
let binaryName;
let downloadUrl;

if (platform === 'win32') {
  binaryName = 'zup.exe';
  downloadUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}/zup_windows_x64.exe`;
} else if (platform === 'darwin') {
  binaryName = 'zup';
  downloadUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}/zup_macos_${arch}`;
} else if (platform === 'linux') {
  binaryName = 'zup';
  downloadUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/v${VERSION}/zup_linux_${arch}`;
} else {
  console.error('❌ Platform qo\'llab-quvvatlanmaydi:', platform);
  process.exit(1);
}

const targetPath = path.join(zupDir, binaryName);

// Binary mavjudligini tekshirish
const localBinary = path.join(__dirname, 'bin', binaryName);
if (fs.existsSync(localBinary)) {
  // Local binary mavjud - ko'chirish
  console.log('📁 Binary ko\'chirilmoqda...');
  fs.copyFileSync(localBinary, targetPath);

  // Unix platformalarda executable qilish
  if (platform !== 'win32') {
    fs.chmodSync(targetPath, '755');
  }

  console.log('✅ zup o\'rnatildi:', targetPath);
} else {
  // GitHub dan yuklab olish
  console.log('📥 GitHub dan yuklab olinmoqda...');
  console.log('   URL:', downloadUrl);

  downloadFile(downloadUrl, targetPath, () => {
    // Unix platformalarda executable qilish
    if (platform !== 'win32') {
      fs.chmodSync(targetPath, '755');
    }

    console.log('✅ zup o\'rnatildi:', targetPath);
    console.log('');
    showInstructions();
  });
  return; // Async uchun
}

// VERSION faylini yaratish
const versionFile = path.join(zupDir, 'VERSION');
fs.writeFileSync(versionFile, VERSION);

console.log('');
showInstructions();

function showInstructions() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║              ✅ O\'RNATISH MUVAFFAQIYATLI!                   ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('📌 ISHLATISH:');
  console.log('');
  console.log('   zup apk --arm64         # APK yasash');
  console.log('   zup aab                 # App Bundle yasash');
  console.log('   zup update              # Yangilash');
  console.log('   zup --help              # Yordam');
  console.log('');
  console.log('🚀 Flutter loyihangizga kiring va \'zup apk\' yozing!');
  console.log('');
}

function downloadFile(url, dest, callback) {
  const file = fs.createWriteStream(dest);

  https.get(url, (response) => {
    if (response.statusCode === 302 || response.statusCode === 301) {
      // Redirect
      return downloadFile(response.headers.location, dest, callback);
    }

    if (response.statusCode !== 200) {
      console.error('❌ Yuklab olishda xato. Status:', response.statusCode);
      console.log('');
      console.log('⚠️  GitHub Releases dan qo\'lda yuklab oling:');
      console.log('   https://github.com/' + REPO_OWNER + '/' + REPO_NAME + '/releases');
      console.log('');
      process.exit(1);
    }

    const totalSize = parseInt(response.headers['content-length'], 10);
    let downloadedSize = 0;
    let lastPercent = 0;

    response.on('data', (chunk) => {
      downloadedSize += chunk.length;
      const percent = Math.floor((downloadedSize / totalSize) * 100);

      if (percent !== lastPercent && percent % 10 === 0) {
        process.stdout.write(`   ${percent}% yuklab olindi...\r`);
        lastPercent = percent;
      }
    });

    response.pipe(file);

    file.on('finish', () => {
      file.close(() => {
        console.log('   100% yuklab olindi!   ');
        callback();
      });
    });
  }).on('error', (err) => {
    fs.unlinkSync(dest);
    console.error('❌ Yuklab olishda xato:', err.message);
    console.log('');
    console.log('⚠️  GitHub Releases dan qo\'lda yuklab oling:');
    console.log('   https://github.com/' + REPO_OWNER + '/' + REPO_NAME + '/releases');
    console.log('');
    process.exit(1);
  });
}
