import 'dart:io';

import 'package:path/path.dart' as p;

import 'system_info.dart';

/// gradle.properties ga kiritilgan o'zgarish haqidagi hisobot.
class TuneResult {
  TuneResult({
    required this.changed,
    required this.added,
    required this.updated,
    required this.backupPath,
    this.error,
  });

  final bool changed;
  final List<String> added;
  final List<String> updated;
  final String? backupPath;
  final String? error;

  static TuneResult none() =>
      TuneResult(changed: false, added: [], updated: [], backupPath: null);
}

/// `android/gradle.properties` faylini kompyuter quvvatiga qarab
/// tezlik uchun sozlaydi.
///
/// Faqat ishlash tezligiga ta'sir qiladigan kalitlar boshqariladi.
/// Loyiha xatti-harakatini o'zgartirishi mumkin bo'lgan kalitlarga
/// (jetifier, R8 fullMode, nonTransitiveRClass va h.k.) tegilmaydi —
/// shuning uchun yig'ish natijasi buzilmaydi.
class GradleTuner {
  GradleTuner(this.androidDir, this.system);

  final String androidDir;
  final SystemInfo system;

  static const _marker = '# --- zero_up_apk: tezlik sozlamalari ---';
  static const _backupSuffix = '.zero_up_apk.bak';

  File get _file => File(p.join(androidDir, 'gradle.properties'));
  File get _backupFile => File('${_file.path}$_backupSuffix');

  /// Boshqariladigan kalitlar va tavsiya etilgan qiymatlar.
  Map<String, String> managedValues({required bool aggressive}) {
    final jvmArgs = [
      '-Xmx${system.gradleHeapMb}m',
      '-XX:MaxMetaspaceSize=${system.metaspaceMb}m',
      '-XX:+UseParallelGC',
      '-XX:+HeapDumpOnOutOfMemoryError',
      '-Dfile.encoding=UTF-8',
    ].join(' ');

    final values = <String, String>{
      'org.gradle.jvmargs': jvmArgs,
      'org.gradle.daemon': 'true',
      'org.gradle.parallel': 'true',
      'org.gradle.caching': 'true',
      'org.gradle.workers.max': '${system.gradleWorkers}',
      'org.gradle.vfs.watch': 'true',
      'kotlin.incremental': 'true',
      'kotlin.incremental.useClasspathSnapshot': 'true',
      'kotlin.daemon.jvmargs': '-Xmx${system.kotlinHeapMb}m',
    };

    if (aggressive) {
      // Konfiguratsiyani talab bo'yicha yuklash — ko'p pluginli loyihalarda
      // sezilarli tezlik, lekin ba'zi eski pluginlar bilan muammo bo'lishi
      // mumkin. Shuning uchun faqat --aggressive bilan.
      values['org.gradle.configureondemand'] = 'true';
      if (system.ramGb >= 8) {
        values['kotlin.compiler.execution.strategy'] = 'in-process';
      }
    }
    return values;
  }

  /// Sozlamalarni yozadi. Avval zaxira nusxa yaratadi.
  TuneResult apply({bool aggressive = false}) {
    try {
      final desired = managedValues(aggressive: aggressive);
      final file = _file;
      final originalText = file.existsSync() ? file.readAsStringSync() : '';
      final lines = originalText.isEmpty
          ? <String>[]
          : originalText.replaceAll('\r\n', '\n').split('\n');

      final added = <String>[];
      final updated = <String>[];
      final handled = <String>{};

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq).trim();
        if (!desired.containsKey(key)) continue;

        final currentValue = line.substring(eq + 1).trim();
        final wanted = desired[key]!;
        handled.add(key);
        if (currentValue != wanted) {
          lines[i] = '$key=$wanted';
          updated.add(key);
        }
      }

      final missing = desired.keys.where((k) => !handled.contains(k)).toList();
      if (missing.isNotEmpty) {
        if (lines.isNotEmpty && lines.last.trim().isNotEmpty) lines.add('');
        lines.add(_marker);
        for (final key in missing) {
          lines.add('$key=${desired[key]}');
          added.add(key);
        }
        lines.add('');
      }

      if (added.isEmpty && updated.isEmpty) {
        return TuneResult(
          changed: false,
          added: const [],
          updated: const [],
          backupPath: _backupFile.existsSync() ? _backupFile.path : null,
        );
      }

      // Zaxira nusxa — faqat birinchi marta, asl holatni saqlab qolish uchun.
      if (file.existsSync() && !_backupFile.existsSync()) {
        _backupFile.writeAsStringSync(originalText);
      }

      file.parent.createSync(recursive: true);
      file.writeAsStringSync(lines.join('\n'));

      return TuneResult(
        changed: true,
        added: added,
        updated: updated,
        backupPath: _backupFile.existsSync() ? _backupFile.path : null,
      );
    } catch (e) {
      return TuneResult(
        changed: false,
        added: const [],
        updated: const [],
        backupPath: null,
        error: '$e',
      );
    }
  }

  /// Zaxira nusxadan asl gradle.properties ni tiklaydi.
  bool restore() {
    try {
      if (!_backupFile.existsSync()) return false;
      _file.writeAsStringSync(_backupFile.readAsStringSync());
      _backupFile.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get hasBackup => _backupFile.existsSync();
}
