import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Yig'ishlar tarixi — `zup last` uchun.
///
/// NEGA `build_stats.dart` KENGAYTIRILMADI: u boshqa vazifani bajaradi —
/// har bir konfiguratsiya uchun BITTA silliqlangan vaqt taxminini saqlaydi
/// va har bir yig'ishning issiq yo'lida o'qiladi. Unga har bir ishga
/// tushirishning artefaktlari va loglarini qo'shsak:
///   * progress taxmini cheksiz o'sadigan faylga bog'lanib qoladi
///   * buzilgan bitta yozuv progress barni ishdan chiqaradi
///   * u faqat muvaffaqiyatlarni yozadi, tarix esa xatolarni ham
///     ko'rsatishi kerak (agent uchun eng qimmatlisi shu)
class BuildHistory {
  BuildHistory(this.projectRoot);

  final String projectRoot;

  static const int _maxEntries = 20;
  static const int schemaVersion = 1;

  String get _path =>
      p.join(projectRoot, '.dart_tool', 'zero_up_apk', 'history.json');

  /// Yozuvlarni o'qiydi — eng yangisi birinchi.
  List<HistoryEntry> load() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return [];

      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map) return [];
      if (raw['schemaVersion'] != schemaVersion) return [];

      final entries = raw['entries'];
      if (entries is! List) return [];

      return entries
          .whereType<Map>()
          .map((e) => HistoryEntry.fromJson(e.cast<String, Object?>()))
          .toList();
    } catch (_) {
      // Buzuq tarix tufayli zup ishdan chiqmasligi kerak.
      return [];
    }
  }

  /// Yangi yozuv qo'shadi (eng boshiga).
  void add(HistoryEntry entry) {
    try {
      final entries = load()
        ..insert(0, entry);
      final trimmed =
          entries.length > _maxEntries ? entries.sublist(0, _maxEntries) : entries;

      final file = File(_path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': schemaVersion,
          'entries': trimmed.map((e) => e.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Tarix yozilmasa ham yig'ish muvaffaqiyatli hisoblanadi.
    }
  }
}

/// Bitta yig'ish haqidagi yozuv.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.zupVersion,
    required this.startedAt,
    required this.durationMs,
    required this.ok,
    required this.exitCode,
    required this.targets,
    required this.mode,
    this.appVersion,
    this.onlyArm64 = false,
    this.flavor,
    this.outputDir,
    this.logPath,
    this.failureCode,
    this.artifacts = const [],
  });

  factory HistoryEntry.fromJson(Map<String, Object?> json) {
    return HistoryEntry(
      id: json['id'] as String? ?? '',
      zupVersion: json['zupVersion'] as String? ?? '',
      startedAt: json['startedAt'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      ok: json['ok'] as bool? ?? false,
      exitCode: (json['exitCode'] as num?)?.toInt() ?? 0,
      targets: (json['targets'] as List?)?.cast<String>() ?? const [],
      mode: json['mode'] as String? ?? 'release',
      appVersion: json['appVersion'] as String?,
      onlyArm64: json['onlyArm64'] as bool? ?? false,
      flavor: json['flavor'] as String?,
      outputDir: json['outputDir'] as String?,
      logPath: json['logPath'] as String?,
      failureCode: json['failureCode'] as String?,
      artifacts: (json['artifacts'] as List?)
              ?.whereType<Map>()
              .map((a) => HistoryArtifact.fromJson(a.cast<String, Object?>()))
              .toList() ??
          const [],
    );
  }

  final String id;
  final String zupVersion;
  final String startedAt;
  final int durationMs;
  final bool ok;
  final int exitCode;
  final List<String> targets;
  final String mode;
  final String? appVersion;
  final bool onlyArm64;
  final String? flavor;
  final String? outputDir;
  final String? logPath;
  final String? failureCode;
  final List<HistoryArtifact> artifacts;

  DateTime? get startedAtTime => DateTime.tryParse(startedAt);

  Map<String, Object?> toJson() => {
        'id': id,
        'zupVersion': zupVersion,
        'startedAt': startedAt,
        'durationMs': durationMs,
        'ok': ok,
        'exitCode': exitCode,
        'targets': targets,
        'mode': mode,
        'appVersion': appVersion,
        'onlyArm64': onlyArm64,
        'flavor': flavor,
        'outputDir': outputDir,
        'logPath': logPath,
        'failureCode': failureCode,
        'artifacts': artifacts.map((a) => a.toJson()).toList(),
      };
}

/// Tarixdagi bitta fayl.
class HistoryArtifact {
  const HistoryArtifact({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    this.abi,
  });

  factory HistoryArtifact.fromJson(Map<String, Object?> json) {
    return HistoryArtifact(
      fileName: json['fileName'] as String? ?? '',
      path: json['path'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      abi: json['abi'] as String?,
    );
  }

  final String fileName;
  final String path;
  final int sizeBytes;
  final String? abi;

  /// Fayl hali ham joyidami — o'qish paytida tekshiriladi.
  ///
  /// Agent "oxirgi nima yig'gandim, u hali turibdimi?" degan savolga
  /// rost javob olishi kerak.
  bool get exists {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Map<String, Object?> toJson() => {
        'fileName': fileName,
        'path': path,
        'sizeBytes': sizeBytes,
        'abi': abi,
      };

  Map<String, Object?> toJsonWithExists() => {
        ...toJson(),
        'exists': exists,
      };
}
