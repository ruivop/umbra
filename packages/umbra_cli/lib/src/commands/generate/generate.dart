import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason/mason.dart' hide packageVersion;
import 'package:path/path.dart' as path;
import 'package:umbra/umbra.dart';
import 'package:umbra_cli/src/commands/generate/targets/targets.dart';
import 'package:umbra_cli/src/umbra_command.dart';

final _targets = [
  DartShaderTarget(),
  RawShaderTarget(),
  SpirvBinaryTarget(),
];

final _defaultTarget = _targets.first;

/// {@template generate_command}
/// `umbra generate` command which generates files based on Umbra shaders.
/// {@endtemplate}
class GenerateCommand extends UmbraCommand {
  /// {@macro generate_command}
  GenerateCommand({
    super.logger,
    super.cmd,
    super.platform,
  }) {
    argParser
      ..addOption(
        'output',
        abbr: 'o',
        help: 'The output directory for the created file(s).',
        valueHelp: 'directory',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The target used for generation.',
        defaultsTo: _defaultTarget.name,
        valueHelp: 'target',
        allowed: _targets.map((element) => element.name).toList(),
        allowedHelp: _targets.fold<Map<String, String>>(
          {},
          (previousValue, element) => {
            ...previousValue,
            element.name: element.help,
          },
        ),
      );
  }

  @override
  final String description = 'Generate files based on an Umbra Shader.';

  @override
  final String name = 'generate';

  @override
  String get invocation => 'umbra generate <shader_name>';

  File get _shaderFile {
    final rest = results.rest;
    if (rest.isEmpty || rest.first.isEmpty) {
      throw UsageException('No file specified.', usage);
    }
    final shaderFile = File(rest.first);
    if (!shaderFile.existsSync()) {
      throw UsageException('File "${shaderFile.path}" does not exist.', usage);
    }
    return shaderFile;
  }

  Directory get _outputDirectory {
    final directory = Directory(
      results['output'] == null
          ? Directory.current.path
          : results['output'] as String,
    );

    if (!directory.existsSync()) {
      throw UsageException(
        'Directory "${directory.path}" does not exist.',
        usage,
      );
    }
    return directory;
  }

  Target get _target {
    final targetName = results['target'] as String?;

    return _targets.firstWhere(
      (element) => element.name == targetName,
      orElse: () => _defaultTarget,
    );
  }

  @override
  Future<int> run() async {
    final shaderFile = _shaderFile;
    final outputDirectory = _outputDirectory;
    final target = _target;

    final parsingShader = logger.progress('Parsing shader file');
    final specification = _parseShaderSpecification(shaderFile);
    parsingShader.complete('Shader file parsed');

    final generateDone = logger.progress('Generating');
    final generator = await target.generator(specification, cmd, dataDirectory);
    final bytes = await generator.generate();
    generateDone.complete('Generated');

    final outputName = '${specification.name}.${target.extension}';
    final outputFile = File(path.join(outputDirectory.path, outputName));
    if (outputFile.existsSync()) {
      final answer = logger.confirm('${yellow.wrap('Overwrite $outputName?')}');
      if (!answer) {
        logger.err('Aborting.');
        return ExitCode.cantCreate.code;
      }
    }
    outputFile.writeAsBytesSync(bytes);

    return ExitCode.success.code;
  }

  ShaderSpecification _parseShaderSpecification(File shader) {
    return ShaderSpecification.fromFile(shader);
  }
}
