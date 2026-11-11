<?php
declare(strict_types=1);

// Customer pages: account creation, login, reservations and tickets.

/** Remembers ?retour=/seances/12 so the visitor comes back after logging in. */
function remember_return(): void
{
    $path = $_GET['retour'] ?? '';
    if (is_string($path) && preg_match('#^/[a-z0-9/_-]*$#', $path)) {
        $_SESSION['after_login'] = $path;
    }
}

/** @param list<string> $errors */
function errors_html(array $errors): string
{
    if ($errors === []) {
        return '';
    }
    $html = '<div class="form-errors" role="alert"><p>Corrigez ces points pour continuer.</p><ul>';
    foreach ($errors as $error) {
        $html .= '<li>' . e($error) . '</li>';
    }
    return $html . '</ul></div>';
}

/**
 * @param list<string> $errors
 * @param array<string, string> $old
 */
function register_form(array $errors = [], array $old = []): void
{
    ob_start(); ?>
<div class="auth">
  <h1>Créer un compte</h1>
  <p class="lead">Un compte sert à réserver vos places et à retrouver vos billets.</p>
  <?= errors_html($errors) ?>
  <form class="form" method="post" action="/inscription">
    <?= csrf_field() ?>
    <label for="name">Nom</label>
    <input id="name" name="name" autocomplete="name" required maxlength="100" value="<?= e($old['name'] ?? '') ?>">
    <label for="email">Courriel</label>
    <input type="email" id="email" name="email" autocomplete="email" required maxlength="190" value="<?= e($old['email'] ?? '') ?>">
    <label for="password">Mot de passe</label>
    <input type="password" id="password" name="password" autocomplete="new-password" required minlength="8" aria-describedby="password-hint">
    <p class="hint" id="password-hint">Au moins 8 caractères.</p>
    <button class="button" type="submit">Créer mon compte</button>
  </form>
  <p>Vous avez déjà un compte ? <a href="/connexion">Connectez-vous</a></p>
</div>
<?php
    render('Créer un compte', (string) ob_get_clean(), 'compte');
}

function page_register_form(): void
{
    remember_return();
    register_form();
}

function page_register(): void
{
    $old = ['name' => field('name'), 'email' => mb_strtolower(field('email'))];
    $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';

    $errors = [];
    if (mb_strlen($old['name']) < 2 || mb_strlen($old['name']) > 100) {
        $errors[] = 'Entrez votre nom (2 à 100 caractères).';
    }
    if (filter_var($old['email'], FILTER_VALIDATE_EMAIL) === false || strlen($old['email']) > 190) {
        $errors[] = 'Entrez une adresse courriel valide, par exemple nom@exemple.com.';
    }
    if (strlen($password) < 8) {
        $errors[] = 'Choisissez un mot de passe d’au moins 8 caractères.';
    }

    if ($errors === []) {
        try {
            query('INSERT INTO users (name, email, password_hash) VALUES (?, ?, ?)',
                [$old['name'], $old['email'], password_hash($password, PASSWORD_DEFAULT)]);
        } catch (PDOException $e) {
            if ($e->getCode() !== '23000') {
                throw $e;
            }
            $errors[] = 'Un compte existe déjà avec ce courriel. Connectez-vous plutôt.';
        }
    }

    if ($errors !== []) {
        http_response_code(422);
        register_form($errors, $old);
        return;
    }

    log_in((int) db()->lastInsertId());
    flash('Compte créé. Bienvenue, ' . $old['name'] . '.');
    redirect(take_after_login('/compte'));
}

