#!/bin/sh
# End-to-end test of the website on k3s01. Run it on ctrl-iac:
#
#   sh k8s/web/smoke-test.sh [traefik address]
#
# It visits the public pages, creates customer and staff accounts, resets a
# password with a link from the staff, gives and takes back the staff
# section, deletes an account, adds a film with a poster and a screening 30
# days ahead in Salle 2 (24 places), fills the room, cancels a reservation,
# then deletes everything it made.
# curl --resolve sends the requests straight to Traefik, so no DNS record
# or proxy01 is needed. It uses HTTPS (port 443, Traefik's self-signed
# certificate): from VLAN 10 the firewall lets HTTPS through to k3s01, but
# not HTTP, which only proxy01 may use. Set SCHEME=http for a local test.
# kubectl runs cli.php to promote the staff account; set PHP_EXEC to run it
# another way (for example `docker exec cde-php`). For the development server
# on web01, run it there: SCHEME=http PMA= PHP_EXEC="sudo cde-env" sh smoke-test.sh 127.0.0.1
set -eu

PHP_EXEC=${PHP_EXEC:-kubectl -n web exec deploy/php --}

ADDR=${1:-10.10.20.31}
SCHEME=${SCHEME:-https}
WEB=${WEB:-web.cde.lan}
PMA=${PMA-pma.cde.lan}                  # empty: no phpMyAdmin to check
SITE=$SCHEME://$WEB
if [ "$SCHEME" = https ]; then PORT=443; else PORT=80; fi

RUN=$(date +%s)
WORK=$(mktemp -d)
PASSWORD=$(head -c 18 /dev/urandom | base64)
FAILED=0
USERS=""
FILM_ID=""
JAR=$WORK/visitor

pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; FAILED=$((FAILED + 1)); }

# expect <description> <actual> <expected>
expect() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (got '$2', expected '$3')"; fi
}

# check <description> <command...>: passes if the command succeeds.
check() {
    description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

# curl through Traefik with the cookies of the current $JAR.
# (Pipe it to `grep >/dev/null`, not `grep -q`: -q stops reading early and
# curl then reports a write error.)
web() {
    curl -sSk --max-time 60 --resolve "$WEB:$PORT:$ADDR" --resolve "${PMA:-$WEB}:$PORT:$ADDR" \
        -b "$JAR" -c "$JAR" "$@"
}

# page_has <path> <text>
page_has() {
    web "$SITE$1" | grep -F "$2" >/dev/null
}

# CSRF token from the first form on a page.
token() {
    web "$SITE$1" | sed -n 's/.*name="csrf" value="\([0-9a-f]*\)".*/\1/p' | head -n 1
}

# Prints "<status> <redirect path>" for a request.
status() {
    web -o /dev/null -w '%{http_code} %{redirect_url}' "$@" | sed "s#$SITE##; s/ $//"
}

# post <path> <page with the form> [form fields]
post() {
    post_path=$1 form_page=$2
    shift 2
    status --data-urlencode "csrf=$(token "$form_page")" "$@" "$SITE$post_path"
}

cli() {
    # shellcheck disable=SC2086 # PHP_EXEC is a command with its arguments
    $PHP_EXEC php /var/www/html/app/cli.php "$@" >/dev/null
}

email_of() {
    echo "smoke-$RUN-$1@exemple.test"
}

# as <name>: switch to that person's cookies.
as() {
    JAR=$WORK/$1
}

# register <name>: creates the account and stays logged in as that person.
register() {
    as "$1"
    USERS="$USERS $(email_of "$1")"
    expect "create the account of $1" "$(post /inscription /inscription \
        --data-urlencode "name=Essai $1" --data-urlencode "email=$(email_of "$1")" \
        --data-urlencode "password=$PASSWORD")" "303 /compte"
}

# reserve <screening id> <places>
reserve() {
    post "/seances/$1/reserver" "/seances/$1" --data-urlencode "seats=$2"
}

cleanup() {
    if [ -n "$FILM_ID" ]; then
        as staff
        post "/gestion/films/$FILM_ID/supprimer" "/gestion/films/$FILM_ID" >/dev/null || true
    fi
    for email in $USERS; do
        cli delete-user "$email" 2>/dev/null || true      # some are deleted by the test
    done
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "Testing $SITE through $ADDR"

# Health check: PHP, extensions, MariaDB, schema, volume, rewrite.
code=$(web -o "$WORK/status.json" -w '%{http_code}' "$SITE/status")
expect "status: every check passes" "$code" 200
[ "$code" = 200 ] || cat "$WORK/status.json"
first=$(sed -n 's/.*"session_visits": \([0-9]*\).*/\1/p' "$WORK/status.json")
second=$(web "$SITE/status" | sed -n 's/.*"session_visits": \([0-9]*\).*/\1/p')
expect "session kept between requests" "$second" "$((${first:-0} + 1))"

# Public pages.
for page in / /programmation /jeux /postes /infos /films/metropolis /connexion /inscription /mot-de-passe-oublie; do
    expect "page $page" "$(status "$SITE$page")" 200
done
check "home page names the centre" page_has / "Centre de divertissement de l’Estrie"
expect "font served" "$(web -o /dev/null -w '%{http_code}' "$SITE/big-shoulders.woff2")" 200
expect "unknown page answers 404" "$(status "$SITE/nulle-part")" 404
code=$(status "$SITE/.htaccess")
case $code in
    403 | 404) pass ".htaccess is not served ($code)" ;;
    *) fail ".htaccess is not served (got $code)" ;;
