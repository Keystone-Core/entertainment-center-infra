# Website of the Centre de divertissement de l'Estrie

The centre's public website, in French, running on the `k3s01` cluster as a LAMP stack (Apache, PHP 8.4, MariaDB 11.8) with phpMyAdmin.

| Part | Runs as | Address |
| ---- | ------- | ------- |
| Apache + PHP 8.4 (FPM) | Deployment `php`, image `serversideup/php` | `https://www.divertissementestrie.ca` (Caddy, then Traefik) |
| MariaDB 11.8 | Deployment `mariadb`, PVC `mariadb-data` | Service `mariadb:3306`, inside the cluster only |
| phpMyAdmin 5.2 | Deployment `phpmyadmin` | `https://phpmyadmin.divertissementestrie.ca` (Caddy, then Traefik) |
| Posters | PVC `uploads` | Mounted on the `php` pod, outside the web root |
| Sessions | PVC `sessions` | Mounted on the `php` pod, so a restart logs no one out |

## What the site does

| Audience | Pages |
| -------- | ----- |
| Everyone | Home page with tonight's screenings on a letter board, the week's schedule (`/programmation`), film pages (`/films/<slug>`), game servers (`/jeux`), public workstations (`/postes`), hours and prices (`/infos`) |
| Customers | Account creation and login, seat reservations (up to 6 per screening, capped by the room's capacity), tickets with a booking code, cancellation until the screening starts (`/compte`), a forgotten password (`/mot-de-passe-oublie`) |
| Staff | `/gestion`: today's screenings with the front-desk list, screenings (a room can't be double-booked), films with poster uploads, announcements, accounts, game servers, a link to phpMyAdmin |

**Forgotten passwords** work with one-time links, valid 24 hours. A customer asks for one at `/mot-de-passe-oublie` and gets it by email, at most once every 5 minutes. The page gives the same answer whether the account exists or not. The staff can also create a link from `/gestion/comptes` and give it at the front desk or by phone. Only a hash of each link is stored.

**Accounts** (`/gestion/comptes`): search by name or email, create a password link, give or take back the staff section, delete an account with its reservations. A staff member can't change or delete their own account, so the centre can't lose its last staff access by mistake.

`/status` is a JSON health check for the smoke test and monitoring. Staff see the details; everyone else sees only pass or fail.

## Code

| Path | Contents |
| ---- | -------- |
| [`site/public/`](site/public/) | The web root: `index.php` (the router), `.htaccess`, the stylesheet, the fonts and the favicon |
| [`site/app/`](site/app/) | The rest of the PHP code, outside the web root: `core.php` (database, French formatting, rules), `web.php` (session, accounts, CSRF), the pages (`public.php`, `account.php`, `admin.php`), `layout.php`, `views.php` and `cli.php` |
| [`site/app/content.php`](site/app/content.php) | The centre's practical information: address, phone, email, hours and prices. The centre is fictional, so these values are invented (the phone number is in the 555-01xx range reserved for fiction): change them there |
| [`schema.sql`](schema.sql) | The tables and the starting content (two rooms, seven classic films, three game servers, two announcements) |
| [`site/licenses/`](site/licenses/) | Licenses of the two fonts (SIL Open Font License) |

Kustomize turns `site/public/`, `site/app/` and `schema.sql` into ConfigMaps. Editing a file and applying again rolls out the `php` pod.

The schema only runs the first time MariaDB starts with an empty volume. To change a table later, use phpMyAdmin, then update `schema.sql` so a fresh install matches.

The table `password_resets` was added on November 11, 2026. A database created before that date needs it once (run on `ctrl-iac`; `/status` reports it missing until then):

```bash
sed -n '/^CREATE TABLE password_resets/,/;$/p' k8s/web/schema.sql \
  | sed 's/CREATE TABLE/CREATE TABLE IF NOT EXISTS/' \
  | kubectl -n web exec -i deploy/mariadb -- sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot site'
```

