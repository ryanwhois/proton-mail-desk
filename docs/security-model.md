# Security model

This repository connects only to a locally running Proton Mail Bridge at `127.0.0.1`.

`Initialize-ProtonBridgeProfile.ps1` stores the Bridge mailbox username and password in `.local/bridge-profile.clixml`. PowerShell protects the `SecureString` password using Windows DPAPI: the current Windows user on this machine can decrypt it, but it is not portable to another user or machine. The `.local/` directory is ACL-restricted and ignored by Git.

The profile uses the **Bridge-generated mailbox password**, never the Proton account password. The password is converted to plaintext only in memory to start the local Node client, then process-scoped environment values are restored before the PowerShell process returns.

The upstream client is pinned to `proton-mail-bridge-client@2.1.49`, the MIT-licensed MCP/CLI project from [googlarz](https://github.com/googlarz/proton-mail-bridge-client). It supplies IMAP/SMTP communication and the MCP server. This project supplies Windows setup, credential handling, local endpoint validation, and a command guard.

Full-access profiles permit normal mailbox changes and sending, but the upstream `PROTONMAIL_CONFIRM_DESTRUCTIVE=true` policy remains enabled. The wrapper also requires `-ConfirmDestructive` for send, permanent-delete, and generic MCP-tool commands. This is a local safety gate, not an assurance that a user cannot execute a direct upstream command outside this repository.
