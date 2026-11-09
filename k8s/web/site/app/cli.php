<?php
declare(strict_types=1);

// Admin commands, run inside the php pod:
//
//   kubectl -n web exec deploy/php -- php /var/www/html/app/cli.php <command>
//
//   staff <email>        give an account access to /gestion
//   client <email>       remove that access
//   delete-user <email>  delete an account and its reservations
//   demo                 add demo screenings for the next 7 days

if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require '/var/www/html/app/core.php';

function fail(string $message): never
{
    fwrite(STDERR, $message . PHP_EOL);
    exit(1);
}

function find_user_id(string $email): int
{
    $id = query('SELECT id FROM users WHERE email = ?', [mb_strtolower($email)])->fetchColumn();
    if ($id === false) {
        fail("No account with the email $email");
    }
    return (int) $id;
}

/**
 * Adds screenings for the next 7 days, rotating through the films. Skips
 * Mondays (closed), times already past, and slots that overlap a
 * screening already in the room. Safe to run again.
 */
function add_demo_screenings(): int
{
    $films = query('SELECT id, duration_min FROM films ORDER BY id')->fetchAll();
    if ($films === []) {
        fail('No films: add some first.');
    }
    $evening = [[2, '18:30'], [1, '19:00'], [2, '20:45'], [1, '21:30']];
    $matinee = [[1, '14:00'], [2, '14:30']];

    $added = 0;
    $turn = 0;
    for ($d = 0; $d < 7; $d++) {
        $day = now()->setTime(0, 0)->modify("+$d days");
        $weekday = (int) $day->format('N');              // 1 = Monday
        if ($weekday === 1) {
            continue;
        }
        $slots = $weekday >= 6 ? array_merge($matinee, $evening) : $evening;
        foreach ($slots as [$room, $time]) {
            [$hour, $minute] = array_map('intval', explode(':', $time));
            $start = $day->setTime($hour, $minute);
            $film = $films[$turn++ % count($films)];
            if ($start <= now() || screening_conflict($room, $start, (int) $film['duration_min']) !== null) {
                continue;
            }
            query('INSERT INTO screenings (film_id, room_id, starts_at) VALUES (?, ?, ?)', [$film['id'], $room, sql_time($start)]);
            $added++;
        }
    }
    return $added;
}

$command = $argv[1] ?? '';
$email = $argv[2] ?? '';

switch ($command) {
    case 'staff':
    case 'client':
        $id = find_user_id($email);
        query('UPDATE users SET role = ? WHERE id = ?', [$command, $id]);
        echo "$email is now $command" . PHP_EOL;
        break;

    case 'delete-user':
        $id = find_user_id($email);
        query('DELETE FROM users WHERE id = ?', [$id]);
        echo "Deleted $email and its reservations" . PHP_EOL;
        break;

    case 'demo':
        echo add_demo_screenings() . ' screenings added' . PHP_EOL;
        break;

    default:
        fail("Usage: php cli.php staff|client|delete-user <email>\n       php cli.php demo");
}
