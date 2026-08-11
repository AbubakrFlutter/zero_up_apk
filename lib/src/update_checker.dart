import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// GitHub Releases orqali yangilanish tekshiruvchi
class UpdateChecker {
  UpdateChecker({
    required this.currentVersion,
    required this.repoOwner,
    required this.repoName,
  });

  final String currentVersion;
  final String repoOwner;
  final String repoName;

  static const _checkCooldown = Duration(hours: 24);

  /// GitHub API orqali eng so'nggi versiyani olish
  Future<String?> fetchLatestVersion() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('Timeout', 408),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final tagName = data['tag_name'] as String?;

        // "v1.3.0" → "1.3.0"
        if (tagName != null) {
          return tagName.startsWith('v') ? tagName.substring(1) : tagName;
        }
      }
    } catch (_) {
      // Internet yo'q yoki GitHub API muammosi - indamay o'tamiz
    }
    return null;
  }

  /// Yangilanish borligini tekshirish (24 soatda bir marta)
  Future<bool> shouldCheckForUpdate() async {
    final lastCheckFile = await _getLastCheckFile();

    if (!lastCheckFile.existsSync()) {
      return true;
    }

    try {
      final lastCheckStr = lastCheckFile.readAsStringSync().trim();
      final lastCheck = DateTime.parse(lastCheckStr);
      final now = DateTime.now();

      return now.difference(lastCheck) > _checkCooldown;
    } catch (_) {
      return true;
    }
  }

  /// Oxirgi tekshirilgan vaqtni saqlash
  Future<void> saveLastCheckTime() async {
    try {
      final lastCheckFile = await _getLastCheckFile();
      lastCheckFile.parent.createSync(recursive: true);
      lastCheckFile.writeAsStringSync(DateTime.now().toIso8601String());
    } catch (_) {
      // Xato bo'lsa, indamay o'tamiz
    }
  }

  /// Yangi versiya borligini tekshirish
  Future<String?> getUpdateIfAvailable() async {
    // 24 soatdan ko'p vaqt o'tmagan bo'lsa - tekshirmaymiz
    if (!await shouldCheckForUpdate()) {
      return null;
    }

    final latestVersion = await fetchLatestVersion();
    await saveLastCheckTime();

    if (latestVersion != null && latestVersion != currentVersion) {
      // Versiyalarni solishtirish
      if (_isNewerVersion(latestVersion, currentVersion)) {
        return latestVersion;
      }
    }

    return null;
  }

  /// Yangi versiyani yuklab olish
  Future<File?> downloadLatestRelease() async {
    try {
      final url = Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final assets = data['assets'] as List<dynamic>?;

      if (assets == null || assets.isEmpty) return null;

      // Windows uchun .exe faylni topish
      final exeAsset = assets.firstWhere(
        (asset) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          return name.endsWith('.exe') &&
                 (name.contains('windows') || name.contains('win'));
        },
        orElse: () => null,
      );

      if (exeAsset == null) return null;

      final downloadUrl = exeAsset['browser_download_url'] as String?;
      if (downloadUrl == null) return null;

      // Faylni yuklab olish
      print('📥 Yangi versiya yuklab olinmoqda...');
      final fileResponse = await http.get(Uri.parse(downloadUrl));

      if (fileResponse.statusCode != 200) return null;

      // Vaqtinchalik faylga saqlash
      final tempDir = Directory.systemTemp.createTempSync('zup_update_');
      final tempFile = File(p.join(tempDir.path, 'zup_new.exe'));
      await tempFile.writeAsBytes(fileResponse.bodyBytes);

      print('✅ Yuklab olish yakunlandi');
      return tempFile;
    } catch (e) {
      print('❌ Yuklab olishda xato: $e');
      return null;
    }
  }

  /// Versiyalarni solishtirish (semver)
  bool _isNewerVersion(String newVer, String currentVer) {
    final newParts = newVer.split('.').map(int.tryParse).whereType<int>().toList();
    final currentParts = currentVer.split('.').map(int.tryParse).whereType<int>().toList();

    for (var i = 0; i < 3; i++) {
      final newPart = i < newParts.length ? newParts[i] : 0;
      final currentPart = i < currentParts.length ? currentParts[i] : 0;

      if (newPart > currentPart) return true;
      if (newPart < currentPart) return false;
    }

    return false;
  }

  Future<File> _getLastCheckFile() async {
    final homeDir = Platform.environment['USERPROFILE'] ??
                    Platform.environment['HOME'] ??
                    '';

    return File('$homeDir\\.zup\\last_check.txt');
  }
}
