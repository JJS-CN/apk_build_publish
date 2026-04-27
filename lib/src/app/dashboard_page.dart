import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/models/market_type.dart';
import '../core/models/project_config.dart';
import '../core/models/publish_request.dart';
import '../core/services/apk_publish_service.dart';
import '../core/services/base_apk_matcher.dart';
import '../core/services/market_channel_schema.dart';
import '../core/services/project_store.dart';
import '../core/services/tool_bundle.dart';
import '../core/widgets/middle_ellipsis_text.dart';
import 'project_form_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.controller});

  final DashboardPageController? controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ProjectStore _store = ProjectStore();
  final ApkPublishService _publishService = ApkPublishService();
  final List<ProjectConfig> _projects = <ProjectConfig>[];
  final List<String> _logs = <String>[];

  bool _loading = true;
  bool _queryingBasePackage = false;
  bool _generatingAllChannels = false;
  String? _selectedProjectId;
  BaseApkLookupResult? _baseApkLookupResult;
  final Map<String, _ChannelTaskStatus> _channelGenerateStatuses =
      <String, _ChannelTaskStatus>{};
  final Map<String, _ProjectUpdateDraft> _updateDrafts =
      <String, _ProjectUpdateDraft>{};
  final Map<String, _BasePackageInfoDraft> _basePackageInfoDrafts =
      <String, _BasePackageInfoDraft>{};
  final Map<String, TextEditingController> _releaseNotesControllers =
      <String, TextEditingController>{};

  ProjectConfig? get _selectedProject {
    if (_projects.isEmpty) {
      return null;
    }

    for (final project in _projects) {
      if (project.id == _selectedProjectId) {
        return project;
      }
    }
    return _projects.first;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(
      importConfigs: _importConfigs,
      exportConfigs: _exportConfigs,
    );
    unawaited(_loadProjects());
  }

  @override
  void dispose() {
    widget.controller?._unbind();
    for (final controller in _releaseNotesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProjects({String? preferredProjectId}) async {
    final projects = await _store.loadAll();
    if (!mounted) {
      return;
    }

    final fallbackId = projects.isEmpty ? null : projects.first.id;
    final selectedId = _resolveSelectedProjectId(
      projects,
      preferredProjectId ?? _selectedProjectId,
      fallbackId,
    );

    setState(() {
      _projects
        ..clear()
        ..addAll(projects);
      _selectedProjectId = selectedId;
      if (_selectedProjectId != selectedId) {
        _baseApkLookupResult = null;
      }
      _loading = false;
    });

    _pruneProjectScopedState(projects);

    final selectedProject = _selectedProject;
    if (selectedProject != null) {
      unawaited(_ensureUpdateCardDataLoaded(selectedProject));
    }
  }

  String? _resolveSelectedProjectId(
    List<ProjectConfig> projects,
    String? preferredProjectId,
    String? fallbackId,
  ) {
    if (preferredProjectId != null) {
      for (final project in projects) {
        if (project.id == preferredProjectId) {
          return preferredProjectId;
        }
      }
    }
    return fallbackId;
  }

  void _pruneProjectScopedState(List<ProjectConfig> projects) {
    final projectIds = projects.map((project) => project.id).toSet();

    _updateDrafts.removeWhere(
      (projectId, _) => !projectIds.contains(projectId),
    );
    _basePackageInfoDrafts.removeWhere(
      (projectId, _) => !projectIds.contains(projectId),
    );
    _channelGenerateStatuses.removeWhere((key, _) {
      final separator = key.indexOf(':');
      if (separator <= 0) {
        return true;
      }
      return !projectIds.contains(key.substring(0, separator));
    });

    final removedControllerKeys = _releaseNotesControllers.keys
        .where((projectId) => !projectIds.contains(projectId))
        .toList();
    for (final projectId in removedControllerKeys) {
      _releaseNotesControllers.remove(projectId)?.dispose();
    }
  }

  void _selectProject(ProjectConfig project) {
    setState(() {
      _selectedProjectId = project.id;
      _baseApkLookupResult = null;
    });
    unawaited(_ensureUpdateCardDataLoaded(project));
  }

  Future<void> _openCreateProject() async {
    final result = await Navigator.of(context).push<ProjectFormResult>(
      MaterialPageRoute<ProjectFormResult>(
        builder: (_) => const ProjectFormPage(),
      ),
    );
    await _applyResult(result);
  }

  Future<void> _openEditProject(ProjectConfig project) async {
    final result = await Navigator.of(context).push<ProjectFormResult>(
      MaterialPageRoute<ProjectFormResult>(
        builder: (_) => ProjectFormPage(initialProject: project),
      ),
    );
    await _applyResult(result);
  }

  Future<void> _applyResult(ProjectFormResult? result) async {
    if (result == null) {
      return;
    }

    await _loadProjects(preferredProjectId: result.projectId);
    if (!mounted) {
      return;
    }

    if (result.messages.isEmpty) {
      return;
    }

    setState(() {
      _logs.insertAll(0, result.messages.reversed);
    });
  }

  Future<void> _exportConfigs() async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'apk_build_publish_projects.json',
        confirmButtonText: '导出配置',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
      );
      if (location == null) {
        return;
      }

      await _store.saveToFile(File(location.path), _projects);
      if (!mounted) {
        return;
      }
      setState(() {
        _logs.insert(0, '已导出 ${_projects.length} 个项目到 ${location.path}');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置导出成功')));
    } catch (error) {
      _showActionError('导出配置失败', error);
    }
  }

  Future<void> _importConfigs() async {
    try {
      final file = await openFile(
        confirmButtonText: '导入配置',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
      );
      if (file == null) {
        return;
      }

      final importedProjects = await _store.loadFromFile(File(file.path));
      final mergedProjects = <ProjectConfig>[..._projects];
      for (final project in importedProjects) {
        final index = mergedProjects.indexWhere(
          (item) => item.id == project.id || item.name == project.name,
        );
        if (index >= 0) {
          mergedProjects[index] = project;
        } else {
          mergedProjects.add(project);
        }
      }

      await _store.saveAll(mergedProjects);
      await _loadProjects(
        preferredProjectId: importedProjects.isEmpty
            ? _selectedProjectId
            : importedProjects.first.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _logs.insert(
          0,
          '已导入 ${importedProjects.length} 个项目配置，当前共 ${mergedProjects.length} 个项目。',
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置导入成功')));
    } catch (error) {
      _showActionError('导入配置失败', error);
    }
  }

  void _showActionError(String prefix, Object error) {
    if (!mounted) {
      return;
    }

    final message = '$prefix: $error';
    setState(() {
      _logs.insert(0, message);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  _ProjectUpdateDraft _updateDraftOf(ProjectConfig project) {
    return _updateDrafts.putIfAbsent(
      project.id,
      () => _ProjectUpdateDraft(releaseNotes: _initialReleaseNotes(project)),
    );
  }

  _BasePackageInfoDraft _basePackageInfoOf(ProjectConfig project) {
    return _basePackageInfoDrafts.putIfAbsent(
      project.id,
      () => _BasePackageInfoDraft(packagePath: project.basePackagePath),
    );
  }

  TextEditingController _releaseNotesControllerOf(ProjectConfig project) {
    return _releaseNotesControllers.putIfAbsent(project.id, () {
      final controller = TextEditingController(
        text: _updateDraftOf(project).releaseNotes,
      );
      controller.addListener(() {
        _updateDraftOf(project).releaseNotes = controller.text;
      });
      return controller;
    });
  }

  String _initialReleaseNotes(ProjectConfig project) {
    for (final market in project.enabledMarkets) {
      final notes = project.channels[market]?.releaseNotes.trim() ?? '';
      if (notes.isNotEmpty) {
        return notes;
      }
    }
    return '';
  }

  Future<void> _ensureUpdateCardDataLoaded(ProjectConfig project) async {
    final draft = _updateDraftOf(project);
    final basePackageDraft = _basePackageInfoOf(project);
    if (!basePackageDraft.loaded && !basePackageDraft.loading) {
      await _refreshBasePackageInfo(project);
    }
    if (!draft.screenshotsLoaded && !draft.loadingScreenshots) {
      await _refreshProjectScreenshots(project);
    }
  }

  Future<void> _refreshBasePackageInfo(ProjectConfig project) async {
    final draft = _basePackageInfoOf(project);
    if (draft.loading) {
      return;
    }

    setState(() {
      draft.loading = true;
      draft.loaded = true;
      draft.message = '正在读取基础包信息...';
      draft.packagePath = project.basePackagePath;
    });

    BaseApkLookupResult? lookupResult;
    _ApkBadgingInfo? badgingInfo;
    _LogoExtractionResult? logoResult;
    String message;
    String logoMessage = draft.logoMessage;

    try {
      lookupResult = await BaseApkMatcher.lookup(project);
      if (!lookupResult.found || lookupResult.matchedFile == null) {
        message = '基础包信息读取失败：${lookupResult.message}';
      } else {
        final apkFile = lookupResult.matchedFile!;
        badgingInfo = await _readApkBadgingInfo(apkFile);
        logoResult = await _extractLogoFromApk(apkFile);
        logoMessage = logoResult.message;
        message = badgingInfo == null ? '已读取基础包地址，但未能完整解析 APK 元数据' : '基础包信息已更新';
      }
    } catch (error) {
      message = '基础包信息读取失败：$error';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      draft.loading = false;
      draft.message = message;
      draft.logoMessage = logoMessage;
      if (lookupResult != null) {
        draft.packagePath = lookupResult.message;
        if (_selectedProjectId == project.id) {
          _baseApkLookupResult = lookupResult;
        }
      }
      draft.displayName = badgingInfo?.label ?? draft.displayName;
      draft.packageName = badgingInfo?.packageName ?? draft.packageName;
      draft.versionCode = badgingInfo?.versionCode ?? draft.versionCode;
      draft.versionName = badgingInfo?.versionName ?? draft.versionName;
      if (logoResult?.bytes != null) {
        draft.logoBytes = logoResult!.bytes;
        draft.logoName = logoResult.entryName;
      }
    });
  }

  Future<void> _refreshProjectScreenshots(ProjectConfig project) async {
    final draft = _updateDraftOf(project);
    if (draft.loadingScreenshots) {
      return;
    }

    setState(() {
      draft.loadingScreenshots = true;
      draft.screenshotsLoaded = true;
      draft.screenshotMessage = '正在读取市场图...';
    });

    List<File> screenshotFiles = <File>[];
    String screenshotMessage;

    try {
      final outputDirectoryPath = project.outputDirectory.trim();
      if (outputDirectoryPath.isEmpty) {
        screenshotMessage = '未配置输出目录，无法读取 screenshot 文件夹。';
      } else {
        final screenshotDirectory = Directory(
          '$outputDirectoryPath${Platform.pathSeparator}screenshot',
        );
        if (!await screenshotDirectory.exists()) {
          screenshotMessage = '未找到目录：${screenshotDirectory.path}';
        } else {
          screenshotFiles = await screenshotDirectory
              .list(followLinks: false)
              .where(
                (entity) =>
                    entity is File && _isSupportedImageFile(entity.path),
              )
              .cast<File>()
              .toList();
          screenshotFiles.sort(
            (left, right) => _fileName(
              left,
            ).toLowerCase().compareTo(_fileName(right).toLowerCase()),
          );
          screenshotMessage = screenshotFiles.isEmpty
              ? '目录下没有可用市场图。'
              : '已读取 ${screenshotFiles.length} 张市场图，可拖动调整顺序。';
        }
      }
    } catch (error) {
      screenshotMessage = '市场图读取失败：$error';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      draft.loadingScreenshots = false;
      draft.screenshots = screenshotFiles;
      draft.screenshotMessage = screenshotMessage;
    });
  }

  Future<_LogoExtractionResult> _extractLogoFromApk(File apkFile) async {
    final apktoolFile = await ToolBundle.apktool();
    final tempDir = await Directory.systemTemp.createTemp('apk_logo_');
    final outputDir = Directory('${tempDir.path}/decoded');
    try {
      final decodeResult = await Process.run('java', <String>[
        '-jar',
        apktoolFile.path,
        'd',
        '-f',
        '-s',
        '-o',
        outputDir.path,
        apkFile.path,
      ]);
      if (decodeResult.exitCode != 0) {
        return _LogoExtractionResult.failure('无法解析 APK 资源');
      }

      final manifestFile = File('${outputDir.path}/AndroidManifest.xml');
      if (!await manifestFile.exists()) {
        return _LogoExtractionResult.failure('未找到 AndroidManifest.xml');
      }

      final manifestContent = await manifestFile.readAsString();
      final iconReference = _readManifestIconReference(manifestContent);
      if (iconReference != null) {
        final resolvedLogoPath = await _resolveImageResourceFromReference(
          outputDir,
          iconReference,
        );
        if (resolvedLogoPath != null) {
          final extractedFile = File(resolvedLogoPath);
          if (await extractedFile.exists()) {
            return _LogoExtractionResult.success(
              bytes: await extractedFile.readAsBytes(),
              entryName: _fileName(extractedFile),
              message:
                  '已根据 AndroidManifest.xml 定位 Logo：$iconReference -> ${_fileName(extractedFile)}',
            );
          }
        }
      }

      final fallbackResult = await _extractLogoWithAapt(
        apkFile: apkFile,
        workingDirectory: tempDir,
        iconReference: iconReference,
      );
      if (fallbackResult != null) {
        return fallbackResult;
      }

      if (iconReference == null) {
        return _LogoExtractionResult.failure(
          'AndroidManifest.xml 中未找到 application icon',
        );
      }
      return _LogoExtractionResult.failure(
        '未能根据 AndroidManifest.xml 中的 $iconReference 定位真实图片',
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<_LogoExtractionResult?> _extractLogoWithAapt({
    required File apkFile,
    required Directory workingDirectory,
    required String? iconReference,
  }) async {
    final badgingResult = await Process.run('aapt', <String>[
      'dump',
      'badging',
      apkFile.path,
    ]);
    if (badgingResult.exitCode != 0) {
      return null;
    }

    final iconEntry = _readResolvedIconEntryFromBadging(
      badgingResult.stdout.toString(),
    );
    if (iconEntry == null) {
      return null;
    }

    final extractResult = await Process.run('jar', <String>[
      '--extract',
      '--file',
      apkFile.path,
      iconEntry,
    ], workingDirectory: workingDirectory.path);
    if (extractResult.exitCode != 0) {
      return null;
    }

    final extractedFile = File('${workingDirectory.path}/$iconEntry');
    if (!await extractedFile.exists()) {
      return null;
    }

    final iconSource = iconReference ?? 'manifest icon';
    return _LogoExtractionResult.success(
      bytes: await extractedFile.readAsBytes(),
      entryName: _fileName(extractedFile),
      message: '已根据 $iconSource 解析 Logo：$iconEntry',
    );
  }

  Future<_ApkBadgingInfo?> _readApkBadgingInfo(File apkFile) async {
    final badgingResult = await Process.run('aapt', <String>[
      'dump',
      'badging',
      apkFile.path,
    ]);
    if (badgingResult.exitCode != 0) {
      return null;
    }
    return _parseBadgingInfo(badgingResult.stdout.toString());
  }

  String? _readManifestIconReference(String manifestContent) {
    final applicationMatch = RegExp(
      r'<application\b[^>]*android:icon="([^"]+)"',
      dotAll: true,
    ).firstMatch(manifestContent);
    return applicationMatch?.group(1);
  }

  Future<String?> _resolveImageResourceFromReference(
    Directory decodedApkDir,
    String resourceReference, {
    Set<String>? visitedReferences,
  }) async {
    final normalized = resourceReference.trim();
    if (normalized.isEmpty || !normalized.startsWith('@')) {
      return null;
    }
    if (normalized.startsWith('@android:')) {
      return null;
    }

    final visited = visitedReferences ?? <String>{};
    if (!visited.add(normalized)) {
      return null;
    }

    final slashIndex = normalized.indexOf('/');
    if (slashIndex < 0) {
      return null;
    }

    final rawResourceType = normalized.substring(1, slashIndex);
    final resourceType = rawResourceType.contains(':')
        ? rawResourceType.split(':').last
        : rawResourceType;
    final resourceName = normalized.substring(slashIndex + 1);
    if (resourceType.isEmpty || resourceName.isEmpty) {
      return null;
    }

    final resDir = Directory('${decodedApkDir.path}/res');
    if (!await resDir.exists()) {
      return null;
    }

    final matchingFiles = await resDir
        .list(recursive: true, followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              _matchesResourceFile(
                file: entity,
                resourceType: resourceType,
                resourceName: resourceName,
              ),
        )
        .cast<File>()
        .toList();

    final imageCandidates =
        matchingFiles.where((file) => _isSupportedImageFile(file.path)).toList()
          ..sort(_compareResourceFilePriority);
    if (imageCandidates.isNotEmpty) {
      return imageCandidates.first.path;
    }

    final xmlCandidates =
        matchingFiles
            .where((file) => file.path.toLowerCase().endsWith('.xml'))
            .toList()
          ..sort(_compareResourceFilePriority);

    for (final candidate in xmlCandidates) {
      final xmlContent = await candidate.readAsString();
      for (final nestedReference in _extractNestedDrawableReferences(
        xmlContent,
      )) {
        final resolvedPath = await _resolveImageResourceFromReference(
          decodedApkDir,
          nestedReference,
          visitedReferences: visited,
        );
        if (resolvedPath != null) {
          return resolvedPath;
        }
      }
    }

    return null;
  }

  bool _matchesResourceFile({
    required FileSystemEntity file,
    required String resourceType,
    required String resourceName,
  }) {
    final normalizedDirectory = file.parent.uri.pathSegments.isEmpty
        ? ''
        : file.parent.uri.pathSegments.last.toLowerCase();
    final normalizedName = resourceName.toLowerCase();
    final normalizedFileName = _fileName(file).toLowerCase();
    if (!normalizedDirectory.startsWith(resourceType.toLowerCase())) {
      return false;
    }

    return normalizedFileName == '$normalizedName.png' ||
        normalizedFileName == '$normalizedName.webp' ||
        normalizedFileName == '$normalizedName.jpg' ||
        normalizedFileName == '$normalizedName.jpeg' ||
        normalizedFileName == '$normalizedName.xml';
  }

  int _compareResourceFilePriority(File left, File right) {
    final densityDiff = _resourceDensityScore(
      right.path,
    ).compareTo(_resourceDensityScore(left.path));
    if (densityDiff != 0) {
      return densityDiff;
    }

    final leftIsImage = _isSupportedImageFile(left.path);
    final rightIsImage = _isSupportedImageFile(right.path);
    if (leftIsImage != rightIsImage) {
      return rightIsImage ? 1 : -1;
    }

    return left.path.compareTo(right.path);
  }

  int _resourceDensityScore(String path) {
    final normalized = path.toLowerCase();
    const densityOrder = <String, int>{
      'xxxhdpi': 6,
      'xxhdpi': 5,
      'xhdpi': 4,
      'hdpi': 3,
      'mdpi': 2,
      'nodpi': 1,
      'anydpi': 0,
    };
    return densityOrder.entries
        .where((entry) => normalized.contains(entry.key))
        .map((entry) => entry.value)
        .fold<int>(-1, (current, value) => value > current ? value : current);
  }

  Iterable<String> _extractNestedDrawableReferences(String xmlContent) {
    return RegExp(r'android:drawable="([^"]+)"')
        .allMatches(xmlContent)
        .map((match) => match.group(1) ?? '')
        .where(
          (value) =>
              value.startsWith('@mipmap/') || value.startsWith('@drawable/'),
        );
  }

  String? _readResolvedIconEntryFromBadging(String badgingOutput) {
    final densityMatches = RegExp(
      r"application-icon-(\d+):'([^']+)'",
    ).allMatches(badgingOutput).toList();
    if (densityMatches.isNotEmpty) {
      densityMatches.sort((left, right) {
        final leftDensity = int.tryParse(left.group(1) ?? '') ?? 0;
        final rightDensity = int.tryParse(right.group(1) ?? '') ?? 0;
        return rightDensity.compareTo(leftDensity);
      });
      return densityMatches.first.group(2);
    }

    final applicationMatch = RegExp(
      r"application:.* icon='([^']+)'",
      dotAll: false,
    ).firstMatch(badgingOutput);
    return applicationMatch?.group(1);
  }

  _ApkBadgingInfo? _parseBadgingInfo(String badgingOutput) {
    final packageMatch = RegExp(
      r"package: name='([^']+)'.*versionCode='([^']*)'.*versionName='([^']*)'",
      dotAll: false,
    ).firstMatch(badgingOutput);
    if (packageMatch == null) {
      return null;
    }

    final localizedLabelMatch = RegExp(
      r"application-label-[^:]+:'([^']+)'",
    ).firstMatch(badgingOutput);
    final defaultLabelMatch = RegExp(
      r"application-label:'([^']+)'",
    ).firstMatch(badgingOutput);

    return _ApkBadgingInfo(
      packageName: packageMatch.group(1) ?? '-',
      versionCode: packageMatch.group(2) ?? '-',
      versionName: packageMatch.group(3) ?? '-',
      label:
          localizedLabelMatch?.group(1) ?? defaultLabelMatch?.group(1) ?? '-',
    );
  }

  bool _isSupportedImageFile(String path) {
    final normalized = path.toLowerCase();
    return normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.webp');
  }

  void _reorderScreenshots(ProjectConfig project, int oldIndex, int newIndex) {
    final draft = _updateDraftOf(project);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    setState(() {
      final item = draft.screenshots.removeAt(oldIndex);
      draft.screenshots.insert(newIndex, item);
    });
  }

  Future<void> _generateChannelPackage(
    ProjectConfig project,
    MarketType market,
  ) async {
    final initialStatus = _generationStatusOf(project, market);
    if (_generatingAllChannels || initialStatus.isRunning) {
      return;
    }

    setState(() {
      _setGenerationStatus(project, market, _ChannelTaskStatus.running('生成中'));
    });

    final result = await _runChannelPackageGeneration(
      project: project,
      markets: <MarketType>[market],
      actionLabel: '${market.displayName} 渠道包生成',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      if (result.lookupResult != null) {
        _baseApkLookupResult = result.lookupResult;
      }
      _setGenerationStatus(
        project,
        market,
        result.success
            ? _ChannelTaskStatus.success('已完成')
            : _ChannelTaskStatus.failed('失败'),
      );
      _logs.insert(0, result.logMessage);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.snackBarMessage)));

    if (result.success) {
      unawaited(_refreshProjectScreenshots(project));
      if (_basePackageInfoOf(project).logoBytes == null) {
        unawaited(_refreshBasePackageInfo(project));
      }
    }
  }

  Future<void> _generateAllChannelPackages(ProjectConfig project) async {
    final enabledMarkets = project.enabledMarkets;
    if (enabledMarkets.isEmpty) {
      const message = '当前项目还没有启用任何渠道，无法生成渠道包。';
      setState(() {
        _logs.insert(0, message);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
      return;
    }

    setState(() {
      _generatingAllChannels = true;
      for (final market in enabledMarkets) {
        _setGenerationStatus(
          project,
          market,
          _ChannelTaskStatus.running('生成中'),
        );
      }
    });

    final result = await _runChannelPackageGeneration(
      project: project,
      markets: enabledMarkets,
      actionLabel: '全部渠道包生成',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _generatingAllChannels = false;
      if (result.lookupResult != null) {
        _baseApkLookupResult = result.lookupResult;
      }
      for (final market in enabledMarkets) {
        _setGenerationStatus(
          project,
          market,
          result.success
              ? _ChannelTaskStatus.success('已完成')
              : _ChannelTaskStatus.failed('失败'),
        );
      }
      _logs.insert(0, result.logMessage);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.snackBarMessage)));

    if (result.success) {
      unawaited(_refreshProjectScreenshots(project));
      if (_basePackageInfoOf(project).logoBytes == null) {
        unawaited(_refreshBasePackageInfo(project));
      }
    }
  }

  Future<_ChannelGenerationResult> _runChannelPackageGeneration({
    required ProjectConfig project,
    required List<MarketType> markets,
    required String actionLabel,
  }) async {
    BaseApkLookupResult? lookupResult;

    try {
      lookupResult = await BaseApkMatcher.lookup(project);
      if (!lookupResult.found || lookupResult.matchedFile == null) {
        final message = '$actionLabel失败: ${lookupResult.message}';
        return _ChannelGenerationResult.failed(
          lookupResult: lookupResult,
          logMessage: message,
          snackBarMessage: message,
        );
      }

      final baseApk = lookupResult.matchedFile!;
      final outputPath = project.outputDirectory.trim().isEmpty
          ? baseApk.parent.path
          : project.outputDirectory.trim();
      final outputDirectory = Directory(outputPath);
      await outputDirectory.create(recursive: true);

      final vasDollyFile = await ToolBundle.vasDolly();
      final channelNames = markets.map((market) => market.id).join(',');

      final result = await Process.run('java', <String>[
        '-jar',
        vasDollyFile.path,
        'put',
        '-c',
        channelNames,
        baseApk.path,
        outputDirectory.path,
      ]);

      final outputSummary = _pickProcessSummary(
        stdout: result.stdout,
        stderr: result.stderr,
      );

      if (result.exitCode == 0) {
        final snackBarMessage = outputSummary == null
            ? '$actionLabel成功，输出目录 $outputPath'
            : '$actionLabel成功，输出目录 $outputPath：$outputSummary';
        return _ChannelGenerationResult.success(
          lookupResult: lookupResult,
          logMessage: '$actionLabel成功: ${markets.length} 个渠道，输出目录 $outputPath',
          snackBarMessage: snackBarMessage,
        );
      }

      final message =
          '$actionLabel失败(exitCode=${result.exitCode}): ${outputSummary ?? 'VasDolly 未返回详细信息'}';
      return _ChannelGenerationResult.failed(
        lookupResult: lookupResult,
        logMessage: message,
        snackBarMessage: message,
      );
    } on ProcessException catch (error) {
      final message = '$actionLabel失败: 无法启动 java 命令，$error';
      return _ChannelGenerationResult.failed(
        lookupResult: lookupResult,
        logMessage: message,
        snackBarMessage: message,
      );
    } catch (error) {
      final message = '$actionLabel失败: $error';
      return _ChannelGenerationResult.failed(
        lookupResult: lookupResult,
        logMessage: message,
        snackBarMessage: message,
      );
    }
  }

  String? _pickProcessSummary({
    required Object stdout,
    required Object stderr,
  }) {
    final stdoutText = stdout.toString().trim();
    if (stdoutText.isNotEmpty) {
      return stdoutText.split('\n').first.trim();
    }

    final stderrText = stderr.toString().trim();
    if (stderrText.isNotEmpty) {
      return stderrText.split('\n').first.trim();
    }

    return null;
  }

  Future<void> _queryBasePackage(ProjectConfig project) async {
    setState(() {
      _queryingBasePackage = true;
      _baseApkLookupResult = null;
    });

    try {
      final result = await BaseApkMatcher.lookup(project);
      if (!mounted) {
        return;
      }
      setState(() {
        _queryingBasePackage = false;
        _baseApkLookupResult = result;
        _logs.insert(
          0,
          result.found
              ? '基础包匹配成功: ${result.message}'
              : '基础包匹配失败: ${result.message}',
        );
      });
      if (result.found) {
        unawaited(_refreshBasePackageInfo(project));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _queryingBasePackage = false;
        _baseApkLookupResult = BaseApkLookupResult(
          matchedFile: null,
          message: '查询失败: $error',
          searchedDirectory: project.basePackagePath,
        );
        _logs.insert(0, '基础包查询失败: $error');
      });
    }
  }

  Future<void> _runUploadPrecheck(ProjectConfig project) async {
    final enabledMarkets = project.enabledMarkets;
    final lookupResult = await BaseApkMatcher.lookup(project);
    if (!mounted) {
      return;
    }

    final issues = <String>[];
    if (enabledMarkets.isEmpty) {
      issues.add('未启用任何渠道');
    }
    if (!lookupResult.found) {
      issues.add('基础包未匹配成功');
    }
    for (final market in enabledMarkets) {
      final channel = project.channels[market];
      if (channel == null) {
        issues.add('${market.displayName} 缺少渠道配置');
        continue;
      }
      final error = MarketChannelSchemas.validateEnabledChannel(channel);
      if (error != null) {
        issues.add(error);
      }
    }

    final message = issues.isEmpty
        ? '上传前检查通过：基础包和 ${enabledMarkets.length} 个渠道已就绪'
        : '上传前检查未通过：${issues.join('，')}';

    setState(() {
      _baseApkLookupResult = lookupResult;
      _logs.insert(0, message);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startAllUploads(ProjectConfig project) async {
    final markets = project.enabledMarkets;
    if (markets.isEmpty) {
      const message = '当前项目还没有启用任何渠道，无法开始上传。';
      setState(() {
        _logs.insert(0, message);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
      return;
    }

    await _publishProjectToMarkets(project, markets);
  }

  Future<void> _startUpload(ProjectConfig project, MarketType market) async {
    await _publishProjectToMarkets(project, <MarketType>[market]);
  }

  Future<void> _publishProjectToMarkets(
    ProjectConfig project,
    List<MarketType> markets,
  ) async {
    final updateDraft = _updateDraftOf(project);
    final notes = updateDraft.releaseNotes.trim();

    setState(() {
      _logs.insert(
        0,
        '开始上传 ${markets.map((market) => market.displayName).join(' / ')}...',
      );
    });

    try {
      final result = await _publishService.publishProject(
        project: project,
        request: PublishRequest(
          markets: markets,
          releaseNotesOverride: notes.isEmpty ? null : notes,
          includeIcon: updateDraft.updateLogo,
          includeScreenshots: updateDraft.updateScreenshots,
        ),
      );
      if (!mounted) {
        return;
      }

      final summary = result.results
          .map(
            (item) =>
                '${item.market.displayName}: ${item.success ? '成功' : '失败'} - ${item.message}',
          )
          .toList();
      setState(() {
        _logs.insertAll(0, summary.reversed);
      });

      final successCount = result.results.where((item) => item.success).length;
      final message = '上传完成：$successCount/${result.results.length} 个渠道成功';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showActionError('上传失败', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProject = _selectedProject;
    final basePackageInfo = selectedProject == null
        ? null
        : _basePackageInfoOf(selectedProject);
    final updateDraft = selectedProject == null
        ? null
        : _updateDraftOf(selectedProject);
    final releaseNotesController = selectedProject == null
        ? null
        : _releaseNotesControllerOf(selectedProject);
    final basePackageText = _queryingBasePackage
        ? '查询中...'
        : _baseApkLookupResult?.message ??
              selectedProject?.basePackagePath.ifEmpty('未配置基础包目录') ??
              '未配置基础包目录';
    final basePackageColor = _queryingBasePackage
        ? theme.colorScheme.primary
        : (_baseApkLookupResult == null || _baseApkLookupResult!.found)
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.error;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFE8F6EF),
              Color(0xFFF8EFE2),
              Color(0xFFF2D9B1),
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '项目列表',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: _openCreateProject,
                                  icon: const Icon(Icons.add),
                                  label: const Text('新建项目'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '列表页仅展示简要信息；选中项目后在下方查看启用渠道和独立状态。',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            if (_projects.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFCF7),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                child: const Text('还没有已保存项目，先创建一个吧。'),
                              )
                            else
                              ..._projects.map(
                                (project) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ProjectListTile(
                                    project: project,
                                    selected: project.id == _selectedProjectId,
                                    onTap: () => _selectProject(project),
                                    onEdit: () => _openEditProject(project),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child:
                            selectedProject == null || basePackageInfo == null
                            ? const Text('请选择一个项目查看基础包信息。')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          '基础包信息',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      FilledButton.tonalIcon(
                                        onPressed: basePackageInfo.loading
                                            ? null
                                            : () => _refreshBasePackageInfo(
                                                selectedProject,
                                              ),
                                        icon: basePackageInfo.loading
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.refresh),
                                        label: const Text('刷新信息'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    basePackageInfo.message,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  _BasePackageInfoSection(
                                    packagePath: basePackageInfo.packagePath,
                                    logoBytes: basePackageInfo.logoBytes,
                                    logoName: basePackageInfo.logoName,
                                    displayName: basePackageInfo.displayName,
                                    packageName: basePackageInfo.packageName,
                                    versionCode: basePackageInfo.versionCode,
                                    versionName: basePackageInfo.versionName,
                                    pathColor: basePackageColor,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child:
                            selectedProject == null ||
                                basePackageInfo == null ||
                                updateDraft == null ||
                                releaseNotesController == null
                            ? const Text('请选择一个项目填写更新信息。')
                            : Builder(
                                builder: (context) {
                                  final packageInfo = basePackageInfo;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        '更新信息',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Logo 从基础包读取，市场图从输出目录下的 `screenshot` 文件夹读取，可在这里确认是否需要随本次更新提交。',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 16),
                                      _UpdateAssetSection(
                                        title: 'Logo',
                                        subtitle: '来源：基础包内的应用图标资源',
                                        enabled: updateDraft.updateLogo,
                                        loading: packageInfo.loading,
                                        onToggle: (value) {
                                          setState(() {
                                            updateDraft.updateLogo = value;
                                          });
                                          if (value &&
                                              packageInfo.logoBytes == null &&
                                              !packageInfo.loading) {
                                            unawaited(
                                              _refreshBasePackageInfo(
                                                selectedProject,
                                              ),
                                            );
                                          }
                                        },
                                        onRefresh: () =>
                                            _refreshBasePackageInfo(
                                              selectedProject,
                                            ),
                                        child: _LogoPreview(
                                          enabled: updateDraft.updateLogo,
                                          loading: packageInfo.loading,
                                          logoBytes: packageInfo.logoBytes,
                                          logoName: packageInfo.logoName,
                                          message: packageInfo.logoMessage,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      _UpdateAssetSection(
                                        title: '市场图',
                                        subtitle:
                                            '来源：${selectedProject.outputDirectory.ifEmpty('未配置输出目录')}${Platform.pathSeparator}screenshot',
                                        enabled: updateDraft.updateScreenshots,
                                        loading: updateDraft.loadingScreenshots,
                                        onToggle: (value) {
                                          setState(() {
                                            updateDraft.updateScreenshots =
                                                value;
                                          });
                                          if (value &&
                                              updateDraft.screenshots.isEmpty &&
                                              !updateDraft.loadingScreenshots) {
                                            unawaited(
                                              _refreshProjectScreenshots(
                                                selectedProject,
                                              ),
                                            );
                                          }
                                        },
                                        onRefresh: () =>
                                            _refreshProjectScreenshots(
                                              selectedProject,
                                            ),
                                        child: _ScreenshotListSection(
                                          enabled:
                                              updateDraft.updateScreenshots,
                                          loading:
                                              updateDraft.loadingScreenshots,
                                          message:
                                              updateDraft.screenshotMessage,
                                          screenshots: updateDraft.screenshots,
                                          onReorder: (oldIndex, newIndex) =>
                                              _reorderScreenshots(
                                                selectedProject,
                                                oldIndex,
                                                newIndex,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      TextField(
                                        controller: releaseNotesController,
                                        maxLength: 800,
                                        maxLines: 8,
                                        decoration: const InputDecoration(
                                          labelText: '更新说明',
                                          alignLabelWithHint: true,
                                          hintText: '请输入本次更新说明，最多 800 字',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: selectedProject == null
                            ? const Text('请选择一个项目查看渠道状态。')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Text(
                                        '渠道信息',
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(width: 12),
                                      Spacer(),
                                      const SizedBox(width: 12),
                                      FilledButton.tonalIcon(
                                        onPressed: _queryingBasePackage
                                            ? null
                                            : () => _queryBasePackage(
                                                selectedProject,
                                              ),
                                        icon: _queryingBasePackage
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.search),
                                        label: const Text('检查基础包'),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.tonal(
                                        onPressed: _generatingAllChannels
                                            ? null
                                            : () => _generateAllChannelPackages(
                                                selectedProject,
                                              ),
                                        child: _generatingAllChannels
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Text('全部渠道包生成'),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text('基础包：'),
                                      MiddleEllipsisText(
                                        basePackageText,
                                        startLength: 0,
                                        endLength: 120,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: basePackageColor),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (selectedProject.enabledMarkets.isEmpty)
                                    const Text('当前项目还没有启用任何渠道。')
                                  else
                                    ...selectedProject.enabledMarkets.map(
                                      (market) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _ChannelStatusTile(
                                          marketName: market.displayName,
                                          generationStatus: _generationStatusOf(
                                            selectedProject,
                                            market,
                                          ),
                                          onGenerate:
                                              _generatingAllChannels ||
                                                  _generationStatusOf(
                                                    selectedProject,
                                                    market,
                                                  ).isRunning
                                              ? null
                                              : () => _generateChannelPackage(
                                                  selectedProject,
                                                  market,
                                                ),
                                          onUpload: () => _startUpload(
                                            selectedProject,
                                            market,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: <Widget>[
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _runUploadPrecheck(selectedProject),
                                        icon: const Icon(Icons.fact_check),
                                        label: const Text('上传前检查'),
                                      ),
                                      const SizedBox(width: 12),
                                      FilledButton.icon(
                                        onPressed: () =>
                                            _startAllUploads(selectedProject),
                                        icon: const Icon(Icons.cloud_upload),
                                        label: const Text('开始上传'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '最近操作',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_logs.isEmpty)
                              const Text('暂无操作记录')
                            else
                              ..._logs
                                  .take(8)
                                  .map(
                                    (message) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Text(message),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _channelStatusKey(ProjectConfig project, MarketType market) {
    return '${project.id}:${market.id}';
  }

  _ChannelTaskStatus _generationStatusOf(
    ProjectConfig project,
    MarketType market,
  ) {
    return _channelGenerateStatuses[_channelStatusKey(project, market)] ??
        const _ChannelTaskStatus.pending('待开始');
  }

  void _setGenerationStatus(
    ProjectConfig project,
    MarketType market,
    _ChannelTaskStatus status,
  ) {
    _channelGenerateStatuses[_channelStatusKey(project, market)] = status;
  }

  String _fileName(FileSystemEntity entity) {
    if (entity.uri.pathSegments.isEmpty) {
      return entity.path;
    }
    return entity.uri.pathSegments.last;
  }
}

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({
    required this.project,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  final ProjectConfig project;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channels = project.enabledMarkets
        .map((market) => market.displayName)
        .join(' / ')
        .ifEmpty('未启用渠道');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${project.name} / ${project.packageName.ifEmpty('未设置包名')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      channels,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BasePackageInfoSection extends StatelessWidget {
  const _BasePackageInfoSection({
    required this.packagePath,
    required this.logoBytes,
    required this.logoName,
    required this.displayName,
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.pathColor,
  });

  final String packagePath;
  final Uint8List? logoBytes;
  final String? logoName;
  final String displayName;
  final String packageName;
  final String versionCode;
  final String versionName;
  final Color pathColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EEE4),
                  borderRadius: BorderRadius.circular(0),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoBytes == null
                    ? Icon(
                        Icons.android_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : Image.memory(logoBytes!, fit: BoxFit.cover),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _InfoLine(
                      label: '渠道包地址',
                      child: Text(
                        packagePath.ifEmpty('-'),
                        maxLines: 2,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: pathColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(
                      label: 'Logo',
                      value: logoName?.ifEmpty('-') ?? '-',
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(label: '名称', value: displayName.ifEmpty('-')),
                    const SizedBox(height: 8),
                    _InfoLine(label: '包名', value: packageName.ifEmpty('-')),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _InfoLine(
                            label: '版本号',
                            value: versionCode.ifEmpty('-'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _InfoLine(
                            label: '版本名',
                            value: versionName.ifEmpty('-'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            '$label：',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: child ?? Text(value ?? '-', style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _UpdateAssetSection extends StatelessWidget {
  const _UpdateAssetSection({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.loading,
    required this.onToggle,
    required this.onRefresh,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final bool loading;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                onPressed: loading ? null : onRefresh,
                tooltip: '刷新$title',
                icon: const Icon(Icons.refresh),
              ),
              Switch.adaptive(value: enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: enabled ? 1 : 0.55,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  const _LogoPreview({
    required this.enabled,
    required this.loading,
    required this.logoBytes,
    required this.logoName,
    required this.message,
  });

  final bool enabled;
  final bool loading;
  final Uint8List? logoBytes;
  final String? logoName;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AbsorbPointer(
      absorbing: !enabled,
      child: Row(
        children: <Widget>[
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFF4EEE4),
              borderRadius: BorderRadius.circular(0),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : logoBytes == null
                ? Icon(
                    Icons.image_not_supported_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : Image.memory(logoBytes!, fit: BoxFit.cover),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  logoName ?? '未读取到 Logo',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotListSection extends StatelessWidget {
  const _ScreenshotListSection({
    required this.enabled,
    required this.loading,
    required this.message,
    required this.screenshots,
    required this.onReorder,
  });

  final bool enabled;
  final bool loading;
  final String message;
  final List<File> screenshots;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (screenshots.isEmpty) {
      return Text(message, style: theme.textTheme.bodySmall);
    }

    return AbsorbPointer(
      absorbing: !enabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(message, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 136,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              itemCount: screenshots.length,
              onReorder: onReorder,
              itemBuilder: (context, index) {
                final file = screenshots[index];
                return ReorderableDragStartListener(
                  key: ValueKey(file.path),
                  index: index,
                  child: Container(
                    width: 120,
                    margin: EdgeInsets.only(
                      right: index == screenshots.length - 1 ? 0 : 10,
                    ),
                    decoration: BoxDecoration(color: Colors.white),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: <Widget>[
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0xFFF7F0E7),
                                  Color(0xFFE7DBC8),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Image.file(file, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: <Color>[
                                  Colors.black.withValues(alpha: 0.78),
                                  Colors.black.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      file.uri.pathSegments.last,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    size: 12,
                                    Icons.drag_indicator,
                                    color: enabled
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelStatusTile extends StatelessWidget {
  const _ChannelStatusTile({
    required this.marketName,
    required this.generationStatus,
    required this.onGenerate,
    required this.onUpload,
  });

  final String marketName;
  final _ChannelTaskStatus generationStatus;
  final VoidCallback? onGenerate;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  marketName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: onGenerate,
                child: generationStatus.isRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('渠道包生成'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: onUpload, child: const Text('开始上传')),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _StatusBlock(
                  label: '渠道包生成状态',
                  value: generationStatus.label,
                  color: generationStatus.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatusBlock(
                  label: '上传状态',
                  value: '待开始',
                  color: const Color(0xFF005B99),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectUpdateDraft {
  _ProjectUpdateDraft({required this.releaseNotes});

  bool updateLogo = false;
  bool updateScreenshots = false;
  bool loadingScreenshots = false;
  bool screenshotsLoaded = false;
  List<File> screenshots = <File>[];
  String screenshotMessage = '尚未读取市场图';
  String releaseNotes;
}

class _BasePackageInfoDraft {
  _BasePackageInfoDraft({required this.packagePath});

  bool loading = false;
  bool loaded = false;
  String message = '尚未读取基础包信息';
  String logoMessage = '尚未读取 Logo';
  String packagePath;
  Uint8List? logoBytes;
  String? logoName;
  String displayName = '-';
  String packageName = '-';
  String versionCode = '-';
  String versionName = '-';
}

class _ApkBadgingInfo {
  const _ApkBadgingInfo({
    required this.label,
    required this.packageName,
    required this.versionCode,
    required this.versionName,
  });

  final String label;
  final String packageName;
  final String versionCode;
  final String versionName;
}

class _LogoExtractionResult {
  const _LogoExtractionResult({
    required this.bytes,
    required this.entryName,
    required this.message,
  });

  const _LogoExtractionResult.success({
    required Uint8List bytes,
    required String entryName,
    required String message,
  }) : this(bytes: bytes, entryName: entryName, message: message);

  const _LogoExtractionResult.failure(String message)
    : this(bytes: null, entryName: null, message: message);

  final Uint8List? bytes;
  final String? entryName;
  final String message;
}

class _ChannelGenerationResult {
  const _ChannelGenerationResult({
    required this.success,
    required this.lookupResult,
    required this.logMessage,
    required this.snackBarMessage,
  });

  const _ChannelGenerationResult.success({
    required BaseApkLookupResult? lookupResult,
    required String logMessage,
    required String snackBarMessage,
  }) : this(
         success: true,
         lookupResult: lookupResult,
         logMessage: logMessage,
         snackBarMessage: snackBarMessage,
       );

  const _ChannelGenerationResult.failed({
    required BaseApkLookupResult? lookupResult,
    required String logMessage,
    required String snackBarMessage,
  }) : this(
         success: false,
         lookupResult: lookupResult,
         logMessage: logMessage,
         snackBarMessage: snackBarMessage,
       );

  final bool success;
  final BaseApkLookupResult? lookupResult;
  final String logMessage;
  final String snackBarMessage;
}

class _ChannelTaskStatus {
  const _ChannelTaskStatus._({
    required this.label,
    required this.color,
    required this.isRunning,
  });

  const _ChannelTaskStatus.pending(String label)
    : this._(label: label, color: const Color(0xFF9A6700), isRunning: false);

  const _ChannelTaskStatus.running(String label)
    : this._(label: label, color: const Color(0xFF005B99), isRunning: true);

  const _ChannelTaskStatus.success(String label)
    : this._(label: label, color: const Color(0xFF1A7F37), isRunning: false);

  const _ChannelTaskStatus.failed(String label)
    : this._(label: label, color: const Color(0xFFC62828), isRunning: false);

  final String label;
  final Color color;
  final bool isRunning;
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class DashboardPageController extends ChangeNotifier {
  VoidCallback? _importAction;
  VoidCallback? _exportAction;

  void _bind({
    required VoidCallback importConfigs,
    required VoidCallback exportConfigs,
  }) {
    _importAction = importConfigs;
    _exportAction = exportConfigs;
  }

  void _unbind() {
    _importAction = null;
    _exportAction = null;
  }

  void importConfigs() {
    _importAction?.call();
  }

  void exportConfigs() {
    _exportAction?.call();
  }
}
