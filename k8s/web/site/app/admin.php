<?php
declare(strict_types=1);

// Staff pages (/gestion): today's screenings, screenings, films with
// their posters, announcements and game servers. Every handler starts
// with require_staff().

function admin_page(string $title, string $current, string $content): void
{
    render($title, '<div class="admin">' . admin_nav($current) . '<div class="admin-body">' . $content . '</div></div>', 'gestion');
}

/** Integer form field within bounds, or null. */
function int_field(string $name, int $min, int $max): ?int
{
    $value = field($name);
    if (!preg_match('/^\d{1,6}$/', $value)) {
        return null;
    }
    $number = (int) $value;
    return $number >= $min && $number <= $max ? $number : null;
}

/** @return array<int, string> film id => title */
function film_choices(): array
{
    return query('SELECT id, title FROM films ORDER BY title')->fetchAll(PDO::FETCH_KEY_PAIR);
}

/** @return array<int, string> room id => name */
function room_choices(): array
{
    return query('SELECT id, name FROM rooms ORDER BY id')->fetchAll(PDO::FETCH_KEY_PAIR);
}

// ---------------------------------------------------------------------
// Today

function page_admin_home(): void
{
    $user = require_staff();
    $now = now();
    $today = find_screenings('s.starts_at >= ? AND s.starts_at < ?',
        [sql_time($now->setTime(0, 0)), sql_time($now->setTime(0, 0)->modify('+1 day'))]);

    ob_start(); ?>
<div class="page-head">
  <h1>Aujourd’hui</h1>
  <p class="lead"><?= e(ucfirst(fr_date($now, true))) ?>. Bonjour, <?= e($user['name']) ?>.</p>
</div>
<?php if ($today === []): ?>
  <p class="empty">Aucune séance aujourd’hui. <a href="/gestion/seances">Ajouter une séance</a></p>
<?php else: ?>
  <table class="data">
    <thead><tr><th scope="col">Heure</th><th scope="col">Film</th><th scope="col">Salle</th><th scope="col">Réservé</th><th scope="col"><span class="visually-hidden">Actions</span></th></tr></thead>
    <tbody>
    <?php foreach ($today as $s): ?>
      <tr<?= $s['starts_at'] < $now ? ' class="is-past"' : '' ?>>
        <td><?= e(fr_time($s['starts_at'])) ?></td>
        <td><?= e($s['title']) ?></td>
        <td><?= e($s['room']) ?></td>
        <td><?= (int) $s['capacity'] - $s['seats_left'] ?> sur <?= (int) $s['capacity'] ?></td>
        <td><a href="/gestion/seances/<?= (int) $s['id'] ?>">Liste des réservations</a></td>
      </tr>
    <?php endforeach ?>
    </tbody>
  </table>
<?php endif ?>
<?php
    admin_page('Gestion', '/gestion', (string) ob_get_clean());
}

// ---------------------------------------------------------------------
// Screenings

