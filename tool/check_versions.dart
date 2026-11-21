import 'dart:io';

import 'src/cli_args.dart';
import 'src/reference_markdown.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/check_versions.dart [--tag vX.Y.Z[-pre]]',
    );
    return;
  }
  final String? expectedTag = parseStringFlag(args, 'tag');

  final List<String> errors = <String>[];

  final String? texMathVersion = _readPubspecVersion(
    'packages/tex_math/pubspec.yaml',
    errors,
  );
  final String? flutterVersion = _readPubspecVersion(
    'packages/tex_math_flutter/pubspec.yaml',
    errors,
  );
  final String? flutterDepConstraint = _readPubspecDependency(
    'packages/tex_math_flutter/pubspec.yaml',
    'tex_math',
    errors,
  );
  final String? texMathChangelog = _readTopChangelogVersion(
    'packages/tex_math/CHANGELOG.md',
    errors,
  );
  final String? flutterChangelog = _readTopChangelogVersion(
    'packages/tex_math_flutter/CHANGELOG.md',
    errors,
  );
  final String? referenceVersion = _readReferenceVersion(
    'REFERENCE.md',
    'tex_math',
    errors,
  );
  final String? referenceFlutterVersion = readReferenceVersionFromFile(
    'REFERENCE.md',
    'tex_math_flutter',
  );

  if (texMathVersion != null) {
    if (flutterVersion != null && flutterVersion != texMathVersion) {
      errors.add(
        'Version mismatch: packages/tex_math/pubspec.yaml is $texMathVersion '
        'but packages/tex_math_flutter/pubspec.yaml is $flutterVersion.',
      );
    }
    final String expectedConstraint = '^$texMathVersion';
    if (flutterDepConstraint != null &&
        flutterDepConstraint != expectedConstraint) {
      errors.add(
        'Dependency mismatch: packages/tex_math_flutter/pubspec.yaml has '
        'tex_math: $flutterDepConstraint, expected $expectedConstraint.',
      );
    }
    if (texMathChangelog != null && texMathChangelog != texMathVersion) {
      errors.add(
        'Changelog mismatch: packages/tex_math/CHANGELOG.md top heading is '
        '$texMathChangelog, expected $texMathVersion.',
      );
    }
    if (flutterChangelog != null && flutterChangelog != texMathVersion) {
      errors.add(
        'Changelog mismatch: packages/tex_math_flutter/CHANGELOG.md top '
        'heading is $flutterChangelog, expected $texMathVersion.',
      );
    }
    if (referenceVersion != null && referenceVersion != texMathVersion) {
      errors.add(
        'REFERENCE.md mismatch: tex_math entry is $referenceVersion, '
        'expected $texMathVersion.',
      );
    }
    if (referenceFlutterVersion != null &&
        referenceFlutterVersion != texMathVersion) {
      errors.add(
        'REFERENCE.md mismatch: tex_math_flutter entry is '
        '$referenceFlutterVersion, expected $texMathVersion.',
      );
    }
    if (expectedTag != null) {
      final String requiredTag = 'v$texMathVersion';
      if (expectedTag != requiredTag) {
        errors.add(
          'Tag mismatch: provided --tag $expectedTag does not match '
          'lockstep version tag $requiredTag.',
        );
      }
    }
  }

  if (errors.isNotEmpty) {
    for (final String error in errors) {
      stderr.writeln('ERROR: $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Version lockstep verified: $texMathVersion'
    '${expectedTag != null ? ' (tag $expectedTag)' : ''}.',
  );
}

String? _readPubspecVersion(String path, List<String> errors) {
  final File file = File(path);
  if (!file.existsSync()) {
    errors.add('Missing file: $path');
    return null;
  }
  final List<String> lines = file.readAsLinesSync();
  final RegExp versionPattern = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\s*(?:#.*)?$',
  );
  for (final String line in lines) {
    final RegExpMatch? match = versionPattern.firstMatch(line);
    if (match != null) {
      return match.group(1);
    }
  }
  errors.add('Could not find valid semver version: field in $path.');
  return null;
}

String? _readPubspecDependency(
  String path,
  String packageName,
  List<String> errors,
) {
  final File file = File(path);
  if (!file.existsSync()) {
    errors.add('Missing file: $path');
    return null;
  }
  final List<String> lines = file.readAsLinesSync();
  bool inDependencies = false;
  final RegExp depPattern = RegExp(
    '^\\s+${RegExp.escape(packageName)}:\\s*[\'"]?([^\'"\\s#]+)[\'"]?\\s*(?:#.*)?\$',
  );

  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    if (!line.startsWith(' ') && !line.startsWith('\t')) {
      inDependencies = trimmed == 'dependencies:';
      continue;
    }
    if (inDependencies) {
      final RegExpMatch? match = depPattern.firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
  }
  errors.add('Could not find dependencies.$packageName constraint in $path.');
  return null;
}

String? _readTopChangelogVersion(String path, List<String> errors) {
  final File file = File(path);
  if (!file.existsSync()) {
    errors.add('Missing file: $path');
    return null;
  }
  final List<String> lines = file.readAsLinesSync();
  final RegExp headingPattern = RegExp(
    r'^##\s+\[?([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\]?(?:\s|$)',
  );
  for (final String line in lines) {
    final RegExpMatch? match = headingPattern.firstMatch(line.trim());
    if (match != null) {
      return match.group(1);
    }
  }
  errors.add('Could not find top ## <version> heading in $path.');
  return null;
}

String? _readReferenceVersion(String path, String key, List<String> errors) {
  final File file = File(path);
  if (!file.existsSync()) {
    errors.add('Missing file: $path');
    return null;
  }
  final String? version = readReferenceVersionFromFile(path, key);
  if (version == null) {
    errors.add('Could not find `$key` version row in $path.');
  }
  return version;
}
