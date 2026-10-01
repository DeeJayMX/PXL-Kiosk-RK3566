# Installation — box « serveur d'habillage + preview »

Une box RK3566 dédiée qui :
1. fait tourner le **serveur d'habillage** (ex. `urban-trail-2026/serveur.js`) et sert les pages à **vMix**, à la
   console et au StreamDeck. C'est le **travail critique** ;
2. affiche la **preview** sur sa sortie HDMI, pour le réal. C'est **secondaire** : elle ne doit jamais gêner le
   serveur ;
3. se **surveille à distance** par Tailscale (santé en JSON, SSH).

## La pile

Mesurée en chroot sur la TurboNode le 01/10/2026 : [`docs/recherche/ppa_rockchip_multimedia.md`](../docs/recherche/ppa_rockchip_multimedia.md).

| Pièce | Source |
|---|---|
| Système | Armbian/ophub **Ubuntu 24.04 noble** pour la box, avec le noyau Rockchip 6.1 (MPP) |
| GPU | **Panfrost** (pilote libre du noyau) + Mesa de noble. Ni kbase, ni libmali, rien à compiler |
| Affichage | **Weston** `kiosk-shell` : triple tampon, bascule calée sur l'écran, sortie fixée (25p par défaut) |
| Navigateur | **Chromium 132 rkmpp** (MPP + Wayland) du PPA `liujianfeng1994/rockchip-multimedia`, avec `rockchip-multimedia-config` (pose `/dev/video-dec0` et la libv4l patchée) |
| Serveur | **Node 22 officiel** (nodejs.org, empreinte vérifiée) |
| Accès distant | **Tailscale officiel** avec `--ssh` |

## Installer

```bash
# sur la box, en root, Ubuntu noble fraîchement flashée
git clone https://github.com/DeeJayMX/PXL-Kiosk-RK3566 && cd PXL-Kiosk-RK3566
cp installation/pxl-kiosk.conf.exemple /etc/pxl-kiosk.conf && nano /etc/pxl-kiosk.conf
#   APP_SOURCE : un dossier local (copie de l'application) ou une URL git
TS_AUTHKEY=tskey-… bash installation/installer.sh
```

- Le script se relance sans dommage : il remet à jour la pile, l'application et les services.
- `installer.sh --verifier` contrôle sans rien toucher : services, ports, `/dev/mpp_service`,
  `/dev/video-dec0`, mode HDMI, et rendu de Chromium **par le GPU** (WebGL lu dans la page).

## Ce qu'il pose

| Service | Rôle | Priorité |
|---|---|---|
| `pxl-serveur` | `node $APP_CMD` dans `$APP_DIR`, écoute `$APP_HOST:$APP_PORT` | **haute** : `Nice=-5`, `CPUWeight=400`, protégé du manque de mémoire |
| `pxl-preview` | Weston + Chromium sur `$PREVIEW_URL`, profil en mémoire | **basse** : `Nice=10`, `CPUWeight=50`, tué en premier si la mémoire manque |
| `pxl-sante` | `:$SANTE_PORT/sante` (JSON) et `/sante.txt` (lisible) : températures, charge, mémoire, disque, GPU, services et relances, `/api/sante` du serveur | — |
| `seatd` | accès DRM et entrées pour Weston, sans session de bureau | — |

Les trois services `pxl-*` sont relancés seuls (`Restart=always`). Si la preview tombe, le serveur continue.

Réglages pour une exploitation dans un car régie :
- démarrage direct sur la preview, sans bureau ni écran de connexion ;
- **aucune mise à jour automatique** : on met à jour quand on le décide, en relançant `installer.sh` ;
- journal persistant borné à 200 Mo ;
- **chien de garde matériel** : la box redémarre seule si le noyau se fige.

## Exploiter

```bash
pxl-kiosk etat                    # résumé santé
pxl-kiosk maj-app                 # nouvelle version de l'application (etat-local/ est conservé)
pxl-kiosk redemarrer preview      # ou serveur, ou tout
pxl-kiosk journal serveur         # journal en direct
curl http://<NOM_MACHINE>:8790/sante.txt    # depuis le tailnet
```

## ⚠️ Ce qui n'est PAS encore vérifié

- **Le script n'a pas encore tourné de bout en bout sur une box en Ubuntu noble.** La pile l'a fait, en chroot.
  Le premier passage sur la box dédiée est la vraie recette.
- **Décodage vidéo MPP sous Weston** : jamais mesuré. Le chroot d'essai n'avait pas `rockchip-multimedia-config`.
  Vérifier pendant la lecture d'une vidéo avec `grep -c rkvdec /proc/mpp_service/sessions-summary` ; le résultat
  doit valoir au moins 1.
- **Chromium en utilisateur non-root** : le chroot tournait en root avec `--no-sandbox`. Ici, il tourne en `pxl`
  avec `chromium-sandbox` (setuid). À confirmer au premier lancement : `journalctl -u pxl-preview`.
- **Endurance 24 h** : `urban-trail-2026/outils/endurance.js` sur la box, avant un événement.
- **Preview** mesurée en 25p (01/10) : un élément seul tient 23-26 img/s ; la carte 19 et la séquence complète 13.
  Ça convient pour un moniteur de contrôle, pas pour l'antenne.
