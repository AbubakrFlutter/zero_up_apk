import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Foydalanuvchining doimiy sozlamalari — `~/.zup/config.json`.
///
/// Har safar `--out` yozib o'tirmaslik uchun: bir marta `zup config` bilan
/// sozlanadi va keyingi barcha yig'ishlarda o'sha papka ishlatiladi.
///
/// Ustuvorlik tartibi:
///   1. `--out` bayrog'i (faqat shu ishga tushirish uchun)
///   2. config.json dagi `out`
///   3. Ish stoli (Desktop) — standart holat
class ZupConfig {
  ZupConfig({
    this.outputDir,
    this.openFolder,
    this.arm64,
    this.copyOutput,
  });

  /// Yig'ilgan fayllar tushadigan papka. `null` — ish stoli (standart).
  final String? outputDir;

  /// Yig'ish tugagach papkani avtomatik ochish.
  final bool? openFolder;

  /// Standart holatda faqat arm64 uchun yig'ish.
  final bool? arm64;

  /// Fayllarni chiqish papkasiga ko'chirish.
  final bool? copyOutput;

  /// Sozlamalar faylining to'liq yo'li.
  static String? get filePath {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return p.join(home, '.zup', 'config.json');
  }

  static bool get exists {
    final path = filePath;
    return path != null && File(path).existsSync();
  }

  /// Sozlamalarni o'qiydi. Fayl yo'q yoki buzuq bo'lsa — bo'sh sozlama
  /// qaytaradi (hech qachon xato tashlamaydi: sozlama fayli tufayli
  /// yig'ish to'xtab qolmasligi kerak).
  static ZupConfig load() {
    final path = filePath;
    if (path == null) return ZupConfig();

    final file = File(path);
    if (!file.existsSync()) return ZupConfig();

    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return ZupConfig();

      return ZupConfig(
        outputDir: _readString(raw['out']),
        openFolder: _readBool(raw['open']),
        arm64: _readBool(raw['arm64']),
        copyOutput: _readBool(raw['copy']),
      );
    } catch (_) {
      // Buzuq JSON — sozlamasiz davom etamiz.
      return ZupConfig();
    }
  }

  /// Sozlamalarni saqlaydi. Muvaffaqiyatsiz bo'lsa xato matnini qaytaradi.
  String? save() {
    final path = filePath;
    if (path == null) {
      return 'USERPROFILE (uy papkasi) aniqlanmadi';
    }

    try {
      final file = File(path);
      file.parent.createSync(recursive: true);

      final data = <String, Object?>{
        if (outputDir != null) 'out': outputDir,
        if (openFolder != null) 'open': openFolder,
        if (arm64 != null) 'arm64': arm64,
        if (copyOutput != null) 'copy': copyOutput,
      };

      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(data),
      );
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Sozlamalar faylini o'chiradi (hamma narsa standart holatga qaytadi).
  static String? reset() {
    final path = filePath;
    if (path == null) return 'USERPROFILE (uy papkasi) aniqlanmadi';
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  ZupConfig copyWith({
    String? outputDir,
    bool? openFolder,
    bool? arm64,
    bool? copyOutput,
    bool clearOutputDir = false,
  }) {
    return ZupConfig(
      outputDir: clearOutputDir ? null : (outputDir ?? this.outputDir),
      openFolder: openFolder ?? this.openFolder,
      arm64: arm64 ?? this.arm64,
      copyOutput: copyOutput ?? this.copyOutput,
    );
  }

  bool get isEmpty =>
      outputDir == null &&
      openFolder == null &&
      arm64 == null &&
      copyOutput == null;

  static String? _readString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static bool? _readBool(Object? value) => value is bool ? value : null;
}

/// Papka yo'lini tekshiradi: yozish mumkinmi?
/// `null` — hammasi joyida, aks holda xato matni.
String? validateOutputDir(String path) {
  if (path.trim().isEmpty) return "Papka yo'li bo'sh";

  try {
    final dir = Directory(path);

    if (!dir.existsSync()) {
      // Papka yo'q — yaratib ko'ramiz (foydalanuvchi yangi papka nomini
      // kiritgan bo'lishi mumkin).
      dir.createSync(recursive: true);
    }

    // Haqiqatan yozish mumkinligini tekshiramiz — faqat mavjudligi yetarli
    // emas (masalan, C:\Windows ga yozib bo'lmaydi).
    final probe = File(
      p.join(dir.path, '.zup_yozish_testi_${DateTime.now().microsecondsSinceEpoch}'),
    );
    probe.writeAsStringSync('test');
    probe.deleteSync();

    return null;
  } on FileSystemException catch (e) {
    return e.osError?.message ?? e.message;
  } catch (e) {
    return e.toString();
  }
}
