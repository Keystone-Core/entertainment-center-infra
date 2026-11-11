<?php
declare(strict_types=1);

// Shared by the web pages and cli.php: configuration, database access,
// French formatting and the rules about screenings. No output here.

const APP_DIR = '/var/www/html/app';
const UPLOAD_DIR = '/var/www/html/storage/uploads';

const MAX_SEATS = 6;                     // places per reservation
const ROOM_TURNOVER_MIN = 15;            // between two screenings in a room
const POSTER_MAX_BYTES = 5 * 1024 * 1024;
const POSTER_TYPES = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
const RESET_LINK_HOURS = 24;             // validity of a link to choose a new password
const MAIL_FROM_NAME = 'Centre de divertissement de l’Estrie';

const JOURS = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi'];
const MOIS = [1 => 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre'];

/** A problem the visitor can fix: the message is shown as is. */
final class UserError extends RuntimeException
{
}

function env(string $name): string
{
    $value = getenv($name);
    if ($value === false || $value === '') {
        throw new RuntimeException("Environment variable $name is not set");
    }
    return $value;
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf('mysql:host=%s;dbname=%s;charset=utf8mb4', env('DB_HOST'), env('DB_NAME'));
        $pdo = new PDO($dsn, env('DB_USER'), env('DB_PASSWORD'), [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
            PDO::ATTR_TIMEOUT => 5,
        ]);
    }
    return $pdo;
}

/** Runs a prepared query and returns the statement. */
function query(string $sql, array $params = []): PDOStatement
{
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    return $stmt;
}

function now(): DateTimeImmutable
{
    return new DateTimeImmutable('now');
}

function sql_time(DateTimeInterface $time): string
{
    return $time->format('Y-m-d H:i:s');
}

