import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:pub_semver/pub_semver.dart';

import 'file_updater.dart';

void main(List<String> arguments) async {
  exitCode = 0;
  final runner = CommandRunner('pub-helper', 'A pub helper for dependabot')
    ..addCommand(VersionParserCommand())
    ..addCommand(RequirementCheckerCommand())
    ..addCommand(RequirementUpdaterCommand())
    ..addCommand(FileUpdaterCommand());
  if (arguments.isEmpty) {
    final inputLine =
        stdin.readLineSync(encoding: Encoding.getByName('utf-8')!);
    final input = jsonDecode(inputLine!);
    final result = await runner.run([
      pick(input, 'function').asStringOrThrow(),
      ...pick(input, 'args').asListOrThrow((pick) => pick.asStringOrThrow()),
    ]);
    stdout.write(jsonEncode({'result': result}));
  } else {
    final result = await runner.run(arguments);
    print(result);
  }
}

class VersionParserCommand extends Command {
  VersionParserCommand() {
    argParser.addOption('version');
  }

  @override
  String name = 'version_parser';

  @override
  String description = 'Parses dart version requirements.';

  @override
  String? run() {
    final version = argResults?['version'];
    if (version == null) {
      stderr.writeln('error: --version must be set');
      exitCode = 2;
      return null;
    }
    try {
      final range = VersionConstraint.parse(version);
      if (range.isAny) return '*';
      if (range.isEmpty) return null;
      if (range is! VersionRange) {
        stderr.writeln('error: internal version parsing error');
        exitCode = 2;
        return null;
      }
      final minOp = range.includeMin ? '>=' : '>';
      final maxOp = range.includeMax ? '<=' : '<';
      final restrictions = '$minOp ${range.min} and $maxOp ${range.max}';
      return restrictions;
    } on FormatException catch (e) {
      stderr.writeln('error: version has invalid format');
      stderr.writeln(e.message);
      exitCode = 2;
      return null;
    }
  }
}

class RequirementCheckerCommand extends Command {
  RequirementCheckerCommand() {
    argParser.addOption('requirement');
    argParser.addOption('version');
  }

  @override
  String name = 'requirement_checker';

  @override
  String description =
      'Checks if a Dart version is allowed by a version constraint.';

  @override
  bool? run() {
    final requirement = argResults?['requirement'];
    final version = argResults?['version'];
    if (requirement == null || version == null) {
      stderr.writeln('error: --requirement and --version must be set');
      exitCode = 2;
      return null;
    }
    try {
      final constraint = VersionConstraint.parse(requirement);
      return constraint.allows(Version.parse(version));
    } on FormatException catch (e) {
      stderr.writeln('error: version has invalid format');
      stderr.writeln(e.message);
      exitCode = 2;
      return null;
    }
  }
}

class RequirementUpdaterCommand extends Command {
  RequirementUpdaterCommand() {
    argParser.addOption('requirement');
    argParser.addOption('latest-version');
    argParser.addOption(
      'strategy',
      allowed: ['bump_versions', 'widen_ranges'],
    );
  }

  @override
  String name = 'requirement_updater';

  @override
  String description =
      'Updates a version constraint with the given latest version';

  @override
  String? run() {
    final requirement = argResults?['requirement'];
    final latestVersion = argResults?['latest-version'];
    final strategy = argResults?['strategy'];
    if (requirement == null || latestVersion == null || strategy == null) {
      stderr.writeln(
        'error: --requirement, --latest-version, and --strategy must be set',
      );
      exitCode = 2;
      return null;
    }
    final UpdateStrategy updateStrategy;
    switch (strategy) {
      case 'bump_versions':
        updateStrategy = UpdateStrategy.bumpVersions;
        break;
      case 'widen_ranges':
        updateStrategy = UpdateStrategy.widenRanges;
        break;
      default:
        throw UnimplementedError('--strategy $strategy is not handled');
    }
    try {
      final constraint = VersionConstraint.parse(requirement);
      return constraint
          .updateWith(
            Version.parse(latestVersion),
            strategy: updateStrategy,
          )
          .toString();
    } on FormatException catch (e) {
      stderr.writeln('error: version has invalid format');
      stderr.writeln(e.message);
      exitCode = 2;
      return null;
    }
  }
}

class FileUpdaterCommand extends Command {
  FileUpdaterCommand() {
    argParser.addOption(
      'type',
      allowed: ['yaml', 'lock'],
    );
    argParser.addOption('content');
    argParser.addOption('dependency');
    argParser.addOption('version');
    argParser.addOption('requirement');
  }

  @override
  String name = 'file_updater';

  @override
  String description = 'Updates a given pubspec file with the requirement';

  @override
  String? run() {
    final type = argResults?['type'];
    final content = argResults?['content'];
    final dependency = argResults?['dependency'];
    final version = argResults?['version'];
    final stringRequirement = argResults?['requirement'];
    if (content == null ||
        stringRequirement == null ||
        version == null ||
        type == null) {
      stderr.writeln(
        'error: --type, --content, --dependency, --version, and --requirement must be set',
      );
      exitCode = 2;
      return null;
    }
    final requirement = Requirement.fromMap(jsonDecode(stringRequirement));
    switch (type) {
      case 'yaml':
        return updatePubspecYamlFile(
          content,
          dependency,
          version,
          requirement,
        );
      case 'lock':
        return updatePubspecLockFile(
          content,
          dependency,
          version,
          requirement,
        );
      default:
        throw UnimplementedError('--type $type is not handled');
    }
  }
}
