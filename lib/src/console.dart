import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;


import 'output_mode.dart';

/// Windows konsolida UTF-8 ni yoqadi (o'zbekcha harflar va chizma belgilar
/// to'g'ri ko'rinishi uchun). Boshqa OS larda hech narsa qilmaydi.
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
    // Muhim emas — belgilar ASCII ga tushib qoladi.
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

/// ─────────────────────────  VIZUAL TIZIM  ─────────────────────────
///
/// Chekinish FAQAT ikki daraja:
///   2 — asosiy qatorlar (bosqich, ogohlantirish, xato, sarlavha)
///   5 — tafsilot (bosqich ostidagi izoh, harakat taklifi)
///
/// Ilgari 2, 4, 5, 6 va quti ichi — beshta har xil daraja ishlatilardi.
const int indentMain = 2;
const int indentDetail = 5;

/// "kalit: qiymat" jadvallarida kalit ustuni kengligi — HAMMA JOYDA bir xil.
/// Ilgari uch xil edi: `kv`=22, xulosa=12, MALUMOT.txt=16.
const int keyColumnWidth = 20;

/// Konsolga chiqarish uchun yagona nuqta.
///
/// Rang, belgi va kenglik haqidagi qarorlarni O'ZI QABUL QILMAYDI —
/// ularni [OutputDecision] dan oladi. Ilgari bu qaror shu klass ichida
/// tarqoq edi (`_color`, `interactive`) va Node bilan kelishmasdi.
class Ui {
  Ui(this.out, {IOSink? sink})
      : _sink = sink ?? stdout;

  /// Sinov uchun: qaror va oqimni ko'rsatmasdan.
  factory Ui.simple({bool ascii = false}) {
    bool hasTerminal;
    bool ansi;
    try {
      hasTerminal = stdout.hasTerminal;
      ansi = hasTerminal && stdout.supportsAnsiEscapes;
    } catch (_) {
      hasTerminal = false;
      ansi = false;
    }
    return Ui(decideOutput(
      ascii: ascii,
      env: Platform.environment,
      stdoutHasTerminal: hasTerminal,
      stdoutAnsi: ansi,
      stdoutColumns: hasTerminal ? stdout.terminalColumns : null,
    ));
  }

  final OutputDecision out;

  /// Chiqish oqimi. JSON rejimida `stderr` ga o'rnatiladi — stdout'da
  /// faqat bitta JSON obyekt qolishi uchun.
  final IOSink _sink;

  bool get ascii => !out.unicode;
  bool get _color => out.color;

  /// Terminal kengligi — chizishda hamma joyda shundan foydalaniladi.
  int get columns => out.columns;

  // ─────────────────────────  RANGLAR  ─────────────────────────


  String bold(String t) => _color ? '${_C.bold}$t${_C.reset}' : t;
  String dim(String t) => _color ? '${_C.dim}$t${_C.reset}' : t;
  String red(String t) => _color ? '${_C.red}$t${_C.reset}' : t;
  String green(String t) => _color ? '${_C.green}$t${_C.reset}' : t;
  String yellow(String t) => _color ? '${_C.yellow}$t${_C.reset}' : t;
  String blue(String t) => _color ? '${_C.blue}$t${_C.reset}' : t;
  String cyan(String t) => _color ? '${_C.cyan}$t${_C.reset}' : t;
  String magenta(String t) => _color ? '${_C.magenta}$t${_C.reset}' : t;
  String grey(String t) => _color ? '${_C.grey}$t${_C.reset}' : t;

  // ─────────────────────────  BELGILAR  ─────────────────────────
  //
  // HAR BIRI `--ascii` da almashadi. Ilgari `•`, `→`, `…`, `💡`, `—`
  // qattiq kodlangan edi va `--ascii` ni buzardi.

  String get sDone => ascii ? '[OK]' : '✔';
  String get sActive => ascii ? '>' : '▶';
  String get sPending => ascii ? '-' : '·';
  String get sWarn => ascii ? '[!]' : '▲';
  String get sError => ascii ? '[X]' : '✖';
  String get sAction => ascii ? '->' : '→';
  String get sBullet => ascii ? '*' : '·';
  String get sEllipsis => ascii ? '...' : '…';
  String get sSeparator => ascii ? '|' : '·';

