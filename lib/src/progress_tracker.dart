import 'dart:math' as math;

/// Yig'ish bosqichlari.
enum BuildPhase {
  prepare(0, 4, 'Tayyorgarlik'),
  pubGet(4, 10, "Paketlar yuklanmoqda"),
  gradle(10, 94, "Gradle yig'moqda"),
  finalize(94, 100, 'Yakunlanmoqda');

  const BuildPhase(this.from, this.to, this.uzName);

  final double from;
  final double to;
  final String uzName;
}

/// Flutter/Gradle chiqishini o'qib, real foizni hisoblaydi.
///
/// Ikki manbadan foydalanadi:
///  1. Gradle bajarilgan tasklar soni (oldingi yig'ishdagi umumiy son bilan
///     solishtiriladi) — aniq, lekin notekis.
///  2. O'tgan vaqt / kutilgan vaqt — tekis, lekin taxminiy.
/// Ikkalasi aralashtiriladi, natija hech qachon orqaga qaytmaydi.
class ProgressTracker {
  ProgressTracker({this.expectedDuration, this.expectedTasks});

  final Duration? expectedDuration;
  final int? expectedTasks;

  final Set<String> _seenTasks = <String>{};
  final DateTime _start = DateTime.now();

  BuildPhase _phase = BuildPhase.prepare;
  DateTime? _gradleStart;
  double _percent = 0;
  String _label = 'Tayyorgarlik...';
  String? _currentTask;
  bool _built = false;

  double get percent => _percent;
  String get label => _label;
  BuildPhase get phase => _phase;
  int get taskCount => _seenTasks.length;
  Duration get elapsed => DateTime.now().difference(_start);
  bool get built => _built;

  static final _taskRe = RegExp(r'>\s+Task\s+(:[A-Za-z0-9_.:\-]+)');
  static final _builtRe = RegExp(r'Built\s+.*\.(apk|aab)', caseSensitive: false);

  /// Yig'ish chiqishidagi bitta qatorni qayta ishlaydi.
  void onLine(String line) {
    if (_phase == BuildPhase.prepare) {
      if (line.contains('pub get') || line.contains('Resolving dependencies')) {
        _enter(BuildPhase.pubGet, 'Paketlar yuklanmoqda...');
      }
    }

    if (_phase.index < BuildPhase.gradle.index) {
      final isGradle =
          line.contains("Running Gradle task") ||
          (line.contains('gradlew') &&
              (line.contains('assemble') || line.contains('bundle'))) ||
          _taskRe.hasMatch(line);
      if (isGradle) {
        _enter(BuildPhase.gradle, "Gradle ishga tushmoqda...");
        _gradleStart = DateTime.now();
      }
    }

    final taskMatch = _taskRe.firstMatch(line);
    if (taskMatch != null) {
      final task = taskMatch.group(1)!;
      _seenTasks.add(task);
      _currentTask = task;
      _label = _describeTask(task);
      _gradleStart ??= DateTime.now();
      if (_phase.index < BuildPhase.gradle.index) {
        _phase = BuildPhase.gradle;
      }
    }

    if (_builtRe.hasMatch(line)) {
      _built = true;
      _enter(BuildPhase.finalize, 'Fayllar tayyorlanmoqda...');
    }
  }

  void _enter(BuildPhase phase, String label) {
    if (phase.index >= _phase.index) {
      _phase = phase;
      _label = label;
      _bump(phase.from);
    }
  }

  /// Vaqt o'tishi bilan foizni yangilab turadi (taymer chaqiradi).
  void tick() {
    switch (_phase) {
      case BuildPhase.prepare:
        _bump(math.min(3.5, elapsed.inMilliseconds / 1000 * 1.2));
      case BuildPhase.pubGet:
        final f = _asymptotic(_sinceStartSeconds(), 12);
        _bump(_lerp(BuildPhase.pubGet, f));
      case BuildPhase.gradle:
        _bump(_lerp(BuildPhase.gradle, _gradleFraction()));
      case BuildPhase.finalize:
        _bump(math.min(99, _percent + 0.4));
    }
  }

