# Jellyfin

Jellyfin is an intranet service at https://jellyfin.atlas.home.arpa. Traefik
terminates HTTPS and applies the standard `secured@file` middleware (network
allowlist, rate limit, and HTTPS redirect). Authelia provides OIDC login. No host
port is published. Native clients use the same URL.

For TV clients without the homelab CA, use http://jellyfin.atlas.home.arpa
over WireGuard and sign in using Quick Connect. This temporary HTTP route keeps
the standard network allowlist and entrypoint rate limit, with higher priority
than Traefik's catch-all HTTPS redirect. HTTPS remains available at the original
URL. HTTP traffic is encrypted inside WireGuard, but not between its gateway
and Jellyfin. Remove the `jellyfin-http` router labels when no longer needed.

Start with `docker compose up -d`. Stop with `docker compose stop`.
Clients must trust the homelab CA and support the certificate and TLS settings
used by the existing Traefik service. LAN IPv4 and IPv6 HTTPS have been verified
through the router using a modern TLS client. Host-local
requests can receive 403 because Docker presents a gateway address
outside the standard allowlist; the router's curl also cannot negotiate the current
certificate. Shared Traefik configuration has not been changed for this stack.

The standard policy permits LAN, trusted WiFi, Cortex, and WireGuard over IPv4
and IPv6, plus Docker IPv4 sources (`172.16.0.0/12`). Guest and IoT networks are
excluded. Jellyfin and Traefik share the dedicated `jellyfin_traefik` network.
Other stacks cannot reach Jellyfin directly over this network; requests through
Traefik still use the standard allowlist.

## Authentication

Jellyfin uses OpenID Connect with Authelia, which authenticates against FreeIPA.
The `SSO-Auth` plugin from [danbro96/jellyfin-plugin-sso](https://github.com/danbro96/jellyfin-plugin-sso),
version 5.0.0.0 (Jellyfin 12 ABI), is installed in the configuration volume.
The LDAP plugin and its bind credentials have been removed from Jellyfin.
There is no Authelia ForwardAuth gate on the Jellyfin route.

### Sign in

In a browser, select **Sign in with Authelia**, or visit
https://jellyfin.atlas.home.arpa/sso/OID/start/authelia directly. Use your FreeIPA
credentials on Authelia. Authentication currently uses Authelia's `one_factor`
policy, matching the existing intranet services; OIDC alone does not add MFA.
The `ldap_ro` directory service account is denied by the client policy.

For Android TV or another client that does not offer browser SSO, select
**Quick Connect**, then approve its code from an already signed-in Jellyfin
browser under Settings → Quick Connect. Quick Connect remains enabled. Native
Android browser SSO is supported by this plugin fork; actual device compatibility
still needs checking. Direct username/password login to Jellyfin is disabled.

FreeIPA's `admins` group grants administrator access. Other users receive normal
viewing accounts with access to all libraries; media deletion and management
remain disabled for existing non-admin users. Group-derived administrator status
is refreshed at each SSO login, not continuously during an active session.
Existing usernames retain their Jellyfin IDs and watch history. All existing
accounts now use SSO-only authentication and previous device sessions have been
revoked. A preserved account without a matching FreeIPA username (currently
`brandon`) needs that directory identity or an explicit account link before it
can sign in through SSO. No local administrator or LDAP password login remains.

### TV account

FreeIPA user `tv` is a playback-only Jellyfin account. Its generated password is
stored in ignored `secrets/tv_password` (mode 600). Sign in as `tv` through
Authelia in a separate browser session, then approve the TV's Quick Connect code.
The account has no administrator, media deletion, download, Live TV, shared-device
control, or library-management permissions. Playback and transcoding are enabled.

In FreeIPA, `tv` has `/usr/sbin/nologin`, `/nonexistent` as its home, its own
unprivileged primary group, and no `ipausers`, `admins`, or application-role
membership. The `allow_all` and `allow_systemd-user` HBAC rules now allow only
`ipausers` and `admins`; all previously existing users remain covered. Vault's
LDAP and Kerberos user filters explicitly exclude `uid=tv`. Other Authelia apps
require privileged groups. Standard FreeIPA directory/self-service access still
exists; this account is not isolated from FreeIPA itself.

If recreating `tv`, remove its automatically assigned `ipausers` membership
before distributing its password. Do not restore `usercategory=all` on either
HBAC rule, as that would also admit this account to host services.

### Plugin configuration

Add the repository
`https://raw.githubusercontent.com/danbro96/jellyfin-plugin-sso/manifest-release/manifest.json`
in Dashboard → Plugins → Repositories, install SSO-Auth 5.0.0.0, and restart.
The installed archive was checked against manifest MD5
`88f964a08c20bce65a9404afbd5b270e`. Configure provider `authelia`:

| Setting | Value |
| --- | --- |
| OIDC endpoint | `https://authelia.atlas.home.arpa` |
| Client ID | `jellyfin` |
| Client secret | Private `secrets/oidc_client_secret` |
| Enabled / authorization / all folders | Enabled / enabled / enabled |
| Admin roles / role claim | `admins` / `groups` |
| Required roles | Empty (all users admitted by Authelia's client policy) |
| Additional scopes | `groups` (the plugin also requests `openid profile`) |
| Username claim | `preferred_username` |
| Default provider | `Jellyfin.Plugin.SSO_Auth.Api.SSOController` |
| Scheme override / new path | `https` / enabled |
| Disable pushed authorization | Enabled |
| Disable HTTPS / skip endpoint or issuer validation | All disabled |
| Live TV access / management | Disabled / disabled |

The callback is `https://jellyfin.atlas.home.arpa/sso/OID/redirect/authelia`.
Authelia requires PKCE S256 and `client_secret_post`. Its client definition is
tracked in `../authelia/config/configuration.yml`; its PBKDF2 secret digest is
mounted from ignored `../authelia/secrets/oidc_jellyfin_client_secret_digest`.
The digest file needs read access for remapped container UID 101000.

The plugin stores the raw OIDC secret and account links in writable
`/config/plugins/configurations/SSO-Auth.xml` (mode 600). It does not support a
secret-file field. The private source secret is ignored by Git. Back up the
configuration volume securely: the XML and backups contain credentials.
Before migration, configuration, database, and plugins were backed up to
`secrets/before-oidc.tar.gz`. Restoring that backup also restores LDAP and the
previous sessions; stop Jellyfin before restoring. Historical local password
files are not active login credentials.

## Media and hardening

The host directory `/scratch/qbittorrent` is mounted read-only at `/media`.
Use `/media` paths in Dashboard → Libraries. Configuration and cache use Docker
volumes. UID 1000 maps to host UID 101000, matching the media owner. All Linux
capabilities are dropped, privilege escalation is blocked, and the root
filesystem is read-only. The service has a 2 GiB memory limit and four CPUs.
No GPU is exposed, so transcoding uses the CPU.

Jellyfin trusts forwarded headers from the dedicated `jellyfin_traefik` IPv4
and IPv6 subnets. Set Known Proxies in Dashboard → Networking to the subnets
reported by `docker network inspect jellyfin_traefik`; update them if the network
is recreated with different subnets. The previous Cloudflare connector, public
DNS record, and tunnel have been removed, along with their Terraform configuration.
