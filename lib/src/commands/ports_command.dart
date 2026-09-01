import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:io/ansi.dart';
import 'package:io/io.dart';
import '../api/acr_client.dart';

class ServicePortDef {
  final String id;
  final String name;
  final String envVar;
  final int defaultPort;
  final String healthPath;
  final String protocol;

  const ServicePortDef({
    required this.id,
    required this.name,
    required this.envVar,
    required this.defaultPort,
    required this.healthPath,
    this.protocol = 'http',
  });
}

const List<ServicePortDef> defaultServices = [
  ServicePortDef(
    id: 'acr-core',
    name: 'ACR Core Daemon',
    envVar: 'ACR_CORE_PORT',
    defaultPort: 20443,
    healthPath: '/health',
  ),
  ServicePortDef(
    id: 'acr-meta-mcp',
    name: 'Meta-MCP Forward Proxy',
    envVar: 'ACR_META_MCP_PORT',
    defaultPort: 20445,
    healthPath: '/health',
  ),
  ServicePortDef(
    id: 'acr-bridge',
    name: 'ACR MCP Bridge',
    envVar: 'ACR_BRIDGE_PORT',
    defaultPort: 20444,
    healthPath: '/health',
  ),
  ServicePortDef(
    id: 'nats-jetstream',
    name: 'Internal NATS Broker',
    envVar: 'ACR_NATS_PORT',
    defaultPort: 4222,
    healthPath: '',
    protocol: 'tcp',
  ),
  ServicePortDef(
    id: 'gitea',
    name: 'Local Ecosystem Gitea',
    envVar: 'ACR_GITEA_PORT',
    defaultPort: 3300,
    healthPath: '/api/v1/version',
  ),
];

File _getConfigFile() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  final acrDir = Directory('$home/.acr');
  if (!acrDir.existsSync()) {
    acrDir.createSync(recursive: true);
  }
  return File('$home/.acr/ports.json');
}

Map<String, int> _loadPortOverrides() {
  final file = _getConfigFile();
  if (!file.existsSync()) return {};
  try {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final ports = (data['ports'] as Map<String, dynamic>?) ?? {};
    return ports.map((k, v) => MapEntry(k, (v as num).toInt()));
  } catch (_) {
    return {};
  }
}

void _savePortOverrides(Map<String, int> overrides) {
  final file = _getConfigFile();
  final data = {
    'version': '1.0.0',
    'updatedAt': DateTime.now().toIso8601String(),
    'ports': overrides,
  };
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
}

int _resolvePort(ServicePortDef def, Map<String, int> overrides) {
  final envVal = Platform.environment[def.envVar];
  if (envVal != null && int.tryParse(envVal) != null) {
    return int.parse(envVal);
  }
  return overrides[def.id] ?? def.defaultPort;
}

class PortsCommand extends Command<int> {
  @override
  final String name = 'ports';

  @override
  final String description = 'Inspect, configure, test, and export ecosystem service port mappings.';

  final AcrClient client;

  PortsCommand({required this.client}) {
    addSubcommand(PortsListCommand());
    addSubcommand(PortsSetCommand());
    addSubcommand(PortsResetCommand());
    addSubcommand(PortsTestCommand());
    addSubcommand(PortsExportCommand());
  }

  @override
  Future<int> run() async {
    printUsage();
    return ExitCode.success.code;
  }
}

class PortsListCommand extends Command<int> {
  @override
  final String name = 'list';

  @override
  final String description = 'List all ecosystem service port bindings and live status.';

  @override
  Future<int> run() async {
    final overrides = _loadPortOverrides();

    stdout.writeln('\n${cyan.wrap('======================================================================')}');
    stdout.writeln(bold.wrap(' ACR ECOSYSTEM SERVICE PORT MAPPINGS'));
    stdout.writeln('${cyan.wrap('======================================================================')}');

    for (final s in defaultServices) {
      final port = _resolvePort(s, overrides);
      final isCustom = port != s.defaultPort;
      final badge = isCustom ? yellow.wrap('[CUSTOM]') : green.wrap('[DEFAULT]');
      final envVarStr = darkGray.wrap('(\$${s.envVar})');
      final portStr = bold.wrap(':$port'.padRight(8));

      stdout.writeln('  $badge ${s.name.padRight(24)} -> $portStr $envVarStr');
    }

    final cfgFile = _getConfigFile().path;
    stdout.writeln('\nConfig file: $cfgFile\n');
    return ExitCode.success.code;
  }
}

class PortsSetCommand extends Command<int> {
  @override
  final String name = 'set';

  @override
  final String description = 'Set a custom port binding for a service.';

  PortsSetCommand() {
    argParser.addOption('service', abbr: 's', help: 'Service ID (acr-core, acr-meta-mcp, acr-bridge, nats-jetstream, gitea)');
    argParser.addOption('port', abbr: 'p', help: 'Port number (1024-65535)');
  }

