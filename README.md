# APK Build Publish

一个基于 Flutter/Dart 的 Android APK 多应用市场自动上传工具，包含：

- `CLI`：适合接入 CI/CD
- `Desktop GUI`：适合运营或测试同学手动操作
- `Pure Dart Core`：上传逻辑、项目配置、持久化存储统一复用

## 已实现架构

```text
bin/apk_publish.dart        # CLI 入口
lib/main.dart               # Flutter 桌面入口
lib/src/core/               # 纯 Dart 核心层
lib/src/app/                # Flutter 界面层
```

核心层提供：

- 项目配置模型：基础包地址、签名配置、渠道配置、输出目录
- 项目持久化：自动保存到本机配置目录下的 `projects.json`
- 市场上传注册机制：默认内置华为、小米、OPPO、vivo、应用宝
- 通用 HTTP Multipart 上传器：CLI 和 GUI 共用

> 注意：各应用市场的官方上传接口、鉴权字段、额外参数并不统一。当前版本提供了可扩展的市场适配架构，并通过每个市场的 `endpoint / token / headers / fields` 配置实现接入。要对接某个市场的正式开放平台，只需要替换对应 uploader 或补充该市场的专属参数构造逻辑。

## 本地存储

项目配置会持久化到系统配置目录：

- macOS: `~/Library/Application Support/apk_build_publish/projects.json`
- Windows: `%APPDATA%\\apk_build_publish\\projects.json`
- Linux: `~/.config/apk_build_publish/projects.json`

## CLI 用法

列出项目：

```bash
dart run bin/apk_publish.dart project-list
```

初始化项目：

```bash
dart run bin/apk_publish.dart project-init \
  --name demo \
  --base-package build/app/outputs/flutter-apk/app-release.apk \
  --output-dir build/app/outputs
```

配置某个市场：

```bash
dart run bin/apk_publish.dart project-set-market \
  --project demo \
  --market huawei \
  --enabled true \
  --endpoint https://your-upload-endpoint.example.com \
  --token your-token \
  --track production \
  --header X-App-Id=123 \
  --field packageName=com.example.app
```

执行 dry run：

```bash
dart run bin/apk_publish.dart publish --project demo --dry-run
```

上传到指定市场：

```bash
dart run bin/apk_publish.dart publish --project demo --markets huawei,xiaomi
```

## 桌面端

运行桌面界面：

```bash
flutter run -d macos
# 或
flutter run -d windows
```

桌面端支持：

- 维护多个项目
- 编辑基础包地址、签名配置、渠道配置、输出目录
- 配置每个市场的上传地址、Token、Headers、Fields、更新说明
- 一键保存并持久化
- Dry Run / 真实上传切换
- 查看上传日志

## 建议的下一步

1. 按应用市场补充专属 uploader，例如 `HuaweiUploader`、`XiaomiUploader`
2. 将签名与打包流程接入核心层，实现“构建 + 上传”一体化
3. 为 GUI 增加文件选择器、密文存储、任务队列和上传历史
4. 在 CI 中通过 CLI 注入敏感变量，避免将 token 明文保存在本地文件
