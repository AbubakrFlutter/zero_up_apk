import 'dart:io';

import 'package:path/path.dart' as p;

import 'build_options.dart';
import 'console.dart';
import 'project_info.dart';

/// Ish stoliga (Desktop) ko'chirilgan bitta fayl.
class DeliveredFile {
  DeliveredFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.abi,
    required this.target,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// `arm64-v8a`, `armeabi-v7a`, `x86_64` yoki null (universal).
  final String? abi;
  final BuildTarget target;

  String get readableSize => formatBytes(sizeBytes);

  /// Fayl qaysi protsessorlar uchun ekani — o'zbekcha.
  /// AAB da ABI bo'linishi Google Play tomonida bajariladi.
  String get abiText {
    if (abi != null) return '$abi protsessorlari uchun';
    if (target == BuildTarget.aab) {
      return 'Google Play barcha protsessorlar uchun o\'zi ajratadi';
    }
    return 'barcha protsessorlar uchun (universal)';
  }

  /// Yakuniy ro'yxatda qavs ichida ko'rsatiladigan qisqa yorliq.
  String get abiLabel {
    if (abi != null) return abi!;
    return target == BuildTarget.aab ? 'App Bundle' : 'universal';
  }
}

/// Yig'ilgan fayllarni topib, Desktop dagi yangi papkaga ko'chiradi.
class OutputManager {
  OutputManager({required this.project, required this.options});

  final ProjectInfo project;
  final BuildOptions options;

  /// Ish stoli papkasini aniqlaydi (OneDrive ko'chirilgan holat ham).
  static Future<String?> desktopPath() async {
    if (Platform.isWindows) {
      final fromRegistry = await _windowsDesktopFromRegistry();
      if (fromRegistry != null) return fromRegistry;
    }
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return null;

    for (final candidate in [
      p.join(home, 'Desktop'),
      p.join(home, 'OneDrive', 'Desktop'),
      p.join(home, 'Ish stoli'),
      p.join(home, 'Рабочий стол'),
    ]) {
      if (Directory(candidate).existsSync()) return candidate;
    }
    return home;
  }

