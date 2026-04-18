import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/models/project_config.dart';
import '../core/services/project_store.dart';
import 'project_form_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.controller});

  final DashboardPageController? controller;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final ProjectStore _store = ProjectStore();
  final List<ProjectConfig> _projects = <ProjectConfig>[];
  final List<String> _logs = <String>[];

  bool _loading = true;
  String? _selectedProjectId;

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
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProject = _selectedProject;

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
                                    onTap: () {
                                      setState(() {
                                        _selectedProjectId = project.id;
                                      });
                                    },
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
                        child: selectedProject == null
                            ? const Text('请选择一个项目查看渠道状态。')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '已启用渠道',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (selectedProject.enabledMarkets.isEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFFCF7),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: const Text('当前项目还没有启用任何渠道。'),
                                    )
                                  else
                                    ...selectedProject.enabledMarkets.map(
                                      (market) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _ChannelStatusTile(
                                          marketName: market.displayName,
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

class _ChannelStatusTile extends StatelessWidget {
  const _ChannelStatusTile({required this.marketName});

  final String marketName;

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
      child: Row(
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
          Expanded(
            child: _StatusBlock(
              label: '渠道包生成状态',
              value: '待开始',
              color: const Color(0xFF9A6700),
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
    );
  }
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
