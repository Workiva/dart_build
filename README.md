# dart_build

## NOTE: This project is < 1.0.0 and is not considered stable yet

A command line tool that provides Dart 1 and Dart 2 compatible build and
serve commands to ease the transition to Dart 2.

This tool is intended to be used as a transition tool when moving from Dart 1
to Dart 2. Since the `pub serve` and `pub build` commands are not present in
Dart 2, you can use dart_build to run the same command under both versions of
Dart, thus easing the transition to Dart 2. With dart_build you don't need to
modify your pubspec.yaml to add build_runner and build_web_compilers to be
able to build under Dart 2. Those dependencies are included by adding a
dependency on dart_build.

## Installation

Add dart_build as a dev_dependency to your pubspec.yaml. When pub get solves
you'll either the #.#.#+dart1 or the #.#.#+dart2 version depending on if you
run the pub get command under Dart 1 or Dart 2.

```
dev_dependencies:
  dart_build: ^0.1.0
```

## Usage

To run a build or serve simply swap out `pub` with `pub run dart_build`
in your usual commands. All of the command line options and arguments
are passed along, so all supported options of pub serve or build_runner
should be supported. For local use, adding an alias is recommended so you
don't need to type such a long command.

```console
alias db='pub run dart_build'
```

## Example:
```console
pub run dart_build serve
pub run dart_build build
```
or with the alias set up:
```console
db serve
db build
```

