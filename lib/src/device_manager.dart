import 'dart:io';

import 'build_options.dart';
import 'doctor.dart';
import 'output_manager.dart';

/// Ulangan Android qurilmasi.
class AndroidDevice {
  const AndroidDevice({
    required this.id,
    required this.state,
    this.model,
    this.supportedAbis = const [],
    this.sdk,
    this.release,
  });

  /// adb dagi identifikator (`emulator-5554`, seriya raqami).
  final String id;

  /// `device` — tayyor, `unauthorized` — ruxsat berilmagan, `offline`.
  final String state;

  final String? model;

  /// Qurilma qo'llab-quvvatlaydigan ABI lar — eng afzali birinchi.
  final List<String> supportedAbis;

  final int? sdk;
  final String? release;

  bool get isEmulator => id.startsWith('emulator-');
  bool get isReady => state == 'device';

  /// Ko'rsatish uchun nom.
  String get displayName {
    final name = model ?? id;
    final android = release == null ? '' : ' · Android $release';
    final kind = isEmulator ? ' · emulyator' : '';
    return '$name$android$kind';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'state': state,
        'model': model,
        'supportedAbis': supportedAbis,
        'sdk': sdk,
        'release': release,
        'isEmulator': isEmulator,
        'ready': isReady,
      };
}

/// O'rnatish natijasi.
class InstallResult {
  const InstallResult({
    required this.ok,
    required this.deviceId,
    required this.apkPath,
    required this.duration,
    this.errorOutput,
  });

  final bool ok;
  final String deviceId;
  final String apkPath;
  final Duration duration;
  final String? errorOutput;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'deviceId': deviceId,
        'apk': apkPath,
        'durationMs': duration.inMilliseconds,
        'errorOutput': errorOutput,
      };
}

/// adb orqali qurilmalar bilan ishlaydi.
class DeviceManager {
  DeviceManager({Map<String, String>? env})
      : env = env ?? Platform.environment;

  final Map<String, String> env;

  String? get adbPath => findAdb(env);

  /// Ulangan qurilmalar ro'yxati.
  ///
  /// Har biri uchun ABI va Android versiyasi ham so'raladi — `-i` da
  /// mos APK ni tanlash uchun kerak.
  Future<List<AndroidDevice>> listDevices() async {
    final adb = adbPath;
    if (adb == null) return [];

    final ProcessResult result;
    try {
      result = await Process.run(adb, ['devices', '-l'])
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return [];
    }
    if (result.exitCode != 0) return [];

    final devices = <AndroidDevice>[];
    for (final line in result.stdout.toString().split('\n').skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final id = parts[0];
      final state = parts[1];
      final model = RegExp(r'model:(\S+)').firstMatch(trimmed)?.group(1);

      // Faqat tayyor qurilmalardan xossalarini so'raymiz.
      var abis = <String>[];
      int? sdk;
      String? release;

      if (state == 'device') {
        abis = await _getProperty(adb, id, 'ro.product.cpu.abilist')
            .then((v) => v?.split(',').map((s) => s.trim()).toList() ?? []);
        sdk = int.tryParse(
          await _getProperty(adb, id, 'ro.build.version.sdk') ?? '',
        );
        release = await _getProperty(adb, id, 'ro.build.version.release');
      }

      devices.add(AndroidDevice(
        id: id,
        state: state,
        model: model?.replaceAll('_', ' '),
        supportedAbis: abis,
        sdk: sdk,
        release: release,
      ));
    }

    return devices;
  }

  Future<String?> _getProperty(String adb, String id, String key) async {
    try {
      final r = await Process.run(adb, ['-s', id, 'shell', 'getprop', key])
          .timeout(const Duration(seconds: 10));
      final value = r.stdout.toString().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// APK ni qurilmaga o'rnatadi.
  Future<InstallResult> install({
    required String apkPath,
    required String deviceId,
  }) async {
    final adb = adbPath;
    final started = DateTime.now();

    if (adb == null) {
      return InstallResult(
        ok: false,
        deviceId: deviceId,
        apkPath: apkPath,
        duration: Duration.zero,
        errorOutput: 'adb topilmadi',
      );
    }

    try {
      // -r: mavjud ilovani almashtirish, -t: test APK ga ham ruxsat
      final result = await Process.run(
        adb,
        ['-s', deviceId, 'install', '-r', '-t', apkPath],
      ).timeout(const Duration(minutes: 5));

      final output = '${result.stdout}${result.stderr}';
      // adb muvaffaqiyatda ham 0 qaytaradi, lekin matnda "Failure" bo'lishi
      // mumkin — shuning uchun ikkalasini tekshiramiz.
      final ok = result.exitCode == 0 && !output.contains('Failure');

      return InstallResult(
        ok: ok,
        deviceId: deviceId,
        apkPath: apkPath,
        duration: DateTime.now().difference(started),
        errorOutput: ok ? null : output.trim(),
      );
    } catch (e) {
      return InstallResult(
        ok: false,
        deviceId: deviceId,
        apkPath: apkPath,
        duration: DateTime.now().difference(started),
        errorOutput: e.toString(),
      );
    }
  }
}

/// Qurilmaga MOS APK ni tanlaydi.
///
/// `--split-per-abi` bilan bir necha APK chiqadi va noto'g'risini
/// o'rnatish "ilova ochilmaydi" degan tushunarsiz natijaga olib keladi.
/// Qurilmaning ABI ro'yxati bo'yicha eng mosini tanlaymiz.
DeliveredFile? pickApkForDevice(
  List<DeliveredFile> files,
  AndroidDevice device,
) {
  final apks = files.where((f) => f.target == BuildTarget.apk).toList();
  if (apks.isEmpty) return null;

  // 1) Qurilma afzal ko'rgan ABI tartibida qidiramiz.
  for (final abi in device.supportedAbis) {
    for (final apk in apks) {
      if (apk.abi == abi) return apk;
    }
  }

  // 2) Universal APK (ABI ko'rsatilmagan) — hamma joyda ishlaydi.
  for (final apk in apks) {
    if (apk.abi == null) return apk;
  }

  // 3) ABI ma'lum bo'lmasa (masalan qurilma javob bermadi) — birinchisi.
  return device.supportedAbis.isEmpty ? apks.first : null;
}
