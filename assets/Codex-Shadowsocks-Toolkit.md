# Codex Shadowsocks Toolkit

This guide explains the Shadowsocks helpers that are seeded from the official URLs in `Desktop\lia.txt`.

## Official sources

- `https://github.com/shadowsocks`
- `https://shadowsocks.org/`

The toolkit reads `lia.txt` if it exists and uses those URLs as the source anchors for release discovery and documentation.

## New commands

- `ss-source-show`
- `ss-secret-discover`
- `ss-secret-import`
- `ss-secret-clear`
- `ss-profile-new`
- `ss-client-fetch`
- `ss-client-open`
- `ss-server-bundle`

## Private secret import

If this machine already has real private Shadowsocks details, keep them out of the public repo and let the toolkit import them locally:

```powershell
ss-secret-discover
ss-secret-import -FetchWindowsClient -ExpandWindowsClient
```

Supported discovery sources include:

- `CODEX_SS_URI`
- `CODEX_SS_SERVER`, `CODEX_SS_PORT`, `CODEX_SS_METHOD`, `CODEX_SS_PASSWORD`
- private local files such as `Desktop\lia.private.txt` or `Desktop\lia.private.json`
- existing local Windows Shadowsocks client configs

The imported active secret is written only to:

- `Toolkit\config\private\shadowsocks.active.json`

## Client workflow

Download and expand the official Windows client:

```powershell
ss-client-fetch -Expand
```

Generate matching client and server configs in official JSON format:

```powershell
ss-profile-new -Name dorm-link -Server 203.0.113.8
```

That writes config files under:

- `Toolkit\config\shadowsocks\profiles`

It also returns a SIP002 URI that many clients can import directly.

## Server workflow

Generate a pinned `shadowsocks-rust` bundle:

```powershell
ss-server-bundle -Name dorm-link
```

That writes:

- `install-shadowsocks-rust.sh`
- `config.server.json`
- `shadowsocks-rust.service`

under:

- `Toolkit\examples\shadowsocks-rust-server`

## Notes

- The default method is `chacha20-ietf-poly1305`, which is one of the recommended AEAD ciphers in the official docs.
- A real working deployment still needs a real server address and an opened TCP/UDP port on the remote machine.
