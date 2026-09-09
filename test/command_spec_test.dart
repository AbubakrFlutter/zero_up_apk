import 'package:test/test.dart';
import 'package:zero_up_apk/zero_up_apk.dart';

void main() {
  group('parseCommand — yig\'ish', () {
    test('apk', () {
      final c = parseCommand(['apk']) as BuildCommand;
      expect(c.targets, [BuildTarget.apk]);
    });

    test('aab va uning taxalluslari', () {
      for (final word in ['aab', 'appbundle', 'bundle']) {
        final c = parseCommand([word]) as BuildCommand;
        expect(c.targets, [BuildTarget.aab], reason: word);
      }
    });

    test('hammasi — ikkala maqsad', () {
      for (final word in ['hammasi', 'both', 'all', 'ikkalasi']) {
        final c = parseCommand([word]) as BuildCommand;
        expect(c.targets, containsAll([BuildTarget.apk, BuildTarget.aab]),
            reason: word);
      }
    });

    test('apk aab — birlashadi', () {
      final c = parseCommand(['apk', 'aab']) as BuildCommand;
      expect(c.targets, containsAll([BuildTarget.apk, BuildTarget.aab]));
    });

    test('katta harf ham ishlaydi', () {
      expect(parseCommand(['APK']), isA<BuildCommand>());
    });
  });

  group('parseCommand — xavfli holatlar (2.0 gacha APK yig\'ilardi)', () {
    test("bo'sh — MISSING_TARGET, hech qachon standart yig'ish emas", () {
      expect(
        () => parseCommand([]),
        throwsA(isA<CommandParseError>()
            .having((e) => e.code, 'code', 'MISSING_TARGET')),
      );
    });

    test("'reset' yolg'iz — qattiq xato", () {
      expect(
        () => parseCommand(['reset']),
        throwsA(isA<CommandParseError>()
            .having((e) => e.code, 'code', 'UNKNOWN_COMMAND')),
      );
    });

    test("noto'g'ri yozilgan 'apkk' — xato va taklif beradi", () {
      try {
        parseCommand(['apkk']);
        fail('xato tashlanishi kerak edi');
      } on CommandParseError catch (e) {
        expect(e.code, 'UNKNOWN_COMMAND');
        expect(e.didYouMean, contains('apk'));
      }
    });

    test("'docter' → doctor taklifi", () {
      try {
        parseCommand(['docter']);
        fail('xato tashlanishi kerak edi');
      } on CommandParseError catch (e) {
        expect(e.didYouMean, contains('doctor'));
      }
    });

    test('apk config — CONFLICTING_COMMAND', () {
      expect(
        () => parseCommand(['apk', 'config']),
        throwsA(isA<CommandParseError>()
            .having((e) => e.code, 'code', 'CONFLICTING_COMMAND')),
      );
    });

    test('doctor info — CONFLICTING_COMMAND', () {
      expect(
        () => parseCommand(['doctor', 'info']),
        throwsA(isA<CommandParseError>()
            .having((e) => e.code, 'code', 'CONFLICTING_COMMAND')),
      );
    });

    test("apk uchun qo'shimcha so'z — xato", () {
      expect(
        () => parseCommand(['apk', 'nimadir']),
        throwsA(isA<CommandParseError>()),
      );
    });
  });

  group('parseCommand — config', () {
    test('config', () {
      final c = parseCommand(['config']) as ConfigCommand;
      expect(c.reset, isFalse);
    });

    test('config reset', () {
      final c = parseCommand(['config', 'reset']) as ConfigCommand;
      expect(c.reset, isTrue);
      expect(c.resetKey, isNull);
    });

    test('config reset out — bitta sozlama', () {
      final c = parseCommand(['config', 'reset', 'out']) as ConfigCommand;
      expect(c.reset, isTrue);
      expect(c.resetKey, 'out');
    });

    test("config reset noma'lum-sozlama — xato", () {
      expect(
        () => parseCommand(['config', 'reset', 'nimadir']),
        throwsA(isA<CommandParseError>()
            .having((e) => e.code, 'code', 'BAD_ARGUMENT')),
      );
    });

    test("config noma'lum-amal — xato", () {
      expect(
        () => parseCommand(['config', 'ishla']),
        throwsA(isA<CommandParseError>()),
      );
    });
  });

  group('parseCommand — last', () {
    test('last — standart 5 ta', () {
      final c = parseCommand(['last']) as LastCommand;
      expect(c.count, 5);
    });

    test('last 10', () {
      final c = parseCommand(['last', '10']) as LastCommand;
      expect(c.count, 10);
    });

    test('last abc — xato', () {
      expect(
        () => parseCommand(['last', 'abc']),
        throwsA(isA<CommandParseError>()),
      );
    });

    test('last 0 — xato', () {
      expect(
        () => parseCommand(['last', '0']),
        throwsA(isA<CommandParseError>()),
      );
    });
  });

  group('parseCommand — boshqa buyruqlar', () {
    test('doctor / tekshir', () {
      expect(parseCommand(['doctor']), isA<DoctorCommand>());
      expect(parseCommand(['tekshir']), isA<DoctorCommand>());
    });

    test('info / malumot', () {
      expect(parseCommand(['info']), isA<InfoCommand>());
      expect(parseCommand(['malumot']), isA<InfoCommand>());
    });

    test('devices / qurilmalar', () {
      expect(parseCommand(['devices']), isA<DevicesCommand>());
      expect(parseCommand(['qurilmalar']), isA<DevicesCommand>());
    });

    test('install — faylsiz va fayl bilan', () {
      expect((parseCommand(['install']) as InstallCommand).apkPath, isNull);
      expect(
        (parseCommand(['install', 'app.apk']) as InstallCommand).apkPath,
        'app.apk',
      );
    });

    test('help / yordam / version', () {
      expect(parseCommand(['help']), isA<HelpCommand>());
      expect(parseCommand(['yordam']), isA<HelpCommand>());
      expect(parseCommand(['version']), isA<VersionCommand>());
    });
  });

  group('suggest', () {
    test('yaqin so\'zlarni topadi', () {
      expect(suggest('apkk'), contains('apk'));
      expect(suggest('aab2'), contains('aab'));
      expect(suggest('conifg'), contains('config'));
    });

    test('umuman boshqa so\'zga taklif bermaydi', () {
      expect(suggest('zzzzzzzzz'), isEmpty);
    });

    test('bir buyruqni ikki marta taklif qilmaydi', () {
      final result = suggest('aa');
      expect(result.length, result.toSet().length);
    });
  });
}