function login_form(string $error = '', string $email = ''): void
{
    ob_start(); ?>
<div class="auth">
  <h1>Connexion</h1>
  <p class="lead">Connectez-vous pour réserver vos places.</p>
  <?= $error === '' ? '' : '<div class="form-errors" role="alert"><p>' . e($error) . '</p></div>' ?>
  <form class="form" method="post" action="/connexion">
    <?= csrf_field() ?>
    <label for="email">Courriel</label>
    <input type="email" id="email" name="email" autocomplete="email" required value="<?= e($email) ?>">
    <label for="password">Mot de passe</label>
    <input type="password" id="password" name="password" autocomplete="current-password" required>
    <button class="button" type="submit">Me connecter</button>
  </form>
  <p><a href="/mot-de-passe-oublie">Mot de passe oublié ?</a></p>
  <p>Pas encore de compte ? <a href="/inscription">Créez-en un</a></p>
</div>
<?php
    render('Connexion', (string) ob_get_clean(), 'compte');
}

function page_login_form(): void
{
    remember_return();
    login_form();
}

function page_login(): void
{
    $email = mb_strtolower(field('email'));
    $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';

    $row = query('SELECT id, role, password_hash FROM users WHERE email = ?', [$email])->fetch();
    // Check a password even for an unknown email, so both cases take as long.
    $hash = $row === false ? '$2y$12$abcdefghijklmnopqrstuuJ6Nt6m2qFvUh0z0o9ZPpqbkpBhq3hq2' : $row['password_hash'];
    $valid = password_verify($password, $hash);

    if ($row === false || !$valid) {
        http_response_code(422);
        login_form('Courriel ou mot de passe incorrect.', $email);
        return;
    }

    log_in((int) $row['id']);
    redirect(take_after_login($row['role'] === 'staff' ? '/gestion' : '/compte'));
}

function page_logout(): void
{
    $_SESSION = [];
    session_regenerate_id(true);
    flash('Vous êtes déconnecté.');
    redirect('/');
}

// ---------------------------------------------------------------------
// Forgotten password. The answer is the same whether the account exists or
// not, so the form can't be used to find out who has an account.

function page_forgot_form(): void
{
    ob_start(); ?>
<div class="auth">
  <h1>Mot de passe oublié</h1>
  <p class="lead">Entrez le courriel de votre compte. Nous vous enverrons un lien pour choisir un nouveau mot de passe.</p>
  <form class="form" method="post" action="/mot-de-passe-oublie">
    <?= csrf_field() ?>
    <label for="email">Courriel</label>
    <input type="email" id="email" name="email" autocomplete="email" required maxlength="190">
    <button class="button" type="submit">Recevoir un lien</button>
  </form>
  <p>Vous pouvez aussi demander un lien à l’accueil, ou au <?= e(CENTRE_PHONE) ?>.</p>
</div>
<?php
    render('Mot de passe oublié', (string) ob_get_clean(), 'compte');
}

function page_forgot(): void
{
    $email = mb_strtolower(field('email'));
    $user = query('SELECT id, name, email FROM users WHERE email = ?', [$email])->fetch();
    // At most one email every 5 minutes per account.
    $recent = $user === false ? true : (bool) query(
        'SELECT 1 FROM password_resets WHERE user_id = ? AND created_at > ?',
        [$user['id'], sql_time(now()->modify('-5 minutes'))],
    )->fetchColumn();
    if ($user !== false && !$recent) {
        $link = create_reset_link((int) $user['id']);
        send_mail($user['email'], 'Choisir un nouveau mot de passe',
            "Bonjour {$user['name']},\n\n"
            . "Pour choisir un nouveau mot de passe, ouvrez ce lien dans les " . RESET_LINK_HOURS . " prochaines heures :\n\n"
            . "$link\n\n"
            . "Si vous n’avez rien demandé, ignorez ce message : votre mot de passe ne change pas.\n\n"
            . CENTRE_NAME . "\n" . CENTRE_PHONE . "\n");
    }

    ob_start(); ?>
<div class="auth">
  <h1>Vérifiez vos courriels</h1>
  <p class="lead">Si un compte existe avec cette adresse, nous venons de lui envoyer un lien valable <?= RESET_LINK_HOURS ?>&nbsp;heures.</p>
  <p>Rien reçu après quelques minutes ? Vérifiez vos indésirables, ou demandez un lien à l’accueil ou au <?= e(CENTRE_PHONE) ?>.</p>
  <p><a href="/connexion">Retour à la connexion</a></p>
</div>
<?php
    render('Mot de passe oublié', (string) ob_get_clean(), 'compte');
}

