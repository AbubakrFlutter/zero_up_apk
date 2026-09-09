# zup — AI rejimi

Claude Code kabi kodlash agentlari uchun. Har bir chaqiruv **stdout'da bitta
JSON obyekt** qaytaradi.

## Chaqirish

```bash
zup ai apk              # yig'ish
zup ai info             # loyiha va muhit holati
zup ai doctor           # muhit tekshiruvi
zup ai last             # oxirgi yig'ishlar
zup ai devices          # ulangan qurilmalar
```

Bir xil natija beradigan boshqa shakllar:

```bash
zup apk --json
zup apk --ai
zup -m ai apk
ZUP_OUTPUT=json zup apk
```

**`ZUP_OUTPUT=json`** — muhit o'zgaruvchisi. Bir marta o'rnatilsa, model
`--json` yozishni o'ylamagan chaqiruvlar ham JSON qaytaradi. Agent harness'i
uchun eng ishonchli yo'l.

## Kafolatlar

1. **stdout — faqat bitta JSON obyekt.** Odamlarga mo'ljallangan matn, progress
   va ogohlantirishlar `stderr` ga ketadi. `JSON.parse(stdout)` hech qanday
   qatorlarni saralashsiz ishlaydi.
2. **Hech qachon savol bermaydi.** Menyu ochilmaydi, tasdiq so'ralmaydi.
3. **Barqaror mashina kodlari.** O'zbekcha matn odamlar uchun — agent
   `code` bo'yicha tarmoqlanadi. Tarjima o'zgarsa kod o'zgarmaydi.
4. **Chiqish kodlari qotirilgan** (quyida).

## Konvert

Har bir javob bir xil tashqi tuzilishga ega:

```jsonc
{
  "schemaVersion": 1,
  "tool": "zup",
  "toolVersion": "2.0.0",
  "kind": "build",           // build|info|doctor|history|devices|install|error
  "ok": true,
  "exitCode": 0,
  "startedAt": "2026-09-09T10:31:04.123Z",
  "finishedAt": "2026-09-09T10:34:08.435Z",
  "durationMs": 184312,
  "warnings": [
    { "code": "SPLIT_IGNORED_ARM64", "message": "…" }
  ],
  "data": { }                // `kind` ga bog'liq
}
```

`data` ichkarida — shunda konvertni bir marta qayta ishlash mumkin, so'ng
`kind` bo'yicha `data` ning shaklini bilib olinadi.

## `kind: "build"` — muvaffaqiyat

```jsonc
"data": {
  "project": {
    "root": "C:\\proj\\myapp",
    "packageName": "my_app",
    "appName": "My App",
    "version": "1.0.0",
    "buildNumber": "3",
    "fullVersion": "1.0.0+3",
    "applicationId": "com.example.my_app",
    "hasAndroid": true
  },
  "request": {
    "targets": ["apk"], "mode": "release", "entryPoint": null,
    "splitPerAbi": true, "onlyArm64": false, "obfuscate": false,
    "clean": false, "tune": true, "treeShakeIcons": true,
    "flavor": null, "dartDefines": [], "buildName": null,
    "buildNumber": null, "extraArgs": [], "copyOutput": true,
    "outputDir": null, "install": false, "deviceId": null
  },
  "resolvedFrom": { "arm64": "flag", "copy": "default", "open": "config" },
  "flutterCommand": ["build","apk","--release","--split-per-abi",
                     "--tree-shake-icons","-v"],
  "targets": [
    {
      "target": "apk",
      "durationMs": 141002,
      "gradleTasks": 312,
      "logPath": "…\\build\\zero_up_apk\\log\\apk.log",
      "artifacts": [
        {
          "fileName": "My_App_v1.0.0+3_arm64-v8a.apk",
          "path": "C:\\Users\\a\\Desktop\\My_App_v1.0.0+3\\…apk",
          "sizeBytes": 8123456,
          "modifiedAt": "2026-09-09T10:33:51.004Z",
          "abi": "arm64-v8a",
          "universal": false,
          "type": "apk",
          "sha256": null
        }
      ]
    }
  ],
  "outputDir": "C:\\Users\\a\\Desktop\\My_App_v1.0.0+3"
}
```