## Deploying

Everything runs on `ctrl-iac`, from a copy of this folder (see the [k3s guide](../../docs/guides/deploying-services-on-k3s.md)).

The database passwords are in the Secret `web-db`, which isn't in the repository. Create it once, before the first apply:

```bash
kubectl apply -f k8s/web/namespace.yaml
kubectl -n web create secret generic web-db \
  --from-literal=root-password="$(openssl rand -base64 24)" \
  --from-literal=password="$(openssl rand -base64 24)"
```

Then apply the folder and wait for the pods:

```bash
kubectl apply -k k8s/web
kubectl -n web rollout status deploy/mariadb deploy/php deploy/phpmyadmin
```

### Email (optional)

Without email, the site works the same: the forgotten-password form answers normally, and the staff give the links from `/gestion/comptes`. To send the links by email, create an account for the site on mail01 (hMailServer, `10.10.20.201`, submission on port 587, TLS not in use), then the Secret `web-smtp`, and restart the `php` pod:

```bash
read -rs SMTP_PASSWORD
kubectl -n web create secret generic web-smtp \
  --from-literal=host=10.10.20.201 --from-literal=port=587 \
  --from-literal=user=site@divertissementestrie.ca --from-literal=password="$SMTP_PASSWORD" \
  --from-literal=from=no-reply@divertissementestrie.ca
unset SMTP_PASSWORD
kubectl -n web rollout restart deploy/php
```

The site logs a refused message in the `php` pod's logs (`kubectl -n web logs deploy/php`).

## Admin commands

`cli.php` runs inside the `php` pod:

```bash
php_cli() { kubectl -n web exec deploy/php -- php /var/www/html/app/cli.php "$@"; }

php_cli staff alexy@example.com        # give an account access to /gestion
php_cli client alexy@example.com       # remove that access
php_cli delete-user alexy@example.com  # delete an account and its reservations
php_cli reset-link alexy@example.com   # print a one-time link to choose a new password
php_cli demo                           # add demo screenings for the next 7 days
```

To get the first staff account, create an account on the site (`/inscription`), then run `staff` with its email.

`demo` fills the next seven days around the opening hours. It skips Mondays and never overlaps a screening that's already planned, so it's safe to run again before a presentation.

## Testing

