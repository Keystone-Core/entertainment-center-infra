<?php
declare(strict_types=1);

// Front controller: .htaccess sends every request that isn't a real file
// here. The code lives outside the web root, in /var/www/html/app.
// (Absolute path: in a ConfigMap, __DIR__ points into a hidden ..data folder.)
require '/var/www/html/app/web.php';
require APP_DIR . '/public.php';
require APP_DIR . '/account.php';
require APP_DIR . '/admin.php';

// [method, path pattern, handler]. Captured parts are passed as strings.
$routes = [
    ['GET',  '#^/$#',                                 'page_home'],
    ['GET',  '#^/programmation$#',                    'page_programme'],
    ['GET',  '#^/films/([a-z0-9-]+)$#',               'page_film'],
    ['GET',  '#^/jeux$#',                             'page_games'],
    ['GET',  '#^/postes$#',                           'page_workstations'],
    ['GET',  '#^/infos$#',                            'page_info'],
    ['GET',  '#^/affiches/([a-z0-9.]+)$#',            'page_poster'],
    ['GET',  '#^/status$#',                           'page_status'],

    ['GET',  '#^/inscription$#',                      'page_register_form'],
    ['POST', '#^/inscription$#',                      'page_register'],
    ['GET',  '#^/connexion$#',                        'page_login_form'],
    ['POST', '#^/connexion$#',                        'page_login'],
    ['POST', '#^/deconnexion$#',                      'page_logout'],
    ['GET',  '#^/compte$#',                           'page_account'],
    ['GET',  '#^/seances/(\d+)$#',                    'page_screening'],
    ['POST', '#^/seances/(\d+)/reserver$#',           'page_reserve'],
    ['GET',  '#^/reservations/([A-Z0-9]{8})$#',       'page_ticket'],
    ['POST', '#^/reservations/([A-Z0-9]{8})/annuler$#', 'page_cancel'],

    ['GET',  '#^/gestion$#',                          'page_admin_home'],
    ['GET',  '#^/gestion/seances$#',                  'page_admin_screenings'],
    ['POST', '#^/gestion/seances$#',                  'page_admin_screening_create'],
    ['GET',  '#^/gestion/seances/(\d+)$#',            'page_admin_screening'],
    ['POST', '#^/gestion/seances/(\d+)/supprimer$#',  'page_admin_screening_delete'],
    ['GET',  '#^/gestion/films$#',                    'page_admin_films'],
    ['POST', '#^/gestion/films$#',                    'page_admin_film_create'],
    ['GET',  '#^/gestion/films/nouveau$#',            'page_admin_film_new'],
    ['GET',  '#^/gestion/films/(\d+)$#',              'page_admin_film'],
    ['POST', '#^/gestion/films/(\d+)$#',              'page_admin_film_update'],
    ['POST', '#^/gestion/films/(\d+)/supprimer$#',    'page_admin_film_delete'],
    ['GET',  '#^/gestion/annonces$#',                 'page_admin_news'],
    ['POST', '#^/gestion/annonces$#',                 'page_admin_news_create'],
    ['POST', '#^/gestion/annonces/(\d+)/supprimer$#', 'page_admin_news_delete'],
    ['GET',  '#^/gestion/jeux$#',                     'page_admin_games'],
    ['POST', '#^/gestion/jeux$#',                     'page_admin_game_create'],
    ['GET',  '#^/gestion/jeux/(\d+)$#',               'page_admin_game'],
    ['POST', '#^/gestion/jeux/(\d+)$#',               'page_admin_game_update'],
    ['POST', '#^/gestion/jeux/(\d+)/supprimer$#',     'page_admin_game_delete'],
];

$method = $_SERVER['REQUEST_METHOD'];
$path = rtrim(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/', '/') ?: '/';

$path_matched = false;
foreach ($routes as [$route_method, $pattern, $handler]) {
    if (!preg_match($pattern, $path, $m)) {
        continue;
    }
    $path_matched = true;
    if ($route_method === $method) {
        if ($method === 'POST') {
            check_post();
        }
        $handler(...array_slice($m, 1));
        exit;
    }
}

if ($path_matched) {
    http_response_code(405);
    render('Action impossible', '<div class="page-head"><h1>Action impossible</h1></div>'
        . '<p class="lead">Cette adresse ne s’utilise pas de cette façon. <a href="/">Retour à l’accueil</a></p>');
} else {
    not_found();
}