/** @param list<string> $errors */
function screenings_page(array $errors = [], array $old = []): void
{
    require_staff();
    $screenings = find_screenings('s.starts_at >= ? AND s.starts_at < ?',
        [sql_time(now()->setTime(0, 0)), sql_time(now()->setTime(0, 0)->modify('+15 days'))]);
    $films = film_choices();

    ob_start(); ?>
<div class="page-head">
  <h1>Séances</h1>
  <p class="lead">Les séances des 14 prochains jours. Une salle doit être libre pendant le film et <?= ROOM_TURNOVER_MIN ?> minutes après.</p>
</div>
<section class="panel" aria-labelledby="add-screening">
  <h2 id="add-screening">Ajouter une séance</h2>
  <?= errors_html($errors) ?>
  <?php if ($films === []): ?>
    <p>Ajoutez d’abord un <a href="/gestion/films/nouveau">film</a>.</p>
  <?php else: ?>
  <form class="form form-grid" method="post" action="/gestion/seances">
    <?= csrf_field() ?>
    <div class="field-wide">
      <label for="film">Film</label>
      <select id="film" name="film_id" required><?= options_html($films, $old['film_id'] ?? '') ?></select>
    </div>
    <div>
      <label for="room">Salle</label>
      <select id="room" name="room_id" required><?= options_html(room_choices(), $old['room_id'] ?? '') ?></select>
    </div>
    <div>
      <label for="date">Date</label>
      <input type="date" id="date" name="date" required min="<?= e(now()->format('Y-m-d')) ?>" value="<?= e($old['date'] ?? '') ?>">
    </div>
    <div>
      <label for="time">Heure</label>
      <input type="time" id="time" name="time" required step="300" value="<?= e($old['time'] ?? '') ?>">
    </div>
    <div class="field-submit"><button class="button" type="submit">Ajouter la séance</button></div>
  </form>
  <?php endif ?>
</section>
<?php if ($screenings === []): ?>
  <p class="empty">Aucune séance prévue.</p>
<?php else: ?>
  <table class="data">
    <thead><tr><th scope="col">Date</th><th scope="col">Heure</th><th scope="col">Film</th><th scope="col">Salle</th><th scope="col">Réservé</th><th scope="col"><span class="visually-hidden">Actions</span></th></tr></thead>
    <tbody>
    <?php foreach ($screenings as $s): ?>
      <tr>
        <td><?= e(fr_day($s['starts_at'])) ?></td>
        <td><?= e(fr_time($s['starts_at'])) ?></td>
        <td><?= e($s['title']) ?></td>
        <td><?= e($s['room']) ?></td>
        <td><?= (int) $s['capacity'] - $s['seats_left'] ?> sur <?= (int) $s['capacity'] ?></td>
        <td><a href="/gestion/seances/<?= (int) $s['id'] ?>">Détails</a></td>
      </tr>
    <?php endforeach ?>
    </tbody>
  </table>
<?php endif ?>
<?php
    admin_page('Séances', '/gestion/seances', (string) ob_get_clean());
}

function page_admin_screenings(): void
{
    screenings_page();
}

function page_admin_screening_create(): void
{
    require_staff();
    $old = ['film_id' => field('film_id'), 'room_id' => field('room_id'), 'date' => field('date'), 'time' => field('time')];
    $errors = [];

    $film = query('SELECT id, title, duration_min FROM films WHERE id = ?', [(int) $old['film_id']])->fetch();
    $room = query('SELECT id, name FROM rooms WHERE id = ?', [(int) $old['room_id']])->fetch();
    $start = DateTimeImmutable::createFromFormat('!Y-m-d H:i', $old['date'] . ' ' . $old['time']);

    if ($film === false) {
        $errors[] = 'Choisissez un film.';
    }
    if ($room === false) {
        $errors[] = 'Choisissez une salle.';
    }
    if ($start === false) {
        $errors[] = 'Entrez une date et une heure valides.';
    } elseif ($start <= now()) {
        $errors[] = 'Choisissez une date et une heure à venir.';
    }

    if ($errors === []) {
        $conflict = screening_conflict((int) $room['id'], $start, (int) $film['duration_min']);
        if ($conflict !== null) {
            $at = new DateTimeImmutable($conflict['starts_at']);
            $errors[] = $room['name'] . ' est occupée : ' . $conflict['title'] . ' commence ' . mb_strtolower(fr_day($at))
                . ' à ' . fr_time($at) . '. Choisissez une autre heure ou une autre salle.';
        }
    }

    if ($errors !== []) {
        http_response_code(422);
        screenings_page($errors, $old);
        return;
    }

    query('INSERT INTO screenings (film_id, room_id, starts_at) VALUES (?, ?, ?)', [$film['id'], $room['id'], sql_time($start)]);
    flash('Séance ajoutée : ' . $film['title'] . ', ' . mb_strtolower(fr_day($start)) . ' à ' . fr_time($start) . ', ' . $room['name'] . '.');
    redirect('/gestion/seances');
}