esac

# Customer accounts.
register alice
expect "log out" "$(post /deconnexion /compte)" "303 /"
expect "wrong password refused" "$(post /connexion /connexion \
    --data-urlencode "email=$(email_of alice)" --data-urlencode "password=x$PASSWORD")" 422
expect "log in" "$(post /connexion /connexion \
    --data-urlencode "email=$(email_of alice)" --data-urlencode "password=$PASSWORD")" "303 /compte"
expect "customers can't open the staff section" "$(status "$SITE/gestion")" 403

# Staff account, promoted with cli.php.
register staff
cli staff "$(email_of staff)"
expect "staff opens the staff section" "$(status "$SITE/gestion")" 200

# Forgotten passwords: the form answers the same for any email, and the
# staff create one-time links from /gestion/comptes.
as visitor
web --data-urlencode "csrf=$(token /mot-de-passe-oublie)" --data-urlencode "email=personne-$RUN@exemple.test" \
    "$SITE/mot-de-passe-oublie" > "$WORK/forgot.html"
check "an unknown email gets the usual answer" grep -qF "Si un compte existe" "$WORK/forgot.html"
as alice
expect "customers can't open the accounts page" "$(status "$SITE/gestion/comptes")" 403

as staff
account_id() {
    web "$SITE/gestion/comptes?q=$(email_of "$1")" | grep -o '/gestion/comptes/[0-9]*/lien' | head -n 1 | tr -dc 0-9
}
alice_id=$(account_id alice)
staff_id=$(account_id staff)
expect "the staff create a password link for alice" "$(post "/gestion/comptes/$alice_id/lien" /gestion/comptes)" "303 /gestion/comptes"
link=$(web "$SITE/gestion/comptes" | grep -o '/mot-de-passe/[0-9a-f]\{64\}' | head -n 1)
check "the accounts page showed the link" test -n "$link"
if page_has /gestion/comptes "$link"; then fail "the link is shown only once"; else pass "the link is shown only once"; fi
expect "the staff can't remove their own access" "$(post "/gestion/comptes/$staff_id/role" /gestion/comptes)" "303 /gestion/comptes"
expect "the staff can't delete their own account" "$(post "/gestion/comptes/$staff_id/supprimer" /gestion/comptes)" "303 /gestion/comptes"
expect "the staff member keeps the staff section" "$(status "$SITE/gestion")" 200

as alice
new_password=$(head -c 18 /dev/urandom | base64)
expect "alice opens the link" "$(status "$SITE$link")" 200
expect "alice chooses a new password" "$(post "$link" "$link" --data-urlencode "password=$new_password")" "303 /compte"
expect "the link works only once" "$(status "$SITE$link")" 404
expect "alice logs out" "$(post /deconnexion /compte)" "303 /"
expect "the old password is refused" "$(post /connexion /connexion \
    --data-urlencode "email=$(email_of alice)" --data-urlencode "password=$PASSWORD")" 422
expect "the new password works" "$(post /connexion /connexion \
    --data-urlencode "email=$(email_of alice)" --data-urlencode "password=$new_password")" "303 /compte"

as staff
expect "the staff give alice the staff section" "$(post "/gestion/comptes/$alice_id/role" /gestion/comptes)" "303 /gestion/comptes"
as alice
expect "alice opens the staff section" "$(status "$SITE/gestion")" 200
as staff
expect "the staff take it back" "$(post "/gestion/comptes/$alice_id/role" /gestion/comptes)" "303 /gestion/comptes"
as alice
expect "alice can't open it any more" "$(status "$SITE/gestion")" 403

register frank
as staff
expect "the staff delete frank's account" "$(post "/gestion/comptes/$(account_id frank)/supprimer" /gestion/comptes)" "303 /gestion/comptes"
as frank
expect "frank is logged out" "$(status "$SITE/compte")" "303 /connexion"
# shellcheck disable=SC2086 # PHP_EXEC is a command with its arguments
cli_link=$($PHP_EXEC php /var/www/html/app/cli.php reset-link "$(email_of staff)")
case $cli_link in
    */mot-de-passe/????????????????????????????????????????????????????????????????) pass "cli.php reset-link prints a link" ;;
    *) fail "cli.php reset-link prints a link (got '$cli_link')" ;;
