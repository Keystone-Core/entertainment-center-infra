<?php
declare(strict_types=1);

// The centre's practical information. Hours, prices and the phone number
// are placeholders until the centre confirms them: change them here.

const CENTRE_NAME = 'Centre de divertissement de l’Estrie';
const CENTRE_CITY = 'Sherbrooke (Québec)';
const CENTRE_PHONE = "819\u{a0}555-0142";

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
];

const PRICES_WORKSTATIONS = [
    ['L’heure', "5\u{a0}$"],
    ['La soirée, jusqu’à la fermeture', "15\u{a0}$"],
];

const WORKSTATION_COUNT = 12;