[`smoke-test.sh`](smoke-test.sh) runs through the whole site with curl. It runs on `ctrl-iac` and sends its requests straight to Traefik, so it needs neither DNS nor `proxy01`. It uses HTTPS on port 443 (Traefik's self-signed certificate): from VLAN 10 the firewall blocks HTTP to `k3s01`.

```bash
sh k8s/web/smoke-test.sh
```

It visits the public pages and creates customer and staff accounts. It resets a password with a link from the staff, gives and takes back the staff section, and deletes an account. It adds a film with a poster and checks that a PHP file is refused as a poster. It fills a room, cancels a reservation, and finally deletes everything it created.

To work on the site without the cluster, run the same images with Docker:

```bash
docker network create cde-test
docker run -d --name cde-db --network cde-test -e MARIADB_DATABASE=site -e MARIADB_USER=site \
  -e MARIADB_PASSWORD=dev -e MARIADB_RANDOM_ROOT_PASSWORD=1 \
  -v "$PWD/k8s/web/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro" mariadb:11.8.9
docker run -d --name cde-php --network cde-test -p 127.0.0.1:80:8080 \
  -e DB_HOST=cde-db -e DB_NAME=site -e DB_USER=site -e DB_PASSWORD=dev -e TRUSTED_PROXY=local \
  -e PHP_DATE_TIMEZONE=America/Toronto -e PHP_UPLOAD_MAX_FILE_SIZE=20M -e PHP_POST_MAX_SIZE=25M \
  -v "$PWD/k8s/web/site/public:/var/www/html/public:ro" -v "$PWD/k8s/web/site/app:/var/www/html/app:ro" \
  -v cde-uploads:/var/www/html/storage/uploads serversideup/php:8.4-fpm-apache-trixie-v5.0.3
docker exec cde-php php /var/www/html/app/cli.php demo
SCHEME=http PHP_EXEC="docker exec cde-php" sh k8s/web/smoke-test.sh 127.0.0.1   # phpMyAdmin check fails: not started
```

## phpMyAdmin

Log in with the `site` account, or `root` for full access. To read a password on `ctrl-iac` (don't paste it anywhere):

```bash
kubectl -n web get secret web-db -o jsonpath='{.data.password}' | base64 -d; echo
```

## Backups (task T5.2)

`sauvegarde-site` backs up the database and the posters every night at 03:15 (Québec time), from `ctrl-iac`. The role [`sauvegarde_site`](../../ansible/roles/sauvegarde_site) installs it with a systemd timer:

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook sauvegarde-site.yml
```

| Item | Value |
| ---- | ----- |
| Script | [`sauvegarde-site`](../../ansible/roles/sauvegarde_site/files/sauvegarde-site), in `/usr/local/sbin` on `ctrl-iac` |
| Schedule | `sauvegarde-site.timer`, every night at 03:15 (a missed night runs at the next start) |
| Content | `site.sql.gz` (`mariadb-dump --single-transaction`, without locking the site), `affiches.tar.gz`, `SHA256SUMS` |
| Location | `/root/sauvegardes/site/<date>/` on `ctrl-iac` (mode 700), kept 14 days |
| Check | Each dump is loaded into a scratch database (`site_verif`) and must give every table, or the backup is refused |
| Logs | `journalctl -u sauvegarde-site` |

```bash
sauvegarde-site                      # back up now
sauvegarde-site list                 # list the backups
sauvegarde-site restore <date>       # replace the database and posters (asks to type OUI)
```

A restore checks the SHA-256 sums first, then replaces the tables and the posters. It was tested on November 11, 2026: a poster deleted after a backup came back.

## Development server (web01)

`web01` runs the same site on Apache 2.4, PHP 8.4 and MariaDB 11.8 installed by the role [`lamp`](../../ansible/roles/lamp), the same versions as the containers. It has its own database, so tests there never touch the real reservations. It's the "web development server" of the functional specification (Fp5).

| Item | Value |
| ---- | ----- |
| Address | `http://10.10.20.21`, from VLAN 20 (staff and room workstations). It isn't published by `proxy01` |
| Code | `/var/www/html/public` and `/var/www/html/app`, copied from this folder |
| Database | `site` on web01, created from `schema.sql`; password in `/root/.cde-secrets/web01/base-site` on `ctrl-iac` |
| Commands | `sudo cde-env php /var/www/html/app/cli.php staff <email>` on web01 |

To try a change, push it to a branch and update web01 from `ctrl-iac`, then run the smoke test there:

```bash
cd /root/entertainment-center-infra/ansible && ansible-playbook lamp.yml
scp -i ~/.ssh/ansible_cde k8s/web/smoke-test.sh ansible@10.10.20.21: && ssh -i ~/.ssh/ansible_cde ansible@10.10.20.21 \
  'SCHEME=http PMA= PHP_EXEC="sudo cde-env" sh smoke-test.sh 127.0.0.1'
```

The role only creates the schema on a new database: a table change needs the same step as on k3s01, on web01's MariaDB.

## Not done yet

- **Email:** the forgotten-password emails need an account for the site on mail01 (J. Leclerc) and the Secret `web-smtp`. For customers outside the centre, mail01 must also be able to deliver mail to the Internet (rules 11 and 12 on fw01). Until then, the staff give the links.
- **Backups off the Proxmox host:** the copies are on `ctrl-iac`, which runs on the same physical server as `k3s01`. Veeam (`bkp01`) could also copy `/root/sauvegardes`.
- **Demo screenings** stay manual: `php_cli demo` before a presentation.