function reset_form(string $token, array $reset, string $error = ''): void
{
    ob_start(); ?>
<div class="auth">
  <h1>Nouveau mot de passe</h1>
  <p class="lead">Compte de <?= e($reset['name']) ?> (<?= e($reset['email']) ?>).</p>
  <?= $error === '' ? '' : '<div class="form-errors" role="alert"><p>' . e($error) . '</p></div>' ?>
  <form class="form" method="post" action="/mot-de-passe/<?= e($token) ?>">
    <?= csrf_field() ?>
    <label for="password">Nouveau mot de passe</label>
    <input type="password" id="password" name="password" autocomplete="new-password" required minlength="8" aria-describedby="password-hint">
    <p class="hint" id="password-hint">Au moins 8 caractères.</p>
    <button class="button" type="submit">Enregistrer</button>
  </form>
</div>
<?php
    render('Nouveau mot de passe', (string) ob_get_clean(), 'compte');
}

function expired_reset(): void
{
    http_response_code(404);
    render('Lien expiré', '<div class="auth"><h1>Ce lien ne fonctionne plus</h1>'
        . '<p class="lead">Il a déjà servi, ou il date de plus de ' . RESET_LINK_HOURS . "\u{a0}heures.</p>"
        . '<p><a href="/mot-de-passe-oublie">Demander un nouveau lien</a></p></div>', 'compte');
}

function page_reset_form(string $token): void
{
    $reset = find_reset($token);
    $reset === null ? expired_reset() : reset_form($token, $reset);
}

function page_reset(string $token): void
{
    $reset = find_reset($token);
    if ($reset === null) {
        expired_reset();
        return;
    }
    $password = is_string($_POST['password'] ?? null) ? $_POST['password'] : '';
    if (strlen($password) < 8) {
        http_response_code(422);
        reset_form($token, $reset, 'Choisissez un mot de passe d’au moins 8 caractères.');
        return;
    }
    query('UPDATE users SET password_hash = ? WHERE id = ?', [password_hash($password, PASSWORD_DEFAULT), $reset['user_id']]);
    query('DELETE FROM password_resets WHERE user_id = ?', [$reset['user_id']]);
    log_in($reset['user_id']);
    flash('Mot de passe changé. Vous êtes connecté.');
    redirect($reset['role'] === 'staff' ? '/gestion' : '/compte');
}

/** Reservations of one user, with their screening. */
function user_reservations(int $user_id, bool $upcoming): array
{
    $rows = query(
        'SELECT b.code, b.seats, s.starts_at, r.name AS room, f.title, f.slug
         FROM reservations b
         JOIN screenings s ON s.id = b.screening_id
         JOIN rooms r ON r.id = s.room_id
         JOIN films f ON f.id = s.film_id
         WHERE b.user_id = ? AND s.starts_at ' . ($upcoming ? '>=' : '<') . ' ?
         ORDER BY s.starts_at ' . ($upcoming ? 'ASC' : 'DESC') . '
         LIMIT 20',
        [$user_id, sql_time(now())],
    )->fetchAll();
    foreach ($rows as &$row) {
        $row['starts_at'] = new DateTimeImmutable($row['starts_at']);
    }
    return $rows;
}

