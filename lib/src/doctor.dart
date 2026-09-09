import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_info.dart';
import 'system_info.dart';

/// Bitta tekshiruv natijasi.
class DoctorCheck {
  const DoctorCheck({
    required this.id,
    required this.label,
    required this.status,
    required this.message,
    this.value,
    this.path,
    this.remedies = const [],
  });

  /// Barqaror ID — agent aynan shu tekshiruvni topa olishi uchun.
  final String id;

  final String label;
  final DoctorStatus status;
  final String message;

  /// Topilgan qiymat (versiya, son).
  final String? value;

  /// Topilgan yo'l.
  final String? path;

  final List<String> remedies;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'status': status.name,
        'value': value,
        'path': path,
        'message': message,
        'remedies': remedies,
      };
}

enum DoctorStatus { pass, warn, fail, skip }

/// Muhitni tekshiradi.
///
/// Ba'zi faktlarni Dart o'zi bila olmaydi (Node qaysi Dart'ni topgani,
/// binary bloklangani) — ular muhit o'zgaruvchilari orqali keladi.
class Doctor {
  Doctor({required this.env, this.projectPath});

  final Map<String, String> env;
  final String? projectPath;

  Future<List<DoctorCheck>> run() async {
    // Ketma-ket emas, parallel — `flutter --version` sekin ishlaydi.
    final results = await Future.wait([
      _checkFlutter(),
      _checkDart(),
      _checkJava(),
      _checkAndroidSdk(),
      _checkAdb(),
      _checkDisk(),
    ]);

    return [
      ...results,
      _checkZupBinary(),
      if (projectPath != null) ..._checkProject(projectPath!),
    ];
  }

  // ─────────────────────────  ASBOBLAR  ─────────────────────────

  Future<DoctorCheck> _checkFlutter() async {
    final found = await _runTool('flutter', ['--version']);
    if (found == null) {
      return const DoctorCheck(
        id: 'flutter',
        label: 'Flutter SDK',
        status: DoctorStatus.fail,
        message: "Flutter topilmadi — zup usiz ishlay olmaydi",
        remedies: [
          "Flutter o'rnating: https://docs.flutter.dev/get-started/install",
          "O'rnatilgan bo'lsa, flutter/bin ni PATH ga qo'shing",
        ],
      );
    }

    final version = RegExp(r'Flutter (\S+)').firstMatch(found)?.group(1);
    return DoctorCheck(
      id: 'flutter',
      label: 'Flutter SDK',
      status: DoctorStatus.pass,
      value: version,
      message: 'Flutter ${version ?? "topildi"}',
    );
  }

  Future<DoctorCheck> _checkDart() async {
    // Node qaysi Dart'ni topganini bilamiz — uni takrorlab qidirmaymiz.
    final fromNode = env['ZUP_DART_PATH'];
    final output = await _runTool(fromNode ?? 'dart', ['--version']);

    if (output == null) {
      return const DoctorCheck(
        id: 'dart',
        label: 'Dart SDK',
        status: DoctorStatus.fail,
        message: "Dart topilmadi — zup kompilyatsiya qilinmaydi",
        remedies: ['Dart Flutter bilan birga keladi — Flutter o\'rnating'],
      );
    }

    final version = RegExp(r'version: (\S+)').firstMatch(output)?.group(1) ??
        RegExp(r'Dart SDK version: (\S+)').firstMatch(output)?.group(1);
    return DoctorCheck(
      id: 'dart',
      label: 'Dart SDK',
      status: DoctorStatus.pass,
      value: version,
      path: fromNode,
      message: 'Dart ${version ?? "topildi"}',
    );
  }

