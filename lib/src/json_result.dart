import 'dart:convert';
import 'dart:io';

import 'build_options.dart';
import 'error_translator.dart';
import 'output_manager.dart';
import 'project_info.dart';

/// AI/JSON chiqishi — Claude Code kabi agentlar uchun.
///
/// QAT'IY QOIDA: stdout'da FAQAT bitta JSON obyekt bo'ladi. Odamlarga
/// mo'ljallangan barcha matn stderr ga ketadi (buni `Ui` ning `sink`i
/// hal qiladi). Shu tufayli agent `JSON.parse(stdout)` ni hech qanday
/// qatorlarni saralashsiz bajara oladi.

/// JSON sxemasi versiyasi. Faqat buzuvchi o'zgarishda oshiriladi.
const int jsonSchemaVersion = 1;

/// Diagnostika xabari — kod (mashina uchun) + matn (odam uchun).
class JsonWarning {
  const JsonWarning(this.code, this.message);
  final String code;
  final String message;

  Map<String, Object?> toJson() => {'code': code, 'message': message};
}

/// Bajariladigan taklif.
class Remedy {
  const Remedy(this.message, {this.command});
  final String message;

  /// Agent to'g'ridan-to'g'ri ishga tushira oladigan buyruq.
  final String? command;

  Map<String, Object?> toJson() => {'message': message, 'command': command};
}

/// Yig'ish qaysi bosqichda yiqildi.
enum FailurePhase { preflight, pubGet, clean, gradle, deliver, install }

/// Yig'ish natijasini yig'ib boradi va oxirida JSON chiqaradi.
///
/// Yig'ish davomida to'ldiriladi, `emit()` bir marta chaqiriladi.
class JsonResult {
  JsonResult({
    required this.kind,
    required this.toolVersion,
  }) : startedAt = DateTime.now().toUtc();

  /// `build` | `info` | `doctor` | `history` | `devices` | `install` | `error`
  final String kind;
  final String toolVersion;
  final DateTime startedAt;

  final List<JsonWarning> warnings = [];

  /// Buyruqqa xos ma'lumot.
  final Map<String, Object?> data = {};

  void warn(String code, String message) =>
      warnings.add(JsonWarning(code, message));

  /// Loyiha ma'lumotini yozadi.
  void setProject(ProjectInfo project, {String? flutterVersion}) {
    data['project'] = {
      'root': project.root,
      'packageName': project.packageName,
      'appName': project.appName,
      'version': project.version,
      'buildNumber': project.buildNumber,
      'fullVersion': project.fullVersion,
      'applicationId': project.applicationId,
      'hasAndroid': project.hasAndroid,
      if (flutterVersion != null) 'flutterVersion': flutterVersion,
    };
  }

  /// So'ralgan sozlamalar va ular QAYERDAN kelgani.
  ///
  /// `resolvedFrom` agentga "nega arm64 yig'ilyapti, men so'ramadim-ku?"
  /// degan savolga javob beradi — sozlama fayliga qaramasdan.
  void setRequest(BuildOptions options, Map<String, String> resolvedFrom) {
    data['request'] = {
      'targets': options.targets.map((t) => t.name).toList(),
      'mode': options.mode.name,
      'entryPoint': options.entryPoint,
      'splitPerAbi': options.splitPerAbi,
      'onlyArm64': options.onlyArm64,
      'obfuscate': options.obfuscate,
      'clean': options.clean,
      'tune': options.tune,
      'aggressive': options.aggressive,
      'treeShakeIcons': options.treeShakeIcons,
      'flavor': options.flavor,
      'dartDefines': options.dartDefines,
      'buildName': options.buildName,
      'buildNumber': options.buildNumber,
      'extraArgs': options.extraArgs,
      'copyOutput': options.copyOutput,
      'outputDir': options.outputDir,
      'install': options.install,
      'deviceId': options.deviceId,
    };
    data['resolvedFrom'] = resolvedFrom;
  }

  /// Aynan qanday `flutter build` chaqirildi — agent takrorlay oladi.
  void setFlutterCommand(List<String> command) {
    data['flutterCommand'] = command;
  }

  /// Bitta maqsad (APK yoki AAB) natijasi.
  void addTarget({
    required BuildTarget target,
    required Duration duration,
    required int gradleTasks,
    required String logPath,
    required List<DeliveredFile> artifacts,
  }) {
    final list = (data['targets'] as List?) ?? [];
    list.add({
      'target': target.name,
      'durationMs': duration.inMilliseconds,
      'gradleTasks': gradleTasks,
      'logPath': logPath,
      'artifacts': artifacts.map(_artifactJson).toList(),
    });
    data['targets'] = list;
  }