  double _gradleFraction() {
    final gradleElapsed = _gradleStart == null
        ? 0.0
        : DateTime.now().difference(_gradleStart!).inMilliseconds / 1000.0;

    // Vaqt bo'yicha taxmin.
    double timeFraction;
    final expected = expectedDuration;
    if (expected != null && expected.inSeconds > 3) {
      // Umumiy vaqtning ~88% i gradle bosqichiga to'g'ri keladi.
      final expectedGradle = expected.inSeconds * 0.88;
      timeFraction = (gradleElapsed / expectedGradle).clamp(0.0, 1.0);
      if (timeFraction >= 1.0) {
        // Kutilgandan uzoq davom etyapti — sekin 100% ga yaqinlashamiz.
        timeFraction = 0.94 + _asymptotic(gradleElapsed - expectedGradle, 60) * 0.06;
      }
    } else {
      timeFraction = _asymptotic(gradleElapsed, 150);
    }

    // Tasklar bo'yicha taxmin.
    final total = expectedTasks;
    if (total != null && total > 0) {
      final taskFraction = (_seenTasks.length / total).clamp(0.0, 1.0);
      return (taskFraction * 0.55 + timeFraction * 0.45).clamp(0.0, 0.985);
    }
    return timeFraction.clamp(0.0, 0.985);
  }

  double _sinceStartSeconds() => elapsed.inMilliseconds / 1000.0;

  /// 0 dan 1 ga sekinlashib yaqinlashuvchi funksiya (hech qachon 1 ga
  /// yetmaydi — shuning uchun bar "qotib qolgandek" ko'rinmaydi).
  double _asymptotic(double seconds, double scale) {
    if (seconds <= 0) return 0;
    return 1 - math.exp(-seconds / scale);
  }

  double _lerp(BuildPhase phase, double fraction) =>
      phase.from + (phase.to - phase.from) * fraction.clamp(0.0, 1.0);

  void _bump(double value) {
    if (value > _percent) _percent = math.min(value, 99.5);
  }

  /// Muvaffaqiyatli tugaganda.
  void complete() {
    _percent = 100;
    _label = 'Tayyor';
  }

  /// Gradle task nomini o'zbekcha tushuntirishga aylantiradi.
  static String _describeTask(String task) {
    final name = task.split(':').last;
    for (final entry in _taskLabels.entries) {
      if (name.toLowerCase().contains(entry.key)) return entry.value;
    }
    return "Gradle: $name";
  }

  static const Map<String, String> _taskLabels = {
    'compileflutterbuild': "Dart kodi native kodga o'girilmoqda (AOT)",
    'bundleflutterassets': "Flutter resurslari joylanmoqda",
    'packlibs': "Native kutubxonalar tayyorlanmoqda",
    'kotlin': "Kotlin kodi kompilyatsiya qilinmoqda",
    'javawithjavac': "Java kodi kompilyatsiya qilinmoqda",
    'minify': "Kod R8 bilan siqilmoqda",
    'shrinkres': "Ortiqcha resurslar olib tashlanmoqda",
    'mergeresources': "Resurslar birlashtirilmoqda",
    'mergeassets': "Assetlar birlashtirilmoqda",
    'mergenativelibs': "Native kutubxonalar birlashtirilmoqda",
    'mergejavares': "Java resurslari birlashtirilmoqda",
    'manifest': "AndroidManifest ishlanmoqda",
    'dexbuilder': "DEX fayllar yaratilmoqda",
    'mergedex': "DEX fayllar birlashtirilmoqda",
    'lint': "Lint tekshiruvi",
    'package': "Paketlanmoqda",
    'sign': "Imzolanmoqda",
    'bundle': "App Bundle yig'ilmoqda",
    'assemble': "Yakuniy fayl yig'ilmoqda",
    'stripdebugsymbols': "Debug belgilari olib tashlanmoqda",
    'compileresources': "Resurslar kompilyatsiya qilinmoqda",
    'processresources': "Resurslar ishlanmoqda",
    'generate': "Kod generatsiya qilinmoqda",
    'checkaarmetadata': "Kutubxonalar tekshirilmoqda",
    'extractproguard': "ProGuard qoidalari o'qilmoqda",
  };

  String? get currentTask => _currentTask;
}
