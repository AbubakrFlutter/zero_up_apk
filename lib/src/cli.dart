import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'build_history.dart';
import 'build_options.dart';
import 'build_stats.dart';
import 'builder.dart';
import 'command_spec.dart';
import 'config.dart';
import 'console.dart';
import 'device_manager.dart';
import 'doctor.dart';
import 'error_translator.dart';
import 'gradle_tuner.dart';
import 'json_result.dart';
import 'output_manager.dart';
import 'output_mode.dart';
import 'project_info.dart';
import 'system_info.dart';

const zeroUpApkVersion = '2.0.0';

/// Terminal holatini xavfsiz aniqlash — chaqiruvlar istisno tashlashi mumkin.
bool _stdoutHasTerminal() {
  try {
    return stdout.hasTerminal;
  } catch (_) {
    return false;
  }
}

bool _stdoutAnsi() {
  try {
    return stdout.hasTerminal && stdout.supportsAnsiEscapes;
  } catch (_) {
    return false;
  }
}

int? _stdoutColumns() {
  try {
    return stdout.hasTerminal ? stdout.terminalColumns : null;
  } catch (_) {
    return null;
  }
}

/// Buyruq qatori interfeysi — barcha bosqichlarni boshqaradi.
class ZeroUpApkCli {
  late Ui ui;
  FlutterBuilder? _builder;

  /// JSON rejimida natijani yig'ib boradi. Oddiy rejimda `null`.
  JsonResult? _json;

  /// JSON rejimida natijani chiqarib, chiqish kodini qaytaradi.
  ///
  /// Har bir chiqish nuqtasida shu orqali o'tiladi — shunda JSON
  /// rejimida hech qanday yo'l "jim" tugamaydi.
  int _finish(int code, {String? errorCode, String? errorMessage}) {
    final json = _json;
    if (json == null) return code;

    if (errorCode != null) {
      json.setError(code: errorCode, message: errorMessage ?? '');
    }
    json.emit(ok: code == 0, exitCode: code);
    return code;
  }

  /// Buyruqni bajaradi va chiqishni HAR DOIM to'g'ri yakunlaydi.
  ///
  /// `_run` da o'nlab qaytish nuqtasi bor — har birida yakunlashni
  /// eslab qolish o'rniga invariantni shu yerda ushlab turamiz:
  /// chiqish aynan bitta bo'sh qator bilan tugaydi va kursor ko'rinadi,
  /// shunda terminal buyruq satri natijaga yopishib qolmaydi.
  Future<int> run(List<String> args) async {
    try {
      return await _run(args);
    } finally {
      // JSON rejimida stdout'da faqat JSON bo'lishi kerak — bo'sh qator
      // ham qo'shilmaydi.
      final json = _json;
      if (json == null) {
        try {
          ui.endOutput();
        } catch (_) {
          // `ui` hali yaratilmagan bo'lishi mumkin (juda erta xato).
        }
      }
    }
  }

  Future<int> _run(List<String> args) async {
    enableUtf8Console();

    final parser = _buildParser();
    ArgResults results;
    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      // Bu yerda `--ascii` hali ma'lum emas, lekin uni argv dan
      // to'g'ridan-to'g'ri ko'rib olamiz — ilgari xato xabari Unicode
      // bilan chiqib, `--ascii` ni buzardi.
      ui = Ui.simple(ascii: args.contains('--ascii'));
      ui.error("Argument xatosi: ${e.message}");
      ui.line();
      _printUsage(parser);
      return 64;
    }

    // Chiqish rejimi — BIR JOYDA hal qilinadi.
    final decision = decideOutput(
      json: results.flag('json'),
      ai: results.flag('ai'),
      quiet: results.flag('quiet'),
      noColor: results.flag('no-color'),
      ascii: results.flag('ascii'),
      noProgress: results.flag('no-progress'),
      env: Platform.environment,
      stdoutHasTerminal: _stdoutHasTerminal(),
      stdoutAnsi: _stdoutAnsi(),
      stdoutColumns: _stdoutColumns(),
    );

    // JSON rejimida odamlarga mo'ljallangan matn STDERR ga ketadi —
    // stdout'da faqat bitta JSON obyekt qolishi shart, aks holda agent
    // uni parse qila olmaydi.
    ui = Ui(decision, sink: decision.isJson ? stderr : stdout);


    if (results.flag('help')) {
      ui.header(zeroUpApkVersion);
      _printUsage(parser);
      return 0;
    }
    if (results.flag('version')) {
      stdout.writeln('zero_up_apk $zeroUpApkVersion');
      return 0;
    }

    // Buyruqni BIR MARTA, BIR JOYDA aniqlaymiz.
    //
    // Ilgari bu `results.rest` "so'zlar to'plami" sifatida bir necha joyda
    // tekshirilardi va noma'lum so'z jim-jimgina APK yig'ishga olib kelardi
    // (`zup reset`, `zup apkk`). Endi noma'lum so'z — qattiq xato.
    final ZupCommand command;
    try {
      command = parseCommand(results.rest);
    } on CommandParseError catch (e) {
      if (_json != null) {
        _json = JsonResult(kind: 'error', toolVersion: zeroUpApkVersion)
          ..setError(
            code: e.code,
            message: e.message,
            detail: e.detail,
            argument: e.argument,
            didYouMean: e.didYouMean,
            remedies: e.didYouMean
                .map((s) => Remedy('Shuni nazarda tutdingizmi?', command: 'zup $s'))
                .toList(),
          );
        _json!.emit(ok: false, exitCode: 64);
        return 64;
      }
      ui.header(zeroUpApkVersion);
      ui.error(e.message);
      if (e.detail != null) ui.detail(e.detail!);
      if (e.didYouMean.isNotEmpty) {
        ui.line();
        ui.detail('Shuni nazarda tutdingizmi?  zup ${e.didYouMean.first}');
      }
      ui.line();
      return 64;
    }

    // JSON konvertining 'kind' maydoni buyruqqa qarab belgilanadi —
    // agent shunga qarab 'data' ning shaklini biladi.
    if (decision.isJson) {
      _json = JsonResult(
        kind: switch (command) {
          DoctorCommand() => 'doctor',
          InfoCommand() => 'info',
          DevicesCommand() => 'devices',
          LastCommand() => 'history',
          InstallCommand() => 'install',
          ConfigCommand() => 'config',
          _ => 'build',
        },
        toolVersion: zeroUpApkVersion,
      );
    }

    ui.header(zeroUpApkVersion);

    // Saqlangan sozlamalar — `--out` va boshqalar uchun standart qiymatlar.
    final config = ZupConfig.load();

    // Loyihani talab qilmaydigan buyruqlar.
    switch (command) {
      case HelpCommand():
        _printUsage(parser);
        return 0;
      case VersionCommand():
        stdout.writeln('zero_up_apk $zeroUpApkVersion');
        return 0;
      case ConfigCommand():
        return _configCommand(results, command, config);
      case DoctorCommand():
        return _doctorCommand(results);
      case DevicesCommand():
        return _devicesCommand();
      case InfoCommand():
        return _infoCommand(results, config);
      case LastCommand():
        return _lastCommand(results, command);
      case InstallCommand():
        ui.error("'zup install' hali tayyor emas.");
        ui.action("Hozircha yig'ish bilan birga", command: 'zup apk -i');
        ui.line();
        return _finish(64,
            errorCode: 'NOT_IMPLEMENTED',
            errorMessage: "'zup install' hali tayyor emas");
      case BuildCommand():
      case RestoreGradleCommand():
        break; // loyiha kerak — pastda davom etadi
    }

