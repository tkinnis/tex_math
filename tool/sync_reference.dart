import 'dart:convert';
import 'dart:io';

import 'src/reference_markdown.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify | --check [--json]]',
    );
    return;
  }

  final bool verifyMode = args.contains('--verify');
  final bool checkMode = args.contains('--check');
  final bool jsonMode = args.contains('--json');

  if (!verifyMode && !checkMode) {
    stderr.writeln('ERROR: Specify --verify or --check.');
    stderr.writeln(
      'Usage: dart run tool/sync_reference.dart [--verify | --check [--json]]',
    );
    exitCode = 2;
    return;
  }

  if (verifyMode) {
    final bool ok = _verifyReference();
    if (!ok) {
      exitCode = 1;
      return;
    }
  }

  if (checkMode) {
    final bool ok = await _checkUpstream(jsonOutput: jsonMode);
    if (!ok) {
      exitCode = 1;
      return;
    }
  }
}

bool _verifyReference() {
  final List<String> errors = <String>[];

  final File packageJsonFile = File('tool/oracle/package.json');
  final File lockfile = File('tool/oracle/package-lock.json');
  final File referenceFile = File('REFERENCE.md');

  if (!packageJsonFile.existsSync()) {
    errors.add('Missing tool/oracle/package.json.');
  }
  if (!lockfile.existsSync()) {
    errors.add('Missing tool/oracle/package-lock.json.');
  }
  if (!referenceFile.existsSync()) {
    errors.add('Missing REFERENCE.md.');
  }

  if (errors.isNotEmpty) {
    for (final String err in errors) {
      stderr.writeln('ERROR: $err');
    }
    return false;
  }

  final Map<String, Object?> packageJson =
      jsonDecode(packageJsonFile.readAsStringSync()) as Map<String, Object?>;
  final Map<String, Object?>? deps =
      packageJson['dependencies'] as Map<String, Object?>?;
  if (deps == null) {
    stderr.writeln('ERROR: tool/oracle/package.json has no dependencies map.');
    return false;
  }

  final String referenceText = referenceFile.readAsStringSync();
  const List<String> requiredPackages = <String>[
    'mathjax',
    '@mathjax/src',
    '@mathjax/mathjax-newcm-font',
    'katex',
  ];

  for (final String pkg in requiredPackages) {
    final String? rawVersion = deps[pkg] as String?;
    if (rawVersion == null || rawVersion.isEmpty) {
      errors.add('Missing dependency "$pkg" in tool/oracle/package.json.');
      continue;
    }
    final String pinnedVersion = _normalizeConstraint(rawVersion);
    final String? refVersion = extractReferenceVersion(referenceText, pkg);
    if (refVersion == null) {
      errors.add('Missing `$pkg` version row in REFERENCE.md.');
    } else if (refVersion != pinnedVersion) {
      errors.add(
        'Version drift for `$pkg`: tool/oracle/package.json pins '
        '$pinnedVersion but REFERENCE.md states $refVersion.',
      );
    }
  }

  final String? lockfileHash = _computeFileSha256(lockfile.path);
  if (lockfileHash == null) {
    errors.add('Unable to compute SHA-256 digest of ${lockfile.path}.');
  } else {
    final String? refHash = extractLockfileSha256(referenceText);
    if (refHash == null) {
      errors.add(
        'Missing `tool/oracle/package-lock.json` SHA-256 hash in REFERENCE.md.',
      );
    } else if (refHash.toLowerCase() != lockfileHash.toLowerCase()) {
      errors.add(
        'Lockfile hash drift: tool/oracle/package-lock.json SHA-256 is '
        '$lockfileHash but REFERENCE.md states $refHash.',
      );
    }
  }

  if (errors.isNotEmpty) {
    for (final String err in errors) {
      stderr.writeln('ERROR: $err');
    }
    return false;
  }

  stdout.writeln(
    'REFERENCE.md verified against tool/oracle/package.json and '
    'tool/oracle/package-lock.json ($lockfileHash).',
  );
  return true;
}

