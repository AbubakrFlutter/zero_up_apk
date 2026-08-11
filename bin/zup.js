#!/usr/bin/env node

const { spawn } = require('child_process');
const path = require('path');
const os = require('os');
const fs = require('fs');

// Platform aniqlash
const platform = os.platform();
const homeDir = os.homedir();

// Binary yo'li
const zupDir = path.join(homeDir, '.zup');
const binaryName = platform === 'win32' ? 'zup.exe' : 'zup';
const binaryPath = path.join(zupDir, binaryName);

// Binary mavjudligini tekshirish
if (!fs.existsSync(binaryPath)) {
  console.error('❌ zup binary topilmadi:', binaryPath);
  console.log('');
  console.log('💡 Qayta o\'rnatib ko\'ring:');
  console.log('   npm install -g github:zero_up_team/zero_up_apk');
  console.log('');
  process.exit(1);
}

// Dart binary ni ishga tushirish
const child = spawn(binaryPath, process.argv.slice(2), {
  stdio: 'inherit',
  shell: platform === 'win32'
});

// Exit code ni to'g'ri qaytarish
child.on('exit', (code) => {
  process.exit(code || 0);
});

// Xatolarni to'g'ri handle qilish
child.on('error', (err) => {
  console.error('❌ Xato:', err.message);
  process.exit(1);
});
