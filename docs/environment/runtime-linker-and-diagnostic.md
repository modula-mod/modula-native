# Linker and diagnostic acceptance — 2026-09-12

Starting branch `phase-n1-ios-native-foundation`, HEAD `4c04fe3`.

## Modula Xcode configuration

The Swift-only ModulaTests bundle inherited `:complete` from the application's Pods. Its link command pulled `libReactCodegen.a(ModulaHostSpec-generated.o)` into the test executable, including `std::__1::logic_error`, `std::__1::length_error`, new/delete and other C++ runtime references. Unlike the app (which compiles Objective-C++), the Swift test bundle did not automatically link libc++. Adding `-lc++` demonstrated the missing dependency but also exposed duplicate ReactCodegen and dependency-provider classes in the host process.

The correction is `inherit! :search_paths` for the hosted unit tests. They import the app through TEST_HOST/BUNDLE_LOADER and use its native dependencies. They do not link another copy of React Native. The experimental blanket libc++ flags were removed. Tests remain enabled and execute.

## Module lifecycle failures found by UI testing

A codegen provider can be constructed before its event callback is installed. Registering a notification observer in init allowed an empty C++ function to be invoked (`std::__1::bad_function_call`). The Modula bridge now starts observing only after the generated callback is installed and checks it before emission. No generated Pod code was changed.

A deliberately caught React render exception opened RN's development LogBox as a separate global window over native Retry. `LogBox.uninstall()` disables that development UI in this embedded runtime; console logging remains, and the module boundary reports failure to native diagnostics. `ignoreAllLogs()` alone did not prevent the error window. Native recovery and navigation remain outside React. Surface identity is scoped to the disposable RN container.

## Evidence

Xcode scheme Modula, Debug, iPhone 17 Pro iOS 26.5 (`439E8DF1-EA4F-4028-98A0-32CA9469EAE0`). `artifacts/DerivedData/Logs/Test/Test-Modula-2026.09.12_16-44-57-+0100.xcresult` (see build log for exact result filename). `/tmp/modula-n1-runtime-test7.log`: five native unit tests and two UI tests pass. Diagnostic sequence: repeated open/close, rejected host action, intentional render failure, native Retry, RN request to native Profile. Native-only routing test runs with runtime explicitly unavailable.

Dependency warnings remain separately classified; this result does not yet prove Vault CRUD, Release, or a physical device.