esac
as staff

# A film with a poster.
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' \
    | base64 -d > "$WORK/poster.png"
film_form() {
    web -o "$WORK/film.html" -w '%{http_code} %{redirect_url}' \
        -F "csrf=$(token /gestion/films/nouveau)" -F "title=Film d’essai $RUN" -F year=2026 \
        -F duration_min=90 -F rating=G -F "synopsis=Créé par smoke-test.sh" \
        -F "poster=@$1;type=image/png" "$SITE/gestion/films" | sed "s#$SITE##; s/ $//"
}
result=$(film_form "$WORK/poster.png")
case $result in
    "303 /gestion/films/"[0-9]*) FILM_ID=${result#303 /gestion/films/}; pass "add a film with a poster" ;;
    *) fail "add a film with a poster (got '$result')" ;;
esac
slug=$(web "$SITE/gestion/films/$FILM_ID" | grep -o 'href="/films/[a-z0-9-]*"' | head -n 1 | sed 's/href="\(.*\)"/\1/')
poster=$(web "$SITE$slug" | grep -o '/affiches/[a-f0-9]*\.png' | head -n 1)
expect "poster served as an image" "$(web -o /dev/null -w '%{http_code} %{content_type}' "$SITE$poster")" "200 image/png"

printf '<?php echo "EXECUTED";\n' > "$WORK/shell.php"
expect "a PHP file sent as a poster is refused" "$(film_form "$WORK/shell.php")" 422
check "the refusal explains why" grep -qF "doit être une image" "$WORK/film.html"

# A screening in 30 days, and a second one that would overlap it.
date=$(date -d '+30 days' +%Y-%m-%d)
expect "add a screening" "$(post /gestion/seances /gestion/seances --data-urlencode "film_id=$FILM_ID" \
    --data-urlencode room_id=2 --data-urlencode "date=$date" --data-urlencode time=13:00)" "303 /gestion/seances"
expect "an overlapping screening is refused" "$(post /gestion/seances /gestion/seances --data-urlencode "film_id=$FILM_ID" \
    --data-urlencode room_id=2 --data-urlencode "date=$date" --data-urlencode time=13:30)" 422
screening=$(web "$SITE$slug" | grep -o '/seances/[0-9]*' | head -n 1 | tr -dc 0-9)

# Reservations: Salle 2 has 24 places, four people take 6 each.
as alice
result=$(reserve "$screening" 6)
code=${result#303 /reservations/}
case $result in
    "303 /reservations/"????????) pass "alice reserves 6 places ($code)" ;;
    *) fail "alice reserves 6 places (got '$result')" ;;
esac
check "alice's ticket shows the code" page_has "/reservations/$code" "$code"
expect "a second reservation for the same screening is refused" "$(reserve "$screening" 1)" "303 /seances/$screening"
for name in bruno chloe david; do
    register "$name"
    case $(reserve "$screening" 6) in
        "303 /reservations/"*) pass "$name reserves 6 places" ;;
        *) fail "$name reserves 6 places" ;;
    esac
done
as bruno
expect "others can't see alice's ticket" "$(status "$SITE/reservations/$code")" 404

register emma
expect "the full screening refuses emma" "$(reserve "$screening" 1)" "303 /seances/$screening"
check "emma is told it is full" page_has "/seances/$screening" "complète"

as alice
expect "alice cancels" "$(post "/reservations/$code/annuler" /compte)" "303 /compte"
as emma
case $(reserve "$screening" 1) in
    "303 /reservations/"*) pass "the freed places go to emma" ;;
    *) fail "the freed places go to emma" ;;
esac

as staff
check "the front desk list counts 19 of 24 places" page_has "/gestion/seances/$screening" "19 places réservées sur 24"

# phpMyAdmin.
if [ -z "$PMA" ]; then
    echo "skip  phpMyAdmin (PMA is empty)"
elif web "$SCHEME://$PMA/" | grep 'phpMyAdmin' >/dev/null; then
    pass "phpMyAdmin login page"
else
    fail "phpMyAdmin login page"
fi

# Clean up: the film takes its screening and reservations with it.
expect "delete the film" "$(post "/gestion/films/$FILM_ID/supprimer" "/gestion/films/$FILM_ID")" "303 /gestion/films"
FILM_ID=""
expect "its screening is gone" "$(status "$SITE/seances/$screening")" 404
expect "its poster is gone" "$(status "$SITE$poster")" 404

as visitor
expect "visitors are sent to the login page" "$(status "$SITE/compte")" "303 /connexion"

if [ "$FAILED" -eq 0 ]; then
    echo "All checks passed."
else
    echo "$FAILED check(s) failed."
    exit 1
fi