Ikki maydon alohida foydali:

**`resolvedFrom`** — har bir sozlama qayerdan kelgani: `flag`, `config` yoki
`default`. "Nega arm64 yig'ilyapti, men so'ramadim-ku?" degan savolga
`~/.zup/config.json` ni o'qimasdan javob beradi.

**`flutterCommand`** — aynan qanday chaqirilgani. Agent uni takrorlashi yoki
qo'lda o'zgartirib qayta ishga tushirishi mumkin.

## `kind: "build"` — xato

```jsonc
"data": {
  "project": { },
  "request": { },
  "failure": {
    "phase": "gradle",              // preflight|pubGet|clean|gradle|deliver|install
    "target": "apk",
    "code": "SIGNING_CONFIG",       // barqaror — shu bo'yicha tarmoqlaning
    "title": "Imzolash sozlamalari noto'g'ri",
    "reason": "Release build uchun signing config kerak…",
    "retryable": false,
    "toolExitCode": 1,
    "matchedLine": "> Task :app:validateSigningRelease FAILED",
    "remedies": [
      { "message": "android/key.properties mavjudligini tekshiring", "command": null },
      { "message": "Debug rejimda sinab ko'ring", "command": "zup apk --mode debug" }
    ],
    "log": {
      "path": "…\\apk.log",
      "lineCount": 4213,
      "highlights": [ { "line": 12, "text": "FAILURE: Build failed…" } ],
      "tail": [ "…oxirgi 60 qator…" ]
    }
  }
}
```

`log.tail` 60 qator bilan cheklangan va `highlights` raqamli — agent
kontekstini 4000 qatorlik log bilan to'ldirmasdan diagnostika qila oladi.
To'liq log `log.path` da.

### Xato kodlari

`FLUTTER_NOT_FOUND` · `GRADLE_BUILD_FAILED` · `BUILD_EXCEPTION` ·
`SIGNING_CONFIG` · `KEYSTORE_CREDENTIALS` · `KEYSTORE` · `GRADLE_TASK_FAILED` ·
`BUILD_GRADLE_SYNTAX` · `NATIVE_CPP` · `JAVA_IMPORT` · `OUT_OF_MEMORY` ·
`ANDROID_SDK_MISSING` · `MANIFEST_MERGER` · `LINT` · `JDK_MISMATCH` ·
`DUPLICATE_CLASS` · `DART_COMPILE_ERROR` · `GRADLE_CONFIG` · `PLUGIN_VERSION` ·
`FILE_LOCKED` · `CMDLINE_TOOLS_MISSING` · `DISK_FULL` · `NETWORK` ·
`R8_MINIFY` · `AAPT_RESOURCE` · `SDK_VERSION_MISMATCH` · `UNKNOWN`

**`retryable: true`** faqat `NETWORK` va `FILE_LOCKED` da — bular o'tkinchi
muammolar, kod xatosi emas. Agent qayta urinib ko'rishi mantiqiy.

## `kind: "info"`

Agent uchun **birinchi chaqiruv**: "shu yerda yig'a olamanmi, yo'q bo'lsa nega?"

```jsonc
"data": {
  "buildable": true,
  "blockers": [],            // [{ code, message }]
  "project": { },
  "config": { "path": "…", "exists": true, "out": null,
              "open": false, "arm64": null, "copy": null },
  "system": { "cpuCores": 8, "ramGb": 16,
              "gradleHeapMb": 4096, "gradleWorkers": 8 },
  "output": { "style": "json", "reason": "ai", "color": false, "columns": 80 }
}
```

`output.reason` — nega shu rejim tanlangani (`ai`, `env:ZUP_OUTPUT`, `ci:CI`,
`stdout-not-tty`, `tty`, …). "Nega progress ko'rinmayapti?" degan savol
o'z-o'zidan javob topadi.

## `kind: "doctor"`

```jsonc
"data": {
  "summary": { "pass": 10, "warn": 0, "fail": 0, "skip": 0 },
  "checks": [
    { "id": "flutter", "label": "Flutter SDK", "status": "pass",
      "value": "3.47.2", "path": null,
      "message": "Flutter 3.47.2", "remedies": [] }
  ]
}
```

