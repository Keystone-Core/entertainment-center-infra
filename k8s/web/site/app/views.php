<?php
declare(strict_types=1);

// HTML pieces used by several pages. Every value is escaped here.

/**
 * The film's poster, or a typographic one when no poster was uploaded.
 *
 * @param array<string, mixed> $film needs id (or film_id), title, year, director, poster
 */
function poster_html(array $film): string
{
    $title = (string) $film['title'];
    if (!empty($film['poster'])) {
        return '<img class="poster" src="/affiches/' . e($film['poster']) . '" alt="Affiche de ' . e($title)
            . '" width="400" height="600" loading="lazy">';
    }
    $tone = ((int) ($film['film_id'] ?? $film['id'])) % 5;
    return '<div class="poster poster-type tone-' . $tone . '" role="img" aria-label="Affiche de ' . e($title) . '">'
        . '<span class="poster-year">' . e($film['year'] ?? '') . '</span>'
        . '<span class="poster-bottom"><span class="poster-title">' . e($title) . '</span>'
        . (empty($film['director']) ? '' : '<span class="poster-credit">' . e($film['director']) . '</span>')
        . '</span></div>';
}

/** "12 places libres" or "Complet"; few places left get their own color. */
function seats_html(int $left): string
{
    if ($left <= 0) {
        return '<span class="seats seats-full">Complet</span>';
    }
    $text = $left === 1 ? '1 place libre' : $left . ' places libres';
    $class = $left <= 5 ? 'seats seats-low' : 'seats';
    return '<span class="' . $class . '">' . e($text) . '</span>';
}

/**
 * Screenings as schedule rows: time, film, room, places, booking link.
 *
 * @param list<array<string, mixed>> $screenings from find_screenings()
 */
function schedule_html(array $screenings, bool $show_film = true): string
{
    $html = '<ul class="schedule">';
    foreach ($screenings as $s) {
        $meta = [$s['room'], fr_duration((int) $s['duration_min']), fr_rating($s['rating'])];
        $html .= '<li class="schedule-row">'
            . '<time class="schedule-time" datetime="' . e($s['starts_at']->format('Y-m-d\TH:i')) . '">'
            . e(fr_time($s['starts_at'])) . '</time>'
            . '<div class="schedule-film">';
        if ($show_film) {
            $html .= '<a class="schedule-title" href="/films/' . e($s['slug']) . '">' . e($s['title']) . '</a>';
        }
        $html .= '<span class="schedule-meta">' . e(implode(', ', $meta)) . '</span></div>'
            . '<div class="schedule-book">' . seats_html((int) $s['seats_left']);
        if ($s['seats_left'] > 0) {
            $html .= '<a class="button button-small" href="/seances/' . (int) $s['id'] . '">Réserver</a>';
        }
        $html .= '</div></li>';
    }
    return $html . '</ul>';
}

/**
 * A reservation shown as a ticket: film, date, time, room, places, code.
 *
 * @param array<string, mixed> $r reservation joined with its screening
 */
function ticket_html(array $r, bool $can_cancel = false): string
{
    $start = $r['starts_at'] instanceof DateTimeInterface ? $r['starts_at'] : new DateTimeImmutable($r['starts_at']);
    $html = '<article class="ticket">'
        . '<div class="ticket-main">'
        . '<h3 class="ticket-film"><a href="/films/' . e($r['slug']) . '">' . e($r['title']) . '</a></h3>'
        . '<dl class="ticket-facts">'
        . '<div><dt>Date</dt><dd>' . e(ucfirst(fr_date($start))) . '</dd></div>'
        . '<div><dt>Heure</dt><dd>' . e(fr_time($start)) . '</dd></div>'
        . '<div><dt>Salle</dt><dd>' . e($r['room']) . '</dd></div>'
        . '<div><dt>Places</dt><dd>' . (int) $r['seats'] . '</dd></div>'
        . '</dl>';
    if ($can_cancel) {
        $html .= '<form method="post" action="/reservations/' . e($r['code']) . '/annuler">' . csrf_field()
            . '<button class="link-button" type="submit">Annuler la réservation</button></form>';
    }
    return $html . '</div>'
        . '<div class="ticket-stub"><span class="ticket-code-label">Code</span>'
        . '<strong class="ticket-code">' . e($r['code']) . '</strong></div>'
        . '</article>';
}

/** Menu of the staff section. */
function admin_nav(string $current): string
{
    $links = [
        '/gestion' => 'Aujourd’hui',
        '/gestion/seances' => 'Séances',
        '/gestion/films' => 'Films',
        '/gestion/annonces' => 'Annonces',
        '/gestion/jeux' => 'Serveurs de jeux',
    ];
    $html = '<nav class="admin-nav" aria-label="Gestion">';
    foreach ($links as $href => $label) {
        $html .= '<a href="' . $href . '"' . ($href === $current ? ' aria-current="page"' : '') . '>' . e($label) . '</a>';
    }
    $pma = getenv('PMA_URL') ?: '';
    if ($pma !== '') {
        $html .= '<a class="admin-nav-external" href="' . e($pma) . '">Base de données</a>';
    }
    return $html . '</nav>';
}

/** <option> list; $selected is compared as a string. */
function options_html(array $options, string|int|null $selected): string
{
    $html = '';
    foreach ($options as $value => $label) {
        $html .= '<option value="' . e($value) . '"' . ((string) $value === (string) $selected ? ' selected' : '') . '>'
            . e($label) . '</option>';
    }
    return $html;
}