  // ─────────────────────────  ASOSIY CHIQISH  ─────────────────────────

  bool _barActive = false;

  void _raw(String s) => _sink.write(s);

  /// Jonli progress qatorini tozalaydi (agar chizilgan bo'lsa).
  void _clearBar() {
    if (!_barActive) return;
    if (_color) {
      _raw('\x1B[2K\r');
    } else {
      // Rangsiz terminalda ham qator kengligidan oshmaydigan tozalash.
      // Ilgari bu 100 ta bo'shliq edi va tor terminalda o'ralib ketardi.
      _raw('\r${' ' * math.min(columns, 200)}\r');
    }
    _barActive = false;
  }

  void line([String text = '']) {
    _clearBar();
    _sink.writeln(text);
  }

  /// Kursorni ko'rsatadi va progress qatorini tozalaydi.
  ///
  /// Ilgari bu har doim bo'sh qator ham qo'shardi — natijada har bir
  /// ishga tushirish ikkita bo'sh qator bilan tugardi.
  void restoreCursor() {
    _clearBar();
    if (_color) _raw('\x1B[?25h');
  }

  // ─────────────────────────  BLOKLAR  ─────────────────────────

  String get _indent => ' ' * indentMain;
  String get _indentDetail => ' ' * indentDetail;

  /// Dastur sarlavhasi — bir marta, boshida.
  void header(String version, {String? subtitle}) {
    final width = math.min(columns - indentMain * 2, 58);
    final rule = (ascii ? '=' : '─') * math.max(width, 20);

    line();
    line('$_indent${cyan(rule)}');
    line(
      '$_indent${bold(magenta(ascii ? "ZERO UP APK" : "⚡ ZERO UP APK"))}'
      '  ${grey("v$version")}',
    );
    if (subtitle != null) line('$_indent${grey(subtitle)}');
    line('$_indent${cyan(rule)}');
    // Yakunlovchi bo'sh qator QO'SHILMAYDI — keyingi blok o'zi qo'shadi.
    // Ilgari ikkalasi ham qo'shib, ikkita bo'sh qator chiqardi.
  }

  /// Bo'lim sarlavhasi.
  void section(String title) {
    line();
    line('$_indent${bold(title.toUpperCase())}');
    line();
  }

  /// Tugagan bosqich.
  void done(String text, {String? hint}) => _step(green(sDone), text, hint);

  /// Hozir bajarilayotgan bosqich.
  void active(String text, {String? hint}) => _step(cyan(sActive), text, hint);

  /// Hali boshlanmagan bosqich.
  void pending(String text, {String? hint}) => _step(grey(sPending), text, hint);

  /// Ma'lumot qatori — muvaffaqiyat EMAS.
  ///
  /// Ilgari bunday qatorlar yashil `✔` bilan chiqardi va "bajarildi"
  /// degan ma'noni bergandek tuyulardi.
  void note(String text, {String? hint}) => _step(grey(sBullet), text, hint);

  void warn(String text) => _step(yellow(sWarn), text, null);
  void error(String text) => _step(red(sError), text, null);

  void _step(String symbol, String text, String? hint) {
    final prefix = '$_indent$symbol  ';
    final available = columns - _visualLength(prefix) - 1;

    if (hint == null) {
      line('$prefix${_fit(text, available)}');
      return;
    }

    // Izoh o'ng tomonda kulrang — sig'sa.
    final hintText = grey(hint);
    final combined = '$prefix$text  $hintText';
    if (_visualLength(combined) <= columns) {
      line(combined);
    } else {
      line('$prefix${_fit(text, available)}');
      detail(hint);
    }
  }

  /// Bosqich ostidagi izoh.
  void detail(String text) {
    final available = columns - indentDetail - 1;
    line('$_indentDetail${grey(_fit(text, available))}');
  }

  /// Foydalanuvchi bajarishi kerak bo'lgan harakat.
  void action(String text, {String? command}) {
    if (command == null) {
      line('$_indentDetail${cyan(sAction)} $text');
    } else {
      line('$_indentDetail${cyan(sAction)} $text');
      line('$_indentDetail  ${cyan(command)}');
    }
  }

