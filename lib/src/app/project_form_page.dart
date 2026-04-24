import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/material.dart';

import '../core/models/market_channel_config.dart';
import '../core/models/market_type.dart';
import '../core/models/project_config.dart';
import '../core/models/publish_request.dart';
import '../core/models/signing_config.dart';
import '../core/services/apk_publish_service.dart';
import '../core/services/market_channel_schema.dart';
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
    final isFormValid = form != null && form.validate();
    if (!isFormValid) {
      return false;
    }

    final marketError = _editor.validateEnabledMarket();
    if (marketError == null) {
      return true;
    }

    setState(() {
      _logs.insert(0, marketError);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(marketError)));
    return false;
  }

  void _handleMarketToggle(MarketType market, bool value) {
    final editor = _editor.marketEditors[market]!;
    if (!value) {
      setState(() {
        editor.enabled.value = false;
      });
      return;
    }

    final error = _editor.validateMarket(market, enabledOverride: true);
    if (error != null) {
      setState(() {
        _logs.insert(0, error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() {
      editor.enabled.value = true;
    });
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
                        '参考原项目配置页，仅保留项目与渠道的必要参数；其余历史字段继续兼容但不在这里编辑。',
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
                                labelText: 'App 名称',
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
                              label: 'APK 目录',
                              buttonText: '选择目录',
                              onPick: _pickApkPath,
                              validator: _requiredValidator,
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
                            onToggle: (value) =>
                                _handleMarketToggle(market, value),
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

class _MarketSection extends StatefulWidget {
  const _MarketSection({
    required this.market,
    required this.editor,
    required this.onToggle,
  });

  final MarketType market;
  final _MarketEditor editor;
  final ValueChanged<bool> onToggle;

  @override
  State<_MarketSection> createState() => _MarketSectionState();
}

class _MarketSectionState extends State<_MarketSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schema = MarketChannelSchemas.schemaOf(widget.market);
    final missingLabels = _missingFieldLabels(schema);
    final isComplete = missingLabels.isEmpty;

    return ValueListenableBuilder<bool>(
      valueListenable: widget.editor.enabled,
      builder: (context, enabled, child) {
        final cardColor = !isComplete
            ? const Color(0xFFF1F3F5)
            : enabled
            ? const Color(0xFFEAF7EA)
            : Colors.white;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: enabled
                  ? const Color(0xFFB8D8B8)
                  : _expanded
                  ? theme.colorScheme.outline
                  : theme.colorScheme.outlineVariant,
              width: _expanded ? 1.6 : 1,
            ),
            color: cardColor,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ExpansionTile(
              onExpansionChanged: (value) {
                setState(() {
                  _expanded = value;
                });
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                widget.market.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  isComplete ? '配置完成' : '参数不全',
                  style: TextStyle(
                    fontSize: 12,
                    color: isComplete
                        ? theme.colorScheme.primary
                        : Colors.redAccent.shade100,
                  ),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _expanded ? '收起' : '展开配置',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  const SizedBox(width: 8),
                  Switch(
                    value: enabled,
                    onChanged: widget.onToggle,
                    activeTrackColor: const Color(0xFFCFEBCF),
                    activeThumbColor: const Color(0xFF8FBC8F),
                    inactiveTrackColor: const Color(0xFFD7DCE0),
                    inactiveThumbColor: Colors.white,
                  ),
                ],
              ),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: <Widget>[
                      if (schema.summary.isNotEmpty)
                        SizedBox(
                          width: 960,
                          child: Text(
                            schema.summary,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ...schema.requiredFields.map(
                        (definition) => SizedBox(
                          width: definition.width,
                          child: TextFormField(
                            controller:
                                widget.editor.requiredFields[definition.key],
                            minLines: definition.multiline ? 3 : 1,
                            maxLines: definition.multiline ? 5 : 1,
                            obscureText: definition.obscureText,
                            decoration: InputDecoration(
                              labelText:
                                  '${definition.label} (${definition.key})',
                              alignLabelWithHint: definition.multiline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<String> _missingFieldLabels(MarketChannelSchema schema) {
    final missing = <String>[];
    for (final definition in schema.requiredFields) {
      final value =
          widget.editor.requiredFields[definition.key]?.text.trim() ?? '';
      if (value.isEmpty) {
        missing.add(definition.label);
      }
    }
    return missing;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: Colors.white.withValues(alpha: 0.72),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
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
          channel.market: _MarketEditor.fromConfig(channel.market, channel),
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
    final resolvedBasePath = basePackagePath.text.trim();
    final resolvedOutputDirectory = outputDirectory.text.trim().isEmpty
        ? resolvedBasePath
        : outputDirectory.text.trim();
    return ProjectConfig.create(name: trimmedName).copyWith(
      id: existingId ?? ProjectConfig.create(name: trimmedName).id,
      name: trimmedName,
      packageName: packageName.text.trim(),
      basePackagePath: resolvedBasePath,
      outputDirectory: resolvedOutputDirectory,
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

  String? validateEnabledMarket() {
    for (final market in MarketType.values) {
      final error = validateMarket(market);
      if (error != null) {
        return error;
      }
    }
    return null;
  }

  String? validateMarket(MarketType market, {bool? enabledOverride}) {
    final editor = marketEditors[market];
    final isEnabled = enabledOverride ?? editor?.enabled.value ?? false;
    if (editor == null || !isEnabled) {
      return null;
    }
    return editor.validationError(market, enabledOverride: isEnabled);
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
    required this.requiredFields,
  });

  factory _MarketEditor.fromConfig(
    MarketType market,
    MarketChannelConfig config,
  ) {
    final schema = MarketChannelSchemas.schemaOf(market);
    return _MarketEditor(
      enabled: ValueNotifier<bool>(config.enabled),
      endpoint: TextEditingController(text: config.endpoint),
      token: TextEditingController(text: config.authToken),
      track: TextEditingController(text: config.track),
      releaseNotes: TextEditingController(text: config.releaseNotes),
      headers: TextEditingController(text: _mapToLines(config.headers)),
      fields: TextEditingController(
        text: _mapToLines(
          MarketChannelSchemas.stripKnownFields(market, config.fields),
        ),
      ),
      requiredFields: {
        for (final definition in schema.requiredFields)
          definition.key: TextEditingController(
            text:
                MarketChannelSchemas.readField(config.fields, definition) ?? '',
          ),
      },
    );
  }

  final ValueNotifier<bool> enabled;
  final TextEditingController endpoint;
  final TextEditingController token;
  final TextEditingController track;
  final TextEditingController releaseNotes;
  final TextEditingController headers;
  final TextEditingController fields;
  final Map<String, TextEditingController> requiredFields;

  MarketChannelConfig build(MarketType market) {
    final mergedFields = _linesToMap(fields.text);
    for (final entry in requiredFields.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        mergedFields[entry.key] = value;
      }
    }
    return MarketChannelConfig(
      market: market,
      enabled: enabled.value,
      endpoint: endpoint.text.trim(),
      authToken: token.text.trim(),
      track: track.text.trim().isEmpty ? 'production' : track.text.trim(),
      releaseNotes: releaseNotes.text.trim(),
      headers: _linesToMap(headers.text),
      fields: mergedFields,
    );
  }

  String? validationError(MarketType market, {bool? enabledOverride}) {
    final channel = build(market).copyWith(enabled: enabledOverride);
    return MarketChannelSchemas.validateEnabledChannel(channel);
  }

  void dispose() {
    enabled.dispose();
    endpoint.dispose();
    token.dispose();
    track.dispose();
    releaseNotes.dispose();
    headers.dispose();
    fields.dispose();
    for (final controller in requiredFields.values) {
      controller.dispose();
    }
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
