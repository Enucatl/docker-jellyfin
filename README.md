# Jellyfin

Private media server: https://jellyfin.atlas.home.arpa.

## Start and stop

```sh
docker compose up -d
docker compose stop
```

Traefik must be running. Puppet configures automatic deployment when
`origin/main` changes. The deployment pulls the image, restarts Jellyfin, and
checks its health. A monthly timer also refreshes the service.

## Sign in

- **Browser:** Select **Sign in with Authelia**. Use your FreeIPA account.
- **TV or native client:** Select **Quick Connect**. In a signed-in browser,
  open **Settings → Quick Connect** and approve the code.
- **Shared TV:** Sign in as `tv` in a separate browser session. Then approve
  the TV code. The password is in `secrets/tv_password`.

Direct Jellyfin password login is disabled. Authelia uses its `one_factor`
policy. FreeIPA members of `admins` get administrator access at SSO login.
Other users can view all libraries. The `tv` account has playback access only.
Existing accounts keep their watch history. An account without a matching
FreeIPA username needs a directory identity or an explicit SSO account link.

## Network access

Use HTTPS with a client that trusts the homelab CA. LAN, trusted WiFi, Cortex,
WireGuard, and Docker IPv4 sources are allowed. Guest and IoT networks are blocked.
No container port is published on the host.

For TVs without the homelab CA, use http://jellyfin.atlas.home.arpa over
WireGuard, then sign in with Quick Connect. This temporary route uses the same
network allowlist. Traffic between the WireGuard gateway and Jellyfin is not
encrypted. Remove the `jellyfin-http` router labels when this route is no longer
needed.

Jellyfin and Traefik share the `jellyfin_traefik` network. In **Dashboard →
Networking → Known Proxies**, enter its IPv4 and IPv6 subnets. Check them with:

```sh
docker network inspect jellyfin_traefik
```

Update Known Proxies if the subnets change. Host-local requests can return 403
when Docker uses a gateway address outside the allowlist.

## Media and storage

Add library paths under `/media` in **Dashboard → Libraries**.

| Data | Storage |
| --- | --- |
| Media, read-only | Host `/scratch/qbittorrent`, mounted at `/media` |
| Configuration and users | Docker volume `config` |
| Cache | Docker volume `cache` |

The container runs as UID/GID 1000, mapped to host UID 101000. It has a read-only
root filesystem, no Linux capabilities, a 2 GiB memory limit, and four CPUs.
Transcoding uses the CPU; no GPU is exposed.

## SSO setup and recovery

Use **SSO-Auth 5.0.0.0** from
[danbro96/jellyfin-plugin-sso](https://github.com/danbro96/jellyfin-plugin-sso)
(Jellyfin 12 ABI). Add this repository in **Dashboard → Plugins → Repositories**,
install the plugin, then restart Jellyfin:

```text
https://raw.githubusercontent.com/danbro96/jellyfin-plugin-sso/manifest-release/manifest.json
```

Configure provider `authelia`:

| Setting | Value |
| --- | --- |
| OIDC endpoint | `https://authelia.atlas.home.arpa` |
| Client ID | `jellyfin` |
| Client secret | Contents of `secrets/oidc_client_secret` |
| Enabled / authorization / all folders | All enabled |
| Admin roles / role claim | `admins` / `groups` |
| Required roles | Empty |
| Additional scopes | `groups` |
| Username claim | `preferred_username` |
| Default provider | `Jellyfin.Plugin.SSO_Auth.Api.SSOController` |
| Scheme override / new path | `https` / enabled |
| Disable pushed authorization | Enabled |
| Disable HTTPS / skip endpoint or issuer validation | All disabled |
| Live TV access / management | Both disabled |

The callback URL is
`https://jellyfin.atlas.home.arpa/sso/OID/redirect/authelia`.
Authelia requires PKCE S256 and `client_secret_post`. Its client settings are in
`../authelia/config/configuration.yml`. Its secret digest is in
`../authelia/secrets/oidc_jellyfin_client_secret_digest`; remapped container UID
101000 must be able to read it.

Back up the configuration volume securely. The plugin stores the raw client
secret and account links in `/config/plugins/configurations/SSO-Auth.xml`
(mode 600). It cannot read the secret from a separate file.

The migration backup is `secrets/before-oidc.tar.gz`. Stop Jellyfin before you
restore it. This backup also restores LDAP login and old device sessions.

If you recreate the FreeIPA `tv` account, remove its default `ipausers` membership
before you share the password. Keep its shell as `/usr/sbin/nologin` and its home
as `/nonexistent`. Do not set `usercategory=all` on the `allow_all` or
`allow_systemd-user` HBAC rules. Vault must continue to exclude `uid=tv`.
The account still has standard FreeIPA directory and self-service access.