function page_account(): void
{
    $user = require_login();
    $upcoming = user_reservations($user['id'], true);
    $past = user_reservations($user['id'], false);

    ob_start(); ?>
<div class="page-head">
  <h1>Mes réservations</h1>
  <p class="lead">Bonjour, <?= e($user['name']) ?>. Présentez le code de votre billet à l’accueil et payez vos places avant la séance.</p>
</div>
<?php if ($upcoming === []): ?>
  <p class="empty">Vous n’avez aucune réservation à venir. <a href="/programmation">Choisir une séance</a></p>
<?php else: ?>
  <div class="tickets">
    <?php foreach ($upcoming as $r): ?>
      <?= ticket_html($r, true) ?>
    <?php endforeach ?>
  </div>
<?php endif ?>
<?php if ($past !== []): ?>
  <section class="section" aria-labelledby="past-heading">
    <h2 id="past-heading">Séances passées</h2>
    <ul class="plain-list">
      <?php foreach ($past as $r): ?>
        <li><?= e($r['title']) ?>, <?= e(fr_date($r['starts_at'], true)) ?>, <?= e(fr_places((int) $r['seats'])) ?></li>
      <?php endforeach ?>
    </ul>
  </section>
<?php endif ?>
<?php if (is_staff($user)): ?>
  <p><a href="/gestion">Aller à la gestion du centre</a></p>
<?php endif ?>
<?php
    render('Mes réservations', (string) ob_get_clean(), 'compte');
}

function page_screening(string $id): void
{
    $s = find_screenings('s.id = ?', [(int) $id])[0] ?? null;
    if ($s === null) {
        not_found();
        return;
    }
    $user = current_user();
    $mine = $user === null ? false
        : query('SELECT code, seats FROM reservations WHERE screening_id = ? AND user_id = ?', [$s['id'], $user['id']])->fetch();
    $started = $s['starts_at'] <= now();
    $max = min(MAX_SEATS, $s['seats_left']);

    ob_start(); ?>
<div class="booking">
  <div class="booking-poster"><?= poster_html($s) ?></div>
  <div class="booking-body">
    <p class="booking-back"><a href="/films/<?= e($s['slug']) ?>">Fiche du film</a></p>
    <h1><?= e($s['title']) ?></h1>
    <p class="booking-when"><?= e(fr_day($s['starts_at'])) ?>, <?= e(fr_time($s['starts_at'])) ?>, <?= e($s['room']) ?></p>
    <p class="muted"><?= e(fr_duration((int) $s['duration_min'])) ?>, <?= e(fr_rating($s['rating'])) ?></p>

    <?php if ($started): ?>
      <p class="notice">Cette séance est commencée. <a href="/films/<?= e($s['slug']) ?>">Voir les prochaines séances</a></p>
    <?php elseif ($mine !== false): ?>
      <p class="notice">Vous avez réservé <?= e(fr_places((int) $mine['seats'])) ?> pour cette séance. <a href="/reservations/<?= e($mine['code']) ?>">Voir mon billet</a></p>
    <?php elseif ($s['seats_left'] <= 0): ?>
      <p class="notice">Cette séance est complète. <a href="/films/<?= e($s['slug']) ?>">Voir les autres séances</a></p>
    <?php elseif ($user === null): ?>
      <p><?= seats_html($s['seats_left']) ?></p>
      <p>Pour réserver, connectez-vous ou créez un compte. Ça prend une minute.</p>
      <p class="actions">
        <a class="button" href="/connexion?retour=/seances/<?= (int) $s['id'] ?>">Me connecter</a>
        <a class="button button-quiet" href="/inscription?retour=/seances/<?= (int) $s['id'] ?>">Créer un compte</a>
      </p>
    <?php else: ?>
      <p><?= seats_html($s['seats_left']) ?></p>
      <form class="form form-inline" method="post" action="/seances/<?= (int) $s['id'] ?>/reserver">
        <?= csrf_field() ?>
        <div>
          <label for="seats">Nombre de places</label>
          <select id="seats" name="seats"><?= options_html(array_combine(range(1, $max), range(1, $max)), 1) ?></select>
        </div>
        <button class="button" type="submit">Réserver</button>
      </form>
      <p class="hint">Vous payez à l’accueil, avant la séance. Annulation possible jusqu’au début de la projection.</p>
    <?php endif ?>
  </div>
</div>
<?php
    render($s['title'] . ', ' . fr_day($s['starts_at']), (string) ob_get_clean(), 'programmation');
}

