'use strict';

const { test, describe } = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const path = require('path');

const { classify, normalize, COMMANDS, VALUE_OPTIONS } = require('../../node/args.js');

describe('normalize — AI rejimi', () => {
  test('zup ai apk → --ai apk', () => {
    assert.deepStrictEqual(normalize(['ai', 'apk']), ['--ai', 'apk']);
  });

  test('zup ai (yolg\'iz) → --ai apk', () => {
    assert.deepStrictEqual(normalize(['ai']), ['--ai', 'apk']);
  });

  test('zup -m ai apk → --ai apk', () => {
    assert.deepStrictEqual(normalize(['-m', 'ai', 'apk']), ['--ai', 'apk']);
  });

  test('zup --mode ai apk → --ai apk', () => {
    assert.deepStrictEqual(normalize(['--mode', 'ai', 'apk']), ['--ai', 'apk']);
  });

  test('zup --mode=ai apk → --ai apk', () => {
    assert.deepStrictEqual(normalize(['--mode=ai', 'apk']), ['--ai', 'apk']);
  });

  test('zup ai apk --mode debug → rejim buzilmaydi', () => {
    const r = normalize(['ai', 'apk', '--mode', 'debug']);
    assert.deepStrictEqual(r, ['--ai', 'apk', '--mode', 'debug']);
  });

  test('AI so\'zsiz — o\'zgarmaydi', () => {
    assert.deepStrictEqual(normalize(['apk', '--arm64']), ['apk', '--arm64']);
  });

  test('--mode release ga tegilmaydi', () => {
    assert.deepStrictEqual(
      normalize(['apk', '--mode', 'release']),
      ['apk', '--mode', 'release'],
    );
  });
});

describe('classify — buyruq aniqlash', () => {
  test('bo\'sh argv — buyruq yo\'q', () => {
    assert.strictEqual(classify([]).command, null);
  });

  test('apk', () => {
    assert.strictEqual(classify(['apk']).command, 'apk');
  });

  test('faqat bayroqlar — buyruq yo\'q (menyu ochilishi kerak)', () => {
    assert.strictEqual(classify(['--clean']).command, null);
    assert.strictEqual(classify(['--arm64', '--verbose']).command, null);
  });

  test('update — istalgan joyda topiladi', () => {
    assert.strictEqual(classify(['update']).command, 'update');
    // `zup update apk` ham ushlanishi kerak (ilgari ushlanmasdi)
    assert.strictEqual(classify(['update', 'apk']).command, 'update');
  });
});

describe('classify — qiymatli opsiyalar buyruq deb o\'ylanmasin', () => {
  test('zup -p C:\\loyiha apk → buyruq apk', () => {
    const r = classify(['-p', 'C:\\loyiha', 'apk']);
    assert.strictEqual(r.command, 'apk');
  });

  test('qiymat buyruq nomiga o\'xshasa ham — buyruq emas', () => {
    // `--out apk` da `apk` — bu papka nomi, buyruq emas
    const r = classify(['--out', 'apk', 'aab']);
    assert.strictEqual(r.command, 'aab');
  });

  test('--flavor qiymati', () => {
    const r = classify(['--flavor', 'prod', 'apk']);
    assert.strictEqual(r.command, 'apk');
  });

  test('--dart-define qiymati', () => {
    const r = classify(['--dart-define', 'ENV=all', 'apk']);
    assert.strictEqual(r.command, 'apk');
  });
});

describe('classify — bayroqlar', () => {
  test('--ai', () => {
    assert.strictEqual(classify(['ai', 'apk']).flags.ai, true);
  });

  test('--json', () => {
    assert.strictEqual(classify(['apk', '--json']).flags.json, true);
  });

  test('-i / --install', () => {
    assert.strictEqual(classify(['apk', '-i']).flags.install, true);
    assert.strictEqual(classify(['apk', '--install']).flags.install, true);
  });

  test('--device=ID va --device ID', () => {
    assert.strictEqual(classify(['apk', '--device=emulator-5554']).flags.device, 'emulator-5554');
    assert.strictEqual(classify(['apk', '--device', 'abc123']).flags.device, 'abc123');
  });

  test('-v version, -h help', () => {
    assert.strictEqual(classify(['-v']).flags.version, true);
    assert.strictEqual(classify(['-h']).flags.help, true);
  });
});

describe('Dart bilan moslik (parity)', () => {
  test('COMMANDS Dart dagi commandAliases bilan mos', () => {
    const dartSource = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'src', 'command_spec.dart'),
      'utf8',
    );

    // `commandAliases` map ichidagi kalitlarni ajratamiz
    const mapStart = dartSource.indexOf('const Map<String, String> commandAliases');
    assert.ok(mapStart > 0, 'commandAliases topilmadi');
    const mapEnd = dartSource.indexOf('};', mapStart);
    const mapBody = dartSource.slice(mapStart, mapEnd);

    const dartKeys = [...mapBody.matchAll(/^\s*'([a-z-]+)':/gm)].map((m) => m[1]);
    assert.ok(dartKeys.length > 10, `kutilgandan kam kalit: ${dartKeys.length}`);

    // Node'da Dart dagi har bir buyruq bo'lishi shart
    for (const key of dartKeys) {
      assert.ok(
        COMMANDS.has(key),
        `Node COMMANDS da '${key}' yo'q — Dart bilan mos emas`,
      );
    }

    // Node'dagi qo'shimchalar faqat Node o'zi bajaradiganlar bo'lishi mumkin
    const nodeOnly = ['update', 'ai'];
    for (const cmd of COMMANDS) {
      if (nodeOnly.includes(cmd)) continue;
      assert.ok(
        dartKeys.includes(cmd),
        `Dart da '${cmd}' yo'q — Node ortiqcha buyruq biladi`,
      );
    }
  });

  test('VALUE_OPTIONS Dart parseridagi opsiyalar bilan mos', () => {
    const cliSource = fs.readFileSync(
      path.join(__dirname, '..', '..', 'lib', 'src', 'cli.dart'),
      'utf8',
    );

    // addOption / addMultiOption — qiymat qabul qiladi
    const names = [...cliSource.matchAll(/add(?:Multi)?Option\(\s*'([a-z-]+)'/g)]
      .map((m) => m[1]);
    assert.ok(names.length > 3, `kutilgandan kam opsiya: ${names.length}`);

    for (const name of names) {
      assert.ok(
        VALUE_OPTIONS.has(`--${name}`),
        `VALUE_OPTIONS da '--${name}' yo'q — 'zup --${name} X apk' buzuladi`,
      );
    }
  });
});
