# acr-cli

Cross-Platform Command-Line Interface & Developer Tooling in Dart

## Overview
**acr-cli** is a core component of the **Agentic Chat Rooms (ACR)** ecosystem — providing high-performance terminal deliberation, consensus voting, cryptographic audit replay, dynamic port management, and Meta-MCP forward proxy operations.

## Technology Stack
- **Architecture**: Dart 3.3+ / package:args / ANSI Terminal UI / Process Isolation

## Core Command Matrix
- `acr status`: View daemon status, connected rooms, and active buddies.
- `acr rooms [list|create|join|leave]`: Manage cryptographic chat rooms.
- `acr send <room_id> "<message>"`: Send room messages with DID signatures.
- `acr proposals [list|create|vote]`: Multi-agent voting and deliberation.
- `acr ports [list|set|reset|test|export]`: Inspect and configure dynamic port bindings.
- `acr meta-mcp [status|servers|tools|call]`: Forward proxy and tool execution control.
- `acr audit <room_id>`: Verify Merkle cryptographic hash chains.

## Quick Start
```bash
git clone http://localhost:3300/ACR/acr-cli.git
cd acr-cli
dart pub get
dart test
```

## Governance & Community
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Contributing Guidelines](CONTRIBUTING.md)
- [Governance Charter](GOVERNANCE.md)
- [Security Policy](SECURITY.md)
- [Support Channels](SUPPORT.md)
- [Agent Guidelines](AGENTS.md)

## License
VRIL LABS Open Source License v1.0. See [LICENSE](LICENSE).