Future<bool> _checkUpstream({required bool jsonOutput}) async {
  final File referenceFile = File('REFERENCE.md');
  if (!referenceFile.existsSync()) {
    stderr.writeln('ERROR: Missing REFERENCE.md.');
    return false;
  }
  final String referenceText = referenceFile.readAsStringSync();
  final String? pinnedMathjax = extractReferenceVersion(
    referenceText,
    'mathjax',
  );
  final String? pinnedJupyterlab = extractReferenceVersion(
    referenceText,
    '@jupyterlab/mathjax-extension',
  );

  if (pinnedMathjax == null || pinnedJupyterlab == null) {
    stderr.writeln(
      'ERROR: Could not extract pinned versions for mathjax or '
      '@jupyterlab/mathjax-extension from REFERENCE.md.',
    );
    return false;
  }

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final String latestMathjax = await _fetchNpmLatest(
      client,
      'https://registry.npmjs.org/mathjax/latest',
    );
    final String latestJupyterlab = await _fetchNpmLatest(
      client,
      'https://registry.npmjs.org/@jupyterlab/mathjax-extension/latest',
    );

    final bool mathjaxUpToDate =
        _compareSemver(latestMathjax, pinnedMathjax) <= 0;
    final bool jupyterlabUpToDate =
        _compareSemver(latestJupyterlab, pinnedJupyterlab) <= 0;
    final bool hasUpdate = !mathjaxUpToDate || !jupyterlabUpToDate;

    final Map<String, Object?> payload = <String, Object?>{
      'hasUpdate': hasUpdate,
      'pinnedMathjax': pinnedMathjax,
      'latestMathjax': latestMathjax,
      'pinnedJupyterlab': pinnedJupyterlab,
      'latestJupyterlab': latestJupyterlab,
      'mathjax': <String, Object?>{
        'package': 'mathjax',
        'pinned': pinnedMathjax,
        'latest': latestMathjax,
        'upToDate': mathjaxUpToDate,
      },
      'jupyterlabMathjax': <String, Object?>{
        'package': '@jupyterlab/mathjax-extension',
        'pinned': pinnedJupyterlab,
        'latest': latestJupyterlab,
        'upToDate': jupyterlabUpToDate,
      },
    };

    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
    } else {
      stdout.writeln(
        'mathjax: pinned=$pinnedMathjax latest=$latestMathjax '
        '(${mathjaxUpToDate ? 'up to date' : 'UPDATE AVAILABLE'})',
      );
      stdout.writeln(
        '@jupyterlab/mathjax-extension: pinned=$pinnedJupyterlab '
        'latest=$latestJupyterlab '
        '(${jupyterlabUpToDate ? 'up to date' : 'UPDATE AVAILABLE'})',
      );
    }
    return true;
  } catch (err) {
    stderr.writeln('ERROR: Failed to query npm registry: $err');
    return false;
  } finally {
    client.close(force: true);
  }
}

Future<String> _fetchNpmLatest(HttpClient client, String url) async {
  final HttpClientRequest request = await client.getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  request.headers.set(HttpHeaders.userAgentHeader, 'tex_math-reference-sync');
  final HttpClientResponse response = await request.close();
  final String body = await utf8.decodeStream(response);
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException(
      'HTTP ${response.statusCode} fetching $url',
      uri: Uri.parse(url),
    );
  }
  final Map<String, Object?> decoded = jsonDecode(body) as Map<String, Object?>;
  final String? version = decoded['version'] as String?;
  if (version == null || version.isEmpty) {
    throw FormatException('Missing "version" field in response from $url');
  }
  return version;
}

String _normalizeConstraint(String raw) {
  return raw.replaceFirst(RegExp(r'^[\^~>=<\s]+'), '');
}

String? _computeFileSha256(String path) {
  final List<List<String>> candidates = <List<String>>[
    <String>['shasum', '-a', '256', path],
    <String>['sha256sum', path],
    <String>[
      'python3',
      '-c',
      'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())',
      path,
    ],
  ];

  for (final List<String> cmd in candidates) {
    try {
      final ProcessResult result = Process.runSync(cmd.first, cmd.sublist(1));
      if (result.exitCode == 0) {
        final String output = (result.stdout as String).trim();
        final RegExpMatch? match = RegExp(
          r'([0-9a-fA-F]{64})',
        ).firstMatch(output);
        if (match != null) {
          return match.group(1)!.toLowerCase();
        }
      }
    } on ProcessException {
      continue;
    }
  }
  return null;
}

int _compareSemver(String a, String b) {
  final List<String> aParts = a.split('-');
  final List<String> bParts = b.split('-');
  final List<int> aCore = aParts.first.split('.').map(int.parse).toList();
  final List<int> bCore = bParts.first.split('.').map(int.parse).toList();

  final int maxLen = aCore.length > bCore.length ? aCore.length : bCore.length;
  for (int i = 0; i < maxLen; i++) {
    final int aNum = i < aCore.length ? aCore[i] : 0;
    final int bNum = i < bCore.length ? bCore[i] : 0;
    if (aNum != bNum) {
      return aNum.compareTo(bNum);
    }
  }

  final bool aHasPre = aParts.length > 1;
  final bool bHasPre = bParts.length > 1;
  if (!aHasPre && !bHasPre) {
    return 0;
  }
  if (!aHasPre) {
    return 1;
  }
  if (!bHasPre) {
    return -1;
  }
  return aParts.sublist(1).join('-').compareTo(bParts.sublist(1).join('-'));
}