  static Future<String?> _windowsDesktopFromRegistry() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders',
        '/v',
        'Desktop',
      ], runInShell: true).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return null;
      final m = RegExp(
        r'Desktop\s+REG_[A-Z_]+\s+(.+)',
      ).firstMatch(result.stdout.toString());
      if (m == null) return null;
      final path = m.group(1)!.trim();
      if (path.isNotEmpty && Directory(path).existsSync()) return path;
    } catch (_) {}
    return null;
  }

  /// Ilova nomi va versiyasi bilan yangi papka yaratadi.
  /// Masalan: `Desktop\MyApp_v1.0.0+1\`
  Future<Directory> createOutputFolder() async {
    final base = options.outputDir ?? await desktopPath();
    if (base == null) {
      throw const FileSystemException('Ish stoli papkasi topilmadi');
    }

    var name = project.outputBaseName;
    var dir = Directory(p.join(base, name));
    var counter = 2;
    while (dir.existsSync() && dir.listSync().isNotEmpty) {
      dir = Directory(p.join(base, '${name}_$counter'));
      counter++;
      if (counter > 99) break;
    }
    dir.createSync(recursive: true);
    return dir;
  }

  /// Yig'ish natijasida paydo bo'lgan fayllarni topadi.
  List<File> findArtifacts(BuildTarget target, DateTime since) {
    final dirs = <String>[
      if (target == BuildTarget.apk) ...[
        p.join(project.root, 'build', 'app', 'outputs', 'flutter-apk'),
        p.join(project.root, 'build', 'app', 'outputs', 'apk'),
      ] else ...[
        p.join(project.root, 'build', 'app', 'outputs', 'bundle'),
      ],
    ];

    final ext = target == BuildTarget.apk ? '.apk' : '.aab';
    final found = <File>[];

    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith(ext)) continue;
        // Vaqtinchalik/oraliq fayllarni chetlab o'tamiz.
        if (entity.path.contains('.tmp')) continue;
        try {
          final modified = entity.lastModifiedSync();
          if (modified.isBefore(since.subtract(const Duration(seconds: 5)))) {
            continue;
          }
        } catch (_) {
          continue;
        }
        found.add(entity);
      }
    }

    // Bir xil fayl ikki papkadan topilishi mumkin — nom bo'yicha yagonalash.
    final seen = <String>{};
    return found.where((f) => seen.add(p.basename(f.path))).toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  }

  /// Fayllarni chiroyli nom bilan chiqish papkasiga ko'chiradi.
  List<DeliveredFile> deliver(
    List<File> artifacts,
    Directory outputDir,
    BuildTarget target,
  ) {
    final delivered = <DeliveredFile>[];
    for (final file in artifacts) {
      // --arm64 rejimida fayl nomida ABI ko'rsatilmaydi, lekin u faqat
      // arm64 uchun — foydalanuvchi buni bilishi kerak.
      final abi =
          _detectAbi(p.basename(file.path)) ??
          (options.onlyArm64 && target == BuildTarget.apk
              ? 'arm64-v8a'
              : null);
      final ext = target == BuildTarget.apk ? 'apk' : 'aab';
      final suffix = abi == null ? '' : '_$abi';
      final newName = '${project.outputBaseName}$suffix.$ext';
      final destination = File(p.join(outputDir.path, newName));
      file.copySync(destination.path);
      delivered.add(
        DeliveredFile(
          path: destination.path,
          name: newName,
          sizeBytes: destination.lengthSync(),
          abi: abi,
          target: target,
        ),
      );
    }
    return delivered;
  }

  static String? _detectAbi(String fileName) {
    for (final abi in const [
      'arm64-v8a',
      'armeabi-v7a',
      'x86_64',
      'x86',
    ]) {
      if (fileName.contains(abi)) return abi;
    }
    return null;
  }

  /// Papkaga o'zbekcha ma'lumot fayli yozadi.
  void writeInfoFile({
    required Directory outputDir,
    required List<DeliveredFile> files,
    required Duration totalDuration,
    required String flutterVersion,
    required String systemSummary,
  }) {
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln('=========================================')
      ..writeln('  ZERO UP APK - yig\'ish hisoboti')
      ..writeln('=========================================')
      ..writeln()
      ..writeln('Ilova nomi      : ${project.appName}')
      ..writeln('Paket (package) : ${project.packageName}')
      ..writeln('Application ID  : ${project.applicationId ?? "aniqlanmadi"}')
      ..writeln('Versiya         : ${project.version}')
      ..writeln('Build raqami    : ${project.buildNumber ?? "-"}')
      ..writeln('Rejim           : ${options.mode.uzName}')
      ..writeln(
        'Sana            : ${_two(now.day)}.${_two(now.month)}.${now.year} '
        '${_two(now.hour)}:${_two(now.minute)}',
      )
      ..writeln('Yig\'ish vaqti   : ${formatDuration(totalDuration)}')
      ..writeln('Flutter         : $flutterVersion')
      ..writeln('Kompyuter       : $systemSummary')
      ..writeln()
      ..writeln('-----------------------------------------')
      ..writeln('  Fayllar')
      ..writeln('-----------------------------------------');

    for (final f in files) {
      b
        ..writeln()
        ..writeln('  ${f.name}')
        ..writeln('     Hajmi : ${f.readableSize}')
        ..writeln('     Turi  : ${f.target.uzName}, ${f.abiText}');
    }

    b
      ..writeln()
      ..writeln('-----------------------------------------')
      ..writeln('  Qaysi faylni tanlash kerak?')
      ..writeln('-----------------------------------------')
      ..writeln()
      ..writeln('  arm64-v8a  - zamonaviy telefonlar (99% holatda shu)')
      ..writeln('  armeabi-v7a- eski telefonlar (2016 yilgacha)')
      ..writeln('  x86_64     - emulyator va ba\'zi planshetlar')
      ..writeln('  .aab fayli - Google Play Console ga yuklash uchun')
      ..writeln()
      ..writeln('Yaratildi: zero_up_apk');

    File(
      p.join(outputDir.path, 'MALUMOT.txt'),
    ).writeAsStringSync(b.toString());
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
