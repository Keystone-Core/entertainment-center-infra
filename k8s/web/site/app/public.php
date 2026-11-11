<?php
declare(strict_types=1);

// Public pages: home, schedule, films, game servers, workstations,
// practical information, posters and the status check.

function page_home(): void
{
    $now = now();
    $midnight = $now->setTime(0, 0)->modify('+1 day');
    $today = find_screenings('s.starts_at >= ? AND s.starts_at < ?', [sql_time($now), sql_time($midnight)]);
    $next = $today === [] ? find_screenings('s.starts_at >= ?', [sql_time($now)], 's.starts_at, r.id', 1) : [];

    // "Ce soir" only when every remaining screening today is in the evening.
    $evening = $today !== [] && (int) $today[0]['starts_at']->format('G') >= 17;

    $week = find_screenings('s.starts_at >= ? AND s.starts_at < ?', [sql_time($now), sql_time($now->setTime(0, 0)->modify('+7 days'))]);
    $films = [];
    foreach ($week as $s) {
        $films[$s['film_id']] ??= $s;           // the first one is the next screening
    }

    $rooms = query('SELECT name, capacity FROM rooms ORDER BY id')->fetchAll();
    $server_count = (int) query('SELECT COUNT(*) FROM game_servers')->fetchColumn();
    $news = query('SELECT title, body, created_at FROM announcements ORDER BY id DESC LIMIT 3')->fetchAll();

    ob_start(); ?>
<section class="board-section" aria-labelledby="board-name">
  <div class="board">
    <h1 class="board-name" id="board-name"><?= e(CENTRE_NAME) ?></h1>
    <?php if ($today !== []): ?>
      <p class="board-when"><?= $evening ? 'Ce soir' : 'Aujourd’hui' ?>, <?= e(fr_date($now)) ?></p>
      <ol class="board-lines">
        <?php foreach (array_slice($today, 0, 6) as $s): ?>
          <li><a href="/seances/<?= (int) $s['id'] ?>">
            <span class="board-time"><?= e(fr_time($s['starts_at'])) ?></span>
            <span class="board-room"><?= e($s['room']) ?></span>
            <span class="board-title"><?= e($s['title']) ?></span>
          </a></li>
        <?php endforeach ?>
      </ol>
    <?php elseif ($next !== []): ?>
      <p class="board-when">Relâche ce soir. Prochaine séance <?= e(mb_strtolower(fr_day($next[0]['starts_at']))) ?></p>
      <ol class="board-lines">
        <li><a href="/seances/<?= (int) $next[0]['id'] ?>">
          <span class="board-time"><?= e(fr_time($next[0]['starts_at'])) ?></span>
          <span class="board-room"><?= e($next[0]['room']) ?></span>
          <span class="board-title"><?= e($next[0]['title']) ?></span>
        </a></li>
      </ol>
    <?php else: ?>
      <p class="board-when">Programmation à venir</p>
    <?php endif ?>
  </div>
  <div class="board-note">
    <p>Cinéma, serveurs de jeux et postes publics à Sherbrooke. Réservez vos places en ligne et payez à l’accueil.</p>
    <a class="button" href="/programmation">Voir la programmation</a>
  </div>
</section>

<?php if ($films !== []): ?>
<section class="section" aria-labelledby="week-heading">
  <h2 id="week-heading">À l’affiche cette semaine</h2>
  <ul class="film-grid">
    <?php foreach (array_slice($films, 0, 6) as $s): ?>
      <li class="film-card">
        <a href="/films/<?= e($s['slug']) ?>" class="film-card-link">
          <?= poster_html($s) ?>
          <span class="film-card-title"><?= e($s['title']) ?></span>
        </a>
        <span class="film-card-next"><?= e(fr_day($s['starts_at'])) ?> à <?= e(fr_time($s['starts_at'])) ?></span>
      </li>
    <?php endforeach ?>
  </ul>
  <?php if (count($films) > 6): ?>
    <p class="more"><a href="/programmation">Les <?= count($films) ?> films de la semaine</a></p>
  <?php endif ?>
</section>
<?php endif ?>

<section class="section offer" aria-labelledby="offer-heading">
  <h2 id="offer-heading">Au centre</h2>
  <div class="offer-columns">
    <div>
      <h3><?= count($rooms) === 2 ? 'Deux salles de cinéma' : 'Nos salles de cinéma' ?></h3>
      <p><?php foreach ($rooms as $i => $room): ?><?= $i > 0 ? ($i === count($rooms) - 1 ? ' et la ' : ', la ') : 'La ' ?><?= e(mb_strtolower($room['name'])) ?> compte <?= (int) $room['capacity'] ?> places<?php endforeach ?>. Réservez jusqu’à <?= MAX_SEATS ?> places par séance.</p>
      <a href="/programmation">Programmation de la semaine</a>
    </div>
    <div>
      <h3>Serveurs de jeux</h3>
      <p><?= $server_count ?> serveurs ouverts aux joueurs, depuis nos postes publics. L’accès est gratuit.</p>
      <a href="/jeux">Adresses des serveurs</a>
    </div>
    <div>
      <h3><?= WORKSTATION_COUNT ?> postes publics</h3>
      <p>Pour jouer en réseau ou naviguer, sans compte à créer. Vous payez à l’heure, à l’accueil.</p>
      <a href="/postes">Tarifs des postes</a>
    </div>
  </div>
</section>

<div class="section split">
  <section aria-labelledby="news-heading">
    <h2 id="news-heading">Nouvelles</h2>
    <?php if ($news === []): ?>
      <p class="muted">Aucune nouvelle pour le moment.</p>
    <?php endif ?>
    <?php foreach ($news as $item): ?>
      <article class="news">
        <h3><?= e($item['title']) ?></h3>
        <p class="news-date"><?= e(ucfirst(fr_date(new DateTimeImmutable($item['created_at']), true))) ?></p>
        <p><?= nl2br(e($item['body'])) ?></p>
      </article>
    <?php endforeach ?>
  </section>
  <aside aria-labelledby="hours-heading">
    <h2 id="hours-heading">Heures d’ouverture</h2>
    <?= hours_html() ?>
    <p class="muted"><a href="/infos">Tarifs et accès</a></p>
  </aside>
</div>
<?php
    render('Accueil', (string) ob_get_clean(), 'accueil');
}

