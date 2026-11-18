## 1.0.0

- Default `AcrClient` and `bin/acr.dart` daemon endpoint to loopback literal `http://127.0.0.1:20443` with redirect blocking (`followRedirects: false`) and 10s request timeout.
- Add local daemon Bearer authentication via `ACR_API_TOKEN` with fallback to `~/.acr/api-token` (and `ACR_META_MCP_API_TOKEN` support in `acr meta-mcp`).
- Implement client-side MCP endpoint validation and routing (`McpEndpoint.validateLocal`, `validateRemote`, `resolve`) with Clerk OAuth `["profile", "email"]` scopes.
- Add `acr login`, `acr logout`, `acr mcp status`, and `acr mcp install` commands.
- Align `acr tunnel` preflight documentation and fix `opsroom_command.dart` analyzer warning/info.
