<?php
/**
 * Page layout, included by render().
 *
 * @var string $title
 * @var string $content  HTML, already escaped
 * @var string $section  menu entry to highlight
 * @var array{id: int, name: string, email: string, role: string}|null $user
 * @var array{message: string, type: string}|null $flash
 */
$nav = [
    'programmation' => ['/programmation', 'Programmation'],
    'jeux' => ['/jeux', 'Serveurs de jeux'],
    'postes' => ['/postes', 'Postes publics'],
    'infos' => ['/infos', 'Heures et tarifs'],
];
$current = fn (string $key): string => $section === $key ? ' aria-current="page"' : '';
$page_title = $section === 'accueil' ? CENTRE_NAME : $title . ' – ' . CENTRE_NAME;
// Changes with each deployment, so browsers fetch the new stylesheet.
$asset_version = (int) @filemtime('/var/www/html/public/site.css');
?>
<!doctype html>
<html lang="fr-CA">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title><?= e($page_title) ?></title>
  <meta name="description" content="Cinéma, serveurs de jeux et postes publics à Sherbrooke.">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <link rel="preload" href="/big-shoulders.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="stylesheet" href="/site.css?v=<?= $asset_version ?>">
</head>
<body>
  <a class="skip-link" href="#contenu">Aller au contenu</a>
  <header class="site-header">
    <div class="wrap header-inner">
      <a class="wordmark" href="/"><?= e(CENTRE_NAME) ?></a>
      <div class="nav-row">
        <nav class="main-nav" aria-label="Navigation principale">
          <?php foreach ($nav as $key => [$href, $label]): ?>
            <a href="<?= $href ?>"<?= $current($key) ?>><?= e($label) ?></a>
          <?php endforeach ?>
        </nav>
        <div class="account-nav">
          <?php if ($user === null): ?>
            <a href="/connexion"<?= $current('compte') ?>>Connexion</a>
          <?php else: ?>
            <?php if ($user['role'] === 'staff'): ?>
              <a href="/gestion"<?= $current('gestion') ?>>Gestion</a>
            <?php endif ?>
            <a href="/compte"<?= $current('compte') ?>>Mes réservations</a>
            <form method="post" action="/deconnexion">
              <?= csrf_field() ?>
              <button class="link-button" type="submit">Déconnexion</button>
            </form>
          <?php endif ?>
        </div>
      </div>
    </div>
  </header>

  <main id="contenu" class="wrap main">
    <?php if ($flash !== null): ?>
      <div class="flash flash-<?= e($flash['type']) ?>" role="<?= $flash['type'] === 'erreur' ? 'alert' : 'status' ?>"><?= e($flash['message']) ?></div>
    <?php endif ?>
    <?= $content ?>
  </main>

  <footer class="site-footer">
    <div class="wrap footer-inner">
      <div>
        <p class="footer-name"><?= e(CENTRE_NAME) ?></p>
        <p><?= e(CENTRE_ADDRESS) ?><br><?= e(CENTRE_CITY) ?>&nbsp; <?= e(CENTRE_POSTAL_CODE) ?></p>
        <p><?= e(CENTRE_PHONE) ?><br><a href="mailto:<?= e(CENTRE_EMAIL) ?>"><?= e(CENTRE_EMAIL) ?></a></p>
      </div>
      <div>
        <h2 class="footer-heading">Heures d’ouverture</h2>
        <ul class="footer-hours">
          <?php foreach (CENTRE_HOURS as [$day, $hours]): ?>
            <li><?= e($day) ?> <span><?= e($hours) ?></span></li>
          <?php endforeach ?>
        </ul>
      </div>
      <nav aria-label="Liens du pied de page">
        <h2 class="footer-heading">Au centre</h2>
        <ul class="footer-links">
          <li><a href="/programmation">Programmation</a></li>
          <li><a href="/jeux">Serveurs de jeux</a></li>
          <li><a href="/postes">Postes publics</a></li>
          <li><a href="/infos">Heures et tarifs</a></li>
        </ul>
      </nav>
    </div>
  </footer>
</body>
</html>
