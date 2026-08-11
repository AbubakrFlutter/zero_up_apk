import 'dart:io';
import 'dart:math' as math;

/// Kompyuter quvvati haqidagi ma'lumot — gradle sozlamalarini shunga qarab
/// moslashtiramiz, shunda kuchsiz noutbukda ham, kuchli PC da ham optimal.
class SystemInfo {
  SystemInfo({required this.cpuCores, required this.ramGb});

  final int cpuCores;
  final int ramGb;

  static Future<SystemInfo> detect() async {
    final cores = math.max(1, Platform.numberOfProcessors);
    final ram = await _detectRamGb();
    return SystemInfo(cpuCores: cores, ramGb: ram);
  }

  static Future<int> _detectRamGb() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
        ], runInShell: true).timeout(const Duration(seconds: 12));
        final bytes = int.tryParse(r.stdout.toString().trim());
        if (bytes != null && bytes > 0) {
          return math.max(2, (bytes / (1024 * 1024 * 1024)).round());
        }
      } else if (Platform.isLinux) {
        final meminfo = File('/proc/meminfo');
        if (meminfo.existsSync()) {
          final m = RegExp(
            r'MemTotal:\s+(\d+) kB',
          ).firstMatch(meminfo.readAsStringSync());
          if (m != null) {
            final kb = int.parse(m.group(1)!);
            return math.max(2, (kb / (1024 * 1024)).round());
          }
        }
      } else if (Platform.isMacOS) {
        final r = await Process.run('sysctl', ['-n', 'hw.memsize'])
            .timeout(const Duration(seconds: 10));
        final bytes = int.tryParse(r.stdout.toString().trim());
        if (bytes != null && bytes > 0) {
          return math.max(2, (bytes / (1024 * 1024 * 1024)).round());
        }
      }
    } catch (_) {
      // Aniqlab bo'lmadi — xavfsiz qiymatga tushamiz.
    }
    return 8;
  }

  /// Gradle JVM uchun ajratiladigan maksimal xotira (MB).
  int get gradleHeapMb {
    if (ramGb <= 4) return 1536;
    if (ramGb <= 6) return 2048;
    if (ramGb <= 8) return 2560;
    if (ramGb <= 12) return 3072;
    if (ramGb <= 16) return 4096;
    if (ramGb <= 32) return 6144;
    return 8192;
  }

  /// Kotlin daemon uchun xotira (MB).
  int get kotlinHeapMb {
    if (ramGb <= 4) return 1024;
    if (ramGb <= 8) return 1536;
    if (ramGb <= 16) return 2048;
    return 3072;
  }

  int get metaspaceMb => ramGb <= 4 ? 512 : 1024;

  /// Bir vaqtda ishlaydigan gradle worker soni.
  int get gradleWorkers {
    if (ramGb <= 4) return math.min(2, cpuCores);
    return cpuCores.clamp(2, 12);
  }

  /// Quvvat darajasi — foydalanuvchiga ko'rsatish uchun.
  String get tier {
    if (ramGb <= 4 || cpuCores <= 2) return 'kuchsiz';
    if (ramGb <= 8 || cpuCores <= 4) return "o'rtacha";
    if (ramGb <= 16) return 'yaxshi';
    return 'kuchli';
  }

  @override
  String toString() => '$cpuCores yadro / $ramGb GB RAM ($tier)';

  /// [path] joylashgan diskda nechta GB bo'sh joy borligini qaytaradi.
  /// Aniqlab bo'lmasa `null`.
  static Future<double?> freeDiskGb(String path) async {
    try {
      if (Platform.isWindows) {
        final drive = path.length >= 2 && path[1] == ':'
            ? path.substring(0, 2)
            : 'C:';
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "(Get-PSDrive ${drive[0]}).Free",
        ], runInShell: true).timeout(const Duration(seconds: 12));
        final bytes = num.tryParse(r.stdout.toString().trim());
        if (bytes != null) return bytes / (1024 * 1024 * 1024);
      } else {
        final r = await Process.run('df', [
          '-k',
          path,
        ]).timeout(const Duration(seconds: 10));
        final lines = r.stdout.toString().trim().split('\n');
        if (lines.length >= 2) {
          final parts = lines.last.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final kb = num.tryParse(parts[3]);
            if (kb != null) return kb / (1024 * 1024);
          }
        }
      }
    } catch (_) {
      // Aniqlab bo'lmadi — tekshiruvni o'tkazib yuboramiz.
    }
    return null;
  }
}
