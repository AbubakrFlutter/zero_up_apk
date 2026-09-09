import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'build_options.dart';
import 'build_stats.dart';
import 'builder.dart';
import 'command_spec.dart';
import 'config.dart';
import 'console.dart';
import 'error_translator.dart';
import 'gradle_tuner.dart';
import 'output_manager.dart';
import 'project_info.dart';
import 'system_info.dart';

const zeroUpApkVersion = '2.0.0';

/// Buyruq qatori interfeysi — barcha bosqichlarni boshqaradi.
class ZeroUpApkCli {
  late Ui ui;
  FlutterBuilder? _builder;

  Future<int> run(List<String> args) async {
    enableUtf8Console();

    final parser = _buildParser();
    ArgResults results;
    try {
      results = parser.parse(args);
    } on FormatException catch (e) {
      ui = Ui();
      ui.error("Argument xatosi: ${e.message}");
      ui.line();
      _printUsage(parser);
      return 64;
    }

    ui = Ui(ascii: results.flag('ascii'));

    if (results.flag('help')) {
      ui.banner(zeroUpApkVersion);
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
      ui.banner(zeroUpApkVersion);
      ui.error(e.message);
      if (e.detail != null) ui.detail(e.detail!);
      if (e.didYouMean.isNotEmpty) {
        ui.line();
        ui.detail('Shuni nazarda tutdingizmi?  zup ${e.didYouMean.first}');
      }
      ui.line();
      return 64;
    }

    ui.banner(zeroUpApkVersion);

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
      case InfoCommand():
      case DevicesCommand():
      case LastCommand():
      case InstallCommand():
        // Keyingi bosqichlarda amalga oshiriladi.
        ui.error("Bu buyruq hali tayyor emas.");
        ui.detail('zup 2.0 ning keyingi bosqichida qo\'shiladi.');
        ui.line();
        return 64;
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
      return 66;
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
      return 66;
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
      return 64;
    }

