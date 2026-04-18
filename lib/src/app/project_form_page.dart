import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/models/market_channel_config.dart';
import '../core/models/market_type.dart';
import '../core/models/project_config.dart';
import '../core/models/publish_request.dart';
import '../core/models/signing_config.dart';
import '../core/services/apk_publish_service.dart';
import '../core/services/project_store.dart';

class ProjectFormResult {
  const ProjectFormResult({required this.projectId, required this.messages});

  final String? projectId;
  final List<String> messages;
}

class ProjectFormPage extends StatefulWidget {
  const ProjectFormPage({super.key, this.initialProject});

  final ProjectConfig? initialProject;

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ProjectStore _store = ProjectStore();
  final ApkPublishService _service = ApkPublishService();

  late final _ProjectEditor _editor;
  final List<String> _logs = <String>[];

  bool _dryRun = true;
  bool _submitting = false;

  bool get _isEditing => widget.initialProject != null;

  @override
  void initState() {
    super.initState();
    _editor = _ProjectEditor.fromProject(
      widget.initialProject ?? ProjectConfig.empty(),
    );
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _pickApkPath() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择基础包目录');
      if (path == null || !mounted) {
        return;
      }

      setState(() {
        _editor.basePackagePath.text = path;
        _logs.insert(0, '已选择基础包目录: $path');
      });
    } catch (error) {
      _showPickerError('基础包目录', error);
    }
  }

  Future<void> _pickOutputDirectory() async {
    try {
      final path = await getDirectoryPath(confirmButtonText: '选择输出目录');
      if (path == null || !mounted) {
        return;
      }

      setState(() {
        _editor.outputDirectory.text = path;
        _logs.insert(0, '已选择输出目录: $path');
      });
    } catch (error) {
      _showPickerError('输出目录', error);
    }
  }

  Future<void> _pickKeystorePath() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(
            label: 'Keystore',
            extensions: <String>['jks', 'keystore', 'p12'],
          ),
        ],
        confirmButtonText: '选择签名文件',
      );
      if (file == null || !mounted) {
        return;
      }

      setState(() {
        _editor.keystorePath.text = file.path;
        _logs.insert(0, '已选择签名文件: ${file.path}');
      });
    } catch (error) {
      _showPickerError('签名文件', error);
    }
  }

  void _showPickerError(String target, Object error) {
    if (!mounted) {
      return;
    }

    final message = '选择$target失败: $error';
    setState(() {
      _logs.insert(0, message);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveAndClose() async {
    if (!_validateForm()) {
      return;
    }

    final draft = _editor.build(existingId: widget.initialProject?.id);
    await _store.saveProject(draft);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      ProjectFormResult(
        projectId: draft.id,
        messages: <String>['已保存项目 ${draft.name}'],
      ),
    );
  }

  Future<void> _deleteAndClose() async {
    final project = widget.initialProject;
    if (project == null) {
      return;
    }

    await _store.deleteProject(project.id);
    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      ProjectFormResult(
        projectId: null,
        messages: <String>['已删除项目 ${project.name}'],
      ),
    );
  }

  Future<void> _publishAndClose() async {
    if (!_validateForm()) {
      return;
    }

    final draft = _editor.build(existingId: widget.initialProject?.id);
    setState(() {
      _submitting = true;
      _logs.insert(0, '开始上传 ${draft.name}...');
    });

    final messages = <String>['开始上传 ${draft.name}...'];

    try {
      await _store.saveProject(draft);
      final result = await _service.publishProject(
        project: draft,
        request: PublishRequest(dryRun: _dryRun),
        onLog: (message) {
          messages.add(message);
          if (!mounted) {
            return;
          }
          setState(() {
            _logs.insert(0, message);
          });
        },
      );
      messages.add(
        result.isSuccess ? '发布完成: ${draft.name}' : '发布结束但存在失败: ${draft.name}',
      );
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pop(ProjectFormResult(projectId: draft.id, messages: messages));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _logs.insert(0, '发布失败: $error');
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败: $error')));
    }
  }

  bool _validateForm() {
    final form = _formKey.currentState;
    return form != null && form.validate();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑项目' : '新建项目'),
        backgroundColor: Colors.transparent,
        foregroundColor: theme.colorScheme.onSurface,
      ),
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
        child: Form(
          key: _formKey,
          child: ListView(
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
                              _isEditing ? '编辑项目配置' : '填写新项目配置',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Switch(
                            value: _dryRun,
                            onChanged: (value) {
                              setState(() {
                                _dryRun = value;
                              });
                            },
                          ),
                          Text(_dryRun ? 'Dry Run' : '真实上传'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '文件路径支持桌面文件选择器；保存或上传后会返回项目列表。',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: <Widget>[
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _editor.name,
                              decoration: const InputDecoration(
                                labelText: '项目名称',
                              ),
                              validator: _requiredValidator,
                            ),
                          ),
                          SizedBox(
                            width: 340,
                            child: TextFormField(
                              controller: _editor.packageName,
                              decoration: const InputDecoration(
                                labelText: '包名',
                              ),
                              validator: _requiredValidator,
                            ),
                          ),
                          SizedBox(
                            width: 560,
                            child: _PathField(
                              controller: _editor.basePackagePath,
                              label: '基础包地址 / 目录路径',
                              buttonText: '选择目录',
                              onPick: _pickApkPath,
                              validator: _requiredValidator,
                            ),
                          ),
                          SizedBox(
                            width: 560,
                            child: _PathField(
                              controller: _editor.outputDirectory,
                              label: '输出目录',
                              buttonText: '选择目录',
                              onPick: _pickOutputDirectory,
                              validator: _requiredValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '签名配置',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: <Widget>[
                          SizedBox(
                            width: 560,
                            child: _PathField(
                              controller: _editor.keystorePath,
                              label: 'Keystore 路径',
                              buttonText: '选择签名文件',
                              onPick: _pickKeystorePath,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _editor.storePassword,
                              decoration: const InputDecoration(
                                labelText: 'Store Password',
                              ),
                              obscureText: true,
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _editor.keyAlias,
                              decoration: const InputDecoration(
                                labelText: 'Key Alias',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              controller: _editor.keyPassword,
                              decoration: const InputDecoration(
                                labelText: 'Key Password',
                              ),
                              obscureText: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '渠道配置',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...MarketType.values.map((market) {
                        final marketEditor = _editor.marketEditors[market]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MarketSection(
                            market: market,
                            editor: marketEditor,
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: _submitting ? null : _saveAndClose,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存并返回'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _submitting ? null : _publishAndClose,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_upload_outlined),
                            label: Text(_dryRun ? '执行 Dry Run 并返回' : '上传并返回'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isEditing && !_submitting
                                ? _deleteAndClose
                                : null,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('删除项目'),
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
                        '当前会话日志',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_logs.isEmpty)
                        const Text('暂无日志')
                      else
                        ..._logs
                            .take(10)
                            .map(
                              (message) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
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

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项必填';
    }
    return null;
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.controller,
    required this.label,
    required this.buttonText,
    required this.onPick,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String buttonText;
  final Future<void> Function() onPick;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            validator: validator,
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton(
            onPressed: () {
              onPick();
            },
            child: Text(buttonText),
          ),
        ),
      ],
    );
  }
}

class _MarketSection extends StatelessWidget {
  const _MarketSection({required this.market, required this.editor});

  final MarketType market;
  final _MarketEditor editor;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      title: Text(market.displayName),
      subtitle: ValueListenableBuilder<bool>(
        valueListenable: editor.enabled,
        builder: (context, enabled, child) {
          return Text(enabled ? '已启用' : '未启用');
        },
      ),
      trailing: ValueListenableBuilder<bool>(
        valueListenable: editor.enabled,
        builder: (context, enabled, child) {
          return Switch(
            value: enabled,
            onChanged: (value) {
              editor.enabled.value = value;
            },
          );
        },
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              SizedBox(
                width: 420,
                child: TextFormField(
                  controller: editor.endpoint,
                  decoration: const InputDecoration(labelText: '上传接口地址'),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextFormField(
                  controller: editor.token,
                  decoration: const InputDecoration(labelText: 'Auth Token'),
                  obscureText: true,
                ),
              ),
              SizedBox(
                width: 220,
                child: TextFormField(
                  controller: editor.track,
                  decoration: const InputDecoration(labelText: '发布轨道'),
                ),
              ),
              SizedBox(
                width: 420,
                child: TextFormField(
                  controller: editor.releaseNotes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '更新说明',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextFormField(
                  controller: editor.headers,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '请求头 (每行 key=value)',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              SizedBox(
                width: 320,
                child: TextFormField(
                  controller: editor.fields,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '附加字段 (每行 key=value)',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProjectEditor {
  _ProjectEditor({
    required this.name,
    required this.packageName,
    required this.basePackagePath,
    required this.outputDirectory,
    required this.keystorePath,
    required this.storePassword,
    required this.keyAlias,
    required this.keyPassword,
    required this.marketEditors,
  });

  factory _ProjectEditor.fromProject(ProjectConfig project) {
    return _ProjectEditor(
      name: TextEditingController(text: project.name),
      packageName: TextEditingController(text: project.packageName),
      basePackagePath: TextEditingController(text: project.basePackagePath),
      outputDirectory: TextEditingController(text: project.outputDirectory),
      keystorePath: TextEditingController(text: project.signing.keystorePath),
      storePassword: TextEditingController(text: project.signing.storePassword),
      keyAlias: TextEditingController(text: project.signing.keyAlias),
      keyPassword: TextEditingController(text: project.signing.keyPassword),
      marketEditors: {
        for (final channel in project.orderedChannels)
          channel.market: _MarketEditor.fromConfig(channel),
      },
    );
  }

  final TextEditingController name;
  final TextEditingController packageName;
  final TextEditingController basePackagePath;
  final TextEditingController outputDirectory;
  final TextEditingController keystorePath;
  final TextEditingController storePassword;
  final TextEditingController keyAlias;
  final TextEditingController keyPassword;
  final Map<MarketType, _MarketEditor> marketEditors;

  ProjectConfig build({String? existingId}) {
    final trimmedName = name.text.trim().isEmpty
        ? 'new-project'
        : name.text.trim();
    return ProjectConfig.create(name: trimmedName).copyWith(
      id: existingId ?? ProjectConfig.create(name: trimmedName).id,
      name: trimmedName,
      packageName: packageName.text.trim(),
      basePackagePath: basePackagePath.text.trim(),
      outputDirectory: outputDirectory.text.trim(),
      signing: SigningConfig(
        keystorePath: keystorePath.text.trim(),
        storePassword: storePassword.text,
        keyAlias: keyAlias.text.trim(),
        keyPassword: keyPassword.text,
      ),
      channels: {
        for (final market in MarketType.values)
          market: marketEditors[market]!.build(market),
      },
    );
  }

  void dispose() {
    name.dispose();
    packageName.dispose();
    basePackagePath.dispose();
    outputDirectory.dispose();
    keystorePath.dispose();
    storePassword.dispose();
    keyAlias.dispose();
    keyPassword.dispose();
    for (final editor in marketEditors.values) {
      editor.dispose();
    }
  }
}

class _MarketEditor {
  _MarketEditor({
    required this.enabled,
    required this.endpoint,
    required this.token,
    required this.track,
    required this.releaseNotes,
    required this.headers,
    required this.fields,
  });

  factory _MarketEditor.fromConfig(MarketChannelConfig config) {
    return _MarketEditor(
      enabled: ValueNotifier<bool>(config.enabled),
      endpoint: TextEditingController(text: config.endpoint),
      token: TextEditingController(text: config.authToken),
      track: TextEditingController(text: config.track),
      releaseNotes: TextEditingController(text: config.releaseNotes),
      headers: TextEditingController(text: _mapToLines(config.headers)),
      fields: TextEditingController(text: _mapToLines(config.fields)),
    );
  }

  final ValueNotifier<bool> enabled;
  final TextEditingController endpoint;
  final TextEditingController token;
  final TextEditingController track;
  final TextEditingController releaseNotes;
  final TextEditingController headers;
  final TextEditingController fields;

  MarketChannelConfig build(MarketType market) {
    return MarketChannelConfig(
      market: market,
      enabled: enabled.value,
      endpoint: endpoint.text.trim(),
      authToken: token.text.trim(),
      track: track.text.trim().isEmpty ? 'production' : track.text.trim(),
      releaseNotes: releaseNotes.text.trim(),
      headers: _linesToMap(headers.text),
      fields: _linesToMap(fields.text),
    );
  }

  void dispose() {
    enabled.dispose();
    endpoint.dispose();
    token.dispose();
    track.dispose();
    releaseNotes.dispose();
    headers.dispose();
    fields.dispose();
  }

  static String _mapToLines(Map<String, String> values) {
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
  }

  static Map<String, String> _linesToMap(String raw) {
    final lines = raw.split('\n');
    final result = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final index = trimmed.indexOf('=');
      if (index <= 0) {
        continue;
      }
      result[trimmed.substring(0, index).trim()] = trimmed
          .substring(index + 1)
          .trim();
    }
    return result;
  }
}
