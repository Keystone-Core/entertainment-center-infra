#!/usr/bin/env python3
# Relie la suite *arr de media01 par les API locales :
#   1. compte admin (connexion par formulaire) dans Sonarr, Radarr et Prowlarr ;
#   2. dossier racine des series (Sonarr) et des films (Radarr) ;
#   3. qBittorrent comme client de telechargement, chacun dans sa categorie ;
#   4. Sonarr et Radarr comme applications de Prowlarr.
# Ne fait que ce qui manque. Chaque changement est affiche sur une ligne qui
# commence par CHANGE. Aucun secret n'est affiche : le mot de passe et les
# cles sont masques dans les messages d'erreur.
# Lance par le role arr (tasks/liens.yml), qui fournit l'environnement.
import json
import os
import sys
import time
import urllib.error
import urllib.request

ADMIN = os.environ["ARR_ADMIN"]
MDP = os.environ["ARR_MDP"]
QBT_PORT = int(os.environ["QBT_PORT"])
CLES = json.loads(os.environ["ARR_CLES"])
APPS = {a["nom"]: a for a in json.loads(os.environ["ARR_APPS"])}
SECRETS = [MDP] + list(CLES.values())


def masquer(texte):
    for s in SECRETS:
        texte = texte.replace(s, "***")
    return texte


def appel(app, methode, chemin, corps=None):
    url = "http://127.0.0.1:%d/api/%s/%s" % (app["port"], app["api"], chemin)
    donnees = None if corps is None else json.dumps(corps).encode()
    entetes = {"X-Api-Key": CLES[app["nom"]], "Content-Type": "application/json"}
    for essai in range(10):
        requete = urllib.request.Request(url, data=donnees, method=methode, headers=entetes)
        try:
            with urllib.request.urlopen(requete, timeout=90) as reponse:
                texte = reponse.read().decode()
                return json.loads(texte) if texte else None
        except urllib.error.HTTPError as e:
            detail = masquer(e.read().decode(errors="replace"))[:600]
            sys.exit("ERREUR %s %s %s : HTTP %d %s" % (app["titre"], methode, chemin, e.code, detail))
        except urllib.error.URLError:
            # L'application demarre encore : on reessaie.
            time.sleep(3)
    sys.exit("ERREUR %s : l'API ne repond pas (%s)" % (app["titre"], url))


def regler(champs, valeurs):
    for champ in champs:
        if champ["name"] in valeurs:
            champ["value"] = valeurs[champ["name"]]


def compte(app):
    hote = appel(app, "GET", "config/host")
    if hote.get("username") == ADMIN and hote.get("authenticationMethod") == "forms":
        return
    hote.update(
        authenticationMethod="forms",
        authenticationRequired="enabled",
        username=ADMIN,
        password=MDP,
        passwordConfirmation=MDP,
    )
    appel(app, "PUT", "config/host/%d" % hote["id"], hote)
    print("CHANGE %s : compte %s, connexion par formulaire" % (app["titre"], ADMIN))


def dossier_racine(app):
    chemin = app["dossier"]
    if not chemin:
        return
    if any(r["path"].rstrip("/") == chemin for r in appel(app, "GET", "rootfolder")):
        return
    appel(app, "POST", "rootfolder", {"path": chemin})
    print("CHANGE %s : dossier racine %s" % (app["titre"], chemin))


def client_qbittorrent(app):
    if any(c["implementation"] == "QBittorrent" for c in appel(app, "GET", "downloadclient")):
        return
    modele = next(s for s in appel(app, "GET", "downloadclient/schema") if s["implementation"] == "QBittorrent")
    valeurs = {"host": "127.0.0.1", "port": QBT_PORT, "useSsl": False, "username": ADMIN, "password": MDP}
    # tvCategory (Sonarr), movieCategory (Radarr), category (Prowlarr) ; pas
    # les categories << importees >>.
    for champ in modele["fields"]:
        if champ["name"].lower().endswith("category") and "imported" not in champ["name"].lower():
            valeurs[champ["name"]] = app["categorie"]
    regler(modele["fields"], valeurs)
    modele.update(name="qBittorrent", enable=True, priority=1)
    # Le test de connexion a qBittorrent est fait par l'application.
    appel(app, "POST", "downloadclient", modele)
    print("CHANGE %s : client qBittorrent, categorie %s" % (app["titre"], app["categorie"]))


def applications_prowlarr(prowlarr, cibles):
    existantes = {a["implementation"] for a in appel(prowlarr, "GET", "applications")}
    modeles = appel(prowlarr, "GET", "applications/schema")
    for cible in cibles:
        if cible["titre"] in existantes:
            continue
        modele = next(s for s in modeles if s["implementation"] == cible["titre"])
        regler(modele["fields"], {
            "prowlarrUrl": "http://127.0.0.1:%d" % prowlarr["port"],
            "baseUrl": "http://127.0.0.1:%d" % cible["port"],
            "apiKey": CLES[cible["nom"]],
        })
        modele.update(name=cible["titre"], syncLevel="fullSync")
        appel(prowlarr, "POST", "applications", modele)
        print("CHANGE Prowlarr : application %s (synchronisation complete)" % cible["titre"])


for app in APPS.values():
    compte(app)
for app in APPS.values():
    dossier_racine(app)
for app in APPS.values():
    client_qbittorrent(app)
applications_prowlarr(APPS["prowlarr"], [APPS["sonarr"], APPS["radarr"]])
print("OK : suite reliee")