  @override
  Future<int> run() async {
    final serviceId = argResults?['service'] as String? ?? (argResults?.rest.isNotEmpty == true ? argResults!.rest[0] : null);
    final portStr = argResults?['port'] as String? ?? (argResults?.rest.length ?? 0 > 1 ? argResults!.rest[1] : null);

    if (serviceId == null || portStr == null) {
      stderr.writeln(yellow.wrap('Usage: acr ports set <service-id> <port>'));
      stderr.writeln('Available services: ${defaultServices.map((s) => s.id).join(', ')}');
      return ExitCode.usage.code;
    }

    final port = int.tryParse(portStr);
    if (port == null || port < 1024 || port > 65535) {
      stderr.writeln(red.wrap('[ERROR] Port must be an integer between 1024 and 65535.'));
      return ExitCode.usage.code;
    }

    final valid = defaultServices.any((s) => s.id == serviceId);
    if (!valid) {
      stderr.writeln(red.wrap('[ERROR] Unknown service "$serviceId". Valid: ${defaultServices.map((s) => s.id).join(', ')}'));
      return ExitCode.usage.code;
    }

    final overrides = _loadPortOverrides();
    overrides[serviceId] = port;
    _savePortOverrides(overrides);

    stdout.writeln(green.wrap('[SUCCESS] Set port for "$serviceId" to :$port in ~/.acr/ports.json'));
    return ExitCode.success.code;
  }
}

class PortsResetCommand extends Command<int> {
  @override
  final String name = 'reset';

  @override
  final String description = 'Reset service port mappings to factory defaults.';

  @override
  Future<int> run() async {
    final serviceId = argResults?.rest.isNotEmpty == true ? argResults!.rest[0] : null;
    final file = _getConfigFile();

    if (serviceId != null) {
      final overrides = _loadPortOverrides();
      overrides.remove(serviceId);
      _savePortOverrides(overrides);
      stdout.writeln(green.wrap('[SUCCESS] Reset port for "$serviceId" to factory default.'));
    } else {
      if (file.existsSync()) {
        file.deleteSync();
      }
      stdout.writeln(green.wrap('[SUCCESS] All service ports reset to factory defaults.'));
    }
    return ExitCode.success.code;
  }
}

class PortsTestCommand extends Command<int> {
  @override
  final String name = 'test';

  @override
  final String description = 'Perform live connectivity health checks against configured ports.';

  @override
  Future<int> run() async {
    final overrides = _loadPortOverrides();

    stdout.writeln('\n${cyan.wrap('======================================================================')}');
    stdout.writeln(bold.wrap(' TESTING SERVICE PORT CONNECTIVITY'));
    stdout.writeln('${cyan.wrap('======================================================================')}');

    for (final s in defaultServices) {
      final port = _resolvePort(s, overrides);
      if (s.healthPath.isEmpty) {
        stdout.writeln('  ${green.wrap('[ONLINE]')} ${s.name.padRight(24)} :$port (TCP socket assume reachable)');
        continue;
      }

      final url = 'http://localhost:$port${s.healthPath}';
      try {
        final stopwatch = Stopwatch()..start();
        final res = await http.get(Uri.parse(url)).timeout(const Duration(milliseconds: 1500));
        stopwatch.stop();
        final ms = stopwatch.elapsedMilliseconds;

        if (res.statusCode < 500) {
          stdout.writeln('  ${green.wrap('[ONLINE]')} ${s.name.padRight(24)} :$port ${darkGray.wrap('(${ms}ms)')}');
        } else {
          stdout.writeln('  ${yellow.wrap('[WARN]  ')} ${s.name.padRight(24)} :$port (HTTP ${res.statusCode})');
        }
      } catch (_) {
        stdout.writeln('  ${red.wrap('[OFFLINE]')} ${s.name.padRight(24)} :$port ${darkGray.wrap('(unreachable)')}');
      }
    }
    stdout.writeln('');
    return ExitCode.success.code;
  }
}

class PortsExportCommand extends Command<int> {
  @override
  final String name = 'export';

  @override
  final String description = 'Export current port bindings as .env or JSON format.';

  PortsExportCommand() {
    argParser.addFlag('env', help: 'Output as .env file format', defaultsTo: true);
    argParser.addFlag('json', help: 'Output as JSON format', defaultsTo: false);
  }

  @override
  Future<int> run() async {
    final overrides = _loadPortOverrides();
    final asJson = argResults?['json'] as bool? ?? false;

    if (asJson) {
      final map = <String, int>{};
      for (final s in defaultServices) {
        map[s.id] = _resolvePort(s, overrides);
      }
      stdout.writeln(const JsonEncoder.withIndent('  ').convert({'version': '1.0.0', 'ports': map}));
    } else {
      stdout.writeln('# ACR Ecosystem Port Configuration');
      for (final s in defaultServices) {
        stdout.writeln('${s.envVar}=${_resolvePort(s, overrides)}');
      }
      stdout.writeln('ACR_DAEMON_URL=http://localhost:${_resolvePort(defaultServices[0], overrides)}');
      stdout.writeln('ACR_META_MCP_URL=http://localhost:${_resolvePort(defaultServices[1], overrides)}');
    }
    return ExitCode.success.code;
  }
}
