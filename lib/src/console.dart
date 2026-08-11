import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

/// Windows konsolida UTF-8 ni yoqadi (kirill/lotin belgilari va progress bar
/// belgilari to'g'ri ko'rinishi uchun). Boshqa OS larda hech narsa qilmaydi.
void enableUtf8Console() {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setConsoleOutputCp = kernel32
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'SetConsoleOutputCP',
        );
    setConsoleOutputCp(65001);
  } catch (_) {
    // Muhim emas — belgilar oddiy ASCII ga tushib qoladi.
  }
}

/// ANSI rang kodlari.
class _C {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const red = '\x1B[38;5;203m';
  static const green = '\x1B[38;5;77m';
  static const yellow = '\x1B[38;5;221m';
  static const blue = '\x1B[38;5;75m';
  static const cyan = '\x1B[38;5;80m';
  static const magenta = '\x1B[38;5;177m';
  static const grey = '\x1B[38;5;245m';
}

/// Konsolga chiqarish uchun yagona nuqta: ranglar, progress bar, xabarlar.
class Ui {
  Ui({this.ascii = false});

  /// Unicode o'rniga faqat ASCII belgilardan foydalanish.
  final bool ascii;

  bool get _color {
    try {
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } catch (_) {
      return false;
    }
  }

  bool get interactive {
    try {
      return stdout.hasTerminal;
    } catch (_) {
      return false;
    }
  }

  String _w(String code, String text) => _color ? '$code$text${_C.reset}' : text;

  String bold(String t) => _w(_C.bold, t);
  String dim(String t) => _w(_C.dim, t);
  String red(String t) => _w(_C.red, t);
  String green(String t) => _w(_C.green, t);
  String yellow(String t) => _w(_C.yellow, t);
  String blue(String t) => _w(_C.blue, t);
  String cyan(String t) => _w(_C.cyan, t);
  String magenta(String t) => _w(_C.magenta, t);
  String grey(String t) => _w(_C.grey, t);

  String get _tick => ascii ? '[OK]' : '✔';
  String get _cross => ascii ? '[X]' : '✖';
  String get _warnSign => ascii ? '[!]' : '▲';
  String get _infoSign => ascii ? '[i]' : '•';
  String get _arrow => ascii ? '->' : '›';

  bool _barActive = false;

  void _raw(String s) => stdout.write(s);

  void _clearLine() {
    if (_barActive) {
      _raw(_color ? '\x1B[2K\r' : '\r${' ' * 100}\r');
      _barActive = false;
    }
  }

  /// Terminalga kursorni qaytarish (dastur tugaganda yoki to'xtatilganda)
  void restoreCursor() {
    _clearLine();
    // Kursorni ko'rsatish
    if (_color) {
      _raw('\x1B[?25h');
    }
    // Yangi qator qo'shish - terminal prompt uchun
    stdout.writeln();
  }

  void line([String text = '']) {
    _clearLine();
    stdout.writeln(text);
  }