  static Map<String, Object?> _artifactJson(DeliveredFile f) {
    int? size;
    String? modified;
    try {
      final file = File(f.path);
      if (file.existsSync()) {
        size = file.lengthSync();
        modified = file.lastModifiedSync().toUtc().toIso8601String();
      }
    } catch (_) {}

    return {
      'fileName': f.name,
      'path': f.path,
      'sizeBytes': size ?? f.sizeBytes,
      'modifiedAt': modified,
      'abi': f.abi,
      'universal': f.abi == null,
      'type': f.target == BuildTarget.aab ? 'aab' : 'apk',
      // `--hash` berilmasa hisoblanmaydi: 200 MB AAB ni xesh'lash
      // tezlikni sotadigan vosita uchun sezilarli vaqt oladi.
      'sha256': null,
    };
  }

  void setOutputDir(String? dir) => data['outputDir'] = dir;

  /// Yig'ish yiqildi.
  void setFailure({
    required FailurePhase phase,
    BuildTarget? target,
    required String code,
    required String title,
    required String reason,
    bool retryable = false,
    int? toolExitCode,
    String? matchedLine,
    List<Remedy> remedies = const [],
    String? logPath,
    int? logLineCount,
    List<LogHighlight> highlights = const [],
    List<String> logTail = const [],
  }) {
    data['failure'] = {
      'phase': phase.name,
      'target': target?.name,
      'code': code,
      'title': title,
      'reason': reason,
      'retryable': retryable,
      'toolExitCode': toolExitCode,
      'matchedLine': matchedLine,
      'remedies': remedies.map((r) => r.toJson()).toList(),
      'log': {
        'path': logPath,
        'lineCount': logLineCount,
        'highlights': highlights.map((h) => h.toJson()).toList(),
        // Cheklangan: agent kontekstini 4000 qatorlik log bilan
        // to'ldirmaslik kerak. To'liq log `path` da.
        'tail': logTail.length > 60
            ? logTail.sublist(logTail.length - 60)
            : logTail,
      },
    };
  }

  /// Buyruq bajarilishidan oldingi xato (noma'lum buyruq, yaroqsiz bayroq).
  void setError({
    required String code,
    required String message,
    String? detail,
    String? argument,
    List<String> didYouMean = const [],
    List<Remedy> remedies = const [],
  }) {
    data['error'] = {
      'code': code,
      'message': message,
      'detail': detail,
      'argument': argument,
      'didYouMean': didYouMean,
      'remedies': remedies.map((r) => r.toJson()).toList(),
    };
  }

  /// JSON ni STDOUT ga chiqaradi — aynan bitta obyekt.
  void emit({required bool ok, required int exitCode}) {
    final finished = DateTime.now().toUtc();

    final envelope = <String, Object?>{
      'schemaVersion': jsonSchemaVersion,
      'tool': 'zup',
      'toolVersion': toolVersion,
      'kind': kind,
      'ok': ok,
      // Chiqish kodi konvertda ham bor — faqat stdout ni o'qigan agent
      // ham uni bilib oladi.
      'exitCode': exitCode,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finished.toIso8601String(),
      'durationMs': finished.difference(startedAt).inMilliseconds,
      'warnings': warnings.map((w) => w.toJson()).toList(),
      'data': data,
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(envelope));
  }
}

/// Logdagi muhim qator — raqami bilan.
///
/// Raqam agentga faylning aynan kerakli joyiga borish imkonini beradi.
class LogHighlight {
  const LogHighlight(this.line, this.text);
  final int line;
  final String text;

  Map<String, Object?> toJson() => {'line': line, 'text': text};
}

/// `TranslatedError` dan yechimlar ro'yxatini yasaydi.
List<Remedy> remediesFrom(TranslatedError error) {
  return error.solutions.map((s) {
    // Yechim matni ichida `zup ...` buyrug'i bo'lsa, uni ajratamiz —
    // agent uni to'g'ridan-to'g'ri ishga tushira oladi.
    final match = RegExp(r"'(zup [^']+)'|\b(zup [a-z-]+(?: --?[a-z-]+)*)")
        .firstMatch(s);
    final command = match?.group(1) ?? match?.group(2);
    return Remedy(s, command: command);
  }).toList();
}
