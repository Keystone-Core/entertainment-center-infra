<?php
declare(strict_types=1);

// The centre's practical information, shown in the footer and on /infos.
// The centre is fictional: the address and phone number are invented (555-01xx
// numbers are reserved for fiction).

const CENTRE_NAME = 'Centre de divertissement de l’Estrie';
const CENTRE_ADDRESS = '2400, rue King Ouest';
const CENTRE_CITY = 'Sherbrooke (Québec)';
const CENTRE_POSTAL_CODE = "J1J\u{a0}2E8";
const CENTRE_PHONE = "819\u{a0}555-0142";
const CENTRE_EMAIL = 'info@divertissementestrie.ca';

const CENTRE_HOURS = [
    ['Lundi', 'Fermé'],
    ['Mardi au jeudi', "16\u{a0}h à 23\u{a0}h"],
    ['Vendredi', "16\u{a0}h à minuit"],
    ['Samedi', "12\u{a0}h à minuit"],
    ['Dimanche', "12\u{a0}h à 22\u{a0}h"],
];

const PRICES_CINEMA = [
    ['Adulte', "11\u{a0}$"],
    ['Étudiant ou aîné', "9\u{a0}$"],
    ['Enfant de 12 ans et moins', "7\u{a0}$"],
    ['Mardi pour tous', "8\u{a0}$"],
];

const PRICES_WORKSTATIONS = [
    ['L’heure', "5\u{a0}$"],
    ['La soirée, jusqu’à la fermeture', "15\u{a0}$"],
    ['Carte de 10 heures', "40\u{a0}$"],
];

const WORKSTATION_COUNT = 12;
