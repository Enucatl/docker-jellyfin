# Jellyfin

Jellyfin is configured for https://jellyfin.enucatl.com, with read-only media from
`/scratch/qbittorrent` mounted at `/media`. Configuration and cache use Docker
volumes. This host remaps container UID 1000 to host UID 101000, matching the
media owner. The service has a 2 GiB memory limit and four CPUs.

Jellyfin manages its own accounts. Use a separate non-admin user for watching.
TV clients can sign in with username/password or supported Quick Connect.
No Cloudflare Access login is added, to preserve native client compatibility.
The initial admin password is stored locally in `secrets/admin_password`;
change it after signing in. Never publish an unfinished setup wizard.

Local start: `docker compose up -d jellyfin`.
After provisioning the tunnel and token: `docker compose --profile public up -d`.
The tunnel and DNS record have been provisioned.
LAN endpoint: `http://atlas.home.arpa:8096` (`http://10.0.0.158:8096`).
No GPU is exposed on this host, so transcoding uses the CPU.

## Tunnel

Terraform follows the neighboring Cloudflare tunnel projects. Credentials come
from Vault `kv/puppet`; never commit credentials, tokens, plans, or state.
The API token must have Cloudflare One Connector: cloudflared Edit permission
for the account and DNS Edit permission for the enucatl.com zone. The new token
is currently stored as `TOKEN` in the ignored `.env` file.

```sh
cd terraform
. ../.env
export CLOUDFLARE_API_TOKEN="$TOKEN"
export TF_VAR_account_id="$(vault kv get -field=cloudflare_account_id kv/puppet)"
export TF_VAR_zone_id="$(vault kv get -field=cloudflare_zone_id kv/puppet)"
terraform init
terraform plan -out=jellyfin.tfplan
terraform apply jellyfin.tfplan
(umask 077; terraform output -raw tunnel_token > ../secrets/tunnel_token)
setfacl -m u:165532:r ../secrets/tunnel_token
```

The ACL lets cloudflared's UID 65532 (host UID 165532 with this host's Docker
remapping) read the token without making it world-readable.

Back up local Terraform state and the configuration volume securely.
Cloudflare restricts video delivery through public Tunnel hostnames on standard
plans unless using an appropriate paid service; bypassing cache does not remove
that restriction. See https://developers.cloudflare.com/cloudflare-one/faq/cloudflare-tunnels-faq/.