function page_reserve(string $id): void
{
    $user = require_login();
    $screening_id = (int) $id;
    $seats = (int) field('seats');
    if ($seats < 1 || $seats > MAX_SEATS) {
        flash('Choisissez entre 1 et ' . MAX_SEATS . ' places.', 'erreur');
        redirect('/seances/' . $screening_id);
    }

    $pdo = db();
    $pdo->beginTransaction();
    try {
        // Locking the screening makes reservations for it wait for each other,
        // so two people can't take the last places at the same time.
        $s = query('SELECT s.starts_at, r.capacity FROM screenings s JOIN rooms r ON r.id = s.room_id
                    WHERE s.id = ? FOR UPDATE', [$screening_id])->fetch();
        if ($s === false) {
            $pdo->rollBack();
            not_found();
            return;
        }
        if (new DateTimeImmutable($s['starts_at']) <= now()) {
            throw new UserError('Cette séance est commencée : il n’est plus possible de réserver.');
        }
        $already = query('SELECT 1 FROM reservations WHERE screening_id = ? AND user_id = ?', [$screening_id, $user['id']])->fetch();
        if ($already !== false) {
            throw new UserError('Vous avez déjà une réservation pour cette séance.');
        }
        $taken = (int) query('SELECT COALESCE(SUM(seats), 0) FROM reservations WHERE screening_id = ?', [$screening_id])->fetchColumn();
        $left = (int) $s['capacity'] - $taken;
        if ($left <= 0) {
            throw new UserError('Cette séance est complète.');
        }
        if ($seats > $left) {
            throw new UserError('Il ne reste que ' . fr_places($left) . ' pour cette séance.');
        }
        $code = booking_code();
        query('INSERT INTO reservations (code, screening_id, user_id, seats) VALUES (?, ?, ?, ?)',
            [$code, $screening_id, $user['id'], $seats]);
        $pdo->commit();
    } catch (UserError $e) {
        $pdo->rollBack();
        flash($e->getMessage(), 'erreur');
        redirect('/seances/' . $screening_id);
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }

    flash('Réservation confirmée. Présentez ce code à l’accueil.');
    redirect('/reservations/' . $code);
}

function find_reservation(string $code): ?array
{
    $r = query(
        'SELECT b.code, b.seats, b.user_id, s.starts_at, r.name AS room, f.title, f.slug
         FROM reservations b
         JOIN screenings s ON s.id = b.screening_id
         JOIN rooms r ON r.id = s.room_id
         JOIN films f ON f.id = s.film_id
         WHERE b.code = ?',
        [$code],
    )->fetch();
    if ($r === false) {
        return null;
    }
    $r['starts_at'] = new DateTimeImmutable($r['starts_at']);
    return $r;
}

function page_ticket(string $code): void
{
    $user = require_login();
    $r = find_reservation($code);
    if ($r === null || ((int) $r['user_id'] !== $user['id'] && !is_staff($user))) {
        not_found();
        return;
    }
    $own_and_upcoming = (int) $r['user_id'] === $user['id'] && $r['starts_at'] > now();

    ob_start(); ?>
<div class="page-head">
  <h1>Votre billet</h1>
  <p class="lead">Présentez ce code à l’accueil et payez vos places avant la séance.</p>
</div>
<div class="tickets"><?= ticket_html($r, $own_and_upcoming) ?></div>
<p><a href="/compte">Toutes mes réservations</a></p>
<?php
    render('Votre billet', (string) ob_get_clean(), 'compte');
}

function page_cancel(string $code): void
{
    $user = require_login();
    $r = find_reservation($code);
    if ($r === null || (int) $r['user_id'] !== $user['id']) {
        not_found();
        return;
    }
    if ($r['starts_at'] <= now()) {
        flash('Cette séance est commencée : la réservation ne peut plus être annulée.', 'erreur');
        redirect('/compte');
    }
    query('DELETE FROM reservations WHERE code = ? AND user_id = ?', [$code, $user['id']]);
    flash('Réservation annulée : ' . $r['title'] . ', ' . fr_day($r['starts_at']) . ' à ' . fr_time($r['starts_at']) . '.');
    redirect('/compte');
}