  /// "kalit: qiymat" qatori.
  void kv(String key, String value) {
    final k = key.length >= keyColumnWidth
        ? '${key.substring(0, keyColumnWidth - 1)} '
        : key.padRight(keyColumnWidth);
    final available = columns - indentMain - keyColumnWidth - 2;
    line('$_indent${grey(k)} ${_fit(value, available)}');
  }

  // ─────────────────────────  PROGRESS  ─────────────────────────

  /// Bir qatorli foizli progress.
  ///
  /// Tor terminalda o'ralib ketmasligi kafolatlanadi — ilgari 62 ustundan
  /// tor bo'lsa bar o'raladi va `\x1B[2K` faqat oxirgi qatorni tozalab,
  /// ekranda parcha qoldirardi.
  void progress({
    required double percent,
    required String label,
    required Duration elapsed,
    Duration? remaining,
  }) {
    if (!out.isRich) return;

    if (!_barActive && _color) _raw('\x1B[?25l');

    final pct = percent.clamp(0.0, 100.0);
    final pctText = '${pct.toStringAsFixed(0).padLeft(3)}%';
    final time = formatDuration(elapsed);
    final eta = remaining == null ? '' : '  ${formatDuration(remaining)} qoldi';

    // Qat'iy qismlar: chekinish + qavslar + foiz + vaqt + ETA
    final fixed = indentMain + 2 + pctText.length + 2 + time.length + eta.length + 4;
    // Bar uchun qolgan joyning yarmi, lekin 10..26 oralig'ida.
    final barWidth = math.max(10, math.min(26, (columns - fixed) ~/ 2));
    final labelWidth = math.max(0, columns - fixed - barWidth - 2);

    final filled = (barWidth * pct / 100).round().clamp(0, barWidth);
    final fillChar = ascii ? '#' : '█';
    final emptyChar = ascii ? '.' : '░';
    final bar = fillChar * filled + emptyChar * (barWidth - filled);

    final open = ascii ? '[' : '▕';
    final close = ascii ? ']' : '▏';
    final colored = pct >= 100 ? green(bar) : cyan(bar);

    final text = labelWidth <= 3 ? '' : '  ${_fit(label, labelWidth)}';
    final output =
        '$_indent$open$colored$close  ${bold(pctText)}$text  ${grey(time)}${grey(eta)}';

    _raw(_color ? '\x1B[2K\r$output' : '\r$output');
    _barActive = true;
  }

  /// Progress qatorini yopadi.
  void progressDone(String message, {bool success = true}) {
    _clearBar();
    if (_color) _raw('\x1B[?25h');
    if (success) {
      done(message);
    } else {
      error(message);
    }
  }

  // ─────────────────────────  QUTI  ─────────────────────────

  /// Ramkali quti.
  ///
  /// Tuzatilgan xatolar:
  ///   * ajratuvchi endi `├───┤` (ilgari `│───│` chizilardi)
  ///   * uzun matn O'RALADI va kerak bo'lsa qisqartiriladi — ilgari
  ///     chegaradan oshib, yopuvchi `│` keyingi qatorga tushib ketardi
  ///   * sarlavha ham rang kodlarisiz o'lchanadi
  void box(String title, List<String> lines, {String color = 'green'}) {
    final maxWidth = math.max(24, math.min(columns - indentMain * 2, 100));

    // Mazmunni ramkaga sig'diramiz.
    final contentWidth = maxWidth - 4;
    final wrapped = <String>[];
    for (final l in lines) {
      if (_visualLength(l) <= contentWidth) {
        wrapped.add(l);
      } else if (_hasAnsi(l)) {
        // Rangli qatorni xavfsiz o'rab bo'lmaydi — qisqartiramiz.
        wrapped.add(_fit(l, contentWidth));
      } else {
        wrapped.addAll(wrapText(l, contentWidth));
      }
    }

    final width = math.min(
      maxWidth,
      math.max(
        _visualLength(title) + 4,
        wrapped.fold<int>(0, (m, l) => math.max(m, _visualLength(l))) + 4,
      ),
    );

    final h = ascii ? '-' : '─';
    final tl = ascii ? '+' : '╭';
    final tr = ascii ? '+' : '╮';
    final bl = ascii ? '+' : '╰';
    final br = ascii ? '+' : '╯';
    final v = ascii ? '|' : '│';
    final ml = ascii ? '+' : '├';
    final mr = ascii ? '+' : '┤';

    String paint(String s) => switch (color) {
      'red' => red(s),
      'yellow' => yellow(s),
      'cyan' => cyan(s),
      'grey' => grey(s),
      _ => green(s),
    };

    String row(String content) {
      final pad = ' ' * math.max(0, width - 3 - _visualLength(content));
      return '$_indent${paint(v)} $content$pad${paint(v)}';
    }

    line();
    line('$_indent${paint("$tl${h * (width - 2)}$tr")}');
    line(row(bold(title)));
    line('$_indent${paint("$ml${h * (width - 2)}$mr")}');
    for (final l in wrapped) {
      line(row(l));
    }
    line('$_indent${paint("$bl${h * (width - 2)}$br")}');
    line();
  }