function page_admin_screening(string $id): void
{
    require_staff();
    $s = find_screenings('s.id = ?', [(int) $id])[0] ?? null;
    if ($s === null) {
        not_found();
        return;
    }
    $reservations = query(
        'SELECT b.code, b.seats, u.name, u.email FROM reservations b JOIN users u ON u.id = b.user_id
         WHERE b.screening_id = ? ORDER BY u.name',
        [$s['id']],
    )->fetchAll();
    $taken = (int) $s['capacity'] - $s['seats_left'];

    ob_start(); ?>
<div class="page-head">
  <h1><?= e($s['title']) ?></h1>
  <p class="lead"><?= e(fr_day($s['starts_at'])) ?>, <?= e(fr_time($s['starts_at'])) ?>, <?= e($s['room']) ?>. <?= $taken ?> places réservées sur <?= (int) $s['capacity'] ?>.</p>
</div>
<?php if ($reservations === []): ?>
  <p class="empty">Aucune réservation pour cette séance.</p>
<?php else: ?>
  <table class="data">
    <thead><tr><th scope="col">Nom</th><th scope="col">Courriel</th><th scope="col">Places</th><th scope="col">Code</th></tr></thead>
    <tbody>
    <?php foreach ($reservations as $r): ?>
      <tr><td><?= e($r['name']) ?></td><td><?= e($r['email']) ?></td><td><?= (int) $r['seats'] ?></td><td class="code"><?= e($r['code']) ?></td></tr>
    <?php endforeach ?>
    </tbody>
  </table>
<?php endif ?>
<form class="danger-zone" method="post" action="/gestion/seances/<?= (int) $s['id'] ?>/supprimer">
  <?= csrf_field() ?>
  <p><?= $taken > 0 ? 'Supprimer la séance annule aussi les ' . e(fr_places($taken)) . ' réservées. Prévenez les clients avant.' : 'Aucune place n’est réservée pour cette séance.' ?></p>
  <button class="button button-danger" type="submit">Supprimer la séance</button>
</form>
<p><a href="/gestion/seances">Toutes les séances</a></p>
<?php
    admin_page($s['title'], '/gestion/seances', (string) ob_get_clean());
}

function page_admin_screening_delete(string $id): void
{
    require_staff();
    $s = find_screenings('s.id = ?', [(int) $id])[0] ?? null;
    if ($s === null) {
        not_found();
        return;
    }
    query('DELETE FROM screenings WHERE id = ?', [$s['id']]);
    flash('Séance supprimée : ' . $s['title'] . ', ' . mb_strtolower(fr_day($s['starts_at'])) . ' à ' . fr_time($s['starts_at']) . '.');
    redirect('/gestion/seances');
}

// ---------------------------------------------------------------------
// Films

/**
 * Saves an uploaded poster on the volume and returns its file name, or
 * null when no file was sent. Only JPEG, PNG and WebP images are kept.
 */
function save_poster(mixed $file): ?string
{
    if (!is_array($file) || !is_int($file['error'] ?? null) || $file['error'] === UPLOAD_ERR_NO_FILE) {
        return null;
    }
    if (in_array($file['error'], [UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE], true) || $file['size'] > POSTER_MAX_BYTES) {
        throw new UserError('L’affiche dépasse 5 Mo. Choisissez une image plus légère.');
    }
    if ($file['error'] !== UPLOAD_ERR_OK) {
        throw new UserError('L’affiche n’a pas pu être reçue. Réessayez.');
    }
    $type = (new finfo(FILEINFO_MIME_TYPE))->file($file['tmp_name']);
    if (!isset(POSTER_TYPES[$type]) || getimagesize($file['tmp_name']) === false) {
        throw new UserError('L’affiche doit être une image JPEG, PNG ou WebP.');
    }
    $name = bin2hex(random_bytes(16)) . '.' . POSTER_TYPES[$type];
    if (!move_uploaded_file($file['tmp_name'], UPLOAD_DIR . '/' . $name)) {
        throw new RuntimeException('Cannot move the poster to ' . UPLOAD_DIR);
    }
    return $name;
}