function e(string|int|null $text): string
{
    return htmlspecialchars((string) $text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

// ---------------------------------------------------------------------
// French formatting (the image has no intl extension)

/** "vendredi 23 octobre", "samedi 1er novembre 2026" */
function fr_date(DateTimeInterface $date, bool $with_year = false): string
{
    $day = $date->format('j');
    $text = JOURS[(int) $date->format('w')] . ' ' . $day . ($day === '1' ? 'er' : '') . ' '
        . MOIS[(int) $date->format('n')];
    return $with_year ? $text . ' ' . $date->format('Y') : $text;
}

/** 0 for today, 1 for tomorrow, -1 for yesterday... */
function days_from_today(DateTimeInterface $date): int
{
    $today = now()->setTime(0, 0);
    $day = DateTimeImmutable::createFromInterface($date)->setTime(0, 0);
    return (int) $today->diff($day)->format('%r%a');
}

/** "Aujourd’hui", "Demain" or the date. */
function fr_day(DateTimeInterface $date): string
{
    return match (days_from_today($date)) {
        0 => 'Aujourd’hui',
        1 => 'Demain',
        default => ucfirst(fr_date($date)),
    };
}

/** "19 h", "19 h 30", with non-breaking spaces. */
function fr_time(DateTimeInterface $time): string
{
    $minutes = $time->format('i');
    return $time->format('G') . "\u{a0}h" . ($minutes === '00' ? '' : "\u{a0}" . $minutes);
}

/** "1 h 28", "45 min" */
function fr_duration(int $minutes): string
{
    if ($minutes < 60) {
        return $minutes . "\u{a0}min";
    }
    $rest = $minutes % 60;
    return intdiv($minutes, 60) . "\u{a0}h" . ($rest === 0 ? '' : "\u{a0}" . str_pad((string) $rest, 2, '0', STR_PAD_LEFT));
}

function fr_rating(string $rating): string
{
    return match ($rating) {
        'G' => 'Général',
        '13+' => '13 ans et plus',
        '16+' => '16 ans et plus',
        '18+' => '18 ans et plus',
        default => $rating,
    };
}

function fr_places(int $count): string
{
    return $count . ($count > 1 ? ' places' : ' place');
}

/** URL part made from a title: "Le Mécano de la « General »" -> "le-mecano-de-la-general" */
function slugify(string $text): string
{
    $text = mb_strtolower($text, 'UTF-8');
    $text = strtr($text, [
        'à' => 'a', 'â' => 'a', 'ä' => 'a', 'á' => 'a', 'ç' => 'c', 'é' => 'e', 'è' => 'e', 'ê' => 'e',
        'ë' => 'e', 'î' => 'i', 'ï' => 'i', 'í' => 'i', 'ô' => 'o', 'ö' => 'o', 'ó' => 'o', 'ù' => 'u',
        'û' => 'u', 'ü' => 'u', 'ú' => 'u', 'ÿ' => 'y', 'ñ' => 'n', 'œ' => 'oe', 'æ' => 'ae',
    ]);
    $text = trim((string) preg_replace('/[^a-z0-9]+/', '-', $text), '-');
    return $text !== '' ? substr($text, 0, 100) : 'film';
}

// ---------------------------------------------------------------------
// Screenings

/**
 * Screenings with their film, room and the places still free.
 *
 * @return list<array<string, mixed>>
 */
function find_screenings(string $where, array $params = [], string $order = 's.starts_at, r.id', int $limit = 500): array
{
    $rows = query(
        "SELECT s.id, s.starts_at, s.film_id, s.room_id, r.name AS room, r.capacity,
                f.title, f.slug, f.duration_min, f.rating, f.year, f.director, f.poster,
                r.capacity - (SELECT COALESCE(SUM(b.seats), 0) FROM reservations b
                              WHERE b.screening_id = s.id) AS seats_left
         FROM screenings s
         JOIN films f ON f.id = s.film_id
         JOIN rooms r ON r.id = s.room_id
         WHERE $where
         ORDER BY $order
         LIMIT $limit",
        $params,
    )->fetchAll();

    foreach ($rows as &$row) {
        $row['starts_at'] = new DateTimeImmutable($row['starts_at']);
        $row['seats_left'] = max(0, (int) $row['seats_left']);
    }
    return $rows;
}

/**
 * The screening that would overlap a new one in the same room, counting
 * the film's length and the time to empty and clean the room.
 *
 * @return array<string, mixed>|null
 */
function screening_conflict(int $room_id, DateTimeImmutable $start, int $duration_min, int $ignore_id = 0): ?array
{
    $end = $start->modify('+' . ($duration_min + ROOM_TURNOVER_MIN) . ' minutes');
    $conflict = query(
        'SELECT s.id, s.starts_at, f.title
         FROM screenings s JOIN films f ON f.id = s.film_id
         WHERE s.room_id = ? AND s.id <> ?
           AND s.starts_at < ?
           AND DATE_ADD(s.starts_at, INTERVAL f.duration_min + ? MINUTE) > ?
         LIMIT 1',
        [$room_id, $ignore_id, sql_time($end), ROOM_TURNOVER_MIN, sql_time($start)],
    )->fetch();
    return $conflict === false ? null : $conflict;
}

/** Booking code without look-alike characters (no 0/O, 1/I). */
function booking_code(): string
{
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    $code = '';
    for ($i = 0; $i < 8; $i++) {
        $code .= $alphabet[random_int(0, strlen($alphabet) - 1)];
    }
    return $code;
}

// ---------------------------------------------------------------------
// Forgotten passwords: one-time links, sent by email or given by the staff.
// Only a hash of the token is stored, so the table alone opens no account.

/** The site's public address, for the links in emails. */
function site_url(): string
{
    return rtrim(getenv('SITE_URL') ?: 'https://www.divertissementestrie.ca', '/');
}

/** A new link to choose a password. It replaces the account's older links. */
function create_reset_link(int $user_id): string
{
    $token = bin2hex(random_bytes(32));
    query('DELETE FROM password_resets WHERE user_id = ?', [$user_id]);
    query('INSERT INTO password_resets (user_id, token_hash, expires_at) VALUES (?, ?, ?)',
        [$user_id, hash('sha256', $token), sql_time(now()->modify('+' . RESET_LINK_HOURS . ' hours'))]);
    return site_url() . '/mot-de-passe/' . $token;
}

/** @return array{user_id: int, name: string, email: string, role: string}|null the account, if the link is still valid */
function find_reset(string $token): ?array
{
    $row = query(
        'SELECT r.user_id, u.name, u.email, u.role
         FROM password_resets r JOIN users u ON u.id = r.user_id
         WHERE r.token_hash = ? AND r.expires_at > ?',
        [hash('sha256', $token), sql_time(now())],
    )->fetch();
    return $row === false ? null : ['user_id' => (int) $row['user_id']] + $row;
}

/**
 * Sends a plain-text email through the SMTP server in SMTP_HOST (mail01),
 * logging in with SMTP_USER and SMTP_PASSWORD if they're set. Returns false
 * when no server is set up or the server refuses the message.
 */
function send_mail(string $to, string $subject, string $body): bool
{
    $host = getenv('SMTP_HOST') ?: '';
    if ($host === '' || filter_var($to, FILTER_VALIDATE_EMAIL) === false) {
        return false;
    }
    $from = getenv('SMTP_FROM') ?: 'no-reply@divertissementestrie.ca';
    $port = (int) (getenv('SMTP_PORT') ?: 587);
    $socket = @stream_socket_client("tcp://$host:$port", $errno, $error, 5);
    if ($socket === false) {
        error_log("SMTP $host:$port unreachable: $error");
        return false;
    }
    stream_set_timeout($socket, 10);

    $encode = fn (string $text): string => '=?UTF-8?B?' . base64_encode($text) . '?=';
    $message = implode("\r\n", [
        'From: ' . $encode(MAIL_FROM_NAME) . " <$from>",
        "To: <$to>",
        'Subject: ' . $encode($subject),
        'Date: ' . date(DATE_RFC2822),
        'Message-ID: <' . bin2hex(random_bytes(12)) . '@divertissementestrie.ca>',
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: base64',
        '',
        rtrim(chunk_split(base64_encode(str_replace("\n", "\r\n", $body)), 76, "\r\n")),
    ]);

    // Each step: the line to send (null for the greeting) and the reply code expected.
    $steps = [[null, '220'], ['EHLO ' . (gethostname() ?: 'site'), '250']];
    $user = getenv('SMTP_USER') ?: '';
    if ($user !== '') {
        $steps[] = ['AUTH LOGIN', '334'];
        $steps[] = [base64_encode($user), '334'];
        $steps[] = [base64_encode(getenv('SMTP_PASSWORD') ?: ''), '235'];
    }
    array_push($steps, ["MAIL FROM:<$from>", '250'], ["RCPT TO:<$to>", '250'], ['DATA', '354'], [$message . "\r\n.", '250']);

    foreach ($steps as [$line, $code]) {
        if ($line !== null) {
            fwrite($socket, $line . "\r\n");
        }
        do {
            $reply = fgets($socket, 515);
        } while ($reply !== false && ($reply[3] ?? '') === '-');
        if ($reply === false || !str_starts_with($reply, $code)) {
            error_log('SMTP refused the message: ' . trim((string) $reply));
            fclose($socket);
            return false;
        }
    }
    fwrite($socket, "QUIT\r\n");
    fclose($socket);
    return true;
}
