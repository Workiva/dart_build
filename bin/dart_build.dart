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
import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';
import 'package:io/ansi.dart';
import 'package:io/io.dart';

const appName = 'dart_build';
const List<String> allowedCommands = const <String>['build', 'serve'];
String get _boldApp => styleBold.wrap(appName);
const _packagesFileName = '.packages';
final bool isDart1 = Platform.version.startsWith('1.');

/// The path to the root directory of the SDK.
final String _sdkDir = (() {
  // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
  // "/path/to/sdk".
  var aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
  assert(FileSystemEntity.isFileSync(p.join(aboveExecutable, 'version')));
  return aboveExecutable;
})();

final String dartPath =
    p.join(_sdkDir, 'bin', Platform.isWindows ? 'dart.exe' : 'dart');
final String pubPath =
    p.join(_sdkDir, 'bin', Platform.isWindows ? 'pub.bat' : 'pub');

Future main(List<String> args) async {
  try {
    // Manually handle all args since we aren't really parsing them
    // but instead just passing along the List to the appropriate command
    args ??= [];
    args.removeWhere((s) => s == null || s.isEmpty);

    if (args.isEmpty || !allowedCommands.contains(args[0])) {
      print(red.wrap('Specify pub run $_boldApp build|serve'));
      exitCode = ExitCode.usage.code;
      return exitCode;
    }
    String command = args.removeAt(0);
    if (isDart1) {
      return await runPub(command, args);
    } else {
      return await runBuildRunner(command, args) ?? 0;
    }
  } on FileSystemException catch (e) {
    print(red.wrap('$_boldApp could not run in the current directory.'));
    print(e.message);
    if (e.path != null) {
      print('  ${e.path}');
    }
    exitCode = ExitCode.config.code;
  } on IsolateSpawnException catch (e) {
    print(red.wrap('$_boldApp failed with an unexpected exception.'));
    print(e.message);
    exitCode = ExitCode.software.code;
  }
}

Future<int> runPub(String command, List<String> extraArgs) async {
  var args = <String>[];
  args.add(command);
  args.addAll(extraArgs ?? <String>['']);
  print('Running: ' + blue.wrap('pub ${args.join(" ")}'));
  Process pubProcess = await Process.start('pub', args);
  pubProcess.stdout
      .transform(UTF8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    print(line);
  });
  pubProcess.stderr
      .transform(UTF8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    print(red.wrap(line));
  });
  return pubProcess.exitCode;
}

Future<int> runBuildRunner(String command, List<String> args) async {
  args ??= [];

  // print('start args: $args');
  if (command == 'serve') {
    // if there aren't any directories listed, look at the
    // filesystem and add ones that exist
    bool hasNonFlags = args.any((s) => !s.startsWith('-'));
    if (!hasNonFlags) {
      for (String dir in ['web', 'test', 'example']) {
        if (new Directory(dir).existsSync()) {
          args.add(dir);
        }
      }
    }
    // for pub serve --port=#, remove the argument and
    // combine it with the directory (dir:port)
    int startPort = 0;
    List<int> indexesToRemove = [];
    for (var i = 0; i < args.length; i++) {
      var s = args[i];
      if (s.startsWith('--port')) {
        indexesToRemove.add(i);
        var pieces = s.split('=');
        if (pieces.length > 1) {
          startPort = int.parse(pieces[1]);
        } else {
          if (i + 1 < args.length) {
            i++;
            startPort = int.parse(args[i]);
            indexesToRemove.add(i);
          }
        }
      }
    }
    for (var i = indexesToRemove.length - 1; i >= 0; i--) {
      args.removeAt(indexesToRemove[i]);
    }

    // now append and increment the port to any directories in the list
    args =
        args.map((s) => !s.startsWith('-') ? '$s:${startPort++}' : s).toList();
  }

  if (command == 'build') {
    // TODO only add these is they don't exist already
    args.addAll(['--output', 'build']);
    args.add('--release');
    args.add('--fail-on-severe');
  }
  args.insert(0, command);
  print('Running: ' + blue.wrap('pub run build_runner ${args.join(" ")}'));
  var exitCode = 0;
  var buildRunnerScript = await _buildRunnerScript();

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
    await Isolate.spawnUri(buildRunnerScript, args, messagePort.sendPort,
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
