<?php
declare(strict_types=1);

// Setup for every web request: error page, security headers, session,
// accounts, CSRF protection and page rendering. Loaded by index.php.

// Absolute paths: in a ConfigMap, __DIR__ points into a hidden ..data folder.
require '/var/www/html/app/core.php';
require APP_DIR . '/content.php';
require APP_DIR . '/views.php';

set_exception_handler(function (Throwable $e): void {
    error_log((string) $e);
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    if (!headers_sent()) {
        http_response_code(500);
    }
    render('Erreur', '<div class="page-head"><h1>La page n’a pas pu être affichée</h1></div>'
        . '<p class="lead">Réessayez dans un moment. Si le problème continue, avisez le personnel à l’accueil.</p>');
});

header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: same-origin');
header("Content-Security-Policy: default-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'");

// Sessions are stored in the pod, so restarting it logs everyone out.
ini_set('session.use_strict_mode', '1');
ini_set('session.cookie_samesite', 'Lax');
session_name('cde_session');
session_start();

/** Trimmed text field from the submitted form ('' if missing). */
function field(string $name): string
{
    $value = $_POST[$name] ?? '';
    return is_string($value) ? trim($value) : '';
}

function redirect(string $path): never
{
    header('Location: ' . $path, true, 303);
    exit;
}

/** Message shown once, on the next page. $type is 'ok' or 'erreur'. */
function flash(string $message, string $type = 'ok'): void
{
    $_SESSION['flash'] = ['message' => $message, 'type' => $type];
}

/** @return array{message: string, type: string}|null */
function take_flash(): ?array
{
    $flash = $_SESSION['flash'] ?? null;
    unset($_SESSION['flash']);
    return $flash;
}

// ---------------------------------------------------------------------
// Accounts. The user is read from the database on each request, so a
// role change or a deleted account takes effect right away.

/** @return array{id: int, name: string, email: string, role: string}|null */
function current_user(bool $reload = false): ?array
{
    static $user = false;
    if ($user === false || $reload) {
        $user = null;
        if (isset($_SESSION['user_id'])) {
            $row = query('SELECT id, name, email, role FROM users WHERE id = ?', [$_SESSION['user_id']])->fetch();
            if ($row === false) {
                unset($_SESSION['user_id']);
            } else {
                $user = ['id' => (int) $row['id'], 'name' => $row['name'], 'email' => $row['email'], 'role' => $row['role']];
            }
        }
    }
    return $user;
}

function is_staff(?array $user): bool
{
    return $user !== null && $user['role'] === 'staff';
}

function log_in(int $user_id): void
{
    session_regenerate_id(true);
    $_SESSION['user_id'] = $user_id;
    current_user(true);
}

/** @return array{id: int, name: string, email: string, role: string} */
function require_login(): array
{
    $user = current_user();
    if ($user === null) {
        if ($_SERVER['REQUEST_METHOD'] === 'GET') {
            $_SESSION['after_login'] = $_SERVER['REQUEST_URI'];
        }
        flash('Connectez-vous pour continuer.');
        redirect('/connexion');
    }
    return $user;
}

/** @return array{id: int, name: string, email: string, role: string} */
function require_staff(): array
{
    $user = require_login();
    if (!is_staff($user)) {
        http_response_code(403);
        render('Accès réservé', '<div class="page-head"><h1>Accès réservé au personnel</h1></div>'
            . '<p class="lead">Cette section sert à gérer la programmation du centre.</p>'
            . '<p><a href="/">Retour à l’accueil</a></p>');
        exit;
    }
    return $user;
}

/** Where to go after logging in: the page that asked for it, if it is ours. */
function take_after_login(string $default): string
{
    $path = $_SESSION['after_login'] ?? '';
    unset($_SESSION['after_login']);
    return is_string($path) && str_starts_with($path, '/') && !str_starts_with($path, '//') ? $path : $default;
}

// ---------------------------------------------------------------------
// Forms

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf'];
}

function csrf_field(): string
{
    return '<input type="hidden" name="csrf" value="' . e(csrf_token()) . '">';
}

/** Runs before every POST handler. */
function check_post(): void
{
    // A body larger than post_max_size reaches PHP empty: report the size
    // instead of a missing form token.
    if ($_POST === [] && $_FILES === [] && (int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > 0) {
        http_response_code(413);
        render('Envoi trop volumineux', '<div class="page-head"><h1>Envoi trop volumineux</h1></div>'
            . '<p class="lead">Le formulaire dépasse la limite de ' . e(rtrim((string) ini_get('post_max_size'), 'M'))
            . "\u{a0}Mo. Revenez en arrière et choisissez un fichier plus petit.</p>");
        exit;
    }
    $token = $_POST['csrf'] ?? '';
    if (!is_string($token) || !hash_equals(csrf_token(), $token)) {
        http_response_code(400);
        render('Formulaire expiré', '<div class="page-head"><h1>Formulaire expiré</h1></div>'
            . '<p class="lead">Revenez en arrière, rechargez la page et envoyez le formulaire de nouveau.</p>');
        exit;
    }
}

// ---------------------------------------------------------------------
// Pages

/** Renders a page in the layout. $section highlights the menu entry. */
function render(string $title, string $content, string $section = ''): void
{
    try {
        $user = current_user();
    } catch (Throwable) {
        $user = null;           // the database is down: still show the page
    }
    $flash = take_flash();
    require APP_DIR . '/layout.php';
}

function not_found(): void
{
    http_response_code(404);
    render('Page introuvable', '<div class="page-head"><h1>Page introuvable</h1></div>'
        . '<p class="lead">Cette adresse ne mène à rien. La séance ou le film a peut-être été retiré.</p>'
        . '<p><a href="/programmation">Voir la programmation</a></p>');
}
