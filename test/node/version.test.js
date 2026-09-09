'use strict';

/**
 * Versiya uchta joyda yozilgan. Ular bir-biriga mos bo'lishi SHART:
 *
 *   package.json          — npm ko'radigan versiya, `zup update` shunga qaraydi
 *   pubspec.yaml          — Dart paketi
 *   lib/src/cli.dart      — `zup --version` chiqaradigan matn
 *
 * 1.3.x da bular uch marta ajralib ketgan edi: banner `v1.3.1` ko'rsatib
 * turganda paket allaqachon 1.3.2 edi.
 */

const { test } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');

test('package.json, pubspec.yaml va cli.dart versiyalari mos', () => {
  const pkg = JSON.parse(
    fs.readFileSync(path.join(root, 'package.json'), 'utf8'),
  ).version;

  const pubspec = fs
    .readFileSync(path.join(root, 'pubspec.yaml'), 'utf8')
    .match(/^version:\s*(.+)$/m)[1]
    .trim();

  const dart = fs
    .readFileSync(path.join(root, 'lib', 'src', 'cli.dart'), 'utf8')
    .match(/const zeroUpApkVersion = '([^']+)'/)[1];

  assert.strictEqual(pubspec, pkg, `pubspec.yaml (${pubspec}) != package.json (${pkg})`);
  assert.strictEqual(dart, pkg, `cli.dart (${dart}) != package.json (${pkg})`);
});

test('bin/zero_up_apk.dart versiyani cli.dart dan oladi', () => {
  const src = fs.readFileSync(
    path.join(root, 'bin', 'zero_up_apk.dart'),
    'utf8',
  );
  assert.ok(
    src.includes('const currentVersion = zeroUpApkVersion;'),
    'bin/zero_up_apk.dart o\'z versiyasini yozib qo\'ymasligi kerak',
  );
});
