# Website of the Centre de divertissement de l'Estrie

The centre's public website, in French, running on the `k3s01` cluster as a LAMP stack (Apache, PHP 8.4, MariaDB 11.8) with phpMyAdmin.

| Part | Runs as | Address |
| ---- | ------- | ------- |
| Apache + PHP 8.4 (FPM) | Deployment `php`, image `serversideup/php` | `https://www.divertissementestrie.ca` (Caddy, then Traefik) |
| MariaDB 11.8 | Deployment `mariadb`, PVC `mariadb-data` | Service `mariadb:3306`, inside the cluster only |
| phpMyAdmin 5.2 | Deployment `phpmyadmin` | `https://phpmyadmin.divertissementestrie.ca` (Caddy, then Traefik) |
| Posters | PVC `uploads` | Mounted on the `php` pod, outside the web root |

## What the site does

| Audience | Pages |
| -------- | ----- |
| Everyone | Home page with tonight's screenings on a letter board, the week's schedule (`/programmation`), film pages (`/films/<slug>`), game servers (`/jeux`), public workstations (`/postes`), hours and prices (`/infos`) |
| Customers | Account creation and login, seat reservations (up to 6 per screening, capped by the room's capacity), tickets with a booking code, cancellation until the screening starts (`/compte`) |
| Staff | `/gestion`: today's screenings with the front-desk list, screenings (a room can't be double-booked), films with poster uploads, announcements, game servers, a link to phpMyAdmin |

`/status` is a JSON health check for the smoke test and monitoring. Staff see the details; everyone else sees only pass or fail.

## Code

| Path | Contents |
| ---- | -------- |
| [`site/public/`](site/public/) | The web root: `index.php` (the router), `.htaccess`, the stylesheet, the fonts and the favicon |
| [`site/app/`](site/app/) | The rest of the PHP code, outside the web root: `core.php` (database, French formatting, rules), `web.php` (session, accounts, CSRF), the pages (`public.php`, `account.php`, `admin.php`), `layout.php`, `views.php` and `cli.php` |
| [`site/app/content.php`](site/app/content.php) | Hours, prices and phone number. **These are placeholders**: change them there |
| [`schema.sql`](schema.sql) | The tables and the starting content (two rooms, seven classic films, three game servers, two announcements) |
| [`site/licenses/`](site/licenses/) | Licenses of the two fonts (SIL Open Font License) |

Kustomize turns `site/public/`, `site/app/` and `schema.sql` into ConfigMaps. Editing a file and applying again rolls out the `php` pod.

The schema only runs the first time MariaDB starts with an empty volume. To change a table later, use phpMyAdmin, then update `schema.sql` so a fresh install matches.

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

## Admin commands

`cli.php` runs inside the `php` pod:

```bash
php_cli() { kubectl -n web exec deploy/php -- php /var/www/html/app/cli.php "$@"; }

php_cli staff alexy@example.com        # give an account access to /gestion
php_cli client alexy@example.com       # remove that access
php_cli delete-user alexy@example.com  # delete an account and its reservations
php_cli demo                           # add demo screenings for the next 7 days
```

To get the first staff account, create an account on the site (`/inscription`), then run `staff` with its email.

`demo` fills the next seven days around the placeholder hours. It skips Mondays and never overlaps a screening that's already planned, so it's safe to run again before a presentation.

## Testing

[`smoke-test.sh`](smoke-test.sh) runs through the whole site with curl. It runs on `ctrl-iac` and sends its requests straight to Traefik, so it needs neither DNS nor `proxy01`. It uses HTTPS on port 443 (Traefik's self-signed certificate): from VLAN 10 the firewall blocks HTTP to `k3s01`.

```bash
sh k8s/web/smoke-test.sh
```

It visits the public pages and creates customer and staff accounts. It adds a film with a poster and checks that a PHP file is refused as a poster. It fills a room, cancels a reservation, and finally deletes everything it created.

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

## Not done yet

- **Placeholder content:** the hours, prices and phone number in `content.php`, the demo films, and the game server addresses (game01's planned address, `10.10.80.20`).
- **Forgotten passwords:** there's no reset by email yet. Staff can delete the account with `cli.php` so the customer can create it again.
- **Backups:** the volumes are folders on `k3s01`'s disk. They're only as safe as the backups of VM 2031.
- **Sessions:** they're stored in the `php` pod, so restarting it logs everyone out.
