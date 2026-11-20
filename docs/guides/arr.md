# \*arr Suite and qBittorrent

`media01` runs the \*arr suite next to Jellyfin (task T7.2):

- **Prowlarr** manages the indexers, the sites that are searched for releases.
- **Sonarr** (series) and **Radarr** (films) find episodes and films, then file them where Jellyfin reads them.
- **qBittorrent** downloads them.

The `arr` Ansible role ([`ansible/arr.yml`](../../ansible/arr.yml)) installs the four, secures them and links them together.

| Application | Use       | Address (VLANs 10 and 20)                    | Port on `media01` | Version         |
| ----------- | --------- | -------------------------------------------- | ----------------- | --------------- |
| Sonarr      | Series    | `https://sonarr.divertissementestrie.ca`      | 8989              | 4.0.20          |
| Radarr      | Films     | `https://radarr.divertissementestrie.ca`      | 7878              | 7.0.3           |
| Prowlarr    | Indexers  | `https://prowlarr.divertissementestrie.ca`    | 9696              | 3.0.2           |
| qBittorrent | Downloads | `https://qbittorrent.divertissementestrie.ca` | 8080              | 5.1.0 (Debian)  |

| Item     | Value                                                                                                   |
| -------- | ------------------------------------------------------------------------------------------------------- |
| Host     | `media01` (VM 2040), `10.10.20.40`, VLAN 20, 4 vCPU, 4 GB RAM                                           |
| Account  | `admin` in all four. Password generated on `ctrl-iac`: `/root/.cde-secrets/media01/arr-admin`           |
| API keys | On `ctrl-iac`: `/root/.cde-secrets/media01/sonarr-api`, `radarr-api` and `prowlarr-api`                 |
| Media    | `/srv/media/films` and `/srv/media/series` (Jellyfin's libraries), `/srv/media/telechargements` (qBittorrent), all on the 250 GB media disk |
| Data     | `/var/lib/sonarr`, `/var/lib/radarr`, `/var/lib/prowlarr`, `/var/lib/qbittorrent`                       |
| Programs | `/opt/Sonarr`, `/opt/Radarr`, `/opt/Prowlarr`; `qbittorrent-nox` (Debian package)                       |

## No Indexer (Team Decision)

No indexer is configured (team decision, November 20, 2026). Until someone adds one in Prowlarr, nothing can be searched or downloaded. Before adding one:

- `media01` only reaches the Internet on the web ports (rule 10: 80 and 443). Torrent trackers and peers use other ports, so qBittorrent can only download from web seeds: web addresses that some torrents include as a source.
- Internet Archive (public domain films) works within these limits. Its torrents have web seeds on `archive.org`, which the cégep's DNS filter doesn't block (tested from `media01` on November 20, 2026). Prowlarr lists it as a public indexer, *Internet Archive*.
- Only add sources for content the centre has the right to download.

## The `arr` Role

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook arr.yml
```

- **Sonarr, Radarr, Prowlarr**: official archives from GitHub, at the versions pinned in `arr_applications` (`roles/arr/defaults/main.yml`). Each archive is checked against the SHA-256 checksum that GitHub publishes with the release. The role installs them in `/opt` only once; after that they update themselves (*System → Updates*), since each folder in `/opt` belongs to its application's user.
- **qBittorrent**: the Debian package `qbittorrent-nox`, with its own systemd unit (`qbittorrent.service`) and its profile in `/var/lib/qbittorrent`.
- **Users and permissions**: each application runs as its own system user in the `media` group (GID 2000, the same as Jellyfin; the `jellyfin` role creates it too), with umask 002. Jellyfin can read what they import, and Sonarr and Radarr import downloads by hard link: no copy, and no extra space used.
- **First configuration**: `config.xml` (Sonarr, Radarr, Prowlarr) and `qBittorrent.conf` are only written if they don't exist, since the applications rewrite them. They take the API key generated on `ctrl-iac`. qBittorrent only keeps a PBKDF2 hash of the password.
- **Links** ([`files/relier-arr.py`](../../ansible/roles/arr/files/relier-arr.py)): the script uses the applications' local APIs and only adds what's missing:
  - the `admin` account with the login form in Sonarr, Radarr and Prowlarr;
  - the root folders: `/srv/media/series` in Sonarr, `/srv/media/films` in Radarr;
  - qBittorrent as the download client of all three, each in its own category (`series`, `films`, `prowlarr`), so the downloads land in `/srv/media/telechargements/<category>`;
  - Sonarr and Radarr as Prowlarr applications, with full sync: an indexer added in Prowlarr appears in both.
- Running the role again changes nothing (`changed=0`). It doesn't reset a password changed in an application, since the account already exists.

## Network

| Flow                                            | Rule                                                                 |
| ----------------------------------------------- | -------------------------------------------------------------------- |
| VLANs 10 and 20 → the four sites                | Caddy on `proxy01`; the names resolve on `fw01` and `dc01`           |
| `proxy01` → `media01` on 7878, 8080, 8989, 9696 | Rule 4 (`PORTS_HTTP`), already in place                              |
| Other VLANs → those ports                       | Blocked: only `proxy01` reaches them                                 |
| `media01` → Internet                            | Web only (rule 10): metadata (TheMovieDB, TheTVDB) and updates       |

Sonarr, Radarr and Prowlarr only believe the `X-Forwarded-Proto` header from their own machine. Behind `proxy01`, they would redirect the browser to `http://…/login`, and port 80 isn't open. Their Caddy sites use the `corriger_http` key, which rewrites those redirects to `https://` ([Publishing Services with Caddy](publishing-services-with-caddy.md)).

## Using the Suite

1. Log in as `admin`. On `ctrl-iac`, `cat /root/.cde-secrets/media01/arr-admin` shows the password.
2. To change the password: *Settings → General → Security* in Sonarr, Radarr and Prowlarr; *Tools → Options → WebUI* in qBittorrent. If you change qBittorrent's, update it in the qBittorrent download client of all three (*Settings → Download Clients*).
3. Add an indexer in Prowlarr (*Indexers → Add Indexer*): it syncs to Sonarr and Radarr.
4. In Radarr (or Sonarr), add a film (or a series) and search for it. qBittorrent downloads it, then Radarr files it in `/srv/media/films`. Jellyfin shows it after its next library scan (*Dashboard → Scan All Libraries* to do it right away).

## Checking

```bash
ssh -i ~/.ssh/ansible_cde ansible@10.10.20.40                 # from ctrl-iac
systemctl status sonarr radarr prowlarr qbittorrent
curl -s http://127.0.0.1:8989/ping                            # {"status": "OK"}
sudo ls /var/lib/sonarr/logs/                                 # each application's logs
ls -la /srv/media/telechargements
```
