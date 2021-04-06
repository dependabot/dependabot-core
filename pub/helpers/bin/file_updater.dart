import 'package:deep_pick/deep_pick.dart';
import 'package:yaml_edit/yaml_edit.dart';
import 'package:yaml/yaml.dart';

/// The subset of strings that don't need quoting in YAML.
///
/// This pattern does not strictly follow the plain scalar grammar of YAML,
/// which means some strings may be unnecessarily quoted, but it's much simpler.
final _unquotableYamlString = RegExp(r'^[a-zA-Z_-][a-zA-Z_0-9-]*$');

enum SourceType {
  hosted,
  git,
  path,
}

class Requirement {
  Requirement.fromMap(data)
      : requirement = pick(data, 'requirement').asStringOrThrow(),
        file = pick(data, 'file').asStringOrThrow(),
        groups = pick(data, 'groups')
            .asListOrEmpty((pick) => pick.asStringOrThrow()),
        source = pick(data, 'source')
            .letOrThrow((pick) => Source.fromMap(pick.asMapOrThrow()));

  final String requirement;
  final String file;
  final List<String> groups;
  final Source source;
}

class Source {
  Source.fromMap(data)
      : type = pick(data, 'type').letOrThrow((pick) {
          final type = pick.asStringOrThrow();
          switch (type) {
            case 'hosted':
              return SourceType.hosted;
            case 'git':
              return SourceType.git;
            case 'path':
              return SourceType.path;
            default:
              throw PickException('Unsupported source type: $type');
          }
        }),
        url = pick(data, 'url').asStringOrNull(),
        path = pick(data, 'path').asStringOrNull(),
        ref = pick(data, 'ref').asStringOrNull(),
        resolvedRef = pick(data, 'resolved_ref').asStringOrNull(),
        relative = pick(data, 'relative').asStringOrNull();

  final SourceType type;
  final String? url;
  final String? path;
  final String? ref;
  final String? resolvedRef;
  final String? relative;
}

String updatePubspecYamlFile(
  String content,
  String dependency,
  String version,
  Requirement requirement,
) {
  final editor = YamlEditor(content);
  switch (requirement.source.type) {
    case SourceType.hosted:
      editor.update(
        [requirement.groups[0], dependency],
        requirement.requirement.contains(' ')
            ? _stringify(requirement.requirement)
            : requirement.requirement,
      );
      break;
    case SourceType.git:
      // Only update pubspec.yaml file if we are able to do so.
      final oldRequirement =
          editor.parseAt([requirement.groups[0], dependency]);
      if (oldRequirement is! YamlMap) return content;
      if (!oldRequirement.containsKey('git')) return content;
      final git = oldRequirement['git'];
      if (git is! YamlMap) return content;

      editor.update(
        [requirement.groups[0], dependency, 'git', 'ref'],
        requirement.source.ref,
      );
      break;
    case SourceType.path:
      // Can't update pubspec files for path dependencies.
      break;
  }
  return editor.toString();
}

String updatePubspecLockFile(
  String content,
  String dependency,
  String version,
  Requirement requirement,
) {
  final editor = YamlEditor(content);
  switch (requirement.source.type) {
    case SourceType.hosted:
      editor.update(
        ['packages', dependency, 'version'],
        _stringify(version),
      );
      break;
    case SourceType.git:
      editor.update(
        ['packages', dependency, 'description', 'ref'],
        _stringify(requirement.source.ref!),
      );
      editor.update(
        ['packages', dependency, 'description', 'resolved-ref'],
        _stringify(requirement.source.resolvedRef!),
      );
      editor.update(
        ['packages', dependency, 'version'],
        _stringify(version),
      );
      break;
    case SourceType.path:
      // Can't update pubspec files for path dependencies.
      break;
  }
  return editor.toString();
}

YamlScalar _stringify(String string) {
  if (_unquotableYamlString.hasMatch(string)) {
    return YamlScalar.wrap(string, style: ScalarStyle.PLAIN);
  }
  return YamlScalar.wrap(
    string,
    style: ScalarStyle.DOUBLE_QUOTED,
  );
}
