import 'dart:convert';
import 'dart:io';

import '../models/project_config.dart';
import 'app_paths.dart';

class ProjectStore {
  ProjectStore({File? storageFile})
    : _storageFile = storageFile ?? AppPaths.projectsFile();

  final File _storageFile;

  Future<List<ProjectConfig>> loadAll() async {
    return loadFromFile(_storageFile);
  }

  Future<void> saveAll(List<ProjectConfig> projects) async {
    await saveToFile(_storageFile, projects);
  }

  Future<void> saveProject(ProjectConfig project) async {
    final projects = await loadAll();
    final existingIndex = projects.indexWhere(
      (item) => item.id == project.id || item.name == project.name,
    );

    if (existingIndex >= 0) {
      projects[existingIndex] = project;
    } else {
      projects.add(project);
    }

    await saveAll(projects);
  }

  Future<void> deleteProject(String id) async {
    final projects = await loadAll();
    projects.removeWhere((project) => project.id == id);
    await saveAll(projects);
  }

  Future<List<ProjectConfig>> loadFromFile(File file) async {
    if (!await file.exists()) {
      return <ProjectConfig>[];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return <ProjectConfig>[];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return <ProjectConfig>[];
    }

    final projects = <ProjectConfig>[];
    for (final item in decoded.whereType<Map>()) {
      final normalized = item.map(
        (dynamic key, dynamic value) => MapEntry(key.toString(), value),
      );
      projects.add(ProjectConfig.fromJson(normalized));
    }
    return projects;
  }

  Future<void> saveToFile(File file, List<ProjectConfig> projects) async {
    await file.parent.create(recursive: true);
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(projects.map((project) => project.toConfigJson()).toList());
    await file.writeAsString('$content\n');
  }
}
