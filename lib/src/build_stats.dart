import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Oldingi yig'ishlar statistikasi. Shu tufayli foiz ko'rsatkichi ikkinchi
/// yig'ishdan boshlab juda aniq bo'ladi.
class BuildStats {
  BuildStats._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;

  static const _fileName = 'stats.json';

  static BuildStats load(String projectRoot) {
    final file = File(
      p.join(projectRoot, '.dart_tool', 'zero_up_apk', _fileName),
    );
    Map<String, dynamic> data = {};
    try {
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) data = decoded;
      }
    } catch (_) {
      data = {};
    }
    return BuildStats._(file, data);
  }

  Map<String, dynamic>? _entry(String key) {
    final e = _data[key];
    return e is Map<String, dynamic> ? e : null;
  }

  /// Shu konfiguratsiya uchun kutilayotgan davomiylik.
  Duration? expectedDuration(String key) {
    final ms = _entry(key)?['durationMs'];
    if (ms is int && ms > 0) return Duration(milliseconds: ms);
    return null;
  }

  /// Shu konfiguratsiya uchun kutilayotgan gradle task soni.
  int? expectedTasks(String key) {
    final t = _entry(key)?['tasks'];
    if (t is int && t > 0) return t;
    return null;
  }

  int successCount(String key) {
    final c = _entry(key)?['builds'];
    return c is int ? c : 0;
  }

  /// Muvaffaqiyatli yig'ishdan keyin yangilaydi (silliqlangan o'rtacha).
  void record(String key, {required Duration duration, required int tasks}) {
    final prevMs = expectedDuration(key)?.inMilliseconds;
    final prevTasks = expectedTasks(key);

    // EMA: yangi natijaga 60% og'irlik — muhit o'zgarsa tez moslashadi.
    final newMs = prevMs == null
        ? duration.inMilliseconds
        : (prevMs * 0.4 + duration.inMilliseconds * 0.6).round();
    final newTasks = tasks <= 0
        ? (prevTasks ?? 0)
        : (prevTasks == null
              ? tasks
              : (prevTasks * 0.4 + tasks * 0.6).round());

    _data[key] = {
      'durationMs': newMs,
      'tasks': newTasks,
      'builds': successCount(key) + 1,
      'lastAt': DateTime.now().toIso8601String(),
    };
    _save();
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_data));
    } catch (_) {
      // Statistika saqlanmasa ham tool ishlayveradi.
    }
  }
}
