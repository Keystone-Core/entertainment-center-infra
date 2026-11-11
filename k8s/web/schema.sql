-- Schema and starting content for the site of the Centre de divertissement
-- de l'Estrie. MariaDB runs this once, in the `site` database, the first
-- time it starts with an empty data folder. Screenings are added by staff,
-- or for a demo with: php /var/www/html/app/cli.php demo

CREATE TABLE users (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(100) NOT NULL,
  email         VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  role          ENUM('client', 'staff') NOT NULL DEFAULT 'client',
  created_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE rooms (
  id       TINYINT UNSIGNED  PRIMARY KEY,
  name     VARCHAR(50)       NOT NULL,
  capacity SMALLINT UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE films (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  slug         VARCHAR(120)      NOT NULL UNIQUE,
  title        VARCHAR(200)      NOT NULL,
  year         SMALLINT UNSIGNED NULL,
  director     VARCHAR(150)      NULL,
  duration_min SMALLINT UNSIGNED NOT NULL,
  rating       ENUM('G', '13+', '16+', '18+') NOT NULL DEFAULT 'G',
  synopsis     TEXT              NOT NULL,
  -- File name on the uploads volume, NULL when there is no poster.
  poster       VARCHAR(40)       NULL,
  created_at   TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE screenings (
  id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  film_id   INT UNSIGNED     NOT NULL,
  room_id   TINYINT UNSIGNED NOT NULL,
  starts_at DATETIME         NOT NULL,
  UNIQUE KEY room_start (room_id, starts_at),
  KEY starts_at (starts_at),
  FOREIGN KEY (film_id) REFERENCES films (id) ON DELETE CASCADE,
  FOREIGN KEY (room_id) REFERENCES rooms (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE reservations (
  id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  code         CHAR(8)          NOT NULL UNIQUE,
  screening_id INT UNSIGNED     NOT NULL,
  user_id      INT UNSIGNED     NOT NULL,
  seats        TINYINT UNSIGNED NOT NULL,
  created_at   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY one_per_user (screening_id, user_id),
  FOREIGN KEY (screening_id) REFERENCES screenings (id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One-time links to choose a new password (site/app/core.php). Only a
-- hash of the token is stored.
CREATE TABLE password_resets (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id    INT UNSIGNED NOT NULL,
  token_hash CHAR(64)     NOT NULL UNIQUE,
  expires_at DATETIME     NOT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE announcements (
  id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  title      VARCHAR(200) NOT NULL,
  body       TEXT         NOT NULL,
  created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE game_servers (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  game        VARCHAR(100)      NOT NULL,
  name        VARCHAR(100)      NOT NULL,
  address     VARCHAR(100)      NOT NULL,
  slots       SMALLINT UNSIGNED NOT NULL,
  description TEXT              NOT NULL,
  created_at  TIMESTAMP         NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Starting content. Staff edit it from /gestion.

INSERT INTO rooms (id, name, capacity) VALUES
  (1, 'Salle 1', 40),
  (2, 'Salle 2', 24);

INSERT INTO films (slug, title, year, director, duration_min, rating, synopsis) VALUES
  ('metropolis', 'Metropolis', 1927, 'Fritz Lang', 148, 'G',
   'Dans une ville futuriste, les puissants vivent au sommet des tours pendant que les ouvriers font tourner les machines sous terre. Freder, fils du maître de la ville, descend dans ce monde souterrain et y rencontre Maria, qui prêche la réconciliation. Version restaurée.'),
  ('nosferatu', 'Nosferatu le vampire', 1922, 'F. W. Murnau', 94, '13+',
   'Un agent immobilier part conclure une vente chez le comte Orlok, au fond des Carpates. Il ne se doute pas que son client le suivra jusque chez lui, la peste dans son sillage. Le premier grand film de vampire, toujours aussi inquiétant.'),
  ('le-mecano-de-la-general', 'Le Mécano de la « General »', 1926, 'Buster Keaton et Clyde Bruckman', 79, 'G',
   'Pendant la guerre de Sécession, un mécanicien refusé par l’armée se lance seul à la poursuite des espions qui lui ont volé sa locomotive, et sa fiancée avec. Des cascades réelles, filmées sans trucage.'),
  ('le-kid', 'Le Kid', 1921, 'Charles Chaplin', 68, 'G',
   'Un vagabond recueille un bébé abandonné et l’élève dans sa mansarde. Cinq ans plus tard, les services sociaux veulent les séparer. Le premier long métrage de Chaplin, entre rires et larmes.'),
  ('monte-la-dessus', 'Monte là-dessus !', 1923, 'Fred C. Newmeyer et Sam Taylor', 73, 'G',
   'Pour impressionner sa fiancée, un vendeur de grand magasin promet un coup publicitaire : l’escalade de la façade de l’immeuble. Faute de grimpeur, c’est lui qui monte. La scène de l’horloge est restée célèbre.'),
  ('le-cabinet-du-docteur-caligari', 'Le Cabinet du docteur Caligari', 1920, 'Robert Wiene', 76, '13+',
   'Dans une foire de village, le docteur Caligari présente Cesare, un somnambule qui prédit l’avenir. Le lendemain, les meurtres commencent. Des décors peints et tordus qui ont marqué le cinéma expressionniste.'),
  ('sherlock-junior', 'Sherlock Junior', 1924, 'Buster Keaton', 45, 'G',
   'Un projectionniste qui rêve d’être détective s’endort pendant la séance et entre dans le film qu’il projette. Quarante-cinq minutes d’inventions visuelles, parfaites pour une sortie en famille.');

INSERT INTO game_servers (game, name, address, slots, description) VALUES
  ('Minecraft', 'Survie coopérative', '10.10.80.20:25565', 20,
   'Un monde en survie partagé par les joueurs du centre. Édition Java, sans mods.'),
  ('Valheim', 'Monde partagé', '10.10.80.20:2456', 10,
   'Explorez, construisez et affrontez les boss à plusieurs. Le monde avance avec les joueurs.'),
  ('Terraria', 'Aventure', '10.10.80.20:7777', 8,
   'Une partie ouverte à tous, idéale pour commencer à plusieurs.');

INSERT INTO announcements (title, body) VALUES
  ('Réservez votre place en ligne',
   'Créez un compte pour réserver jusqu’à six places par séance. Vous payez à l’accueil, et vous pouvez annuler jusqu’au début de la projection.'),
  ('Les soirées répertoire sont commencées',
   'Chaque soir, nos deux salles présentent des classiques du cinéma muet en version restaurée. Consultez la programmation de la semaine.');