function hours_html(): string
{
    $html = '<table class="facts">';
    foreach (CENTRE_HOURS as [$day, $hours]) {
        $html .= '<tr><th scope="row">' . e($day) . '</th><td>' . e($hours) . '</td></tr>';
    }
    return $html . '</table>';
}

function prices_html(array $prices): string
{
    $html = '<table class="facts">';
    foreach ($prices as [$label, $price]) {
        $html .= '<tr><th scope="row">' . e($label) . '</th><td>' . e($price) . '</td></tr>';
    }
    return $html . '</table>';
}

function page_programme(): void
{
    $start = now();
    $screenings = find_screenings('s.starts_at >= ? AND s.starts_at < ?', [sql_time($start), sql_time($start->setTime(0, 0)->modify('+7 days'))]);
    $days = [];
    foreach ($screenings as $s) {
        $days[$s['starts_at']->format('Y-m-d')][] = $s;
    }

    ob_start(); ?>
<div class="page-head">
  <h1>Programmation</h1>
  <p class="lead">Les séances des sept prochains jours. Réservez en ligne jusqu’au début de la projection, puis payez à l’accueil.</p>
</div>
<?php if ($days === []): ?>
  <p class="empty">Aucune séance n’est prévue cette semaine. Revenez bientôt, ou appelez-nous au <?= e(CENTRE_PHONE) ?>.</p>
<?php endif ?>
<?php foreach ($days as $date => $list): ?>
  <section class="day" aria-labelledby="day-<?= e($date) ?>">
    <h2 id="day-<?= e($date) ?>"><?= e(fr_day($list[0]['starts_at'])) ?>
      <?php if (days_from_today($list[0]['starts_at']) <= 1): ?>
        <span class="day-date"><?= e(fr_date($list[0]['starts_at'])) ?></span>
      <?php endif ?>
    </h2>
    <?= schedule_html($list) ?>
  </section>
<?php endforeach ?>
<p class="muted">Tarifs : <?= e(implode(', ', array_map(fn ($p) => mb_strtolower($p[0]) . ' ' . $p[1], PRICES_CINEMA))) ?>. <a href="/infos">Heures et tarifs</a></p>
<?php
    render('Programmation', (string) ob_get_clean(), 'programmation');
}

function page_film(string $slug): void
{
    $film = query('SELECT * FROM films WHERE slug = ?', [$slug])->fetch();
    if ($film === false) {
        not_found();
        return;
    }
    $now = now();
    $screenings = find_screenings('s.film_id = ? AND s.starts_at >= ?', [$film['id'], sql_time($now)], 's.starts_at, r.id', 60);
    $credits = array_filter([$film['year'], $film['director']]);

    ob_start(); ?>
<article class="film">
  <div class="film-poster"><?= poster_html($film) ?></div>
  <div class="film-body">
    <h1><?= e($film['title']) ?></h1>
    <?php if ($credits !== []): ?>
      <p class="film-credits"><?= e(implode(', ', $credits)) ?></p>
    <?php endif ?>
    <p class="film-facts"><?= e(fr_duration((int) $film['duration_min'])) ?>, <?= e(fr_rating($film['rating'])) ?></p>
    <p class="film-synopsis"><?= nl2br(e($film['synopsis'])) ?></p>

    <h2>Prochaines séances</h2>
    <?php if ($screenings === []): ?>
      <p class="empty">Aucune séance n’est prévue pour ce film. <a href="/programmation">Voir la programmation</a></p>
    <?php else: ?>
      <?php
        $days = [];
        foreach ($screenings as $s) {
            $days[$s['starts_at']->format('Y-m-d')][] = $s;
        }
      ?>
      <?php foreach ($days as $list): ?>
        <h3 class="schedule-day"><?= e(fr_day($list[0]['starts_at'])) ?></h3>
        <?= schedule_html($list, false) ?>
      <?php endforeach ?>
    <?php endif ?>
  </div>
</article>
<?php
    render($film['title'], (string) ob_get_clean(), 'programmation');
}