    // 1) Loyihani aniqlash
    final projectPath = p.normalize(
      p.absolute(results.option('path') ?? '.'),
    );
    final project = ProjectInfo.load(projectPath);
    if (project == null) {
      ui.error("Bu papkada Flutter loyihasi topilmadi.");
      ui.detail('Papka: $projectPath');
      ui.detail("pubspec.yaml fayli bor papkada ishga tushiring yoki");
      ui.detail("--path bilan loyiha yo'lini ko'rsating.");
      return _finish(66, errorCode: 'NO_PROJECT', errorMessage: "Bu papkada Flutter loyihasi topilmadi");
    }

    if (results.flag('restore-gradle')) {
      return _restoreGradle(project);
    }

    if (!project.hasAndroid) {
      ui.error("Loyihada 'android' papkasi yo'q — APK yig'ib bo'lmaydi.");
      ui.detail('Papka: ${project.root}');
      ui.detail(
        "Agar bu Flutter paketi (package/plugin) bo'lsa, uni to'g'ridan-to'g'ri "
        "APK ga yig'ib bo'lmaydi.",
      );
      ui.detail("Ilova loyihasida ishga tushiring yoki --path bilan ko'rsating.");
      return _finish(66, errorCode: 'NO_ANDROID_DIR', errorMessage: "Loyihada 'android' papkasi yo'q");
    }

    // 2) Nima yig'amiz? — buyruq grammatikasi allaqachon aniqlagan.
    if (command is! BuildCommand) {
      // restore-gradle yuqorida hal qilindi; bu yerga faqat yig'ish tushadi.
      ui.error("Yig'ish buyrug'i kutilgan edi.");
      return 64;
    }
    final targets = command.targets;
    if (targets.isEmpty) {
      ui.error("Yig'ish uchun hech narsa tanlanmadi.");
      return _finish(64, errorCode: 'MISSING_TARGET', errorMessage: "Yig'ish uchun hech narsa tanlanmadi");
    }

    // Bayroq berilmagan bo'lsa — saqlangan sozlama, u ham bo'lmasa — standart.
    //
    // Qiymat QAYERDAN kelganini ham yozib boramiz: ilgari ogohlantirishlar
    // `results.wasParsed` ga tayanardi va sozlamadan kelgan `arm64`
    // `--split` ni jim o'chirsa, foydalanuvchi bexabar qolardi.
    bool merged(String name, bool? saved, bool fallback) {
      if (results.wasParsed(name)) {
        _sources[name] = 'flag';
        return results.flag(name);
      }
      if (saved != null) {
        _sources[name] = 'config';
        return saved;
      }
      _sources[name] = 'default';
      return fallback;
    }

    final mode = switch (results.option('mode')) {
      'debug' => BuildMode.debug,
      'profile' => BuildMode.profile,
      _ => BuildMode.release,
    };

    final options = BuildOptions(
      projectPath: project.root,
      targets: targets,
      mode: mode,
      splitPerAbi: results.flag('split'),
      onlyArm64: merged('arm64', config.arm64, false),
      obfuscate: results.flag('obfuscate'),
      clean: results.flag('clean'),
      tune: results.flag('tune'),
      aggressive: results.flag('aggressive'),
      copyOutput: merged('copy', config.copyOutput, true),
      outputDir: results.option('out') ?? config.outputDir,
      flavor: results.option('flavor'),
      dartDefines: results.multiOption('dart-define'),
      buildName: results.option('build-name'),
      buildNumber: results.option('build-number'),
      verbose: results.flag('verbose'),
      extraArgs: results.multiOption('extra'),
      entryPoint: results.option('target'),
      treeShakeIcons: results.flag('tree-shake-icons'),
      install: results.flag('install'),
      deviceId: results.option('device'),
    );

    final openFolder = merged('open', config.openFolder, false);

    // Bir-biriga zid yoki e'tiborsiz qoladigan bayroqlar haqida ogohlantiramiz —
    // jim-jimgina e'tiborsiz qoldirish foydalanuvchini chalg'itadi.
    final problem = _validateOptions(
      results: results,
      options: options,
      openFolder: openFolder,
    );
    if (problem != null) return problem;

    // `--save` — shu ishga tushirishdagi sozlamalarni doimiy qilib saqlash.
    if (results.flag('save')) {
      final toSave = config.copyWith(
        outputDir: results.option('out'),
        openFolder: results.wasParsed('open') ? openFolder : null,
        arm64: results.wasParsed('arm64') ? options.onlyArm64 : null,
        copyOutput: results.wasParsed('copy') ? options.copyOutput : null,
      );
      final error = toSave.save();
      if (error != null) {
        ui.warn('Sozlamalar saqlanmadi: $error');
      } else {
        ui.done('Sozlamalar saqlandi (${ZupConfig.filePath})');
      }
    }