  Future<DoctorCheck> _checkJava() async {
    final output = await _runTool('java', ['-version']);
    if (output == null) {
      return const DoctorCheck(
        id: 'java',
        label: 'Java / JDK',
        status: DoctorStatus.warn,
        message: "java topilmadi — Gradle ishlamasligi mumkin",
        remedies: [
          'Android Studio bilan birga keladigan JDK dan foydalaning',
          'Yoki JDK 17 o\'rnating',
        ],
      );
    }

    final version =
        RegExp(r'version "([^"]+)"').firstMatch(output)?.group(1);
    return DoctorCheck(
      id: 'java',
      label: 'Java / JDK',
      status: DoctorStatus.pass,
      value: version,
      message: 'Java ${version ?? "topildi"}',
    );
  }

  Future<DoctorCheck> _checkAndroidSdk() async {
    final home = env['ANDROID_HOME'] ??
        env['ANDROID_SDK_ROOT'] ??
        _defaultSdkPath();

    if (home == null || !Directory(home).existsSync()) {
      return const DoctorCheck(
        id: 'android_sdk',
        label: 'Android SDK',
        status: DoctorStatus.fail,
        message: "Android SDK topilmadi",
        remedies: [
          'Android Studio orqali SDK o\'rnating',
          'Yoki ANDROID_HOME ni to\'g\'ri ko\'rsating',
        ],
      );
    }

    return DoctorCheck(
      id: 'android_sdk',
      label: 'Android SDK',
      status: DoctorStatus.pass,
      path: home,
      message: 'Android SDK topildi',
    );
  }

  Future<DoctorCheck> _checkAdb() async {
    final adb = findAdb(env);
    if (adb == null) {
      return const DoctorCheck(
        id: 'adb',
        label: 'adb (qurilmaga o\'rnatish)',
        status: DoctorStatus.warn,
        message: "adb topilmadi — 'zup apk -i' ishlamaydi",
        remedies: [
          'Android SDK platform-tools ni o\'rnating',
          'Yoki platform-tools papkasini PATH ga qo\'shing',
        ],
      );
    }

    final output = await _runTool(adb, ['version']);
    final version =
        RegExp(r'version (\S+)').firstMatch(output ?? '')?.group(1);

    return DoctorCheck(
      id: 'adb',
      label: 'adb (qurilmaga o\'rnatish)',
      status: DoctorStatus.pass,
      value: version,
      path: adb,
      message: 'adb ${version ?? "topildi"}',
    );
  }

  Future<DoctorCheck> _checkDisk() async {
    final free = await SystemInfo.freeDiskGb(projectPath ?? '.');
    if (free == null) {
      return const DoctorCheck(
        id: 'disk_space',
        label: 'Disk bo\'sh joyi',
        status: DoctorStatus.skip,
        message: "Aniqlab bo'lmadi",
      );
    }

    final gb = free.toStringAsFixed(1);
    if (free < 5) {
      return DoctorCheck(
        id: 'disk_space',
        label: 'Disk bo\'sh joyi',
        status: DoctorStatus.warn,
        value: '$gb GB',
        message: "Atigi $gb GB — yig'ish uchun kamida 5 GB tavsiya etiladi",
        remedies: [
          "'gradlew --stop' so'ng Gradle keshini tozalang",
          "'flutter clean' bilan eski build fayllarini o'chiring",
        ],
      );
    }

    return DoctorCheck(
      id: 'disk_space',
      label: 'Disk bo\'sh joyi',
      status: DoctorStatus.pass,
      value: '$gb GB',
      message: '$gb GB bo\'sh',
    );
  }

  DoctorCheck _checkZupBinary() {
    final blocked = env['ZUP_BINARY_BLOCKED'] == '1';
    final mode = env['ZUP_RUN_MODE'];

    if (blocked) {
      return const DoctorCheck(
        id: 'zup_binary',
        label: 'zup ishga tushishi',
        status: DoctorStatus.warn,
        message: 'Windows kompilyatsiya qilingan faylni bloklagan — '
            'zup manba koddan ishlayapti (biroz sekinroq)',
        remedies: [
          'Hammasi ishlaydi, faqat boshlanishi ~3 soniya sekinroq',
        ],
      );
    }

    return DoctorCheck(
      id: 'zup_binary',
      label: 'zup ishga tushishi',
      status: DoctorStatus.pass,
      value: mode,
      message: mode == 'source'
          ? 'Manba koddan ishlayapti'
          : 'Kompilyatsiya qilingan fayldan ishlayapti',
    );
  }

