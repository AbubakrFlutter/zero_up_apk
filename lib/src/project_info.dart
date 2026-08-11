import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Flutter loyihasi haqidagi ma'lumot: ilova nomi, versiya, papkalar.
class ProjectInfo {
  ProjectInfo({
    required this.root,
    required this.packageName,
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.hasAndroid,
    required this.applicationId,
  });

  final String root;

  /// pubspec.yaml dagi `name`.
  final String packageName;

  /// Foydalanuvchi ko'radigan ilova nomi (AndroidManifest android:label).
  final String appName;

  /// `1.0.0` ko'rinishidagi versiya.
  final String version;

  /// `+` dan keyingi build raqami (bo'lmasa null).
  final String? buildNumber;

  final bool hasAndroid;

  /// `com.example.app` — applicationId / package.
  final String? applicationId;

  String get androidDir => p.join(root, 'android');

  /// `1.0.0+1` yoki `1.0.0`.
  String get fullVersion =>
      buildNumber == null ? version : '$version+$buildNumber';

  /// Fayl/papka nomi uchun xavfsiz ko'rinish: `MyApp_v1.0.0+1`.
  String get outputBaseName =>
      '${sanitizeFileName(appName)}_v${sanitizeFileName(fullVersion)}';

  static ProjectInfo? load(String root) {
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) return null;

    late final YamlMap yaml;
    try {
      final parsed = loadYaml(pubspecFile.readAsStringSync());
      if (parsed is! YamlMap) return null;
      yaml = parsed;
    } catch (_) {
      return null;
    }

    final packageName = (yaml['name'] as Object?)?.toString() ?? 'ilova';
    final rawVersion = (yaml['version'] as Object?)?.toString() ?? '1.0.0';
    final versionParts = rawVersion.split('+');
    final version = versionParts.first.trim().isEmpty
        ? '1.0.0'
        : versionParts.first.trim();
    final buildNumber = versionParts.length > 1 ? versionParts[1].trim() : null;

    final androidDir = Directory(p.join(root, 'android'));
    final hasAndroid = androidDir.existsSync();

    final label = hasAndroid ? _readAppLabel(root) : null;
    final appId = hasAndroid ? _readApplicationId(root) : null;

    return ProjectInfo(
      root: root,
      packageName: packageName,
      appName: label ?? _prettify(packageName),
      version: version,
      buildNumber: buildNumber,
      hasAndroid: hasAndroid,
      applicationId: appId,
    );
  }

  static String _prettify(String packageName) => packageName
      .split(RegExp(r'[_\-]'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// AndroidManifest.xml dan `android:label` ni o'qiydi, `@string/...`
  /// bo'lsa strings.xml dan qiymatini topadi.
  static String? _readAppLabel(String root) {
    try {
      final manifest = File(
        p.join(root, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
      );
      if (!manifest.existsSync()) return null;
      final text = manifest.readAsStringSync();
      final m = RegExp(r'android:label\s*=\s*"([^"]*)"').firstMatch(text);
      if (m == null) return null;
      final value = m.group(1)!.trim();
      if (value.isEmpty) return null;

      if (value.startsWith('@string/')) {
        final key = value.substring('@string/'.length);
        final strings = File(
          p.join(
            root,
            'android',
            'app',
            'src',
            'main',
            'res',
            'values',
            'strings.xml',
          ),
        );
        if (strings.existsSync()) {
          final sm = RegExp(
            '<string[^>]*name\\s*=\\s*"${RegExp.escape(key)}"[^>]*>(.*?)</string>',
            dotAll: true,
          ).firstMatch(strings.readAsStringSync());
          if (sm != null) {
            final resolved = sm.group(1)!.trim();
            if (resolved.isNotEmpty) return resolved;
          }
        }
        return null;
      }
      return value;
    } catch (_) {
      return null;
    }
  }

  static String? _readApplicationId(String root) {
    for (final name in ['build.gradle.kts', 'build.gradle']) {
      final f = File(p.join(root, 'android', 'app', name));
      if (!f.existsSync()) continue;
      try {
        final text = f.readAsStringSync();
        final m = RegExp(
          r'''applicationId\s*=?\s*["']([^"']+)["']''',
        ).firstMatch(text);
        if (m != null) return m.group(1);
      } catch (_) {}
    }
    return null;
  }
}

/// Windows/Unix fayl tizimi uchun xavfsiz nom.
String sanitizeFileName(String input) {
  var out = input.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '');
  out = out.replaceAll(RegExp(r'\s+'), '_');
  out = out.replaceAll(RegExp(r'_{2,}'), '_');
  out = out.replaceAll(RegExp(r'^[._]+|[._]+$'), '');
  if (out.isEmpty) out = 'ilova';
  return out.length > 60 ? out.substring(0, 60) : out;
}
