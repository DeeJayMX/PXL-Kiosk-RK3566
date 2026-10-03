# Flux TurboHQ de la sortie HDMI — writeback SANS COPIE (02/10/2026)

**Ce que c'est** : ce que la box affiche sur le HDMI, publié en canal TurboHQ. Le VOP2 écrit l'image qu'il envoie à
l'écran dans un tampon NV12 (writeback) ; l'encodeur matériel (MPP) lit ce même tampon. Aucune copie processeur, aucune
conversion. Réglage : `/admin` → « Habillage & écran » → « Flux TurboHQ de la sortie HDMI ». Le client TurboHQ (`thq-publish.js`) vient du dépôt TurboHQ, privé : il est posé à part dans `/usr/local/lib/pxl-kiosk/turbohq-client`, pas dans cette recette publique.

```
Weston (patché) ──writeback NV12, anneau de 4 tampons──▶ pxl-wb-enc (H.264 MPP) ──▶ thq-publish ──▶ relais TurboHQ
                  socket /run/pxl-preview/pxl-wb.sock : DMA-BUF une fois, puis « case n + barrière » par image
```

## Pourquoi un Weston patché (lu dans le code de Weston 13.0, 02/10)

La capture « writeback » de Weston (`weston_capture_v1`) existe, mais : un tampon **alloué à chaque image**
(`drm_fb_create_dumb`), une **recopie processeur** dans la mémoire du client (`pixman_copy_screenshot`), au **format de
la sortie** (XRGB8888, 4 o/px — que le writeback du RK3566 ne sait même pas écrire : BG24 AR24 RG16 NV12), et la
boucle d'affichage **bloquée** jusqu'à la fin du writeback (`drm_writeback_should_wait_completion`) — le ÷2 déjà vu sur
la TurboNode. Le patch (`installation/patches/weston-writeback-flux.patch`, drm-backend seul) :
- anneau de 4 tampons NV12 alloués une fois, DMA-BUF passés une fois à l'encodeur ;
- connecteur writeback attaché au CRTC **une seule fois** (ensuite seul `WRITEBACK_FB_ID` change, pas de modeset) ;
- Weston **n'attend pas** la barrière : elle part à l'encodeur, qui l'attend lui-même ;
- un minuteur force une recomposition à la cadence demandée (sinon un écran fixe ne produit pas d'images).

## Mesuré sur la box (02/10/2026, 1280×720p50, flux 25 img/s, H.264 6 Mbit/s CBR)

| | |
|---|---|
| cadence du flux | **24,8 img/s**, 0 image non capturée |
| modesets pendant le flux | **0** (`drm.debug=0x4`, `vop2_crtc_atomic_enable`) |
| écran (rAF de Chromium) | **49,0 img/s avec flux, 48,7 sans** — pire intervalle 40,1 ms dans les deux cas |
| encodeur | ≈ 6 ms/img d'encodage (+ ≈ 20 ms d'attente de barrière : le writeback finit au vblank suivant) |
| processeur (box entière) | 16 % pendant le flux |
| image | décodée par ffprobe : H.264 High 1280×720, couleurs justes (capture vérifiée à l'œil) |

## Suivre une mise à jour de Weston (Ubuntu)

Weston est tenu (`apt-mark hold weston libweston-13-0`) et notre module remplace celui d'Ubuntu par `dpkg-divert`.
`installer.sh` relance `weston-pxl.sh`, qui ne reconstruit que si la version de Weston ou le patch ont changé
(marqueur `/etc/pxl-kiosk/weston-pxl`). Pour prendre une mise à jour : `apt-mark unhold weston libweston-13-0 &&
apt-get install weston`, puis `weston-pxl.sh`. **Si le patch ne s'applique plus, le module d'Ubuntu est gardé** (l'écran
marche, le flux est indisponible) : fusionner le patch à la main. Retour arrière : `weston-pxl.sh --retirer`.

## ENTRELACÉ (1080i50) — le writeback n'écrit qu'UNE trame (ajout du 03/10/2026)

**Mesuré d'abord (03/10, flux v1.7.0 en 1080i50)** : 1920×1080 annoncé, mais seules les **540 premières lignes** sont
écrites, avec toute l'image écrasée dedans ; le reste du tampon reste à zéro (vert en NV12). Ce n'est **pas** un NV12
mal calé : les couleurs de la moitié écrite sont justes, donc le plan UV est au bon endroit.

**Lu dans le pilote** (ophub `linux-6.1.y-rockchip`, 6.1.174 — la box est en 6.1.141, même lignée) :
- en entrelacé le port vidéo passe en `p2i_en` (progressif → entrelacé) et travaille trame par trame (`Fixed V: 540`
  dans `summary`) ; le writeback écrit ce qu'il reçoit ;
- les registres du writeback RK3568/66 sont **onze** : format, adresses Y/UV, réduction X, réduction Y ½, r2y, dither,
  port. **Ni pas de ligne, ni hauteur, ni parité de trame** (le pas, le « oneshot » n'arrivent qu'au RK3576) ;
- `dsp_field_pol` existe, mais c'est la polarité du signal **HDMI** ; aucun `WB_FIELD_POL`, aucune propriété de device
  tree de polarité (vérifié le 03/10 contre une suggestion externe qui les citait).
- une capture = **une trame** : armée au commit, écrite pendant la trame suivante, coupée au début de celle d'après
  (`vop2_wb_handler`, appelé à chaque début de trame).

**La parité existe dans le matériel, pas dans le writeback** (mesuré, lecture de registre par `/dev/mem`) : le compteur
de lignes de `SYS_STATUS0` (bits 16-28) va de **0 à 1124 en 40 ms**, sur l'image entière. Les bits 0-15 ne portent pas
de trame (le bit 1 bat à chaque LIGNE). ⚠️ Inutilisable tel quel : `pxl-wb` tourne en `pxl`, sans `/dev/mem`.

**La solution (v1.8.0) : capturer les DEUX trames et les tisser à la RGA.**
- **Weston** capture par **paires** de trames consécutives (rang 1, puis rang 2 dans le message FRAME) et joint à chacune
  son **numéro de vblank** (`drmCrtcGetSequence`, lu dans l'événement de flip du commit : c'est la trame en cours
  d'écriture). Mesuré : **187 paires sur 187 consécutives** (20,0 ms d'écart), 2 à 12 lignes après le début de trame.
- **Tisser, sans que le processeur touche un pixel** : un NV12 1920×1080 a exactement la disposition d'un NV12
  **3840×540** dont la moitié gauche porte les lignes paires et la droite les impaires — Y **et** UV. Tisser = **deux
  copies RGA ordinaires** (trame du haut à gauche, du bas à droite), coordonnées paires, 3840 ≤ 4096 (RGA2 du RK3566).
  Validé d'abord en fabriquant ce même 3840×540 avec ffmpeg (`hstack`) et en le relisant en 1920×1080.
- **Quelle trame en haut** : parité du numéro de vblank, à un décalage près appris sur l'IMAGE — l'ordre juste est le
  plus lisse entre lignes voisines (mesuré : **1,69 contre 2,81** ; le mauvais ordre peigne le texte, vu au zoom).
  Re-vérifié une paire sur 25 ; trois désaccords francs basculent le décalage. ⚠️ **Une paire ne commence pas toujours
  sur la même trame** (une recomposition ratée la décale, mesuré : rang 1 tombé 123 fois sur une parité, 65 sur
  l'autre) : on ne fige jamais « la première de la paire va en haut ».
- ⚠️ Petite réserve : la chroma d'une trame recopiée dans une image progressive est décalée d'une demi-ligne de chroma
  (bords colorés très fins). C'est le défaut ordinaire d'un entrelacé encodé en progressif.

| Mesuré sur la box (03/10/2026, 1080i50, flux 25 img/s demandées, 6 Mbit/s) | |
|---|---|
| cadence du flux | **23,5 à 24,0 img/s** — 4 à 6 paires cassées / 10 s (recomposition ratée entre les deux trames) |
| ordre des trames | appris en < 1 s ; **17 à 27 accords, 0 bascule** par tranche de 10 s ; « indécis » = image trop uniforme |
| image | **1920×1080 complète, texte net** (enregistrement `thq-record`, décodé par ffmpeg, vérifié au zoom) |
| temps par image | ≈ 41 ms de la 1ʳᵉ barrière à l'encodage (dont ≈ 22 ms d'attente de la 2ᵉ trame) |
| 720p50 (non-régression) | **24,9 img/s**, inchangé |
| ⚠️ non mesuré | l'effet sur la cadence de l'écran en 1080i (rAF) ; `idet` de ffmpeg ne tranche pas sur un multiview presque fixe |

## PsF — « 25p propre » en 1080i (ajout du 03/10/2026, v1.9.0)

En 50i, Weston se cadence à la **trame** (lu : `modes.c` double la fréquence d'un mode entrelacé) et Chromium dessine
jusqu'à 50 img/s : les deux trames d'une paire peuvent être **deux images différentes**, et le flux tissé peigne ce qui
bouge (l'écran, lui, est en vrai 50i). Le réglage **« Cadence en entrelacé » de /admin** (`ENTRELACE=50i|psf` dans
`/etc/pxl-kiosk.conf`) offre l'autre choix :

- **PsF** (`PXL_PSF=1`, posé par `preview.sh`) : Weston se cadence à l'**image** (25 Hz) ; Chromium suit (rAF mesuré
  **25,0 img/s**, pire intervalle 40,1 ms) et fait deux fois moins de travail ;
- la **seconde trame** est capturée par un **commit atomique à nous** qui ne porte que le writeback (+ `ACTIVE` du CRTC,
  sans quoi le noyau refuse le travail) — rien n'est recomposé, Chromium ne voit rien ;
- chaque image est **calée sur la trame du haut** dès que l'encodeur a appris la parité (message `PARITE` vers Weston) :
  une image mal placée est datée d'une trame plus tard, Weston programme la suivante sur une trame du haut ;
- la fenêtre de composition de Weston passe à **15 ms** (au lieu de 7), en PsF seulement.

**Trois erreurs en route, chacune mesurée avant d'être corrigée** :
1. dater l'image mal placée d'une trame **plus tôt** ne laissait que ~13 ms à Weston : il ratait la trame et retombait
   sur une trame du bas (recalage toutes les ~120 ms, flux à 21 img/s) ⇒ la dater plus **tard** ;
2. avant le commit suivant de Weston, j'attendais la **fin du writeback** de notre seconde capture — elle arrive une
   trame trop tard (début de la trame d'après) : Weston ratait sa trame (flux à 16 img/s, ~9 recalages/s) ⇒ attendre
   seulement que notre commit soit **appliqué** (compteur de vblank) ;
3. restait 22-23 img/s. Hypothèse « le minuteur de recomposition part trop tard » : **essayée, sans effet, retirée**.
   La sonde a tranché : écarts entre premières trames capturées **2 → 153, 3 → 43, 4 → 8** sur 10 s, donc des images
   qui glissent d'une trame. Cause : la fenêtre de composition de 7 ms, trop courte pour un 1080 sur le Mali.

| Fenêtre de composition (PsF, 03/10/2026) | glissements / 10 s | rAF de Chromium |
|---|---|---|
| 7 ms (défaut de Weston) | 43 + 8 images perdues | 25,0 |
| 12 ms | 3 | 25,0 (pire 40,1 ms) |
| **15 ms (retenu)** | **1 à 3** | 25,0 ; ⚠️ un trou de 80 ms environ toutes les 12 s |
| 18 ms | 0 | 24,7 (pire 80 ms : Chromium perd une image) |

| Mesuré sur la box (03/10/2026, 1080i50, flux 25 img/s, 6 Mbit/s) | 50i | **PsF** |
|---|---|---|
| Chromium (rAF) | 48,3 img/s | **25,0 img/s** |
| flux | 23,1-23,5 img/s, 4 à 7 paires cassées / 10 s | **24,7-25,0 img/s, 0 paire cassée** |
| recalages | — | 3 au démarrage, puis aucun en régime |
| image du flux | nette (fixe), peigne ce qui bouge (déduit) | nette (zoom sur l'horloge) |
| ⚠️ non mesuré | | le rendu sur un diffuseur qui désentrelace en « tissage » ; le calage est fait pour lui |

## Tous les modes de /admin, et un relais extérieur (ajout du 03/10/2026, v1.10.0)

**Mesuré sur la box, chaque mode réglé comme /admin le règle** (flux 25 img/s demandées, 6 Mbit/s) :

| mode demandé | posé | Chromium (rAF) | flux |
|---|---|---|---|
| 720p25 | 🔴 **3840x2160p60** avant correctif ; **1280x720p50** après (repli dit) | 48,7 | 24,9 img/s |
| 720p50 | 1280x720p50 | 48,7 | 24,3-24,8 img/s |
| 1080p25 | 1920x1080p25 | — | 24,9 img/s |
| 1080p50 | 1920x1080p50 | — | 24,7 img/s |
| 1080i50 (PsF) | 1920x1080i50 | 25,0 | 24,5-24,6 img/s, 0 paire cassée |

🔴 **Un mode que l'écran ne déclare pas fait prendre à Weston son mode PRÉFÉRÉ, sans un mot** : la TV du labo ne
déclare pas le 720p25, Weston est parti en **4K60** (et le flux à 15 img/s). `pxl-mode --liste` donne les modes de
l'écran branché : `preview.sh` se replie explicitement (720p50, puis 1080p50, puis 60 Hz) et le journalise ; /admin
signale le mode absent sans l'interdire (on règle parfois la box pour la TV du lieu).
⚠️ Et la fenêtre de composition de 15 ms du PsF ne s'applique plus qu'en **entrelacé** : le PsF étant devenu le défaut,
elle aurait affamé Chromium en 50p (une image y dure 20 ms).

**Relais extérieur — mesuré vers la TurboNode** : flux poussé sur `ws://100.109.186.25:8080` (le tailnet ; les deux
boxes ne partagent pas de fil Ethernet), relu **depuis la TurboNode** par `thq-record` : 169 images 1920×1080, 0 perdue,
latence 8 ms (p95 32 ms). Ce relais exige une **clé d'accès** : sans elle, le publisher reboucle sur
`reconnecting … error`. La clé est rangée dans `/etc/pxl-kiosk/wb.cle` (0640 root:pxl, posée par /admin, jamais
réaffichée), passée au publisher par l'environnement (`THQ_KEY`), jamais sur la ligne de commande.

**/admin** : *Flux TurboHQ* (destination, « Relais de la box », recherche des relais du réseau local par la sonde UDP
41808 — ⚠️ elle ne traverse ni un routeur ni le tailnet —, clé) et *Relais TurboHQ de la box* (en service, nom annoncé,
clé optionnelle, canaux en cours avec leur source et leurs spectateurs).

## Codec, GOP, mode de débit — et l'admin en bulles (ajout du 03/10/2026, v1.11.0)

`pxl-wb-enc` prend `--codec h264|hevc`, `--gop <images>`, `--rc cbr|vbr` (réglés dans /admin : `WB_CODEC`, `WB_GOP` —
rangé en images, choisi en secondes —, `WB_RC`) ; `pxl-wb.sh` passe `--hevc` à `thq-publish`. **Mesuré** en 1080i PsF,
H.265 VBR GOP 50 : flux `hvc1.1.6.L120.80`, Main, 1920×1080, relu par `thq-record` + ffprobe, **une image clé toutes
les 50 images exactement** (n° 1, 51, 101, 151, 201). ⚠️ Non mesuré : le gain de débit du H.265 sur ce contenu, et quels
navigateurs des spectateurs le décodent.

Sur la page : « Relais de destination » **Local / Personnalisé** (l'adresse, la clé et la recherche n'apparaissent
qu'en Personnalisé), et toutes les explications sont passées derrière des **❔** dont la bulle suit la souris (au doigt :
un appui l'ouvre). Vérifié dans Chromium avec l'état réel de la box : aucune erreur, la bulle s'ouvre et se ferme,
l'envoi porte codec, mode et GOP.