function page_games(): void
{
    $servers = query('SELECT game, name, address, slots, description FROM game_servers ORDER BY game, name')->fetchAll();

    ob_start(); ?>
<div class="page-head">
  <h1>Serveurs de jeux</h1>
  <p class="lead">Le centre héberge des serveurs ouverts à tous. Jouez-y depuis nos postes publics, avec l’adresse indiquée : le jeu est déjà installé. L’accès est gratuit, seul le poste se paie.</p>
</div>
<?php if ($servers === []): ?>
  <p class="empty">Aucun serveur n’est ouvert pour le moment.</p>
<?php endif ?>
<ul class="servers">
  <?php foreach ($servers as $server): ?>
    <li class="server">
      <h2 class="server-game"><?= e($server['game']) ?></h2>
      <p class="server-name"><?= e($server['name']) ?>, <?= (int) $server['slots'] ?> joueurs au maximum</p>
      <p><?= nl2br(e($server['description'])) ?></p>
      <p class="server-address">Adresse <code><?= e($server['address']) ?></code></p>
    </li>
  <?php endforeach ?>
</ul>
<section class="section narrow" aria-labelledby="join-heading">
  <h2 id="join-heading">Pour vous connecter</h2>
  <ol class="steps">
    <li>Lancez le jeu et ouvrez le mode multijoueur.</li>
    <li>Choisissez d’ajouter ou de rejoindre un serveur.</li>
    <li>Entrez l’adresse indiquée ci-dessus, avec le numéro qui suit les deux-points.</li>
  </ol>
  <p class="muted">Un serveur ne répond pas ? Signalez-le à l’accueil ou au <?= e(CENTRE_PHONE) ?>.</p>
</section>
<?php
    render('Serveurs de jeux', (string) ob_get_clean(), 'jeux');
}

function page_workstations(): void
{
    ob_start(); ?>
<div class="page-head">
  <h1>Postes publics</h1>
  <p class="lead"><?= WORKSTATION_COUNT ?> ordinateurs en libre-service pour jouer en réseau ou naviguer. Pas de compte à créer : présentez-vous à l’accueil, on vous attribue un poste.</p>
</div>
<div class="split">
  <section aria-labelledby="ws-use">
    <h2 id="ws-use">Sur les postes</h2>
    <ul class="plain-list">
      <li>Les jeux de nos <a href="/jeux">serveurs</a>, déjà installés.</li>
      <li>Un navigateur web pour vos recherches et vos courriels.</li>
      <li>Des casques d’écoute, prêtés à l’accueil.</li>
    </ul>
    <h2>Bon à savoir</h2>
    <ul class="plain-list">
      <li>Les postes publics sont séparés du réseau du personnel.</li>
      <li>Pensez à vous déconnecter de vos comptes avant de partir.</li>
      <li>Les postes sont attribués dans l’ordre d’arrivée, sans réservation.</li>
    </ul>
  </section>
  <aside aria-labelledby="ws-prices">
    <h2 id="ws-prices">Tarifs</h2>
    <?= prices_html(PRICES_WORKSTATIONS) ?>
    <h2>Heures</h2>
    <?= hours_html() ?>
  </aside>
</div>
<?php
    render('Postes publics', (string) ob_get_clean(), 'postes');
}

