# Agent Guidelines - acr-cli

## CLI Tooling Discipline
1. **Standard Exit Codes**: Return 0 for success, 1 for user/argument errors, 2 for connection/network failures.
2. **Tabular Telemetry**: Ensure CLI output supports both formatted human-readable ANSI tables and machine-readable `--json` flags.
3. **Zero Phantom Deadzones**: Gracefully handle terminal resizing and interactive prompt aborts (`Ctrl+C`).
4. **Dynamic Port Mapping**: Support `acr ports [list|set|reset|test|export]` with resolution against `~/.acr/ports.json` and `ACR_*_PORT` environment variables.
5. **Meta-MCP Control**: Expose `acr meta-mcp` commands for inspecting and bridging proxy operations on port 20445.