function delete_poster(?string $name): void
{
    if ($name !== null && $name !== '' && is_file(UPLOAD_DIR . '/' . $name)) {
        unlink(UPLOAD_DIR . '/' . $name);
    }
}

function page_admin_films(): void
{
    require_staff();
    $films = query(
        'SELECT f.id, f.slug, f.title, f.year, f.duration_min, f.poster,
                (SELECT COUNT(*) FROM screenings s WHERE s.film_id = f.id AND s.starts_at >= ?) AS upcoming
         FROM films f ORDER BY f.title',
        [sql_time(now())],
    )->fetchAll();

    ob_start(); ?>
<div class="page-head page-head-row">
  <h1>Films</h1>
  <a class="button" href="/gestion/films/nouveau">Ajouter un film</a>
</div>
<?php if ($films === []): ?>
  <p class="empty">Aucun film. Ajoutez-en un pour pouvoir créer des séances.</p>
<?php else: ?>
  <table class="data">
    <thead><tr><th scope="col">Titre</th><th scope="col">Année</th><th scope="col">Durée</th><th scope="col">Affiche</th><th scope="col">Séances à venir</th></tr></thead>
    <tbody>
    <?php foreach ($films as $f): ?>
      <tr>
        <td><a href="/gestion/films/<?= (int) $f['id'] ?>"><?= e($f['title']) ?></a></td>
        <td><?= e($f['year']) ?></td>
        <td><?= e(fr_duration((int) $f['duration_min'])) ?></td>
        <td><?= $f['poster'] ? 'Oui' : 'Non' ?></td>
        <td><?= (int) $f['upcoming'] ?></td>
      </tr>
    <?php endforeach ?>
    </tbody>
  </table>
<?php endif ?>
<?php
    admin_page('Films', '/gestion/films', (string) ob_get_clean());
}

/**
 * @param array<string, mixed>|null $film existing film, null for a new one
 * @param list<string> $errors
 */
