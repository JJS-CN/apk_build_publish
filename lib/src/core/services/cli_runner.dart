import 'dart:convert';
import 'dart:io';

import '../models/market_channel_config.dart';
import '../models/market_type.dart';
import '../models/project_config.dart';
import '../models/publish_request.dart';
import '../models/signing_config.dart';
import 'apk_publish_service.dart';
import 'project_store.dart';

Future<int> runCli(List<String> args) async {
  final store = ProjectStore();
  final service = ApkPublishService();

  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    _printUsage();
    return 0;
  }

  final command = args.first;
  final parsed = _ParsedArgs(args.sublist(1));

  try {
    switch (command) {
      case 'project-list':
        return _projectList(store);
      case 'project-show':
        return _projectShow(store, parsed);
      case 'project-init':
        return _projectInit(store, parsed);
      case 'project-set-market':
        return _projectSetMarket(store, parsed);
      case 'project-delete':
        return _projectDelete(store, parsed);
      case 'publish':
        return _publish(store, service, parsed);
      default:
        stderr.writeln('Unknown command: $command');
        _printUsage();
        return 64;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    return 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    return 65;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path ?? ''}');
    return 66;
  }
}

Future<int> _projectList(ProjectStore store) async {
  final projects = await store.loadAll();
  if (projects.isEmpty) {
    stdout.writeln('No saved projects. Use project-init first.');
    return 0;
  }

  for (final project in projects) {
    final enabledMarkets = project.enabledMarkets
        .map((item) => item.id)
        .join(', ');
    stdout.writeln(
      '- ${project.name} (${project.id}) | package: ${project.packageName.isEmpty ? '-' : project.packageName} | base-dir: ${project.basePackagePath.isEmpty ? '-' : project.basePackagePath} | markets: ${enabledMarkets.isEmpty ? '-' : enabledMarkets}',
    );
  }
  return 0;
}

Future<int> _projectShow(ProjectStore store, _ParsedArgs parsed) async {
  final project = await _findProject(store, parsed.singleValue('project'));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(project.toJson()));
  return 0;
}

Future<int> _projectInit(ProjectStore store, _ParsedArgs parsed) async {
  final name = parsed.singleValue('name');
  final packageName = parsed.singleValue('package-name');
  final basePackage = parsed.singleValue('base-package');
  final outputDir = parsed.singleValue('output-dir');

  final existing = await _findProjectOrNull(store, name);
  final project = (existing ?? ProjectConfig.create(name: name)).copyWith(
    id: existing?.id ?? ProjectConfig.create(name: name).id,
    name: name,
    packageName: packageName,
    basePackagePath: basePackage,
    outputDirectory: outputDir,
    signing: SigningConfig(
      keystorePath:
          parsed.optionalValue('keystore') ??
          existing?.signing.keystorePath ??
          '',
      storePassword:
          parsed.optionalValue('store-password') ??
          existing?.signing.storePassword ??
          '',
      keyAlias:
          parsed.optionalValue('key-alias') ?? existing?.signing.keyAlias ?? '',
      keyPassword:
          parsed.optionalValue('key-password') ??
          existing?.signing.keyPassword ??
          '',
    ),
    channels: existing?.channels ?? ProjectConfig.defaultChannels(),
  );

  await store.saveProject(project);
  stdout.writeln('Saved project ${project.name}.');
  return 0;
}

Future<int> _projectSetMarket(ProjectStore store, _ParsedArgs parsed) async {
  final project = await _findProject(store, parsed.singleValue('project'));
  final market = _parseMarket(parsed.singleValue('market'));
  final current =
      project.channels[market] ?? MarketChannelConfig(market: market);

  final next = current.copyWith(
    enabled: parsed.optionalBool('enabled') ?? current.enabled,
    endpoint: parsed.optionalValue('endpoint') ?? current.endpoint,
    authToken: parsed.optionalValue('token') ?? current.authToken,
    track: parsed.optionalValue('track') ?? current.track,
    releaseNotes: parsed.optionalValue('notes') ?? current.releaseNotes,
    headers: parsed.values('header').isEmpty
        ? current.headers
        : _parseKeyValuePairs(parsed.values('header'), label: 'header'),
    fields: parsed.values('field').isEmpty
        ? current.fields
        : _parseKeyValuePairs(parsed.values('field'), label: 'field'),
  );

  final updatedChannels = Map<MarketType, MarketChannelConfig>.from(
    project.channels,
  )..[market] = next;

  await store.saveProject(project.copyWith(channels: updatedChannels));
  stdout.writeln('Updated ${market.displayName} for ${project.name}.');
  return 0;
}