  void banner(String version) {
    final bar = ascii ? '=' * 58 : '─' * 58;
    line();
    line('  ${cyan(bar)}');
    line(
      '  ${bold(magenta(ascii ? "ZERO UP APK" : "⚡ ZERO UP APK"))}  '
      '${grey("v$version")}',
    );
    line('  ${grey("Flutter APK / App Bundle tezkor yig'uvchi")}');
    line('  ${cyan(bar)}');
    line();
  }

  void section(String title) {
    line();
    line('  ${bold(blue("$_arrow $title"))}');
  }

  void step(String text) => line('    ${grey(_infoSign)} $text');
  void ok(String text) => line('    ${green(_tick)} $text');
  void warn(String text) => line('    ${yellow(_warnSign)} $text');
  void error(String text) => line('    ${red(_cross)} $text');
  void detail(String text) => line('      ${grey(text)}');

  void kv(String key, String value) {
    final k = key.padRight(22);
    line('    ${grey(k)} ${bold(value)}');
  }

  /// Bir qatorli foizli progress chizig'i.
  void progress({
    required double percent,
    required String label,
    required Duration elapsed,
  }) {
    final p = percent.clamp(0.0, 100.0);
    if (!interactive) return;

    // Birinchi marta chaqirilganda kursorni yashirish
    if (!_barActive && _color) {
      _raw('\x1B[?25l'); // Hide cursor
    }

    const width = 26;
    final filled = (width * p / 100).round().clamp(0, width);
    final fillChar = ascii ? '#' : '█';
    final emptyChar = ascii ? '.' : '░';
    final bar = fillChar * filled + emptyChar * (width - filled);

    final pctText = '${p.toStringAsFixed(0).padLeft(3)}%';
    final time = formatDuration(elapsed);

    var text = label;
    final maxLabel = _labelWidth();
    if (text.length > maxLabel) {
      text = '${text.substring(0, maxLabel - 1)}…';
    }
    text = text.padRight(maxLabel);

    final colored = p >= 100 ? green(bar) : cyan(bar);
    final out = '  ${ascii ? "[" : "▕"}$colored${ascii ? "]" : "▏"}  '
        '${bold(pctText)}  $text ${grey(time)}';

    _raw(_color ? '\x1B[2K\r$out' : '\r$out');
    _barActive = true;
  }

  int _labelWidth() {
    var w = 44;
    try {
      if (stdout.hasTerminal) {
        w = math.max(18, math.min(48, stdout.terminalColumns - 48));
      }
    } catch (_) {}
    return w;
  }

  /// Progress qatorini yopib, o'rniga yakuniy xabar qo'yadi.
  void progressDone(String message, {bool success = true}) {
    _clearLine();
    // Kursorni qaytarish
    if (_color) {
      _raw('\x1B[?25h'); // Show cursor
    }
    if (success) {
      ok(message);
    } else {
      error(message);
    }
  }

  /// Terminalga sig'adigan maksimal quti kengligi.
  int get _maxBoxWidth {
    try {
      if (stdout.hasTerminal) {
        return math.max(40, math.min(110, stdout.terminalColumns - 4));
      }
    } catch (_) {}
    return 96;
  }

  void box(String title, List<String> lines, {String color = 'green'}) {
    final width = math.min(
      _maxBoxWidth,
      math.max(
        title.length + 4,
        lines.fold<int>(0, (m, l) => math.max(m, _visualLength(l))) + 4,
      ),
    );
    final h = ascii ? '-' : '─';
    final tl = ascii ? '+' : '╭';
    final tr = ascii ? '+' : '╮';
    final bl = ascii ? '+' : '╰';
    final br = ascii ? '+' : '╯';
    final v = ascii ? '|' : '│';

    String paint(String s) => switch (color) {
      'red' => red(s),
      'yellow' => yellow(s),
      'cyan' => cyan(s),
      _ => green(s),
    };

    line();
    line('  ${paint("$tl${h * (width - 2)}$tr")}');
    line(
      '  ${paint(v)} ${bold(title)}${' ' * (width - 3 - title.length)}'
      '${paint(v)}',
    );
    line('  ${paint("$v${h * (width - 2)}$v")}');
    for (final l in lines) {
      final pad = ' ' * math.max(0, width - 3 - _visualLength(l));
      line('  ${paint(v)} $l$pad${paint(v)}');
    }
    line('  ${paint("$bl${h * (width - 2)}$br")}');
    line();
  }

  int _visualLength(String s) =>
      s.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').length;

  /// Foydalanuvchidan tanlov so'raydi (interaktiv menyu).
  String? ask(String prompt, {String? defaultValue}) {
    _clearLine();
    stdout.write('  $prompt ');
    final answer = stdin.readLineSync();
    if (answer == null || answer.trim().isEmpty) return defaultValue;
    return answer.trim();
  }
}

/// Uzun matnni so'zlar bo'yicha bir nechta qatorga bo'ladi.
/// Ikkinchi va keyingi qatorlar [indent] bilan chekinadi.
List<String> wrapText(String text, int width, {String indent = ''}) {
  if (width <= 8) return [text];
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = StringBuffer();

  for (final word in words) {
    final limit = lines.isEmpty ? width : width - indent.length;
    if (current.isEmpty) {
      current.write(word);
    } else if (current.length + 1 + word.length <= limit) {
      current.write(' $word');
    } else {
      lines.add(lines.isEmpty ? current.toString() : '$indent$current');
      current = StringBuffer(word);
    }
  }
  if (current.isNotEmpty) {
    lines.add(lines.isEmpty ? current.toString() : '$indent$current');
  }
  return lines.isEmpty ? [''] : lines;
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (m >= 60) {
    final h = d.inHours;
    return '${h}s ${(m % 60).toString().padLeft(2, '0')}d';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[i]}';
}
