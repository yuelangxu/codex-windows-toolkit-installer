# Codex Network Toolkit

This guide covers the remote-access network helpers that the Codex Windows Toolkit now exposes in PowerShell.

## What gets installed

- `codex.network-tools.ps1` in the PowerShell profile root
- proxy profile commands: `proxy-profile-set`, `proxy-profile-show`, `proxy-profile-clear`
- remote access helpers: `remote-client-init`, `remote-server-bundle`, `remote-health`
- Shadowsocks helpers: `ss-source-show`, `ss-secret-discover`, `ss-secret-import`, `ss-secret-clear`, `ss-profile-new`, `ss-client-fetch`, `ss-client-open`, `ss-server-bundle`

## Managed state roots

- Network profile: `Toolkit\config\network-profile.json`
- Generated server bundle: `Toolkit\examples\remote-access-server`
- Managed SSH client config: `$HOME\.ssh\config.d\codex-network.conf`

## Client-side baseline

Run:

```powershell
remote-client-init -HostAlias labbox -HostName 203.0.113.10 -User admin
```

What it does:

- ensures `$HOME\.ssh\config` includes `config.d/*.conf`
- writes `codex-network.conf` with keepalives, connect timeout, host-key checking, and a ready-to-edit host alias
- keeps the config close to the local PowerShell + SSH environment instead of a Desktop folder

## Proxy profile

Run:

```powershell
proxy-profile-set -HttpsProxy http://proxy.example:8080 -NoProxy localhost,127.0.0.1
proxy-profile-show
```

Notes:

- values are stored in toolkit config, not sprayed into random scripts
- display output redacts embedded credentials
- only process-level proxy env vars are applied when a PowerShell session loads this profile

## Local-only Shadowsocks bootstrap

Run:

```powershell
ss-secret-discover
ss-secret-import -FetchWindowsClient -ExpandWindowsClient
```

What it does:

- looks for private config only on the current machine
- supports env vars, private text or JSON files, and existing local client configs
- writes the imported active secret only into `Toolkit\config\private\shadowsocks.active.json`
- keeps public source control clean while still letting the installed toolkit become genuinely usable on a private machine

## Server-side bundle

Run:

```powershell
remote-server-bundle
```

That generates:

- `Install-CodexRemoteAccessServer.ps1`
- `sshd_config.codex-optimized`
- `README.md`

The bundle targets Windows OpenSSH Server and uses safer defaults for unstable links:

- TCP keepalive plus SSH client-alive intervals
- key-based auth by default
- password bootstrap blocked unless explicitly requested
- forwarding, tunneling, and X11 disabled by default

## Connectivity checks

Run:

```powershell
remote-health -Host github.com -Port 22
remote-health -Host example.com -Port 443 -UseTls
```

This measures DNS lookup time, TCP connect time, and optional TLS metadata so you can tell whether the bottleneck is name resolution, raw reachability, or the TLS path.
