# Jellyfin

Jellyfin is an intranet service at https://jellyfin.atlas.home.arpa. Traefik
terminates HTTPS and applies the standard `secured@file` middleware (network
allowlist, rate limit, and HTTPS redirect). Authelia is not used. No host port is
published. Native clients use the same URL and authenticate directly to Jellyfin.

Start with `docker compose up -d`. Stop with `docker compose stop`.
Clients must trust the homelab CA and support the certificate and TLS settings
used by the existing Traefik service. LAN IPv4 and IPv6 HTTPS have been verified
through the router using a modern TLS client. Host-local
requests can receive 403 because Docker presents a gateway address
outside the standard allowlist; the router's curl also cannot negotiate the current
certificate. Shared Traefik configuration has not been changed for this stack.

The standard policy permits LAN, trusted WiFi, Cortex, and WireGuard over IPv4
and IPv6, plus Docker IPv4 sources (`172.16.0.0/12`). Guest and IoT networks are
excluded. Other containers on the shared `traefik_proxy` network can still reach
Jellyfin directly; the allowlist protects requests entering through Traefik.

## Authentication

The official LDAP Authentication plugin, version 24.0.0.0, is installed in the
persistent configuration volume. It uses FreeIPA directly over verified LDAPS.
Configure it through Dashboard → Plugins → LDAP-Auth:

| Setting | Value |
| --- | --- |
| Server / port | `ipa.home.arpa` / `636` |
| Secure LDAP / StartTLS / skip certificate verification | Enabled / disabled / disabled |
| Root CA path | `/etc/ipa/ca.crt` |
| Bind user | `uid=ldap_ro,cn=users,cn=accounts,dc=home,dc=arpa` |
| User and admin base DN | `cn=users,cn=accounts,dc=home,dc=arpa` |
| User filter | `(&(objectClass=posixAccount)(!(nsAccountLock=TRUE))(!(uid=ldap_ro)))` |
| Admin filter | `(&(objectClass=posixAccount)(memberOf=cn=admins,cn=groups,cn=accounts,dc=home,dc=arpa))` |
| Search attributes / username attribute | `uid` / `uid` |
| Stable ID attribute | `ipaUniqueID` |
| Create LDAP users / access all libraries | Enabled / enabled |
| Allow password changes / memberUid admin filter | Disabled / disabled |

The bind password uses the existing read-only directory account, also used by
Authelia, and is saved privately in the plugin's configuration volume. No LDAP
password is committed. The CA and system trust bundle are mounted read-only.

Sign in with a FreeIPA username and password. LDAP users are created on first
login. Membership of FreeIPA's `admins` group grants Jellyfin administration;
admin status is refreshed at each LDAP login, not continuously during a session.
The existing `admin` account uses LDAP authentication and LDAP password reset;
its former local password is no longer accepted. There is no local administrator.
The existing non-admin `brandon` account and its watch history are preserved.
LDAP-bound accounts cannot use Jellyfin to change directory passwords.

Before migration, configuration, database, and plugins were backed up locally to
`secrets/before-ldap.tar.gz`. Backups contain sensitive data; keep them private.
The original local password file is historical and does not authenticate the
LDAP admin account. Back up the configuration volume securely, including plugin
settings. Restoring the pre-migration backup also restores local authentication.

## Media and hardening

The host directory `/scratch/qbittorrent` is mounted read-only at `/media`.
Use `/media` paths in Dashboard → Libraries. Configuration and cache use Docker
volumes. UID 1000 maps to host UID 101000, matching the media owner. All Linux
capabilities are dropped, privilege escalation is blocked, and the root
filesystem is read-only. The service has a 2 GiB memory limit and four CPUs.
No GPU is exposed, so transcoding uses the CPU.

Jellyfin trusts forwarded headers from the existing `traefik_proxy` IPv4 subnet
`172.16.32.0/20`. Update Known Proxies in Dashboard → Networking if that subnet
changes. The previous Cloudflare connector, public DNS record, and tunnel have
been removed, along with their Terraform configuration.