    return _execute(project, options, openFolder: openFolder);
  }

  Future<int> _execute(
    ProjectInfo project,
    BuildOptions options, {
    required bool openFolder,
  }) async {
    try {
      return await _runBuild(project, options, openFolder: openFolder);
    } finally {
      await _disposeSignalHandler();
    }
  }

  Future<int> _runBuild(
    ProjectInfo project,
    BuildOptions options, {
    required bool openFolder,
  }) async {
    final totalStart = DateTime.now();

    // JSON rejimida natijani yig'ib boramiz.
    _json
      ?..setProject(project)
      ..setRequest(options, _resolvedSources(options));

    final stats = BuildStats.load(project.root);
    final builder = FlutterBuilder(
      ui: ui,
      project: project,
      options: options,
      stats: stats,
    );
    _builder = builder;
    _installSignalHandler();

    // Flutter versiyasini fonda aniqlaymiz — vaqt yo'qotmaymiz.
    final flutterVersionFuture = builder.detectFlutterVersion();

    // --- Loyiha ma'lumoti ---
    ui.section('Loyiha');
    ui.kv('Ilova nomi', project.appName);
    ui.kv('Versiya', project.fullVersion);
    if (project.applicationId != null) {
      ui.kv('Application ID', project.applicationId!);
    }
    ui.kv('Papka', project.root);
    ui.kv(
      "Yig'iladi",
      '${options.targets.map((t) => t.uzName).join(' + ')} '
          '(${options.mode.uzName})',
    );

    // --- Optimizatsiya ---
    ui.section('Optimizatsiya');
    final system = await SystemInfo.detect();
    ui.note('Kompyuter quvvati: ${system.toString()}');

    // Disk to'lgan bo'lsa, Gradle tushunarsiz xatolar beradi — oldindan
    // ogohlantiramiz.
    final freeGb = await SystemInfo.freeDiskGb(project.root);
    if (freeGb != null && freeGb < 5) {
      ui.warn(
        "Diskda atigi ${freeGb.toStringAsFixed(1)} GB bo'sh joy qoldi — "
        "yig'ish uchun kamida 5 GB tavsiya etiladi",
      );
      ui.detail("Joy bo'shatish: 'gradlew --stop' so'ng "
          "C:\\Users\\<siz>\\.gradle\\caches\\build-cache-1 papkasini o'chiring");
    }

    if (options.tune) {
      final tuner = GradleTuner(project.androidDir, system);
      final result = tuner.apply(aggressive: options.aggressive);
      if (result.error != null) {
        ui.warn("gradle.properties sozlanmadi: ${result.error}");
      } else if (result.changed) {
        ui.done(
          "Gradle sozlandi: ${result.added.length} ta qo'shildi, "
          '${result.updated.length} ta yangilandi',
        );
        ui.detail(
          'Xotira: ${system.gradleHeapMb} MB  •  '
          'Parallel: ${system.gradleWorkers} ta oqim  •  '
          'Kesh: yoqilgan',
        );
        if (result.backupPath != null) {
          ui.detail(
            "Asl fayl zaxirasi saqlandi (--restore-gradle bilan qaytariladi)",
          );
        }
      } else {
        ui.note('Gradle allaqachon optimal sozlangan');
      }
      if (options.aggressive) {
        ui.warn(
          "Kuchaytirilgan rejim yoqilgan — juda tez, lekin eski pluginlar "
          "bilan muammo bo'lishi mumkin",
        );
      }
    } else {
      ui.note("Gradle sozlamalariga tegilmadi (--no-tune)");
    }

    if (options.onlyArm64) {
      ui.note("Faqat arm64 rejimi — AOT bosqichi ~2-3 barobar tez");
    } else if (options.splitPerAbi && options.targets.contains(BuildTarget.apk)) {
      ui.note("ABI bo'yicha bo'lish yoqilgan — har bir APK ~2-3x kichik");
    }
    if (options.mode == BuildMode.release) {
      ui.note("Ikonka tree-shaking yoqilgan (ortiqcha glyphlar olib tashlanadi)");
    }

    // --- Tayyorgarlik ---
    ui.section('Tayyorgarlik');
    if (options.clean) {
      ui.note("flutter clean bajarilmoqda (sekinroq, lekin toza)...");
      await builder.clean();
      ui.note('Eski fayllar tozalandi');
    } else {
      ui.note("Inkremental yig'ish — clean qilinmadi (asosiy tezlik manbai)");
    }

    if (builder.needsPubGet()) {
      ui.note('Paketlar yuklanmoqda (flutter pub get)...');
      final ok = await builder.pubGet();
      if (!ok) {
        ui.error("Paketlarni yuklab bo'lmadi.");
        ui.detail("Internet aloqasini tekshirib, qaytadan urinib ko'ring.");
        return 70;
      }
      ui.note('Paketlar tayyor');
    } else {
      ui.note("Paketlar o'zgarmagan — pub get o'tkazib yuborildi");
    }

    // --- Yig'ish ---
    final artifactsByTarget = <BuildTarget, List<File>>{};
    final durations = <BuildTarget, Duration>{};

    for (final target in options.targets) {
      ui.section("${target.uzName} yig'ilmoqda");
      final expected = stats.expectedDuration(options.statsKey(target));
      if (expected != null) {
        ui.note(
          "Taxminiy vaqt: ~${formatDuration(expected)} "
          "(oldingi yig'ishlarga asosan)",
        );
      } else {
        ui.note(
          "Birinchi yig'ish — biroz uzoqroq davom etadi, "
          "keyingilari ancha tez bo'ladi",
        );
      }

      final result = await builder.build(target);

      if (!result.success) {
        ui.progressDone(
          result.cancelled
              ? "Yig'ish foydalanuvchi tomonidan to'xtatildi"
              : "${target.uzName} yig'ilmadi",
          success: false,
        );
        if (result.cancelled) {
          ui.endOutput();
          _json?.setFailure(
            phase: FailurePhase.gradle,
            target: target,
            code: 'CANCELLED',
            title: "To'xtatildi",
            reason: "Yig'ish foydalanuvchi tomonidan to'xtatildi.",
            logPath: result.logPath,
          );
          return _finish(130);
        }
        _reportFailure(result);
        ui.endOutput();
        _recordFailure(result, target);
        _recordHistory(
          project: project,
          options: options,
          totalDuration: DateTime.now().difference(totalStart),
          delivered: const [],
          outputDir: null,
          ok: false,
          exitCode: 70,
          logPath: result.logPath,
          failureCode: ErrorTranslator.translate(result.logTail)?.code,
        );
        return _finish(70);
      }

      ui.progressDone(
        "${target.uzName} tayyor — ${formatDuration(result.duration)}"
        "${result.taskCount > 0 ? ' (${result.taskCount} ta gradle vazifasi)' : ''}",
      );
      durations[target] = result.duration;

      final manager = OutputManager(project: project, options: options);
      final artifacts = manager.findArtifacts(target, result.startedAt);
      if (artifacts.isEmpty) {
        ui.warn("Yig'ilgan fayl topilmadi — build papkasini tekshiring");
      }
      artifactsByTarget[target] = artifacts;
      _lastResults[target] = result;
    }

    // --- Fayllarni yetkazish ---
    final delivered = <DeliveredFile>[];
    Directory? outputDir;
    final manager = OutputManager(project: project, options: options);

    if (options.copyOutput) {
      ui.section('Fayllar tayyorlanmoqda');
      try {
        outputDir = await manager.createOutputFolder();
        for (final entry in artifactsByTarget.entries) {
          delivered.addAll(manager.deliver(entry.value, outputDir, entry.key));
        }
        final totalDuration = DateTime.now().difference(totalStart);
        manager.writeInfoFile(
          outputDir: outputDir,
          files: delivered,
          totalDuration: totalDuration,
          flutterVersion: await flutterVersionFuture,
          systemSummary: system.toString(),
        );
        ui.done('Papka yaratildi: ${p.basename(outputDir.path)}');
      } catch (e) {
        ui.error("Fayllarni ko'chirib bo'lmadi: $e");
        ui.detail(
          "Fayllar loyihaning build papkasida qoldi: "
          "${p.join(project.root, 'build', 'app', 'outputs')}",
        );
      }
    }

    // --- Yakuniy hisobot ---
    final totalDuration = DateTime.now().difference(totalStart);
    _printSummary(
      project: project,
      delivered: delivered,
      outputDir: outputDir,
      totalDuration: totalDuration,
      durations: durations,
      artifactsByTarget: artifactsByTarget,
    );

    // `-i` — yig'ilgan APK ni qurilmaga o'rnatamiz.
    if (options.install && delivered.isNotEmpty) {
      final installError = await _installToDevice(delivered, options);
      if (installError != null) {
        ui.endOutput();
        return _finish(installError);
      }
    }

    if (openFolder && outputDir != null) {
      await _openFolder(outputDir.path);
    }

    // Terminal kursorini tiklash
    ui.endOutput();

    if (_json != null) {
      for (final entry in artifactsByTarget.entries) {
        final target = entry.key;
        final result = _lastResults[target];
        final files = delivered.where((f) => f.target == target).toList();
        _json!.addTarget(
          target: target,
          duration: durations[target] ?? Duration.zero,
          gradleTasks: result?.taskCount ?? 0,
          logPath: result?.logPath ?? '',
          artifacts: files,
        );
      }
      _json!.setOutputDir(outputDir?.path);
    }

    _recordHistory(
      project: project,
      options: options,
      totalDuration: totalDuration,
      delivered: delivered,
      outputDir: outputDir?.path,
      ok: true,
      exitCode: 0,
    );

    return _finish(0);
  }

  /// Har bir sozlama qayerdan kelgani — `flag`, `config` yoki `default`.
  ///
  /// Agentga "nega arm64 yig'ilyapti, men so'ramadim-ku?" degan savolga
  /// javob beradi — sozlama fayliga qaramasdan.
  Map<String, String> _resolvedSources(BuildOptions options) => _sources;

  final Map<String, String> _sources = {};
  final Map<BuildTarget, BuildResult> _lastResults = {};

  /// Yiqilgan yig'ish haqidagi ma'lumotni JSON ga yozadi.
  void _recordFailure(BuildResult result, BuildTarget target) {
    final json = _json;
    if (json == null) return;

    final translated = ErrorTranslator.translate(result.logTail);
    final highlights = ErrorTranslator.highlights(result.logTail, max: 15);

    json.setFailure(
      phase: FailurePhase.gradle,
      target: target,
      code: translated?.code ?? 'UNKNOWN',
      title: translated?.title ?? "Yig'ish bajarilmadi",
      reason: translated?.reason ??
          "Aniq sababni avtomatik aniqlab bo'lmadi.",
      retryable: translated?.retryable ?? false,
      toolExitCode: result.exitCode,
      matchedLine: translated?.rawLine,
      remedies: translated == null ? const [] : remediesFrom(translated),
      logPath: result.logPath,
      logLineCount: result.logTail.length,
      highlights: [
        for (var i = 0; i < highlights.length; i++)
          LogHighlight(i + 1, highlights[i]),
      ],
      logTail: result.logTail,
    );
  }

  void _printSummary({
    required ProjectInfo project,
    required List<DeliveredFile> delivered,
    required Directory? outputDir,
    required Duration totalDuration,
    required Map<BuildTarget, Duration> durations,
    required Map<BuildTarget, List<File>> artifactsByTarget,
  }) {
    // padRight dan keyin ham kamida bitta bo'shliq qolishi kerak —
    // aks holda uzun kalit qiymatga yopishib qoladi.
    String row(String key, String value) =>
        '${ui.grey(key.padRight(12))} $value';

    final lines = <String>[
      row(
        'Ilova',
        '${ui.bold(project.appName)}  ${ui.grey("v${project.fullVersion}")}',
      ),
      row('Umumiy vaqt', ui.bold(formatDuration(totalDuration))),
    ];

    if (durations.length > 1) {
      for (final entry in durations.entries) {
        final short = entry.key == BuildTarget.aab ? 'AAB' : 'APK';
        lines.add(row('  $short', formatDuration(entry.value)));
      }
    }

    lines.add('');
    if (delivered.isNotEmpty) {
      for (final f in delivered) {
        lines.add(
          '${ui.green("•")} ${f.name}  '
          '${ui.grey("(${f.readableSize}, ${f.abiLabel})")}',
        );
      }
    } else {
      for (final entry in artifactsByTarget.entries) {
        for (final file in entry.value) {
          lines.add('${ui.green("•")} ${p.basename(file.path)}');
        }
      }
    }

    ui.box(ui.ascii ? 'TAYYOR!' : "TAYYOR!  ✔", lines, color: 'green');

    // Yo'l qutidan tashqarida — u juda uzun bo'lishi mumkin.
    if (outputDir != null) {
      ui.line('  ${ui.grey("Papka:")} ${outputDir.path}');
    } else if (artifactsByTarget.isNotEmpty) {
      ui.line(
        '  ${ui.grey("Papka:")} '
        '${p.join(project.root, 'build', 'app', 'outputs')}',
      );
    }
    if (delivered.any((f) => f.abi == 'arm64-v8a')) {
      ui.line(
        "  ${ui.grey("Maslahat: telefonga o'rnatish uchun arm64-v8a faylini oling.")}",
      );
    }
    ui.line();
  }

  void _reportFailure(BuildResult result) {
    final translated = ErrorTranslator.translate(result.logTail);

    if (translated != null) {
      const textWidth = 70;
      final lines = <String>[
        ...wrapText(translated.reason, textWidth).map(ui.bold),
        '',
        ui.grey('Nima sodir bo\'ldi:'),
        if (translated.rawLine != null)
          ...wrapText(translated.rawLine!, textWidth - 4, indent: '  ')
              .map((l) => '  ${ui.dim(l)}'),
        if (translated.rawLine != null) '',
        ui.grey('Qanday tuzatish:'),
        for (final solution in translated.solutions)
          ...wrapText(solution, textWidth - 4, indent: '    ').indexed.map(
            (e) => e.$1 == 0 ? '  ${ui.yellow("→")} ${e.$2}' : '    ${e.$2}',
          ),
      ];
      ui.box('XATO: ${translated.title}', lines, color: 'red');
    } else {
      // Xato turi aniqlanmagan bo'lsa - exit code va log analizini ko'rsatamiz
      final exitInfo = result.exitCode != 0
          ? "Exit kod: ${result.exitCode}"
          : "Exit kod 0, lekin build yakunlanmadi";

      ui.box(
        "XATO: yig'ish bajarilmadi",
        [
          ui.bold("Aniq sababni avtomatik aniqlab bo'lmadi."),
          '',
          ui.grey(exitInfo),
          '',
          ui.grey('Quyidagi logdan muhim qatorlarni tekshiring:'),
        ],
        color: 'red',
      );
    }

    final highlights = ErrorTranslator.highlights(result.logTail, max: 15);
    if (highlights.isNotEmpty) {
      ui.line('  ${ui.bold("Logdan muhim qatorlar:")}');
      ui.line();
      for (final line in highlights) {
        // Xato belgisi bo'lsa qizil rangda ko'rsatamiz
        final isError = line.toLowerCase().contains('error') ||
                        line.toLowerCase().contains('failed') ||
                        line.toLowerCase().contains('exception');
        final short = line.length > 120 ? '${line.substring(0, 119)}…' : line;
        if (isError) {
          ui.line('    ${ui.red("✖")} ${ui.red(short)}');
        } else {
          ui.line('    ${ui.dim("•")} ${ui.grey(short)}');
        }
      }
      ui.line();
    }

    ui.line('  ${ui.bold("To'liq log:")} ${result.logPath}');
    ui.line('  ${ui.grey("Bu faylni text editor da ochib batafsil tekshiring.")}');
    ui.line();

    // Qo'shimcha yordam
    ui.line('  ${ui.cyan("💡 MASLAHAT:")}');
    ui.line('     • Log faylini diqqat bilan o\'qing - sabab yuqorida ko\'rsatilgan');
    ui.line('     • Agar tushunarsiz bo\'lsa: zup apk --verbose bilan qayta urinib ko\'ring');
    ui.line('     • Oxirgi o\'zgarishlarni bekor qilib ko\'ring');
    ui.line();
  }

  /// Bir-biriga zid bayroqlarni tekshiradi.
  /// `null` — davom etish mumkin, aks holda chiqish kodi.
  ///
  /// Muhim: xatolar yig'ish BOSHLANISHIDAN oldin topiladi. Aks holda
  /// foydalanuvchi 5 daqiqa kutib, oxirida "papkaga yozib bo'lmadi" degan
  /// xabarni ko'radi.
  int? _validateOptions({
    required ArgResults results,
    required BuildOptions options,
    required bool openFolder,
  }) {
    // 0) `--extra` zup ning o'z bayroqlarini takrorlamasligi kerak.
    final conflicts = FlutterBuilder.findExtraConflicts(options.extraArgs);
    if (conflicts.isNotEmpty) {
      ui.error("--extra zup ning bayrog'ini takrorlaydi: ${conflicts.join(', ')}");
      ui.detail('Bular uchun alohida bayroqlar bor:');
      ui.detail('  -v → --verbose,  --target → -t,  --flavor → --flavor');
      ui.line();
      return 64;
    }

    // 0.1) Kirish fayli mavjudmi?
    final entry = options.entryPoint;
    if (entry != null) {
      final file = File(p.join(options.projectPath, entry));
      if (!file.existsSync() && !File(entry).existsSync()) {
        ui.error("Kirish fayli topilmadi: $entry");
        ui.detail('Masalan: -t lib/main_dev.dart');
        ui.line();
        return 64;
      }
    }

    // 0.2) Flavor nomi — Gradle uni identifikator sifatida ishlatadi.
    final flavor = options.flavor;
    if (flavor != null && !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(flavor)) {
      ui.error("--flavor nomi noto'g'ri: '$flavor'");
      ui.detail('Harf bilan boshlanib, faqat harf/raqam/pastki chiziq bo\'lishi kerak.');
      ui.line();
      return 64;
    }

    // 0.3) Versiya nomi — `1`, `1.0` yoki `1.0.0`.
    final buildName = options.buildName;
    if (buildName != null &&
        !RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(buildName)) {
      ui.error("--build-name noto'g'ri: '$buildName'");
      ui.detail('Masalan: --build-name=1.2.3');
      ui.line();
      return 64;
    }

    // 1) build-number musbat butun son bo'lishi shart — aks holda Gradle
    // tushunarsiz xato beradi. Ilgari 0 va manfiy sonlar o'tib ketardi.
    final buildNumber = options.buildNumber;
    final parsedNumber = buildNumber == null ? null : int.tryParse(buildNumber);
    if (buildNumber != null && (parsedNumber == null || parsedNumber < 1)) {
      ui.error("--build-number musbat butun son bo'lishi kerak: '$buildNumber'");
      ui.detail('Masalan: --build-number=12');
      return 64;
    }

    // 2) dart-define KEY=VALUE ko'rinishida bo'lishi kerak.
    for (final define in options.dartDefines) {
      if (!define.contains('=')) {
        ui.error("--dart-define KEY=VALUE ko'rinishida bo'lishi kerak: '$define'");
        ui.detail('Masalan: --dart-define=API_URL=https://api.example.com');
        return 64;
      }
      if (define.startsWith('=')) {
        ui.error("--dart-define da kalit (KEY) bo'sh: '$define'");
        return 64;
      }
    }

    // 3) Chiqish papkasiga haqiqatan yozib bo'ladimi?
    if (options.copyOutput && options.outputDir != null) {
      final error = validateOutputDir(options.outputDir!);
      if (error != null) {
        ui.error("Chiqish papkasiga yozib bo'lmaydi: ${options.outputDir}");
        ui.detail('Sabab: $error');
        ui.detail("Boshqa papka tanlang: zup config");
        return 73;
      }
    }

    // 4) Jim-jimgina e'tiborsiz qoladigan birikmalar — ogohlantiramiz.
    if (!options.copyOutput) {
      if (results.option('out') != null) {
        ui.warn("--out e'tiborsiz qoldirildi, chunki --no-copy berilgan");
      }
      if (openFolder) {
        ui.warn("--open e'tiborsiz qoldirildi, chunki --no-copy berilgan");
      }
    }

    if (options.obfuscate && options.mode != BuildMode.release) {
      ui.warn(
        "--obfuscate faqat release rejimida ishlaydi — "
        "hozir ${options.mode.uzName} rejimi",
      );
    }

    // arm64 yoqilgan bo'lsa split ishlamaydi — MANBASIDAN QAT'I NAZAR
    // ogohlantiramiz. Ilgari faqat bayroq qo'lda yozilganda ogohlantirardi,
    // sozlamadan kelgan arm64 esa split'ni jim o'chirardi.
    if (options.onlyArm64 && options.splitPerAbi) {
      final from = _sources['arm64'] == 'config' ? ' (sozlamadan)' : '';
      final message =
          "--arm64$from berilgani uchun --split e'tiborsiz qoldirildi";
      ui.warn(message);
      _json?.warn('SPLIT_IGNORED_ARM64', message);
    }

    if (options.aggressive && !options.tune) {
      ui.warn("--aggressive ishlamaydi, chunki --no-tune berilgan");
    }

    return null;
  }

  /// `zup config` — saqlanadigan sozlamalar.
  /// `zup config` — sozlamalarni ko'rish yoki o'zgartirish.
  ///
  /// MENYU YO'Q. Interaktiv sozlamalar menyusi Node tomonida
  /// (`node/menu.js`) — Dart hech qachon savol bermaydi, chunki
  /// "terminal bormi?" degan tekshiruv ikki tomonda turlicha bo'lib,
  /// `echo | zup` da so'ramasdan yig'ishga olib kelgan edi.
  Future<int> _configCommand(
    ArgResults results,
    ConfigCommand command,
    ZupConfig config,
  ) async {
    // `zup config reset [sozlama]`
    if (command.reset) {
      final key = command.resetKey;

      if (key == null) {
        final error = ZupConfig.reset();
        if (error != null) {
          ui.error("Sozlamalarni tozalab bo'lmadi: $error");
          return 73;
        }
        ui.done('Sozlamalar tozalandi — hammasi standart holatga qaytdi.');
        ui.detail('Fayllar yana ish stoliga (Desktop) tushadi.');
        ui.line();
        return 0;
      }

      final updated = config.without(key);
      final error = updated.save();
      if (error != null) {
        ui.error("Saqlab bo'lmadi: $error");
        return 73;
      }
      ui.done("'$key' sozlamasi standart holatga qaytarildi.");
      ui.line();
      return 0;
    }

    // `zup config --out D:\APK`
    if (results.option('out') != null) {
      return _saveOutputDir(results.option('out')!, config);
    }

    // Argumentsiz — hozirgi sozlamalarni ko'rsatamiz.
    _showConfig(config);
    return 0;
  }

  void _showConfig(ZupConfig config) {
    ui.section('Hozirgi sozlamalar');

    ui.kv('Chiqish papkasi', config.outputDir ?? 'Ish stoli (Desktop)');
    ui.kv('Papkani ochish', (config.openFolder ?? false) ? 'ha' : "yo'q");
    ui.kv('Faqat arm64', (config.arm64 ?? false) ? 'ha' : "yo'q");
    ui.kv("Fayllarni ko'chirish", (config.copyOutput ?? true) ? 'ha' : "yo'q");

    ui.line();
    if (ZupConfig.exists) {
      ui.detail('Fayl: ${ZupConfig.filePath}');
    } else {
      ui.detail('Sozlamalar fayli yo\'q — hammasi standart.');
    }
    ui.line();
    ui.detail("O'zgartirish uchun: zup config");
    ui.line();
  }


  Future<int> _saveOutputDir(String path, ZupConfig config) async {
    // Tirnoqlarni olib tashlaymiz — foydalanuvchi "D:\Mening papkam" deb
    // nusxa ko'chirishi juda ehtimolli.
    var cleaned = path.trim();
    if (cleaned.length > 1 &&
        ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
            (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    final error = validateOutputDir(cleaned);
    if (error != null) {
      ui.error("Bu papkaga yozib bo'lmaydi: $cleaned");
      ui.detail('Sabab: $error');
      ui.line();
      return 73;
    }

    final absolute = p.normalize(p.absolute(cleaned));
    final updated = config.copyWith(outputDir: absolute);
    final saveError = updated.save();
    if (saveError != null) {
      ui.error('Saqlanmadi: $saveError');
      ui.line();
      return 73;
    }

    ui.done('Saqlandi! Endi fayllar shu yerga tushadi:');
    ui.detail(absolute);
    ui.line();
    ui.detail('Ish stoliga qaytarish: zup config reset');
    ui.line();
    return 0;
  }

  /// Yig'ishni tarixga yozadi — muvaffaqiyat ham, xato ham.
  ///
  /// `build_stats.dart` dan alohida: u har bir konfiguratsiya uchun bitta
  /// silliqlangan vaqt taxminini saqlaydi va faqat muvaffaqiyatlarni
  /// yozadi. Tarix esa har bir ishga tushirishni, jumladan xatolarni ham
  /// ko'rsatishi kerak.
  void _recordHistory({
    required ProjectInfo project,
    required BuildOptions options,
    required Duration totalDuration,
    required List<DeliveredFile> delivered,
    required String? outputDir,
    required bool ok,
    required int exitCode,
    String? logPath,
    String? failureCode,
  }) {
    try {
      final now = DateTime.now().toUtc();
      BuildHistory(project.root).add(HistoryEntry(
        id: now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-'),
        zupVersion: zeroUpApkVersion,
        startedAt: now.subtract(totalDuration).toIso8601String(),
        durationMs: totalDuration.inMilliseconds,
        ok: ok,
        exitCode: exitCode,
        targets: options.targets.map((t) => t.name).toList(),
        mode: options.mode.name,
        appVersion: project.fullVersion,
        onlyArm64: options.onlyArm64,
        flavor: options.flavor,
        outputDir: outputDir,
        logPath: logPath,
        failureCode: failureCode,
        artifacts: delivered
            .map((f) => HistoryArtifact(
                  fileName: f.name,
                  path: f.path,
                  sizeBytes: f.sizeBytes,
                  abi: f.abi,
                ))
            .toList(),
      ));
    } catch (_) {
      // Tarix yozilmasa ham yig'ish muvaffaqiyatli hisoblanadi.
    }
  }

  /// `zup info` — loyiha, muhit va sozlamalar haqida.
  ///
  /// Agent uchun BIRINCHI chaqiruv: "shu yerda yig'a olamanmi, yo'q bo'lsa
  /// nega?" degan savolga javob beradi.
  Future<int> _infoCommand(ArgResults results, ZupConfig config) async {
    final projectPath = p.normalize(p.absolute(results.option('path') ?? '.'));
    final project = ProjectInfo.load(projectPath);
    final system = await SystemInfo.detect();

    final blockers = <Map<String, Object?>>[];
    if (project == null) {
      blockers.add({
        'code': 'NO_PROJECT',
        'message': "Bu papkada Flutter loyihasi yo'q",
      });
    } else if (!project.hasAndroid) {
      blockers.add({
        'code': 'NO_ANDROID_DIR',
        'message': "Loyihada 'android' papkasi yo'q",
      });
    }

    final buildable = blockers.isEmpty;

    final json = _json;
    if (json != null) {
      json.data['buildable'] = buildable;
      json.data['blockers'] = blockers;
      if (project != null) json.setProject(project);
      json.data['config'] = {
        'path': ZupConfig.filePath,
        'exists': ZupConfig.exists,
        'out': config.outputDir,
        'open': config.openFolder,
        'arm64': config.arm64,
        'copy': config.copyOutput,
      };
      json.data['system'] = {
        'cpuCores': system.cpuCores,
        'ramGb': system.ramGb,
        'gradleHeapMb': system.gradleHeapMb,
        'gradleWorkers': system.gradleWorkers,
      };
      json.data['output'] = {
        'style': ui.out.style.name,
        'reason': ui.out.reason,
        'color': ui.out.color,
        'columns': ui.out.columns,
      };
      json.emit(ok: buildable, exitCode: buildable ? 0 : 66);
      return buildable ? 0 : 66;
    }

    ui.section('Loyiha');
    if (project == null) {
      ui.error("Flutter loyihasi topilmadi");
      ui.detail(projectPath);
    } else {
      ui.kv('Ilova', project.appName);
      ui.kv('Versiya', project.fullVersion);
      if (project.applicationId != null) {
        ui.kv('Application ID', project.applicationId!);
      }
      ui.kv('Papka', project.root);
      ui.kv("Yig'sa bo'ladi", buildable ? 'ha' : "yo'q");
    }

    ui.section('Sozlamalar');
    ui.kv('Chiqish papkasi', config.outputDir ?? 'Ish stoli (Desktop)');
    ui.kv('Papkani ochish', (config.openFolder ?? false) ? 'ha' : "yo'q");
    ui.kv('Faqat arm64', (config.arm64 ?? false) ? 'ha' : "yo'q");

    ui.section('Kompyuter');
    ui.kv('Quvvat', system.toString());
    ui.kv('Gradle xotira', '${system.gradleHeapMb} MB');
    ui.kv('Parallel oqim', '${system.gradleWorkers}');

    ui.line();
    for (final blocker in blockers) {
      ui.error(blocker['message'] as String);
    }
    ui.line();

    return buildable ? 0 : 66;
  }

  /// `zup last` — oxirgi yig'ishlar.
  Future<int> _lastCommand(ArgResults results, LastCommand command) async {
    final projectPath = p.normalize(p.absolute(results.option('path') ?? '.'));
    final history = BuildHistory(projectPath).load();
    final shown = history.take(command.count).toList();

    final json = _json;
    if (json != null) {
      json.data['count'] = shown.length;
      json.data['projectRoot'] = projectPath;
      json.data['entries'] = shown
          .map((HistoryEntry e) => <String, Object?>{
                ...e.toJson(),
                'artifacts':
                    e.artifacts.map((a) => a.toJsonWithExists()).toList(),
              })
          .toList();
      json.emit(ok: true, exitCode: 0);
      return 0;
    }

    ui.section("Oxirgi yig'ishlar");
    if (shown.isEmpty) {
      ui.note("Hali yig'ish qilinmagan");
      ui.detail('Birinchi yig\'ishdan keyin bu yerda tarix ko\'rinadi');
      ui.line();
      return 0;
    }

    for (final entry in shown) {
      final when = entry.startedAtTime;
      final ago = when == null ? '' : _humanAgo(when);
      final targets = entry.targets.join('+');
      final duration = formatDuration(Duration(milliseconds: entry.durationMs));

      if (entry.ok) {
        ui.done('$targets · ${entry.appVersion ?? ""}', hint: '$duration · $ago');
        for (final a in entry.artifacts) {
          final missing = a.exists ? '' : '  (fayl o\'chirilgan)';
          ui.detail('${a.fileName}  ${formatBytes(a.sizeBytes)}$missing');
        }
      } else {
        ui.error('$targets · ${entry.failureCode ?? "xato"}');
        ui.detail('$duration · $ago');
        if (entry.logPath != null) ui.detail('Log: ${entry.logPath}');
      }
    }
    ui.line();
    return 0;
  }

  static String _humanAgo(DateTime time) {
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'hozirgina';
    if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
    if (diff.inHours < 24) return '${diff.inHours} soat oldin';
    return '${diff.inDays} kun oldin';
  }

  /// `zup devices` — ulangan qurilmalar.
  Future<int> _devicesCommand() async {
    final manager = DeviceManager();
    final adb = manager.adbPath;

    if (adb == null) {
      ui.error("adb topilmadi — qurilmalarni ko'rib bo'lmaydi");
      ui.action("Android SDK platform-tools ni o'rnating");
      ui.line();
      return _finish(69,
          errorCode: 'ADB_NOT_FOUND', errorMessage: 'adb topilmadi');
    }

    final devices = await manager.listDevices();

    final json = _json;
    if (json != null) {
      json.data['adb'] = {'found': true, 'path': adb};
      json.data['devices'] = devices.map((d) => d.toJson()).toList();
      json.emit(ok: true, exitCode: 0);
      return 0;
    }

    ui.section('Ulangan qurilmalar');
    if (devices.isEmpty) {
      ui.note('Qurilma topilmadi');
      ui.detail('USB orqali ulang yoki emulyatorni ishga tushiring');
      ui.detail("Telefonda 'USB debugging' yoqilganini tekshiring");
      ui.line();
      return 0;
    }

    for (final device in devices) {
      if (device.isReady) {
        ui.done(device.displayName, hint: device.id);
        if (device.supportedAbis.isNotEmpty) {
          ui.detail('ABI: ${device.supportedAbis.take(3).join(", ")}');
        }
      } else {
        ui.warn('${device.displayName} — ${device.state}');
        if (device.state == 'unauthorized') {
          ui.action('Telefondagi "USB debugging" so\'roviga ruxsat bering');
        }
      }
    }
    ui.line();
    ui.detail("O'rnatish uchun:  zup apk -i");
    ui.line();
    return 0;
  }

  /// Yig'ilgan APK ni qurilmaga o'rnatadi.
  ///
  /// Qurilma tanlash mantiqi: 0 ta — xato; 1 ta — o'sha; bir nechta va
  /// `--device` berilmagan — xato (Dart hech qachon savol bermaydi,
  /// tanlashni Node menyusi qiladi).
  Future<int?> _installToDevice(
    List<DeliveredFile> delivered,
    BuildOptions options,
  ) async {
    final manager = DeviceManager();
    if (manager.adbPath == null) {
      ui.line();
      ui.error("adb topilmadi — o'rnatib bo'lmadi");
      ui.action("Android SDK platform-tools ni o'rnating");
      _json?.warn('ADB_NOT_FOUND', "adb topilmadi");
      return 69;
    }

    final devices =
        (await manager.listDevices()).where((d) => d.isReady).toList();

    if (devices.isEmpty) {
      ui.line();
      ui.error("Ulangan qurilma topilmadi");
      ui.action('Qurilmalarni ko\'rish', command: 'zup devices');
      _json?.warn('NO_DEVICE', 'Ulangan qurilma topilmadi');
      return 69;
    }

    AndroidDevice device;
    if (options.deviceId != null) {
      final match = devices.where((d) => d.id == options.deviceId);
      if (match.isEmpty) {
        ui.line();
        ui.error("Qurilma topilmadi: ${options.deviceId}");
        ui.action('Qurilmalarni ko\'rish', command: 'zup devices');
        return 64;
      }
      device = match.first;
    } else if (devices.length == 1) {
      device = devices.first;
    } else {
      ui.line();
      ui.error("${devices.length} ta qurilma ulangan — qaysinisiga?");
      for (final d in devices) {
        ui.detail('${d.id}  —  ${d.displayName}');
      }
      ui.action('Masalan', command: 'zup apk -i --device=${devices.first.id}');
      _json?.warn('MULTIPLE_DEVICES', "${devices.length} ta qurilma ulangan");
      return 64;
    }

    final apk = pickApkForDevice(delivered, device);
    if (apk == null) {
      ui.line();
      ui.error("Bu qurilmaga mos APK topilmadi");
      ui.detail('Qurilma ABI: ${device.supportedAbis.join(", ")}');
      return 70;
    }

    ui.line();
    ui.active("O'rnatilmoqda: ${device.displayName}");
    final result = await manager.install(
      apkPath: apk.path,
      deviceId: device.id,
    );

    _json?.data['install'] = result.toJson();

    if (result.ok) {
      ui.done("O'rnatildi — ${apk.name}");
      ui.line();
      return null; // xato yo'q
    }

    ui.error("O'rnatib bo'lmadi");
    if (result.errorOutput != null) {
      ui.detail(result.errorOutput!.split('\n').first);
    }
    ui.line();
    return 70;
  }

  /// `zup doctor` — muhitni tekshiradi.
  Future<int> _doctorCommand(ArgResults results) async {
    final projectPath = p.normalize(p.absolute(results.option('path') ?? '.'));
    final doctor = Doctor(
      env: Platform.environment,
      projectPath: Directory(projectPath).existsSync() ? projectPath : null,
    );

    final checks = await doctor.run();
    final failed = checks.where((c) => c.status == DoctorStatus.fail).length;
    final warned = checks.where((c) => c.status == DoctorStatus.warn).length;
    final passed = checks.where((c) => c.status == DoctorStatus.pass).length;

    // Muhim tashqi vosita yo'q bo'lsa — 69 (EX_UNAVAILABLE).
    final exit = failed > 0 ? 69 : 0;

    final json = _json;
    if (json != null) {
      json.data['summary'] = {
        'pass': passed,
        'warn': warned,
        'fail': failed,
        'skip': checks.where((c) => c.status == DoctorStatus.skip).length,
      };
      json.data['checks'] = checks.map((c) => c.toJson()).toList();
      json.emit(ok: failed == 0, exitCode: exit);
      return exit;
    }

    ui.section('Muhit tekshiruvi');
    for (final check in checks) {
      switch (check.status) {
        case DoctorStatus.pass:
          ui.done(check.label, hint: check.message);
        case DoctorStatus.warn:
          ui.warn('${check.label} — ${check.message}');
        case DoctorStatus.fail:
          ui.error('${check.label} — ${check.message}');
        case DoctorStatus.skip:
          ui.pending(check.label, hint: check.message);
      }
      if (check.status != DoctorStatus.pass) {
        for (final remedy in check.remedies) {
          ui.action(remedy);
        }
      }
    }

    ui.line();
    if (failed > 0) {
      ui.error("$failed ta muammo topildi — yig'ish ishlamasligi mumkin");
    } else if (warned > 0) {
      ui.warn("$warned ta ogohlantirish, lekin yig'ish ishlaydi");
    } else {
      ui.done('Hammasi joyida');
    }
    ui.line();

    return exit;
  }

  Future<int> _restoreGradle(ProjectInfo project) async {
    final system = await SystemInfo.detect();
    final tuner = GradleTuner(project.androidDir, system);
    if (!tuner.hasBackup) {
      ui.warn("Zaxira nusxa topilmadi — gradle.properties o'zgartirilmagan.");
      return 0;
    }
    if (tuner.restore()) {
      ui.done('gradle.properties asl holatiga qaytarildi.');
      return 0;
    }
    ui.error("Qaytarib bo'lmadi — faylni qo'lda tekshiring.");
    return 70;
  }

  /// Ctrl+C ni ushlash uchun obuna. Yig'ish tugagach BEKOR QILINISHI SHART —
  /// aks holda Dart hodisalar sikli ochiq qolib, jarayon o'chmaydi va
  /// `zup.exe` qulflanib qoladi.
  StreamSubscription<ProcessSignal>? _signalSubscription;

  void _installSignalHandler() {
    try {
      _signalSubscription = ProcessSignal.sigint.watch().listen((_) {
        ui.endOutput();
        ui.warn("To'xtatilmoqda...");
        _builder?.cancel();
      });
    } catch (_) {
      // Ba'zi muhitlarda signalni kuzatib bo'lmaydi — bunda Ctrl+C
      // jarayonni odatdagidek to'xtatadi.
      //
      // Ilgari bu yerda stdin.readLineSync() bilan zaxira yo'l bor edi,
      // lekin u Future.microtask ichida ishlagani uchun butun hodisalar
      // siklini bloklab, dasturni muzlatib qo'yardi. Bundan tashqari
      // interaktiv menyuning stdin o'qishiga ham xalaqit berardi.
    }
  }

  /// Signal obunasini yopadi.
  ///
  /// Bu bo'lmasa Dart hodisalar sikli ochiq qolib, jarayon yig'ish
  /// tugagandan keyin ham o'chmasdi: `zup.exe` qulflanib qolar va
  /// keyingi o'rnatish "Access is denied" xatosi bilan buzilardi.
  Future<void> _disposeSignalHandler() async {
    await _signalSubscription?.cancel();
    _signalSubscription = null;
  }

  Future<void> _openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  ArgParser _buildParser() => ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Yordam.')
    ..addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Versiyani ko\'rsatish.',
    )
    ..addOption(
      'path',
      abbr: 'p',
      defaultsTo: '.',
      help: "Flutter loyihasi yo'li.",
    )
    ..addOption(
      'mode',
      abbr: 'm',
      allowed: ['release', 'profile', 'debug'],
      defaultsTo: 'release',
      help: "Yig'ish rejimi.",
    )
    ..addFlag(
      'split',
      defaultsTo: true,
      help: "APK ni ABI bo'yicha bo'lish (kichikroq fayllar).",
    )
    ..addFlag(
      'arm64',
      defaultsTo: false,
      help: 'Faqat arm64 uchun — eng tez rejim.',
    )
    ..addFlag('obfuscate', defaultsTo: false, help: 'Dart kodini yashirish.')
    ..addFlag('clean', defaultsTo: false, help: "Avval flutter clean qilish.")
    ..addFlag(
      'tune',
      defaultsTo: true,
      help: 'gradle.properties ni avtomatik optimallashtirish.',
    )
    ..addFlag(
      'aggressive',
      defaultsTo: false,
      help: "Kuchaytirilgan tezlashtirish (tavakkalliroq).",
    )
    ..addFlag(
      'copy',
      defaultsTo: true,
      help: 'Natijani ish stoliga (Desktop) ko\'chirish.',
    )
    ..addFlag('open', defaultsTo: false, help: 'Tugagach papkani ochish.')
    ..addOption(
      'out',
      abbr: 'o',
      help: "Chiqish papkasi (doimiy qilish uchun: zup config).",
    )
    ..addFlag(
      'save',
      negatable: false,
      help: 'Berilgan sozlamalarni doimiy qilib saqlash.',
    )
    ..addOption('flavor', help: 'Flavor nomi.')
    ..addMultiOption('dart-define', help: 'KEY=VALUE ko\'rinishida (bir necha marta ishlatish mumkin). Misol: --dart-define=API_URL=https://api.example.com --dart-define=ENV=production')
    ..addOption('build-name', help: 'Versiya nomini almashtirish.')
    ..addOption('build-number', help: 'Build raqamini almashtirish.')
    ..addFlag(
      'verbose',
      abbr: 'V',
      defaultsTo: false,
      help: "To'liq logni ko'rsatish.",
    )
    ..addFlag('ascii', defaultsTo: false, help: 'Faqat oddiy belgilar.')
    // ── Chiqish ko'rinishi ──
    ..addFlag(
      'json',
      negatable: false,
      help: 'Natijani JSON ko\'rinishida chiqarish.',
    )
    ..addFlag(
      'ai',
      negatable: false,
      help: 'AI rejimi: JSON, savolsiz, rangsiz (zup ai ... bilan bir xil).',
    )
    ..addFlag(
      'quiet',
      abbr: 'q',
      negatable: false,
      help: 'Faqat ogohlantirish va xatolar.',
    )
    ..addFlag('no-color', negatable: false, help: 'Ranglarni o\'chirish.')
    ..addFlag(
      'no-progress',
      negatable: false,
      help: 'Jonli progress o\'rniga oddiy qatorlar.',
    )
    // ── Yig'ish ──
    ..addOption(
      'target',
      abbr: 't',
      help: 'Kirish fayli (standart: lib/main.dart).',
    )
    ..addFlag(
      'tree-shake-icons',
      defaultsTo: true,
      help: 'Ishlatilmagan ikonka glyphlarini olib tashlash.',
    )
    ..addFlag(
      'install',
      abbr: 'i',
      negatable: false,
      help: 'Yig\'ilgach ulangan qurilmaga o\'rnatish.',
    )
    ..addOption('device', help: 'Qurilma ID (adb devices dagi nom).')
    ..addFlag(
      'restore-gradle',
      negatable: false,
      help: 'gradle.properties ni asl holatiga qaytarish.',
    )
    ..addMultiOption('extra', help: "flutter build ga qo'shimcha argument.");

  void _printUsage(ArgParser parser) {
    void cmd(String command, String description) {
      final padded = command.padRight(24);
      ui.line('    ${ui.cyan(padded)}${ui.grey(description)}');
    }

    ui.line('  ${ui.bold("ISHLATISH")}');
    ui.line();
    ui.line('    zup [buyruq] [sozlamalar]');
    ui.line();

    ui.line('  ${ui.bold("YIG'ISH")}');
    ui.line();
    cmd('zup', 'menyu (eng oson yo\'l)');
    cmd('zup apk', 'APK yig\'ish');
    cmd('zup apk --arm64', 'eng tez: faqat arm64');
    cmd('zup aab', 'Google Play uchun App Bundle');
    cmd('zup hammasi', 'APK + AAB');
    cmd('zup apk -i', 'yig\'ib telefonga o\'rnatish');
    ui.line();

    ui.line('  ${ui.bold("BOSHQA BUYRUQLAR")}');
    ui.line();
    cmd('zup config', 'fayllar qayerga tushsin');
    cmd('zup doctor', 'muhitni tekshirish');
    cmd('zup info', 'loyiha va sozlamalar haqida');
    cmd('zup last', 'oxirgi yig\'ishlar');
    cmd('zup devices', 'ulangan qurilmalar');
    cmd('zup update', 'yangilash');
    ui.line();

    ui.line('  ${ui.bold("AI REJIMI")}');
    ui.line();
    ui.line('    ${ui.grey("Claude Code kabi agentlar uchun: natija JSON, savol yo'q.")}');
    ui.line();
    cmd('zup ai apk', 'yig\'ib, natijani JSON qaytaradi');
    cmd('zup ai info', 'loyiha holati JSON');
    cmd('zup ai doctor', 'muhit tekshiruvi JSON');
    ui.line();
    ui.line('    ${ui.grey("ZUP_OUTPUT=json — har bir chaqiruv JSON qaytaradi")}');
    ui.line();

    ui.line('  ${ui.bold("FAYLLAR QAYERGA TUSHADI")}');
    ui.line();
    ui.line('    ${ui.grey("Standart holatda ish stoliga. O'zgartirish:")}');
    ui.line();
    cmd('zup config', 'sozlamalar menyusi');
    cmd(r'zup config --out D:\APK', 'papkani darhol o\'rnatish');
    cmd('zup config reset', 'ish stoliga qaytarish');
    cmd(r'zup apk --out D:\APK', 'faqat shu safar');
    ui.line();

    ui.line('  ${ui.bold("SOZLAMALAR")}');
    ui.line();
    for (final line in parser.usage.split('\n')) {
      ui.line('    ${ui.grey(line)}');
    }
    ui.line();
  }
}
