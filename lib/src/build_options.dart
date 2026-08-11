/// Yig'ish turi.
enum BuildTarget {
  apk('apk', 'APK', 'assemble'),
  aab('appbundle', 'App Bundle (AAB)', 'bundle');

  const BuildTarget(this.flutterCommand, this.uzName, this.gradlePrefix);

  final String flutterCommand;
  final String uzName;
  final String gradlePrefix;
}

/// Yig'ish rejimi.
enum BuildMode {
  release('release', 'Release'),
  profile('profile', 'Profile'),
  debug('debug', 'Debug');

  const BuildMode(this.flag, this.uzName);

  final String flag;
  final String uzName;
}

/// Bitta ishga tushirish uchun barcha sozlamalar.
class BuildOptions {
  BuildOptions({
    required this.projectPath,
    required this.targets,
    this.mode = BuildMode.release,
    this.splitPerAbi = true,
    this.onlyArm64 = false,
    this.obfuscate = false,
    this.clean = false,
    this.tune = true,
    this.aggressive = false,
    this.copyOutput = true,
    this.outputDir,
    this.flavor,
    this.dartDefines = const [],
    this.buildName,
    this.buildNumber,
    this.verbose = false,
    this.ascii = false,
    this.extraArgs = const [],
  });

  final String projectPath;
  final List<BuildTarget> targets;
  final BuildMode mode;

  /// APK ni ABI bo'yicha bo'lib chiqarish (hajmi ~3 barobar kichik bo'ladi).
  final bool splitPerAbi;

  /// Faqat arm64 uchun yig'ish — eng tez rejim (zamonaviy telefonlarning
  /// ~99% i arm64).
  final bool onlyArm64;

  final bool obfuscate;
  final bool clean;

  /// gradle.properties ni kompyuter quvvatiga moslashtirish.
  final bool tune;

  /// Qo'shimcha (tavakkalliroq) tezlashtirishlar.
  final bool aggressive;

  final bool copyOutput;
  final String? outputDir;
  final String? flavor;
  final List<String> dartDefines;
  final String? buildName;
  final String? buildNumber;
  final bool verbose;
  final bool ascii;
  final List<String> extraArgs;

  /// Statistika keshi uchun kalit (shu konfiguratsiya uchun oldingi
  /// yig'ish davomiyligi va task soni saqlanadi).
  String statsKey(BuildTarget target) {
    final parts = [
      target.name,
      mode.name,
      if (onlyArm64) 'arm64',
      if (!onlyArm64 && splitPerAbi && target == BuildTarget.apk) 'split',
      if (obfuscate) 'obf',
      if (flavor != null) 'flavor-$flavor',
    ];
    return parts.join('_');
  }
}