Future<int> _projectDelete(ProjectStore store, _ParsedArgs parsed) async {
  final project = await _findProject(store, parsed.singleValue('project'));
  await store.deleteProject(project.id);
  stdout.writeln('Deleted project ${project.name}.');
  return 0;
}

Future<int> _publish(
  ProjectStore store,
  ApkPublishService service,
  _ParsedArgs parsed,
) async {
  final project = await _findProject(store, parsed.singleValue('project'));
  final marketArg = parsed.optionalValue('markets');
  final markets = marketArg
      ?.split(',')
      .where((item) => item.trim().isNotEmpty)
      .map(_parseMarket)
      .toList();

  final result = await service.publishProject(
    project: project,
    request: PublishRequest(
      apkPath: parsed.optionalValue('apk'),
      markets: markets,
      dryRun: parsed.flag('dry-run'),
      releaseNotesOverride: parsed.optionalValue('notes'),
    ),
    onLog: stdout.writeln,
  );

  stdout.writeln(
    'Finished ${result.isSuccess ? 'successfully' : 'with failures'} for ${project.name}.',
  );
  return result.isSuccess ? 0 : 1;
}

Future<ProjectConfig> _findProject(ProjectStore store, String lookup) async {
  final project = await _findProjectOrNull(store, lookup);
  if (project == null) {
    throw StateError('Project not found: $lookup');
  }
  return project;
}

Future<ProjectConfig?> _findProjectOrNull(
  ProjectStore store,
  String lookup,
) async {
  final projects = await store.loadAll();
  for (final project in projects) {
    if (project.id == lookup || project.name == lookup) {
      return project;
    }
  }
  return null;
}

MarketType _parseMarket(String raw) {
  final market = MarketType.tryParse(raw);
  if (market == null) {
    throw FormatException('Unknown market: $raw');
  }
  return market;
}

Map<String, String> _parseKeyValuePairs(
  List<String> values, {
  required String label,
}) {
  final result = <String, String>{};
  for (final item in values) {
    final separatorIndex = item.indexOf('=');
    if (separatorIndex <= 0) {
      throw FormatException('Invalid $label: $item, expected key=value');
    }
    final key = item.substring(0, separatorIndex).trim();
    final value = item.substring(separatorIndex + 1).trim();
    result[key] = value;
  }
  return result;
}

void _printUsage() {
  stdout.writeln('''
Flutter APK multi-market publisher

Commands:
  project-list
  project-show --project demo
  project-init --name demo --package-name com.example.demo --base-package build/apk-dir --output-dir build/outputs [--keystore path --store-password xxx --key-alias alias --key-password xxx]
  project-set-market --project demo --market huawei [--enabled true] [--endpoint https://upload.example.com] [--token secret] [--track production] [--notes text] [--header K=V] [--field K=V]
  project-delete --project demo
  publish --project demo [--apk build/app.apk] [--markets huawei,xiaomi] [--dry-run] [--notes text]
''');
}

class _ParsedArgs {
  _ParsedArgs(List<String> args) {
    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      if (!argument.startsWith('--')) {
        throw FormatException('Unexpected argument: $argument');
      }

      final key = argument.substring(2);
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        _values.putIfAbsent(key, () => <String>[]).add('true');
        continue;
      }

      _values.putIfAbsent(key, () => <String>[]).add(args[index + 1]);
      index += 1;
    }
  }

  final Map<String, List<String>> _values = <String, List<String>>{};

  bool flag(String key) => (_values[key]?.last ?? 'false') == 'true';

  String singleValue(String key) {
    final value = optionalValue(key);
    if (value == null || value.isEmpty) {
      throw FormatException('Missing --$key');
    }
    return value;
  }

  String? optionalValue(String key) => _values[key]?.last;

  bool? optionalBool(String key) {
    final raw = optionalValue(key);
    if (raw == null) {
      return null;
    }
    if (raw == 'true') {
      return true;
    }
    if (raw == 'false') {
      return false;
    }
    throw FormatException('Invalid bool for --$key: $raw');
  }

  List<String> values(String key) => _values[key] ?? const <String>[];
}
