import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'build_options.dart';
import 'build_stats.dart';
import 'console.dart';
import 'progress_tracker.dart';
import 'project_info.dart';

/// Bitta yig'ish natijasi.
class BuildResult {
  BuildResult({
    required this.success,
    required this.exitCode,
    required this.duration,
    required this.logTail,
    required this.logPath,
    required this.taskCount,
    required this.startedAt,
    this.cancelled = false,
  });

  final bool success;
  final int exitCode;
  final Duration duration;

  /// Xatoni tahlil qilish uchun logning oxirgi qismi.
  final List<String> logTail;
  final String logPath;
  final int taskCount;
  final DateTime startedAt;
  final bool cancelled;
}

/// `flutter build ...` ni ishga tushirib, jarayonni foizlarda ko'rsatadi.
class FlutterBuilder {
  FlutterBuilder({
    required this.ui,
    required this.project,
    required this.options,
    required this.stats,
  });

  final Ui ui;
  final ProjectInfo project;
  final BuildOptions options;
  final BuildStats stats;

  Process? _current;
  bool _cancelled = false;

  static const _maxTailLines = 600;

  String get _flutterExecutable => 'flutter';

  /// `flutter pub get` kerakmi? (pubspec o'zgarmagan bo'lsa - kerak emas,
  /// bu har bir yig'ishdan 3-10 soniya tejaydi)
  bool needsPubGet() {
    try {
      final pubspec = File(p.join(project.root, 'pubspec.yaml'));
      final config = File(
        p.join(project.root, '.dart_tool', 'package_config.json'),
      );
      if (!config.existsSync()) return true;
      if (!pubspec.existsSync()) return false;

      final lock = File(p.join(project.root, 'pubspec.lock'));
      final configTime = config.lastModifiedSync();
      if (pubspec.lastModifiedSync().isAfter(configTime)) return true;
      if (lock.existsSync() && lock.lastModifiedSync().isAfter(configTime)) {
        return true;
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Flutter versiyasini fon rejimida aniqlaydi.
  Future<String> detectFlutterVersion() async {
    try {
      final r = await Process.run(
        _flutterExecutable,
        ['--version'],
        runInShell: Platform.isWindows,
        // Flutter UTF-8 da yozadi — tizim kodlashi bilan o'qilsa,
        // maxsus belgilar buzilib ketadi.
        stdoutEncoding: const Utf8Codec(allowMalformed: true),
        stderrEncoding: const Utf8Codec(allowMalformed: true),
      ).timeout(const Duration(seconds: 60));
      final first = r.stdout
          .toString()
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
      return first.trim().isEmpty ? 'aniqlanmadi' : first.trim();
    } catch (_) {
      return 'aniqlanmadi';
    }
  }

  /// `flutter build` argumentlarini yig'adi.
  List<String> buildArguments(BuildTarget target) {
    final args = <String>['build', target.flutterCommand];

    args.add('--${options.mode.flag}');

    if (options.onlyArm64) {
      args.add('--target-platform=android-arm64');
    } else if (target == BuildTarget.apk && options.splitPerAbi) {
      args.add('--split-per-abi');
    }

    if (options.mode == BuildMode.release) {
      // Ishlatilmagan ikonka glyphlarini olib tashlaydi (hajm kamayadi).
      args.add('--tree-shake-icons');
      if (options.obfuscate) {
        args
          ..add('--obfuscate')
          ..add(
            '--split-debug-info=${p.join('build', 'zero_up_apk', 'symbols')}',
          );
      }
    }

    if (options.flavor != null) args.add('--flavor=${options.flavor}');
    if (options.buildName != null) {
      args.add('--build-name=${options.buildName}');
    }
    if (options.buildNumber != null) {
      args.add('--build-number=${options.buildNumber}');
    }
    for (final define in options.dartDefines) {
      args.add('--dart-define=$define');
    }
    args.addAll(options.extraArgs);

    // Gradle task nomlarini ko'rish uchun kerak — aynan shu tufayli
    // foiz ko'rsatkichi haqiqiy jarayonga mos bo'ladi.
    args.add('-v');

    return args;
  }

  /// `flutter clean` — faqat so'ralganda.
  Future<bool> clean() async {
    try {
      final r = await Process.run(
        _flutterExecutable,
        ['clean'],
        workingDirectory: project.root,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(minutes: 5));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// `flutter pub get`.
  Future<bool> pubGet() async {
    try {
      final r = await Process.run(
        _flutterExecutable,
        ['pub', 'get'],
        workingDirectory: project.root,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(minutes: 10));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Asosiy yig'ish — jarayon davomida foizli chiziq yangilanib turadi.
  Future<BuildResult> build(BuildTarget target) async {
    final key = options.statsKey(target);
    final tracker = ProgressTracker(
      expectedDuration: stats.expectedDuration(key),
      expectedTasks: stats.expectedTasks(key),
    );

    final startedAt = DateTime.now();
    final logFile = File(
      p.join(project.root, 'build', 'zero_up_apk', 'log', '${target.name}.log'),
    );
    logFile.parent.createSync(recursive: true);
    final logSink = logFile.openWrite();

    final tail = <String>[];
    void record(String line) {
      logSink.writeln(line);
      tail.add(line);
      if (tail.length > _maxTailLines) tail.removeAt(0);
      tracker.onLine(line);
      if (options.verbose) {
        ui.line(ui.grey(line));
      }
    }

    final args = buildArguments(target);
    logSink.writeln('> flutter ${args.join(' ')}');

    Process process;
    try {
      process = await Process.start(
        _flutterExecutable,
        args,
        workingDirectory: project.root,
        runInShell: Platform.isWindows,
      );
    } catch (e) {
      await logSink.close();
      return BuildResult(
        success: false,
        exitCode: -1,
        duration: DateTime.now().difference(startedAt),
        logTail: ['flutter buyrug\'ini ishga tushirib bo\'lmadi: $e'],
        logPath: logFile.path,
        taskCount: 0,
        startedAt: startedAt,
      );
    }
    _current = process;

    final decoder = const Utf8Decoder(allowMalformed: true);
    final stdoutDone = process.stdout
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(record)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(decoder)
        .transform(const LineSplitter())
        .listen(record)
        .asFuture<void>();

    Timer? timer;
    if (!options.verbose) {
      var lastMilestone = 0;
      timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        tracker.tick();
        if (ui.interactive) {
          ui.progress(
            percent: tracker.percent,
            label: tracker.label,
            elapsed: DateTime.now().difference(startedAt),
          );
        } else {
          // Terminal bo'lmaganda (log faylga yozilganda) har 10% da bir marta.
          final milestone = (tracker.percent ~/ 10) * 10;
          if (milestone > lastMilestone) {
            lastMilestone = milestone;
            ui.line('    $milestone% — ${tracker.label}');
          }
        }
      });
    }

    final code = await process.exitCode;
    timer?.cancel();
    await Future.wait([stdoutDone, stderrDone]);
    await logSink.flush();
    await logSink.close();
    _current = null;

    final duration = DateTime.now().difference(startedAt);

    // Muvaffaqiyatni to'g'ri baholash:
    // 1. Exit code 0 bo'lishi kerak
    // 2. Bekor qilinmagan bo'lishi kerak
    // 3. Logda "Built" yozuvi bo'lishi kerak (tracker.built)
    // 4. Logda BUILD FAILED yoki FAILURE yo'q bo'lishi kerak
    final hasFailure = tail.any((line) =>
      line.contains('BUILD FAILED') ||
      line.contains('FAILURE: Build failed') ||
      line.contains('Gradle build failed') ||
      line.contains('Exception: Gradle task') && line.contains('failed with exit code')
    );

    final success = code == 0 && !_cancelled && tracker.built && !hasFailure;

    if (success) {
      tracker.complete();
      if (!options.verbose) {
        ui.progress(percent: 100, label: 'Tayyor', elapsed: duration);
      }
      stats.record(key, duration: duration, tasks: tracker.taskCount);
    }

    return BuildResult(
      success: success,
      exitCode: code,
      duration: duration,
      logTail: List.of(tail),
      logPath: logFile.path,
      taskCount: tracker.taskCount,
      startedAt: startedAt,
      cancelled: _cancelled,
    );
  }

  /// Ctrl+C bosilganda ishlayotgan jarayonni to'xtatadi.
  void cancel() {
    _cancelled = true;
    if (_current != null) {
      try {
        // Windows'da Process.kill() ishlamaydi, shuning uchun
        // o'z PID'ni va boshqa child process'larni taskkill bilan o'ldiraymiz.
        if (Platform.isWindows) {
          // Fon jarayonlar uchun forcibly to'xtatish (/F flag)
          Process.runSync(
            'taskkill',
            ['/PID', '${_current!.pid}', '/T', '/F'],
            runInShell: true,
          );
        } else {
          // Linux/macOS'da SIGTERM yuborish
          _current!.kill();
        }
      } catch (_) {
        // Agar taskkill ishlamasa, process o'zining exit codi kutib turamiz
      }
    }
  }
}
