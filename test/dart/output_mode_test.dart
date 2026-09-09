import 'package:test/test.dart';
import 'package:zero_up_apk/zero_up_apk.dart';

/// Terminal bo'lgan holatni bildiruvchi standart argumentlar.
OutputDecision decide({
  bool json = false,
  bool ai = false,
  bool quiet = false,
  bool noColor = false,
  bool ascii = false,
  bool noProgress = false,
  Map<String, String> env = const {},
  bool stdoutHasTerminal = true,
  bool stdoutAnsi = true,
  int? columns,
}) {
  return decideOutput(
    json: json,
    ai: ai,
    quiet: quiet,
    noColor: noColor,
    ascii: ascii,
    noProgress: noProgress,
    env: env,
    stdoutHasTerminal: stdoutHasTerminal,
    stdoutAnsi: stdoutAnsi,
    stdoutColumns: columns,
  );
}

void main() {
  group('ustuvorlik tartibi', () {
    test('terminal bor — boy ko\'rinish', () {
      final d = decide(env: {'ZUP_STDOUT_TTY': '1'});
      expect(d.style, OutputStyle.rich);
      expect(d.reason, 'tty');
    });

    test('--json hammasidan ustun', () {
      final d = decide(json: true, env: {'ZUP_OUTPUT': 'rich'});
      expect(d.style, OutputStyle.json);
      expect(d.color, isFalse, reason: 'JSON da rang bo\'lmasligi kerak');
    });

    test('--ai ham JSON', () {
      final d = decide(ai: true);
      expect(d.style, OutputStyle.json);
      expect(d.reason, 'ai');
    });

    test('ZUP_OUTPUT=json — bayroqsiz ham JSON', () {
      final d = decide(env: {'ZUP_OUTPUT': 'json'});
      expect(d.style, OutputStyle.json);
      expect(d.reason, 'env:ZUP_OUTPUT');
    });

    test('ZUP_OUTPUT=plain', () {
      expect(decide(env: {'ZUP_OUTPUT': 'plain'}).style, OutputStyle.plain);
    });

    test('ZUP_OUTPUT=rich — terminalsiz ham majburlaydi', () {
      final d = decide(
        env: {'ZUP_OUTPUT': 'rich', 'ZUP_STDOUT_TTY': '0'},
      );
      expect(d.style, OutputStyle.rich);
    });

    test('ZUP_OUTPUT noma\'lum qiymat — e\'tiborsiz qoldiriladi', () {
      final d = decide(env: {'ZUP_OUTPUT': 'nimadir'});
      expect(d.style, OutputStyle.rich);
      expect(d.reason, 'tty');
    });

    test('--quiet → oddiy', () {
      final d = decide(quiet: true);
      expect(d.style, OutputStyle.plain);
      expect(d.reason, 'quiet');
    });

    test('--no-progress → oddiy', () {
      expect(decide(noProgress: true).style, OutputStyle.plain);
    });
  });

  group('CI aniqlash', () {
    test('CI=true → oddiy, rangsiz', () {
      final d = decide(env: {'CI': 'true'});
      expect(d.style, OutputStyle.plain);
      expect(d.color, isFalse);
      expect(d.reason, 'ci:CI');
    });

    test('GITHUB_ACTIONS', () {
      expect(decide(env: {'GITHUB_ACTIONS': 'true'}).reason, 'ci:GITHUB_ACTIONS');
    });

    test('CI=false → CI emas', () {
      final d = decide(env: {'CI': 'false'});
      expect(d.style, OutputStyle.rich);
    });

    test('CI bo\'sh qiymat → CI emas', () {
      expect(decide(env: {'CI': ''}).style, OutputStyle.rich);
    });
  });

  group('terminal holati', () {
    test('stdout terminal emas → oddiy', () {
      final d = decide(stdoutHasTerminal: false);
      expect(d.style, OutputStyle.plain);
      expect(d.reason, 'stdout-not-tty');
    });

    test('ZUP_STDOUT_TTY=0 Dart ning javobini bekor qiladi', () {
      final d = decide(
        stdoutHasTerminal: true,
        env: {'ZUP_STDOUT_TTY': '0'},
      );
      expect(d.style, OutputStyle.plain);
    });

    test('ANSI yo\'q → oddiy (jonli qayta chizish ishlamaydi)', () {
      final d = decide(stdoutAnsi: false);
      expect(d.style, OutputStyle.plain);
      expect(d.reason, 'no-ansi');
    });

    test('TERM=dumb → oddiy, rangsiz', () {
      final d = decide(env: {'TERM': 'dumb'});
      expect(d.style, OutputStyle.plain);
      expect(d.color, isFalse);
    });
  });

  group('interactiveStdin — echo | zup xatosining ildizi', () {
    test('ZUP_STDIN_TTY=1 → savol berish mumkin', () {
      expect(decide(env: {'ZUP_STDIN_TTY': '1'}).interactiveStdin, isTrue);
    });

    test('ZUP_STDIN_TTY=0 → savol berib bo\'lmaydi', () {
      expect(decide(env: {'ZUP_STDIN_TTY': '0'}).interactiveStdin, isFalse);
    });

    test("ma'lumot yo'q → savol berib bo'lmaydi (xavfsiz tomon)", () {
      // Bu eng muhim holat: bilmasak, "mumkin emas" deb hisoblaymiz.
      // Aks holda javob kutib osilib qolish yoki standart javobni olib
      // so'ramasdan yig'ish xavfi bor.
      expect(decide().interactiveStdin, isFalse);
    });

    test("stdout terminal bo'lsa ham stdin holati alohida", () {
      final d = decide(
        stdoutHasTerminal: true,
        env: {'ZUP_STDOUT_TTY': '1', 'ZUP_STDIN_TTY': '0'},
      );
      expect(d.style, OutputStyle.rich, reason: 'chiqish boy bo\'lishi mumkin');
      expect(d.interactiveStdin, isFalse, reason: 'lekin savol berilmaydi');
    });
  });

  group('rang va belgilar', () {
    test('NO_COLOR — qiymatidan qat\'i nazar rangni o\'chiradi', () {
      expect(decide(env: {'NO_COLOR': ''}).color, isFalse);
      expect(decide(env: {'NO_COLOR': '1'}).color, isFalse);
    });

    test('--no-color', () {
      expect(decide(noColor: true).color, isFalse);
    });

    test('--no-color uslubga ta\'sir qilmaydi', () {
      expect(decide(noColor: true).style, OutputStyle.rich);
    });

    test('--ascii — unicode o\'chadi, uslub o\'zgarmaydi', () {
      final d = decide(ascii: true);
      expect(d.unicode, isFalse);
      expect(d.style, OutputStyle.rich);
    });

    test('standart holatda unicode yoqilgan', () {
      expect(decide().unicode, isTrue);
    });
  });

  group('terminal kengligi', () {
    test('ZUP_COLUMNS ustun', () {
      expect(decide(env: {'ZUP_COLUMNS': '120'}, columns: 80).columns, 120);
    });

    test('ZUP_COLUMNS yo\'q — Dart ning qiymati', () {
      expect(decide(columns: 100).columns, 100);
    });

    test('hech biri yo\'q — standart 80', () {
      expect(decide().columns, defaultColumns);
    });

    test('yaroqsiz ZUP_COLUMNS e\'tiborsiz qoldiriladi', () {
      expect(decide(env: {'ZUP_COLUMNS': 'abc'}, columns: 90).columns, 90);
      expect(decide(env: {'ZUP_COLUMNS': '0'}, columns: 90).columns, 90);
    });
  });
}