  List<DoctorCheck> _checkProject(String root) {
    final project = ProjectInfo.load(root);
    if (project == null) {
      return [
        DoctorCheck(
          id: 'project',
          label: 'Flutter loyihasi',
          status: DoctorStatus.warn,
          path: root,
          message: "Bu papkada Flutter loyihasi yo'q",
          remedies: const ['Flutter loyihangizga kirib qayta tekshiring'],
        ),
      ];
    }

    final checks = <DoctorCheck>[
      DoctorCheck(
        id: 'project',
        label: 'Flutter loyihasi',
        status: DoctorStatus.pass,
        value: project.fullVersion,
        path: project.root,
        message: '${project.appName} ${project.fullVersion}',
      ),
    ];

    if (!project.hasAndroid) {
      checks.add(const DoctorCheck(
        id: 'android_dir',
        label: "'android' papkasi",
        status: DoctorStatus.fail,
        message: "'android' papkasi yo'q — APK yig'ib bo'lmaydi",
        remedies: ["Ilova loyihasida ishlating (paket/plugin emas)"],
      ));
    } else {
      checks.add(const DoctorCheck(
        id: 'android_dir',
        label: "'android' papkasi",
        status: DoctorStatus.pass,
        message: 'Joyida',
      ));

      // Imzolash sozlangamnmi — release yig'ish uchun kerak.
      final keyProps = File(p.join(project.androidDir, 'key.properties'));
      checks.add(DoctorCheck(
        id: 'signing',
        label: 'Release imzolash',
        status: keyProps.existsSync()
            ? DoctorStatus.pass
            : DoctorStatus.warn,
        path: keyProps.existsSync() ? keyProps.path : null,
        message: keyProps.existsSync()
            ? 'key.properties topildi'
            : "key.properties yo'q — release APK imzolanmaydi",
        remedies: keyProps.existsSync()
            ? const []
            : const [
                'Google Play uchun imzolash sozlanishi kerak',
                'Sinov uchun: zup apk --mode debug',
              ],
      ));
    }

    return checks;
  }

  // ─────────────────────────  YORDAMCHILAR  ─────────────────────────

  static String? _defaultSdkPath() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    if (home == null) return null;

    for (final candidate in [
      if (Platform.isWindows) p.join(home, 'AppData', 'Local', 'Android', 'Sdk'),
      if (Platform.isMacOS) p.join(home, 'Library', 'Android', 'sdk'),
      p.join(home, 'Android', 'Sdk'),
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<String?> _runTool(String executable, List<String> args) async {
    try {
      final result = await Process.run(
        executable,
        args,
        runInShell: true,
      ).timeout(const Duration(seconds: 20));
      if (result.exitCode != 0) return null;
      // `java -version` stderr ga yozadi.
      final out = '${result.stdout}${result.stderr}'.trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }
}

/// adb ni topadi: PATH, keyin Android SDK ning odatiy joylari.
String? findAdb(Map<String, String> env) {
  final exe = Platform.isWindows ? 'adb.exe' : 'adb';

  final roots = <String?>[
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    Doctor._defaultSdkPath(),
  ];

  for (final root in roots) {
    if (root == null) continue;
    final candidate = File(p.join(root, 'platform-tools', exe));
    if (candidate.existsSync()) return candidate.path;
  }

  // PATH da bormi?
  try {
    final which = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(which, ['adb'], runInShell: true);
    if (result.exitCode == 0) {
      final first = result.stdout.toString().split('\n').first.trim();
      if (first.isNotEmpty && File(first).existsSync()) return first;
    }
  } catch (_) {}

  return null;
}
