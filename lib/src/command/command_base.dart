/*
Copyright 2018 Workiva Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

---------------------------------------------------------------------

This software or document includes material copied from or derived 
from webdev https://github.com/dart-lang/webdev

The original license from webdev follows:

Copyright 2017, the Dart project authors. All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
import 'dart:async';
import 'dart:convert';
import 'dart:io' hide exitCode, exit;
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:dart_build/src/util.dart';
import 'package:meta/meta.dart';
import 'package:stack_trace/stack_trace.dart';

const _packagesFileName = '.packages';
const _release = 'release';
const _output = 'output';
const _verbose = 'verbose';

const _requireBuildWebCompilers = 'build-web-compilers';

/// Extend to get a command with the arguments common to all build_runner
/// commands.
abstract class CommandBase extends Command<int> {
  final bool releaseDefault;

  CommandBase({@required this.releaseDefault}) {
    // TODO(nshahan) Expose more common args passed to build_runner commands.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addFlag(_release,
          abbr: 'r',
          defaultsTo: releaseDefault,
          negatable: true,
          help: 'Build with release mode defaults for builders.')
      ..addOption(
        _output,
        abbr: 'o',
        help: 'A directory to write the result of a build to. Or a mapping '
            'from a top-level directory in the package to the directory to '
            'write a filtered build output to. For example "web:deploy".',
      )
      ..addFlag(_verbose,
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.')
      ..addFlag(_requireBuildWebCompilers,
          defaultsTo: true,
          negatable: true,
          help: 'If a dependency on `build_web_compilers` is required to run.');
  }

  List<String> getArgs() {
    var arguments = <String>[];
    if ((argResults[_release] as bool) ?? releaseDefault) {
      arguments.add('--$_release');
    }

    var output = argResults[_output] as String;
    if (output != null) {
      arguments.addAll(['--$_output', output]);
    }

    if (argResults[_verbose] as bool) {
      arguments.add('--$_verbose');
    }
    return arguments;
  }

  Future<int> runCore(String command, {List<String> extraArgs}) async {
    if (isDart1) {
      return await _runPub(command, extraArgs: extraArgs);
    }

    var buildRunnerScript = await _buildRunnerScript();

    final arguments = [command]
      ..addAll(extraArgs ?? const [])
      ..addAll(getArgs());

    var exitCode = 0;

    // Heavily inspired by dart-lang/build @ 0c77443dd7
    // /build_runner/bin/build_runner.dart#L58-L85
    var exitPort = new ReceivePort();
    var errorPort = new ReceivePort();
    var messagePort = new ReceivePort();
    var errorListener = errorPort.listen((e) {
      stderr.writeln('\n\nYou have hit a bug in build_runner');
      stderr.writeln('Please file an issue with reproduction steps at '
          'https://github.com/dart-lang/build/issues\n\n');
      final error = e[0];
      final trace = e[1] as String;
      stderr.writeln(error);
      stderr.writeln(new Trace.parse(trace).terse);
      if (exitCode == 0) exitCode = 1;
    });

    try {
      await Isolate.spawnUri(buildRunnerScript, arguments, messagePort.sendPort,
          onExit: exitPort.sendPort,
          onError: errorPort.sendPort,
          automaticPackageResolution: true);
      StreamSubscription exitCodeListener;
      exitCodeListener = messagePort.listen((isolateExitCode) {
        if (isolateExitCode is! int) {
          throw new StateError(
              'Bad response from isolate, expected an exit code but got '
              '$isolateExitCode');
        }
        exitCode = isolateExitCode as int;
        exitCodeListener.cancel();
        exitCodeListener = null;
      });
      await exitPort.first;
      await errorListener.cancel();
      await exitCodeListener?.cancel();

      return exitCode;
    } finally {
      exitPort.close();
      errorPort.close();
      messagePort.close();
    }
  }

  Future<int> _runPub(String command, {List<String> extraArgs}) async {
    var args = <String>[];
    args.add(command);
    args.addAll(extraArgs ?? <String>['']);
    args.addAll(this.argResults.rest);
    args.removeWhere((s) => s == null || s.isEmpty);
    print('pub ${args.join(" ")}');

    // Start pub
    Process pubProcess = await Process.start('pub', args);
    Completer c = new Completer();
    StreamSubscription stdoutSubscription = pubProcess.stdout
        .transform(UTF8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // The output we get does not have ANSI color codes, because dart:io stdioType
      // is correctly determining that we are not a terminal.
      // There is no way to override this that I can tell.
      // FUTURE - we could mimic the color formatting that pub server has in
      // https://github.com/dart-lang/pub/blob/master/lib/src/command/serve.dart#L148
      // Provide pub serve output to the console
      print(line);
      // Lets the completer know when pub serve has begun serving
      if (line.startsWith('Build completed successfully') && !c.isCompleted) {
        c.complete();
      }
    });
    StreamSubscription stderrSubscription = pubProcess.stderr
        .transform(UTF8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      // Bail if pub serve encounters an error
      if (!c.isCompleted) {
        c.completeError(new Exception(line));
        return;
      }
      print(line);
    });
    try {
      // Wait for pub serve to begin serving
      await c.future;
    } catch (e) {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      print(e);
    }
    return pubProcess.exitCode;
  }
}

Future<Uri> _buildRunnerScript() async {
  var packagesFile = new File(_packagesFileName);
  if (!packagesFile.existsSync()) {
    throw new FileSystemException(
        'A `$_packagesFileName` file does not exist in the target directory.',
        packagesFile.absolute.path);
  }

  var dataUri = new Uri.dataFromString(_bootstrapScript);

  var messagePort = new ReceivePort();
  var exitPort = new ReceivePort();
  var errorPort = new ReceivePort();

  try {
    await Isolate.spawnUri(dataUri, [], messagePort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        errorsAreFatal: true,
        packageConfig: new Uri.file(_packagesFileName));

    var allErrorsFuture = errorPort.forEach((error) {
      var errorList = error as List;
      var message = errorList[0] as String;
      var stack = new StackTrace.fromString(errorList[1] as String);

      stderr.writeln(message);
      stderr.writeln(stack);
    });

    var items = await Future.wait([
      messagePort.toList(),
      allErrorsFuture,
      exitPort.first.whenComplete(() {
        messagePort.close();
        errorPort.close();
      })
    ]);

    var messages = items[0] as List;
    if (messages.isEmpty) {
      throw new StateError('An error occurred while bootstrapping.');
    }

    assert(messages.length == 1);
    return new Uri.file(messages.single as String);
  } finally {
    messagePort.close();
    exitPort.close();
    errorPort.close();
  }
}

const _bootstrapScript = r'''
import 'dart:io';
import 'dart:isolate';

import 'package:build_runner/build_script_generate.dart';
import 'package:path/path.dart' as p;

void main(List<String> args, [SendPort sendPort]) async {
  var buildScript = await generateBuildScript();
  var scriptFile = new File(scriptLocation)..createSync(recursive: true);
  scriptFile.writeAsStringSync(buildScript);
  sendPort.send(p.absolute(scriptLocation));  
}
''';