function film_form(?array $film, array $errors = [], array $old = []): void
{
    $value = fn (string $key): string => (string) ($old[$key] ?? $film[$key] ?? '');
    $ratings = ['G' => 'Général', '13+' => '13 ans et plus', '16+' => '16 ans et plus', '18+' => '18 ans et plus'];
    $action = $film === null ? '/gestion/films' : '/gestion/films/' . (int) $film['id'];

    ob_start(); ?>
<div class="page-head">
  <h1><?= $film === null ? 'Ajouter un film' : e($film['title']) ?></h1>
  <?php if ($film !== null): ?>
    <p class="lead"><a href="/films/<?= e($film['slug']) ?>">Voir la fiche publique</a></p>
  <?php endif ?>
</div>
<?= errors_html($errors) ?>
<form class="form film-form" method="post" action="<?= e($action) ?>" enctype="multipart/form-data">
  <?= csrf_field() ?>
  <div class="film-form-fields">
    <label for="title">Titre</label>
    <input id="title" name="title" required maxlength="200" value="<?= e($value('title')) ?>">
    <div class="form-row">
      <div>
        <label for="year">Année</label>
        <input id="year" name="year" inputmode="numeric" pattern="\d{4}" maxlength="4" value="<?= e($value('year')) ?>">
      </div>
      <div>
        <label for="duration">Durée en minutes</label>
        <input id="duration" name="duration_min" inputmode="numeric" pattern="\d{1,3}" required value="<?= e($value('duration_min')) ?>">
      </div>
      <div>
        <label for="rating">Classement</label>
        <select id="rating" name="rating"><?= options_html($ratings, $value('rating') ?: 'G') ?></select>
      </div>
    </div>
    <label for="director">Réalisation</label>
    <input id="director" name="director" maxlength="150" value="<?= e($value('director')) ?>">
    <label for="synopsis">Résumé</label>
    <textarea id="synopsis" name="synopsis" required maxlength="3000" rows="6"><?= e($value('synopsis')) ?></textarea>
  </div>
  <div class="film-form-poster">
    <?php if ($film !== null): ?>
      <?= poster_html($film) ?>
    <?php endif ?>
    <label for="poster"><?= $film !== null && $film['poster'] ? 'Remplacer l’affiche' : 'Affiche' ?></label>
    <input type="file" id="poster" name="poster" accept="image/jpeg,image/png,image/webp" aria-describedby="poster-hint">
    <p class="hint" id="poster-hint">JPEG, PNG ou WebP, 5 Mo au maximum, au format portrait. Sans affiche, le titre est affiché.</p>
    <?php if ($film !== null && $film['poster']): ?>
      <label class="check"><input type="checkbox" name="remove_poster" value="1"> Retirer l’affiche</label>
    <?php endif ?>
  </div>
  <div class="form-actions">
    <button class="button" type="submit"><?= $film === null ? 'Ajouter le film' : 'Enregistrer' ?></button>
    <a href="/gestion/films">Annuler</a>
  </div>
</form>
<?php if ($film !== null): ?>
  <form class="danger-zone" method="post" action="/gestion/films/<?= (int) $film['id'] ?>/supprimer">
    <?= csrf_field() ?>
    <p>Supprimer le film supprime aussi toutes ses séances et leurs réservations.</p>
    <button class="button button-danger" type="submit">Supprimer le film</button>
  </form>
<?php endif ?>
<?php
    admin_page($film === null ? 'Ajouter un film' : $film['title'], '/gestion/films', (string) ob_get_clean());
}

/**
 * Reads and checks the film form.
 *
 * @return array{0: array<string, mixed>, 1: list<string>} values, errors
 */
function read_film_form(): array
{
    $values = [
        'title' => field('title'),
        'year' => field('year'),
        'director' => field('director'),
        'duration_min' => field('duration_min'),
        'rating' => field('rating'),
        'synopsis' => field('synopsis'),
    ];
    $errors = [];
    if ($values['title'] === '' || mb_strlen($values['title']) > 200) {
        $errors[] = 'Entrez le titre du film (200 caractères au maximum).';
    }
    if ($values['year'] !== '' && int_field('year', 1880, 2100) === null) {
        $errors[] = 'L’année doit compter quatre chiffres, par exemple 1927.';
    }
    if (int_field('duration_min', 1, 600) === null) {
        $errors[] = 'Entrez la durée en minutes, entre 1 et 600.';
    }
    if (!in_array($values['rating'], ['G', '13+', '16+', '18+'], true)) {
        $errors[] = 'Choisissez un classement.';
    }
    if ($values['synopsis'] === '' || mb_strlen($values['synopsis']) > 3000) {
        $errors[] = 'Entrez un résumé (3 000 caractères au maximum).';
    }
    if (mb_strlen($values['director']) > 150) {
        $errors[] = 'Le nom de la réalisation est trop long (150 caractères au maximum).';
    }
    return [$values, $errors];
}

/** A slug not used by another film. */
function unique_slug(string $title, int $ignore_id = 0): string
{
    $base = slugify($title);
    $slug = $base;
    for ($i = 2; query('SELECT 1 FROM films WHERE slug = ? AND id <> ?', [$slug, $ignore_id])->fetch() !== false; $i++) {
        $slug = $base . '-' . $i;
    }
    return $slug;
}

function page_admin_film_new(): void
{
    require_staff();
    film_form(null);
}

