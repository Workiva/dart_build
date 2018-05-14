# dart_build

A CLI that provides dart 1 and dart 2 compatible build and serve commands.

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

*_NOTE: This will likely change when this project is made open source_*
```
dev_dependencies:
  dart_build:
    hosted:
      name: dart_build
      url: https://pub.workiva.org
    version: ^1.3.0
```

## Usage

To run a build or serve simply swap out `pub` with `pub run dart_build`
in your usual commands. All of the command line options and arguments
are passed along, so all supported options of pub serve or build_runner
should be supported.

Example:
```
pub run dart_build serve
pub run dart_build build
```

