import 'dart:io';

/// Extracts a string option value for `--<name> <val>` or `--<name>=<val>`.
String? parseStringFlag(List<String> args, String flagName) {
  final String prefix = '--$flagName';
  for (int i = 0; i < args.length; i++) {
    final String arg = args[i];
    if (arg == prefix) {
      if (i + 1 >= args.length) {
        stderr.writeln('ERROR: $prefix requires a value.');
        exit(2);
      }
      return args[i + 1];
    }
    if (arg.startsWith('$prefix=')) {
      return arg.substring(prefix.length + 1);
    }
  }
  return null;
}

/// Extracts a finite double option value for `--<name> <val>` or `--<name>=<val>`.
double? parseDoubleFlag(List<String> args, String flagName) {
  final String? raw = parseStringFlag(args, flagName);
  if (raw == null) {
    return null;
  }
  final double? parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite) {
    stderr.writeln('ERROR: Invalid numeric value "$raw" for --$flagName.');
    exit(2);
  }
  return parsed;
}