function page_admin_film_create(): void
{
    require_staff();
    [$values, $errors] = read_film_form();
    $poster = null;
    if ($errors === []) {
        try {
            $poster = save_poster($_FILES['poster'] ?? null);
        } catch (UserError $e) {
            $errors[] = $e->getMessage();
        }
    }
    if ($errors !== []) {
        http_response_code(422);
        film_form(null, $errors, $values);
        return;
    }

    $slug = unique_slug($values['title']);
    try {
        query('INSERT INTO films (slug, title, year, director, duration_min, rating, synopsis, poster) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
            $slug, $values['title'], $values['year'] === '' ? null : (int) $values['year'],
            $values['director'] === '' ? null : $values['director'], (int) $values['duration_min'],
            $values['rating'], $values['synopsis'], $poster,
        ]);
    } catch (Throwable $e) {
        delete_poster($poster);
        throw $e;
    }
    flash('Film ajouté : ' . $values['title'] . '. Vous pouvez maintenant lui ajouter des séances.');
    redirect('/gestion/films/' . db()->lastInsertId());
}

function find_film(string $id): ?array
{
    $film = query('SELECT * FROM films WHERE id = ?', [(int) $id])->fetch();
    return $film === false ? null : $film;
}

function page_admin_film(string $id): void
{
    require_staff();
    $film = find_film($id);
    if ($film === null) {
        not_found();
        return;
    }
    film_form($film);
}

function page_admin_film_update(string $id): void
{
    require_staff();
    $film = find_film($id);
    if ($film === null) {
        not_found();
        return;
    }
    [$values, $errors] = read_film_form();
    $poster = null;
    if ($errors === []) {
        try {
            $poster = save_poster($_FILES['poster'] ?? null);
        } catch (UserError $e) {
            $errors[] = $e->getMessage();
        }
    }
    if ($errors !== []) {
        http_response_code(422);
        film_form($film, $errors, $values);
        return;
    }

    $keep = $poster ?? (field('remove_poster') === '1' ? null : $film['poster']);
    query('UPDATE films SET title = ?, year = ?, director = ?, duration_min = ?, rating = ?, synopsis = ?, poster = ? WHERE id = ?', [
        $values['title'], $values['year'] === '' ? null : (int) $values['year'],
        $values['director'] === '' ? null : $values['director'], (int) $values['duration_min'],
        $values['rating'], $values['synopsis'], $keep, $film['id'],
    ]);
    if ($keep !== $film['poster']) {
        delete_poster($film['poster']);
    }
    flash('Modifications enregistrées.');
    redirect('/gestion/films/' . (int) $film['id']);
}

function page_admin_film_delete(string $id): void
{
    require_staff();
    $film = find_film($id);
    if ($film === null) {
        not_found();
        return;
    }
    query('DELETE FROM films WHERE id = ?', [$film['id']]);
    delete_poster($film['poster']);
    flash('Film supprimé : ' . $film['title'] . '.');
    redirect('/gestion/films');
}

// ---------------------------------------------------------------------
// Announcements

function page_admin_news(): void
{
    require_staff();
    $news = query('SELECT id, title, body, created_at FROM announcements ORDER BY id DESC')->fetchAll();

    ob_start(); ?>
<div class="page-head">
  <h1>Annonces</h1>
  <p class="lead">Les trois plus récentes paraissent sur la page d’accueil.</p>
</div>
<section class="panel" aria-labelledby="add-news">
  <h2 id="add-news">Publier une annonce</h2>
  <form class="form" method="post" action="/gestion/annonces">
    <?= csrf_field() ?>
    <label for="title">Titre</label>
    <input id="title" name="title" required maxlength="200">
    <label for="body">Texte</label>
    <textarea id="body" name="body" required maxlength="2000" rows="4"></textarea>
    <button class="button" type="submit">Publier</button>
  </form>
</section>
<?php foreach ($news as $item): ?>
  <article class="news news-admin">
    <h3><?= e($item['title']) ?></h3>
    <p class="news-date"><?= e(ucfirst(fr_date(new DateTimeImmutable($item['created_at']), true))) ?></p>
    <p><?= nl2br(e($item['body'])) ?></p>
    <form method="post" action="/gestion/annonces/<?= (int) $item['id'] ?>/supprimer">
      <?= csrf_field() ?>
      <button class="link-button link-danger" type="submit">Retirer l’annonce</button>
    </form>
  </article>
<?php endforeach ?>
<?php
    admin_page('Annonces', '/gestion/annonces', (string) ob_get_clean());
}

