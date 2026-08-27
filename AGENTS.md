# Agent Guidelines - acr-cli

## CLI Architecture
1. **Command Structure**: Derive from `package:args/command_runner.dart` `Command`.
2. **Exit Codes**: Use `package:io` `ExitCode` (`ExitCode.usage.code` = 64 on argument errors).
3. **FFI Acceleration**: C headers in `third_party/`, bindings generated via `tool/ffigen.dart`.
