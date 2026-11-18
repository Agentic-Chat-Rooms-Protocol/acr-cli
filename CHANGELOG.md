## 1.0.1

- Add `test/fixtures/endpoint-vectors.json` shared compliance suite covering `validateLocal`, `validateRemote`, and `resolveMode` (including `entitlement` routing and invalid-local fail-closed behavior).
- Enforce no-redirect discovery (`followRedirects: false`, `maxRedirects: 0`) and strict RFC 9728 `resource` verification in `LoginCommand`.
- Fall back to `HOME` when `USERPROFILE` is empty in `AcrClient.resolveApiToken` and `McpEndpoint.resolveHomeDir`, and normalize blank `baseUrl`/`override` inputs.
- Expand offline unit and integration tests for redirect blocking, token resolution, and `~/.acr/ports.json` + `~/.acr/api-token` precedence, plus `dart format` compliance across all files.

## 1.0.0

- Default `AcrClient` and `bin/acr.dart` daemon endpoint to loopback literal `http://127.0.0.1:20443` with redirect blocking (`followRedirects: false`) and 10s request timeout.
- Add local daemon Bearer authentication via `ACR_API_TOKEN` with fallback to `~/.acr/api-token` (and `ACR_META_MCP_API_TOKEN` support in `acr meta-mcp`).
- Implement client-side MCP endpoint validation and routing (`McpEndpoint.validateLocal`, `validateRemote`, `resolve`) with Clerk OAuth `["profile", "email"]` scopes.
- Add `acr login`, `acr logout`, `acr mcp status`, and `acr mcp install` commands.
- Align `acr tunnel` preflight documentation and fix `opsroom_command.dart` analyzer warning/info.