function page_admin_news_create(): void
{
    require_staff();
    $title = field('title');
    $body = field('body');
    if ($title === '' || mb_strlen($title) > 200 || $body === '' || mb_strlen($body) > 2000) {
        flash('Une annonce a besoin d’un titre (200 caractères au maximum) et d’un texte (2 000 caractères au maximum).', 'erreur');
        redirect('/gestion/annonces');
    }
    query('INSERT INTO announcements (title, body) VALUES (?, ?)', [$title, $body]);
    flash('Annonce publiée.');
    redirect('/gestion/annonces');
}

function page_admin_news_delete(string $id): void
{
    require_staff();
    query('DELETE FROM announcements WHERE id = ?', [(int) $id]);
    flash('Annonce retirée.');
    redirect('/gestion/annonces');
}

// ---------------------------------------------------------------------
// Game servers

/**
 * @param array<string, mixed>|null $server existing server, null for a new one
 * @param list<string> $errors
 */
function server_form(?array $server, array $errors = [], array $old = []): string
{
    $value = fn (string $key): string => (string) ($old[$key] ?? $server[$key] ?? '');
    $action = $server === null ? '/gestion/jeux' : '/gestion/jeux/' . (int) $server['id'];
    ob_start(); ?>
<?= errors_html($errors) ?>
<form class="form" method="post" action="<?= e($action) ?>">
  <?= csrf_field() ?>
  <div class="form-row">
    <div>
      <label for="game">Jeu</label>
      <input id="game" name="game" required maxlength="100" value="<?= e($value('game')) ?>">
    </div>
    <div>
      <label for="name">Nom de la partie</label>
      <input id="name" name="name" required maxlength="100" value="<?= e($value('name')) ?>">
    </div>
  </div>
  <div class="form-row">
    <div>
      <label for="address">Adresse</label>
      <input id="address" name="address" required maxlength="100" value="<?= e($value('address')) ?>" aria-describedby="address-hint">
    </div>
    <div>
      <label for="slots">Joueurs au maximum</label>
      <input id="slots" name="slots" inputmode="numeric" pattern="\d{1,4}" required value="<?= e($value('slots')) ?>">
    </div>
  </div>
  <p class="hint" id="address-hint">Telle que les joueurs la tapent dans le jeu, avec le port.</p>
  <label for="description">Description</label>
  <textarea id="description" name="description" required maxlength="1000" rows="3"><?= e($value('description')) ?></textarea>
  <button class="button" type="submit"><?= $server === null ? 'Ajouter le serveur' : 'Enregistrer' ?></button>
</form>
<?php
    return (string) ob_get_clean();
}

/** @return array{0: array<string, string>, 1: list<string>} */
function read_server_form(): array
{
    $values = ['game' => field('game'), 'name' => field('name'), 'address' => field('address'),
        'slots' => field('slots'), 'description' => field('description')];
    $errors = [];
    foreach (['game' => 'le jeu', 'name' => 'le nom de la partie', 'address' => 'l’adresse'] as $key => $label) {
        if ($values[$key] === '' || mb_strlen($values[$key]) > 100) {
            $errors[] = 'Entrez ' . $label . ' (100 caractères au maximum).';
        }
    }
    if (int_field('slots', 1, 1000) === null) {
        $errors[] = 'Entrez le nombre de joueurs, entre 1 et 1 000.';
    }
    if ($values['description'] === '' || mb_strlen($values['description']) > 1000) {
        $errors[] = 'Entrez une description (1 000 caractères au maximum).';
    }
    return [$values, $errors];
}

