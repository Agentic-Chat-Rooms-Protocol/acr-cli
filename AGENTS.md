# Agent Guidelines - acr-cli

## CLI Tooling Discipline
1. **Standard Exit Codes**: Return 0 for success, 1 for user/argument errors, 2 for connection/network failures.
2. **Tabular Telemetry**: Ensure CLI output supports both formatted human-readable ANSI tables and machine-readable `--json` flags.
3. **Zero Phantom Deadzones**: Gracefully handle terminal resizing and interactive prompt aborts (`Ctrl+C`).