function page_info(): void
{
    ob_start(); ?>
<div class="page-head">
  <h1>Heures et tarifs</h1>
  <p class="lead">Le <?= e(CENTRE_NAME) ?> est situé au <?= e(CENTRE_ADDRESS) ?>, à <?= e(CENTRE_CITY) ?>. Toutes les places se paient à l’accueil, en argent comptant ou par carte. Les prix comprennent les taxes.</p>
</div>
<div class="info-grid">
  <section aria-labelledby="info-hours">
    <h2 id="info-hours">Heures d’ouverture</h2>
    <?= hours_html() ?>
  </section>
  <section aria-labelledby="info-cinema">
    <h2 id="info-cinema">Cinéma</h2>
    <?= prices_html(PRICES_CINEMA) ?>
    <p class="muted">Prix par place. Réservez en ligne ou à l’accueil.</p>
  </section>
  <section aria-labelledby="info-ws">
    <h2 id="info-ws">Postes publics</h2>
    <?= prices_html(PRICES_WORKSTATIONS) ?>
    <p class="muted">Les serveurs de jeux sont gratuits.</p>
  </section>
  <section aria-labelledby="info-contact">
    <h2 id="info-contact">Nous joindre</h2>
    <p>Par téléphone au <?= e(CENTRE_PHONE) ?>, pendant les heures d’ouverture, ou par courriel à <a href="mailto:<?= e(CENTRE_EMAIL) ?>"><?= e(CENTRE_EMAIL) ?></a>.</p>
    <p><?= e(CENTRE_ADDRESS) ?><br><?= e(CENTRE_CITY) ?>&nbsp; <?= e(CENTRE_POSTAL_CODE) ?></p>
    <p>Pour une réservation de groupe, appelez-nous au moins deux jours à l’avance.</p>
  </section>
</div>
<?php
    render('Heures et tarifs', (string) ob_get_clean(), 'infos');
}

/** Uploaded posters, served from the volume (never from the web root). */
function page_poster(string $file): void
{
    $path = UPLOAD_DIR . '/' . $file;
    $ext = pathinfo($file, PATHINFO_EXTENSION);
    $type = array_search($ext, POSTER_TYPES, true);
    if ($type === false || !preg_match('/^[a-f0-9]{32}\.[a-z]+$/', $file) || !is_file($path)) {
        not_found();
        return;
    }
    header_remove('Pragma');
    header_remove('Expires');
    header('Content-Type: ' . $type);
    header('Content-Length: ' . filesize($path));
    header('Cache-Control: public, max-age=604800, immutable');     // names never change
    readfile($path);
}

/** @return array<string, array{ok: bool, detail: string}> */
function status_checks(): array
{
    $check = fn (bool $ok, string $detail): array => ['ok' => $ok, 'detail' => $detail];
    $checks = [];

    $checks['php'] = $check(true, 'PHP ' . PHP_VERSION . ' (' . PHP_SAPI . ')');

    $missing = array_values(array_filter(
        ['pdo_mysql', 'mysqli', 'fileinfo', 'mbstring'],
        fn (string $ext): bool => !extension_loaded($ext),
    ));
    $checks['extensions'] = $missing === []
        ? $check(true, 'pdo_mysql, mysqli, fileinfo and mbstring loaded')
        : $check(false, 'missing: ' . implode(', ', $missing));

    try {
        $version = (string) db()->query('SELECT VERSION()')->fetchColumn();
        $tables = db()->query('SHOW TABLES')->fetchAll(PDO::FETCH_COLUMN);
        $wanted = ['users', 'rooms', 'films', 'screenings', 'reservations', 'password_resets', 'announcements', 'game_servers'];
        $missing = array_values(array_diff($wanted, $tables));
        $checks['database'] = $check(true, 'MariaDB ' . $version);
        $checks['schema'] = $missing === []
            ? $check(true, count($wanted) . ' tables present')
            : $check(false, 'missing tables: ' . implode(', ', $missing));
    } catch (PDOException $e) {
        error_log('Status check: ' . $e->getMessage());
        $checks['database'] = $check(false, 'cannot connect (details in the pod logs)');
        $checks['schema'] = $check(false, 'not checked');
    }

    $writable = is_dir(UPLOAD_DIR) && is_writable(UPLOAD_DIR);
    $checks['uploads'] = $writable
        ? $check(true, 'volume writable')
        : $check(false, UPLOAD_DIR . ' is not writable');

    // /status is not a file: if index.php is answering, Apache rewrote it.
    $path = (string) parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
    $checks['rewrite'] = $path !== $_SERVER['SCRIPT_NAME']
        ? $check(true, $path . ' was rewritten to ' . $_SERVER['SCRIPT_NAME'])
        : $check(false, 'request was not rewritten');

    return $checks;
}

/** Health check for the smoke test and monitoring. Details are for staff only. */
function page_status(): void
{
    $checks = status_checks();
    $all_ok = !in_array(false, array_column($checks, 'ok'), true);
    $_SESSION['visits'] = ($_SESSION['visits'] ?? 0) + 1;

    $staff = false;
    try {
        $staff = is_staff(current_user());
    } catch (Throwable) {
    }
    if (!$staff) {
        $checks = array_map(fn (array $c): array => ['ok' => $c['ok'], 'detail' => ''], $checks);
    }

    http_response_code($all_ok ? 200 : 503);
    header('Content-Type: application/json');
    echo json_encode([
        'ok' => $all_ok,
        'checks' => $checks,
        'session_visits' => $_SESSION['visits'],
        'pod' => $staff ? (getenv('POD_NAME') ?: gethostname()) : '',
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}