function games_admin_page(array $errors = [], array $old = []): void
{
    $servers = query('SELECT id, game, name, address, slots FROM game_servers ORDER BY game, name')->fetchAll();
    ob_start(); ?>
<div class="page-head">
  <h1>Serveurs de jeux</h1>
  <p class="lead">La liste publiée sur la page Serveurs de jeux.</p>
</div>
<?php if ($servers !== []): ?>
  <table class="data">
    <thead><tr><th scope="col">Jeu</th><th scope="col">Partie</th><th scope="col">Adresse</th><th scope="col">Joueurs</th></tr></thead>
    <tbody>
    <?php foreach ($servers as $s): ?>
      <tr><td><a href="/gestion/jeux/<?= (int) $s['id'] ?>"><?= e($s['game']) ?></a></td><td><?= e($s['name']) ?></td><td class="code"><?= e($s['address']) ?></td><td><?= (int) $s['slots'] ?></td></tr>
    <?php endforeach ?>
    </tbody>
  </table>
<?php endif ?>
<section class="panel" aria-labelledby="add-server">
  <h2 id="add-server">Ajouter un serveur</h2>
  <?= server_form(null, $errors, $old) ?>
</section>
<?php
    admin_page('Serveurs de jeux', '/gestion/jeux', (string) ob_get_clean());
}

function page_admin_games(): void
{
    require_staff();
    games_admin_page();
}

function page_admin_game_create(): void
{
    require_staff();
    [$values, $errors] = read_server_form();
    if ($errors !== []) {
        http_response_code(422);
        games_admin_page($errors, $values);
        return;
    }
    query('INSERT INTO game_servers (game, name, address, slots, description) VALUES (?, ?, ?, ?, ?)',
        [$values['game'], $values['name'], $values['address'], (int) $values['slots'], $values['description']]);
    flash('Serveur ajouté : ' . $values['game'] . '.');
    redirect('/gestion/jeux');
}

function find_server(string $id): ?array
{
    $server = query('SELECT * FROM game_servers WHERE id = ?', [(int) $id])->fetch();
    return $server === false ? null : $server;
}

function game_edit_page(array $server, array $errors = [], array $old = []): void
{
    $content = '<div class="page-head"><h1>' . e($server['game']) . '</h1></div>'
        . server_form($server, $errors, $old)
        . '<form class="danger-zone" method="post" action="/gestion/jeux/' . (int) $server['id'] . '/supprimer">' . csrf_field()
        . '<p>Le serveur disparaît de la page publique. Le serveur de jeu lui-même n’est pas arrêté.</p>'
        . '<button class="button button-danger" type="submit">Retirer le serveur</button></form>'
        . '<p><a href="/gestion/jeux">Tous les serveurs</a></p>';
    admin_page($server['game'], '/gestion/jeux', $content);
}

function page_admin_game(string $id): void
{
    require_staff();
    $server = find_server($id);
    if ($server === null) {
        not_found();
        return;
    }
    game_edit_page($server);
}

function page_admin_game_update(string $id): void
{
    require_staff();
    $server = find_server($id);
    if ($server === null) {
        not_found();
        return;
    }
    [$values, $errors] = read_server_form();
    if ($errors !== []) {
        http_response_code(422);
        game_edit_page($server, $errors, $values);
        return;
    }
    query('UPDATE game_servers SET game = ?, name = ?, address = ?, slots = ?, description = ? WHERE id = ?',
        [$values['game'], $values['name'], $values['address'], (int) $values['slots'], $values['description'], $server['id']]);
    flash('Modifications enregistrées.');
    redirect('/gestion/jeux');
}

function page_admin_game_delete(string $id): void
{
    require_staff();
    $server = find_server($id);
    if ($server === null) {
        not_found();
        return;
    }
    query('DELETE FROM game_servers WHERE id = ?', [$server['id']]);
    flash('Serveur retiré : ' . $server['game'] . '.');
    redirect('/gestion/jeux');
}