  // ─────────────────────────  YORDAMCHILAR  ─────────────────────────

  static final _ansiPattern = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');

  bool _hasAnsi(String s) => _ansiPattern.hasMatch(s);

  /// Ko'rinadigan uzunlik — rang kodlari hisobga olinmaydi.
  int _visualLength(String s) => s.replaceAll(_ansiPattern, '').runes.length;

  /// Matnni berilgan kenglikka sig'diradi.
  ///
  /// Surrogat juftliklarni buzmaydi — `substring` bilan kesish `�`
  /// belgisini chiqarardi (emoji va CJK belgilarda).
  String _fit(String text, int width) {
    if (width <= 0) return '';
    if (_visualLength(text) <= width) return text;

    // Rangli matnni xavfsiz kesib bo'lmaydi — rang kodlarini yo'qotamiz.
    final plain = text.replaceAll(_ansiPattern, '');
    final runes = plain.runes.toList();
    final keep = math.max(0, width - sEllipsis.length);
    return String.fromCharCodes(runes.take(keep)) + sEllipsis;
  }
}

/// Uzun matnni so'zlar bo'yicha bir nechta qatorga bo'ladi.
///
/// Chekinish endi FAQAT shu yerda qo'shiladi — chaqiruvchi tomonda yana
/// bir marta qo'shilishi natijasida ko'chgan qatorlar 8-ustunga siljib
/// ketardi.
List<String> wrapText(String text, int width, {String indent = ''}) {
  if (width <= 4) return [text];

  final result = <String>[];
  for (final paragraph in text.split('\n')) {
    if (paragraph.trim().isEmpty) {
      result.add('');
      continue;
    }

    final words = paragraph.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    var current = StringBuffer();
    var isFirst = true;

    void flush() {
      if (current.isEmpty) return;
      result.add((isFirst ? '' : indent) + current.toString());
      isFirst = false;
      current = StringBuffer();
    }

    for (final word in words) {
      final limit = isFirst ? width : width - indent.length;

      // Chegaradan uzun so'z — bo'lib tashlaymiz, aks holda quti sinadi.
      if (word.runes.length > limit) {
        flush();
        var rest = word.runes.toList();
        while (rest.length > limit) {
          result.add((isFirst ? '' : indent) + String.fromCharCodes(rest.take(limit)));
          isFirst = false;
          rest = rest.skip(limit).toList();
        }
        if (rest.isNotEmpty) current.write(String.fromCharCodes(rest));
        continue;
      }

      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= limit) {
        current.write(' $word');
      } else {
        flush();
        current.write(word);
      }
    }
    flush();
  }

  return result.isEmpty ? [''] : result;
}

/// `MM:SS` yoki soatdan oshsa `1:05:30`.
///
/// Ilgari soatdan oshganda `1s 05d` ko'rinishiga o'tardi va bu
/// "1 sekund" deb o'qilardi.
String formatDuration(Duration d) {
  final total = d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  if (mb < 100) return '${mb.toStringAsFixed(1)} MB';
  if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}