Barqaror `id` lar: `flutter`, `dart`, `java`, `android_sdk`, `adb`,
`disk_space`, `zup_binary`, `project`, `android_dir`, `signing`.

`status`: `pass` | `warn` | `fail` | `skip`. Bitta `fail` bo'lsa — chiqish
kodi **69**.

## `kind: "history"` — `zup ai last`

```jsonc
"data": {
  "count": 2,
  "projectRoot": "…",
  "entries": [
    { "id": "2026-09-09T10-31-04-123Z", "zupVersion": "2.0.0",
      "startedAt": "…", "durationMs": 184312, "ok": true, "exitCode": 0,
      "targets": ["apk"], "mode": "release", "appVersion": "1.0.0+3",
      "onlyArm64": true, "flavor": null, "outputDir": "…",
      "logPath": null, "failureCode": null,
      "artifacts": [ { "fileName": "…apk", "path": "…",
                       "sizeBytes": 8123456, "abi": "arm64-v8a",
                       "exists": true } ] }
  ]
}
```

`artifacts[].exists` o'qish paytida qayta tekshiriladi — "oxirgi nima
yig'gandim, u hali turibdimi?" degan savolga rost javob beradi.

## `kind: "devices"`

```jsonc
"data": {
  "adb": { "found": true, "path": "…\\platform-tools\\adb.exe" },
  "devices": [
    { "id": "emulator-5554", "state": "device", "model": "sdk gphone64",
      "supportedAbis": ["x86_64","arm64-v8a"], "sdk": 34,
      "release": "14", "isEmulator": true, "ready": true }
  ]
}
```

`supportedAbis` — `zup apk -i` shu ro'yxatga qarab mos APK ni tanlaydi
(`--split-per-abi` bilan bir necha APK chiqadi).

## `kind: "error"`

Yig'ish boshlanishidan oldingi xatolar:

```jsonc
{
  "kind": "error", "ok": false, "exitCode": 64,
  "data": { "error": {
    "code": "UNKNOWN_COMMAND",
    "message": "Noma'lum buyruq: 'apkk'",
    "detail": "Mavjud buyruqlar: apk, aab, hammasi, …",
    "argument": "apkk",
    "didYouMean": ["apk"],
    "remedies": [ { "message": "Shuni nazarda tutdingizmi?", "command": "zup apk" } ]
  } }
}
```

Kodlar: `UNKNOWN_COMMAND` · `MISSING_TARGET` · `CONFLICTING_COMMAND` ·
`BAD_ARGUMENT` · `NO_PROJECT` · `NO_ANDROID_DIR` · `ADB_NOT_FOUND` ·
`NO_DEVICE` · `MULTIPLE_DEVICES` · `NOT_IMPLEMENTED`

## Chiqish kodlari

2.x davomida o'zgarmaydi.

| Kod | Ma'nosi |
|-----|---------|
| 0 | muvaffaqiyat |
| 64 | buyruq yoki bayroq xatosi |
| 66 | Flutter loyihasi topilmadi, yoki `android/` papkasi yo'q |
| 69 | tashqi vosita yo'q (flutter, adb) — `doctor` da `fail` bor |
| 70 | yig'ish yiqildi |
| 73 | chiqish papkasiga yozib bo'lmadi |
| 130 | `Ctrl+C` |

## Namuna: agent oqimi

```bash
# 1. Yig'a olamanmi?
zup ai info          # data.buildable, data.blockers

# 2. Muhitda muammo bormi?
zup ai doctor        # exitCode 69 bo'lsa — data.checks dagi fail larni o'qing

# 3. Yig'ish
zup ai apk --arm64   # ok:true bo'lsa data.targets[].artifacts[].path

# 4. Yiqilsa
#    data.failure.code bo'yicha tarmoqlaning
#    data.failure.retryable=true bo'lsa — qayta urinib ko'ring
#    data.failure.remedies[].command ni to'g'ridan-to'g'ri ishlatish mumkin
```
