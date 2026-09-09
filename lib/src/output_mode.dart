/// Chiqish qanday ko'rinishda bo'lishi — BIR JOYDA hal qilinadi.
///
/// Ilgari bu qaror `console.dart` ichida tarqoq edi (`_color`, `interactive`)
/// va Dart faqat `stdout` ga qarardi. Node esa `stdin` ni ham tekshirardi.
/// Ikki tomondagi javob har xil bo'lgani uchun `echo | zup` da Dart
/// "terminal bor" deb menyu ochib, javob kutmasdan APK yig'ib yuborardi.
library;

/// Chiqish uslubi.
enum OutputStyle {
  /// Jonli progress, bosqichlar ro'yxati, ranglar.
  rich,

  /// Har bosqich alohida qatorda, animatsiya yo'q. Log va CI uchun.
  plain,

  /// stdout'da faqat bitta JSON obyekt. Agentlar uchun.
  json,
}

/// Chiqish haqida qabul qilingan qaror.
class OutputDecision {
  const OutputDecision({
    required this.style,
    required this.color,
    required this.unicode,
    required this.interactiveStdin,
    required this.columns,
    required this.reason,
  });

  final OutputStyle style;

  /// ANSI ranglar ishlatiladimi.
  final bool color;

  /// Unicode belgilar (`✔`, `▶`, `█`) yoki ASCII (`[OK]`, `>`, `#`).
  final bool unicode;

  /// stdin terminalmi — savol berish MUMKINMI.
  ///
  /// Dart hech qachon savol bermaydi, lekin bu qiymat "menyu ochishga
  /// urinilmasin" degan invariantni majburlash uchun kerak.
  final bool interactiveStdin;

  /// Terminal kengligi.
  final int columns;

  /// Nega shu qaror qabul qilindi — diagnostika uchun (`zup info`).
  final String reason;

  bool get isJson => style == OutputStyle.json;
  bool get isRich => style == OutputStyle.rich;
}

/// CI muhitini bildiruvchi o'zgaruvchilar.
const _ciVariables = [
  'CI',
  'CONTINUOUS_INTEGRATION',
  'GITHUB_ACTIONS',
  'GITLAB_CI',
  'TEAMCITY_VERSION',
  'TF_BUILD',
  'JENKINS_URL',
  'BUILDKITE',
  'CIRCLECI',
  'TRAVIS',
  'APPVEYOR',
  'CODEBUILD_BUILD_ID',
  'DRONE',
  'WOODPECKER_CI',
];

/// Standart terminal kengligi — aniqlab bo'lmasa.
const int defaultColumns = 80;

/// Chiqish rejimini aniqlaydi.
///
/// SOF FUNKSIYA — terminalsiz to'liq sinovdan o'tkaziladi.
///
/// [stdoutHasTerminal] va [stdoutAnsi] Dart'dan; [env] esa Node uzatgan
/// `ZUP_STDIN_TTY`, `ZUP_STDOUT_TTY`, `ZUP_COLUMNS` ni ham o'z ichiga oladi.
OutputDecision decideOutput({
  bool json = false,
  bool ai = false,
  bool quiet = false,
  bool noColor = false,
  bool ascii = false,
  bool noProgress = false,
  required Map<String, String> env,
  required bool stdoutHasTerminal,
  required bool stdoutAnsi,
  int? stdoutColumns,
}) {
  // Node bilgan, Dart bilmaydigan faktlar.
  final stdinTty = _envBool(env['ZUP_STDIN_TTY']);
  final stdoutTty = _envBool(env['ZUP_STDOUT_TTY']) ?? stdoutHasTerminal;
  final columns = _envInt(env['ZUP_COLUMNS']) ??
      stdoutColumns ??
      defaultColumns;

  // Rang: `NO_COLOR` (qiymatidan qat'i nazar) va `--no-color` uslubdan
  // qat'i nazar rangni o'chiradi.
  final colorForbidden = noColor || env.containsKey('NO_COLOR');
  final unicode = !ascii;

  OutputDecision decide(OutputStyle style, String reason, {bool? color}) {
    final useColor = color ?? (!colorForbidden && stdoutTty && stdoutAnsi);
    return OutputDecision(
      style: style,
      color: style == OutputStyle.json ? false : useColor,
      unicode: unicode,
      // stdin haqida ma'lumot bo'lmasa — savol berib bo'lmaydi deb hisoblaymiz.
      // Xavfsiz tomonga og'ish: noto'g'ri "bor" deb hisoblash osilib qolishga
      // yoki so'ramasdan yig'ishga olib keladi.
      interactiveStdin: stdinTty ?? false,
      columns: columns,
      reason: reason,
    );
  }

  // 1) JSON — eng yuqori ustuvorlik.
  if (json || ai) {
    return decide(OutputStyle.json, ai ? 'ai' : 'json-flag', color: false);
  }

  // 2) ZUP_OUTPUT — agent harness'i bir marta o'rnatadi va model
  //    `--json` yozishni o'ylamagan chaqiruvlar ham JSON qaytaradi.
  final forced = env['ZUP_OUTPUT']?.trim().toLowerCase();
  if (forced != null && forced.isNotEmpty) {
    switch (forced) {
      case 'json':
        return decide(OutputStyle.json, 'env:ZUP_OUTPUT', color: false);
      case 'plain':
        return decide(OutputStyle.plain, 'env:ZUP_OUTPUT');
      case 'rich':
        return decide(OutputStyle.rich, 'env:ZUP_OUTPUT');
      // Noma'lum qiymat — e'tiborsiz qoldirib, avtomatik aniqlashga o'tamiz.
    }
  }

  // 3) Foydalanuvchi aniq so'ragan.
  if (quiet) return decide(OutputStyle.plain, 'quiet');
  if (noProgress) return decide(OutputStyle.plain, 'no-progress');

  // 4) CI — animatsiya log faylni axlatga to'ldiradi.
  for (final key in _ciVariables) {
    final value = env[key];
    if (value != null && value.isNotEmpty && value.toLowerCase() != 'false') {
      return decide(OutputStyle.plain, 'ci:$key', color: false);
    }
  }

  // 5) TERM=dumb — ANSI ni tushunmaydigan terminal.
  if (env['TERM']?.toLowerCase() == 'dumb') {
    return decide(OutputStyle.plain, 'term-dumb', color: false);
  }

  // 6) stdout terminal emas (faylga yoki quvurga yo'naltirilgan).
  if (!stdoutTty) return decide(OutputStyle.plain, 'stdout-not-tty');

  // 7) ANSI qo'llab-quvvatlanmasa — jonli qayta chizish ishlamaydi.
  if (!stdoutAnsi) return decide(OutputStyle.plain, 'no-ansi');

  return decide(OutputStyle.rich, 'tty');
}

bool? _envBool(String? value) {
  if (value == null) return null;
  final v = value.trim();
  if (v == '1' || v.toLowerCase() == 'true') return true;
  if (v == '0' || v.toLowerCase() == 'false') return false;
  return null;
}

int? _envInt(String? value) {
  if (value == null) return null;
  final n = int.tryParse(value.trim());
  return (n != null && n > 0) ? n : null;
}
