import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';
import 'package:yaml/yaml.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:path/path.dart' as p;

Never fail(String message) {
  stderr.writeln(message);
  exit(-1);
}

final client = RetryClient(Client());

ArgResults parseArgs(List<String> args) {
  final argParser = ArgParser()
    ..addOption(
      'directory',
      abbr: 'C',
      defaultsTo: '.',
      help: 'The directory containing the pubspec.yaml of the package.',
    )
    ..addOption('flutter-releases-url',
        help:
            'The url to retrieve the list of available flutter releases from.')
    ..addFlag('help', help: 'Display the usage message.');
  final results;
  try {
    results = argParser.parse(args);
    if (results['help'] as bool) {
      stdout.writeln(
          'Infers the newest available flutter sdk to use for a package.');
      stdout.writeln(argParser.usage);
      exit(0);
    }
    return results;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(argParser.usage);
    exit(-1);
  }
}

Map<String, VersionConstraint> parseSdkConstraints(dynamic pubspec) {
  final dartConstraint =
      VersionConstraint.parse(pubspec['environment']?['sdk'] ?? 'any');
  final flutterConstraint =
      VersionConstraint.parse(pubspec['environment']?['flutter'] ?? 'any');
  return {
    'dart': dartConstraint,
    'flutter': flutterConstraint,
  };
}

Future<void> main(List<String> args) async {
  try {
    final argResults = parseArgs(args);
    var url = argResults['flutter-releases-url'];
    if (url == null || url.isEmpty) {
      url = flutterReleasesUrl;
    }
    final flutterReleases = await retrieveFlutterReleases(url);

    final pubspecPath = p.join(argResults['directory'], 'pubspec.yaml');
    final pubspec = loadYaml(File(pubspecPath).readAsStringSync(),
        sourceUrl: Uri.file(pubspecPath));

    final bestFlutterRelease =
        inferBestFlutterRelease(parseSdkConstraints(pubspec), flutterReleases);
    if (bestFlutterRelease == null) {
      fail(
        'No flutter release matching sdk constraints.',
      );
    }
    stdout.writeln(JsonEncoder.withIndent('  ').convert({
      'flutter': bestFlutterRelease.flutterVersion.toString(),
      'dart': bestFlutterRelease.dartVersion.toString(),
      'channel': {
        Channel.stable: 'stable',
        Channel.beta: 'beta',
        Channel.dev: 'dev'
      }[bestFlutterRelease.channel],
    }));
  } on FormatException catch (e) {
    fail(e.message);
  } finally {
    client.close();
  }
}

String get flutterReleasesUrl =>
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json';

// Retrieves all released versions of Flutter.
Future<List<FlutterRelease>> retrieveFlutterReleases(String url) async {
  final response = await client.get(Uri.parse(url));
  final decoded = jsonDecode(response.body);
  if (decoded is! Map) throw FormatException('Bad response - should be a Map');
  final releases = decoded['releases'];
  if (releases is! List)
    throw FormatException('Bad response - releases should be a list.');
  final result = <FlutterRelease>[];
  for (final release in releases) {
    final channel = {
      'beta': Channel.beta,
      'stable': Channel.stable,
      'dev': Channel.dev
    }[release['channel']];
    if (channel == null) throw FormatException('Release with bad channel');
    final dartVersion = release['dart_sdk_version'];
    // Some releases don't have an associated dart version, ignore.
    if (dartVersion is! String) continue;
    final flutterVersion = release['version'];
    if (flutterVersion is! String) throw FormatException('Not a string');
    result.add(FlutterRelease(
      flutterVersion: Version.parse(flutterVersion),
      dartVersion: Version.parse(dartVersion.split(' ').first),
      channel: channel,
    ));
  }
  return result
      // Sort releases by channel and version.
      .sorted((a, b) {
        final compareChannels = b.channel.index - a.channel.index;
        if (compareChannels != 0) return compareChannels;
        return a.flutterVersion.compareTo(b.flutterVersion);
      })
      // Newest first.
      .reversed
      .toList();
}

/// The "best" Flutter release for a given set of constraints is the first one
/// in [flutterReleases] that matches both the flutter and dart constraint.
FlutterRelease? inferBestFlutterRelease(
    Map<String, VersionConstraint> sdkConstraints,
    List<FlutterRelease> flutterReleases) {
  return flutterReleases.firstWhereOrNull((release) =>
      (sdkConstraints['flutter'] ?? VersionConstraint.any)
          .allows(release.flutterVersion) &&
      (sdkConstraints['dart'] ?? VersionConstraint.any)
          .allows(release.dartVersion));
}

enum Channel {
  stable,
  beta,
  dev,
}

/// A version of the Flutter SDK and its related Dart SDK.
class FlutterRelease {
  final Version flutterVersion;
  final Version dartVersion;
  final Channel channel;
  FlutterRelease({
    required this.flutterVersion,
    required this.dartVersion,
    required this.channel,
  });
}