    // Bayroq berilmagan bo'lsa — saqlangan sozlama, u ham bo'lmasa — standart.
    bool merged(String name, bool? saved, bool fallback) =>
        results.wasParsed(name) ? results.flag(name) : (saved ?? fallback);

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
      ascii: results.flag('ascii'),
      extraArgs: results.multiOption('extra'),
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
        ui.ok('Sozlamalar saqlandi (${ZupConfig.filePath})');
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
    ui.step('Kompyuter quvvati: ${system.toString()}');

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
        ui.ok(
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
        ui.ok('Gradle allaqachon optimal sozlangan');
      }
      if (options.aggressive) {
        ui.warn(
          "Kuchaytirilgan rejim yoqilgan — juda tez, lekin eski pluginlar "
          "bilan muammo bo'lishi mumkin",
        );
      }
    } else {
      ui.step("Gradle sozlamalariga tegilmadi (--no-tune)");
    }

    if (options.onlyArm64) {
      ui.ok("Faqat arm64 rejimi — AOT bosqichi ~2-3 barobar tez");
    } else if (options.splitPerAbi && options.targets.contains(BuildTarget.apk)) {
      ui.ok("ABI bo'yicha bo'lish yoqilgan — har bir APK ~2-3x kichik");
    }
    if (options.mode == BuildMode.release) {
      ui.ok("Ikonka tree-shaking yoqilgan (ortiqcha glyphlar olib tashlanadi)");
    }

    // --- Tayyorgarlik ---
    ui.section('Tayyorgarlik');
    if (options.clean) {
      ui.step("flutter clean bajarilmoqda (sekinroq, lekin toza)...");
      await builder.clean();
      ui.ok('Eski fayllar tozalandi');
    } else {
      ui.ok("Inkremental yig'ish — clean qilinmadi (asosiy tezlik manbai)");
    }

    if (builder.needsPubGet()) {
      ui.step('Paketlar yuklanmoqda (flutter pub get)...');
      final ok = await builder.pubGet();
      if (!ok) {
        ui.error("Paketlarni yuklab bo'lmadi.");
        ui.detail("Internet aloqasini tekshirib, qaytadan urinib ko'ring.");
        return 70;
      }
      ui.ok('Paketlar tayyor');
    } else {
      ui.ok("Paketlar o'zgarmagan — pub get o'tkazib yuborildi");
    }

    // --- Yig'ish ---
    final artifactsByTarget = <BuildTarget, List<File>>{};
    final durations = <BuildTarget, Duration>{};

    for (final target in options.targets) {
      ui.section("${target.uzName} yig'ilmoqda");
      final expected = stats.expectedDuration(options.statsKey(target));
      if (expected != null) {
        ui.step(
          "Taxminiy vaqt: ~${formatDuration(expected)} "
          "(oldingi yig'ishlarga asosan)",
        );
      } else {
        ui.step(
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
          ui.restoreCursor();
          return 130;
        }
        _reportFailure(result);
        ui.restoreCursor();
        return 70;
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
        ui.ok('Papka yaratildi: ${p.basename(outputDir.path)}');
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

    if (openFolder && outputDir != null) {
      await _openFolder(outputDir.path);
    }

    // Terminal kursorini tiklash
    ui.restoreCursor();

    return 0;
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
    // 1) build-number butun son bo'lishi shart — aks holda Gradle tushunarsiz
    // xato beradi.
    final buildNumber = options.buildNumber;
    if (buildNumber != null && int.tryParse(buildNumber) == null) {
      ui.error("--build-number butun son bo'lishi kerak: '$buildNumber'");
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

    if (options.onlyArm64 &&
        results.wasParsed('split') &&
        results.flag('split')) {
      ui.warn("--arm64 berilgani uchun --split e'tiborsiz qoldirildi");
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
        ui.ok('Sozlamalar tozalandi — hammasi standart holatga qaytdi.');
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
      ui.ok("'$key' sozlamasi standart holatga qaytarildi.");
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

    ui.ok('Saqlandi! Endi fayllar shu yerga tushadi:');
    ui.detail(absolute);
    ui.line();
    ui.detail('Ish stoliga qaytarish: zup config reset');
    ui.line();
    return 0;
  }

  Future<int> _restoreGradle(ProjectInfo project) async {
    final system = await SystemInfo.detect();
    final tuner = GradleTuner(project.androidDir, system);
    if (!tuner.hasBackup) {
      ui.warn("Zaxira nusxa topilmadi — gradle.properties o'zgartirilmagan.");
      return 0;
    }
    if (tuner.restore()) {
      ui.ok('gradle.properties asl holatiga qaytarildi.');
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
        ui.restoreCursor();
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
    ..addFlag(
      'restore-gradle',
      negatable: false,
      help: 'gradle.properties ni asl holatiga qaytarish.',
    )
    ..addMultiOption('extra', help: "flutter build ga qo'shimcha argument.");

  void _printUsage(ArgParser parser) {
    ui.line('  ${ui.bold("ISHLATISH")}');
    ui.line();
    ui.line('    zero_up_apk [apk|aab|hammasi] [sozlamalar]');
    ui.line('    zup apk --arm64          ${ui.grey("# qisqa nom")}');
    ui.line();
    ui.line('  ${ui.bold("MISOLLAR")}');
    ui.line();
    ui.line(
      '    ${ui.cyan("zup")}                     '
      '${ui.grey("interaktiv menyu")}',
    );
    ui.line(
      '    ${ui.cyan("zup apk")}                 '
      '${ui.grey("release APK (ABI bo'yicha bo'lingan)")}',
    );
    ui.line(
      '    ${ui.cyan("zup apk --arm64")}         '
      '${ui.grey("eng tez: faqat arm64")}',
    );
    ui.line(
      '    ${ui.cyan("zup aab")}                 '
      '${ui.grey("Google Play uchun App Bundle")}',
    );
    ui.line(
      '    ${ui.cyan("zup hammasi")}             '
      '${ui.grey("APK + AAB")}',
    );
    ui.line(
      '    ${ui.cyan("zup apk -p C:\\loyiham")}   '
      '${ui.grey("boshqa papkadagi loyiha")}',
    );
    ui.line(
      '    ${ui.cyan("zup apk --dart-define=API_URL=https://api.example.com")} '
      "${ui.grey("Dart define parametrlar bilan yig'ish")}",
    );
    ui.line(
      '    ${ui.cyan("zup --restore-gradle")}    '
      '${ui.grey("gradle sozlamalarini qaytarish")}',
    );
    ui.line();
    ui.line('  ${ui.bold("FAYLLAR QAYERGA TUSHADI?")}');
    ui.line();
    ui.line(
      '    ${ui.grey("Standart holatda — ish stoliga (Desktop). O'zgartirish:")}',
    );
    ui.line();
    ui.line(
      '    ${ui.cyan("zup config")}              '
      '${ui.grey("sozlamalar menyusi (eng oson yo'l)")}',
    );
    ui.line(
      '    ${ui.cyan(r"zup config --out D:\APK")} '
      '${ui.grey("papkani darhol o'rnatish")}',
    );
    ui.line(
      '    ${ui.cyan("zup config reset")}        '
      '${ui.grey("ish stoliga qaytarish")}',
    );
    ui.line(
      '    ${ui.cyan(r"zup apk --out D:\APK")}    '
      '${ui.grey("faqat shu safar boshqa papkaga")}',
    );
    ui.line(
      '    ${ui.cyan(r"zup apk --out D:\APK --save")} '
      '${ui.grey("shu papkani doimiy qilib saqlash")}',
    );
    ui.line();
    ui.line('  ${ui.bold("SOZLAMALAR")}');
    ui.line();
    for (final line in parser.usage.split('\n')) {
      ui.line('    ${ui.grey(line)}');
    }
    ui.line();
  }
}
