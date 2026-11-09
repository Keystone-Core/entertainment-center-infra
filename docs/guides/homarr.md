# Homarr Dashboard

`dash01` runs Homarr in a Docker container. The `homarr` Ansible role ([`ansible/homarr.yml`](../../ansible/homarr.yml)) installs Docker, deploys the Compose file and starts the container.

| Item      | Value                                                                             |
| --------- | --------------------------------------------------------------------------------- |
| Host      | `dash01` (VM 2041), `10.10.20.41`, VLAN 20, 2 vCPU, 2 GB RAM, 8 GB disk           |
| Address   | `https://homarr.divertissementestrie.ca` from VLANs 10 and 20; `http://10.10.20.41:7575` from VLAN 20 |
| Folder    | `/opt/homarr`: `docker-compose.yml`, `.env` and `appdata/`                        |
| Image     | `ghcr.io/homarr-labs/homarr:latest`                                               |
| Secret    | `SECRET_ENCRYPTION_KEY` in `/opt/homarr/.env` (mode 600), never in the repository |

## Applying the role

On `ctrl-iac`:

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook homarr.yml --check --diff    # shows what would change
ansible-playbook homarr.yml
```

The role only creates `.env` if it doesn't exist, so running it again never changes the encryption key. Compose recreates the container only when `docker-compose.yml` has changed.

## Backing up

`appdata/` holds the dashboard and its users, and `.env` holds the key that decrypts them: keep both together. Without the key, the data can't be read.

## Status

As of November 9, 2026:

- **The image follows `latest`,** so a `docker-compose pull` can bring a new version. Pin a version before relying on it for the final demonstration.
- A local `admin` account with `sudo` was created by hand on `dash01`. It isn't managed by Ansible.
