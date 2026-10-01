# PPA `liujianfeng1994/rockchip-multimedia` — vérifié le 01/10/2026

Point de départ : la branche `rockchip-rkmpp-130` de `github.com/amazingfate/chromium-debian-build` (Jianfeng
Liu, développeur Armbian/Rockchip). C'est la recette Debian de Chromium avec 20 patchs Rockchip
(`debian/patches/rkmpp/`).

## Ce que contient la recette — lu

- décodeur V4L2 + plugins libv4l : `use_v4l2_codec=true use_v4lplugin=true` en arm64 ;
- correctifs Wayland : `0011`, `0018`, `upstream/wayland-gbm-pixmap.patch` ;
- `0019` « NV12 direct rendering » : retire dans `ui/gfx/linux/gbm_wrapper.cc` le refus « gbm format not
  supported », hors minigbm.
  ⚠️ C'est le fichier de notre échec avec Panfrost (`test_chromium_radxa_126.md`), mais notre message était un
  échec d'**export**, pas ce refus-là. Effet sur Panfrost : **non mesuré**.

## Ce que publie le PPA — interrogé par l'API Launchpad (mesuré)

`ppa:liujianfeng1994/rockchip-multimedia`, série **noble** (Ubuntu 24.04), arm64 :

| Paquet | Version | Publié |
|---|---|---|
| **chromium** | `132.0.6834.159-1~deb12u1+rkmpp` | 06/03/2025 |
| libv4l-rkmpp | 1.7.0 git240515 | 15/05/2024 |
| v4l-utils | 1.26.1 `+rkmpp1` (libv4l patchée) | 15/05/2024 |
| mpp | 1.5.0 git20240612 | 13/06/2024 |
| librga, gstreamer1.0-rockchip, ffmpeg (rkmpp), rockchip-multimedia-config | — | 2024 |

Le PPA voisin `liujianfeng1994/chromium` (« Chromium from debian ») porte un Chromium **135** sans suffixe
`rkmpp`, pour noble, en avril 2025.

## Le binaire Chromium 132 — mesuré

Paquet téléchargé et ouvert dans `/tmp` sur la box, sans l'installer, puis effacé :
- 85,7 Mo ;
- `readelf -d` : `libX11`, `libgbm` ;
- `strings` : `zwp_linux_dmabuf_v1` / `xdg_wm_base` présents, **4 occurrences**. Le Chromium Radxa 126 en a
  **0**. Le libwayland est donc embarqué, et la **plateforme Wayland est compilée**.
- `Depends: libc6 (>= 2.38)` ⇒ **Ubuntu noble obligatoire** ; bookworm a la 2.36.

## Ce que ça change

Tout ce qu'on assemble à la main sur Armbian bookworm existe empaqueté pour **noble** : MPP, libv4l-rkmpp,
libv4l patchée, et un Chromium MPP **avec Wayland**.

Essai à faire, sans réinstaller la box : un environnement noble en chroot sur la TurboNode, avec Mesa/Panfrost
de noble, un compositeur (cage) et ce Chromium, puis le même banc. Aucun changement de pilote noyau.

## Essai en chroot : Weston + Panfrost + Chromium 132 rkmpp — mesuré le 01/10/2026

### Montage

- Chroot Ubuntu 24.04.5 (`ubuntu-base`) dans `/opt/pxl-noble` (1,3 Go), monté par `/opt/pxl-noble-monter.sh`.
- Noyau et pilote GPU de la box inchangés : **Panfrost**, pas de kbase. Mesa **25.2.8** (noble).
- Paquets du PPA : `chromium 132 rkmpp`, `libv4l-rkmpp`, `libv4l` `+rkmpp1`, `librockchip-mpp1`.
- **Weston 13** en `kiosk-shell`, sortie fixée à 1920×1080@60 par `weston.ini`. Lancé par `seatd-launch`.
- ⚠️ `cage` 0.1.5 a été essayé d'abord. Il prend le mode préféré de la TV (2160p) et **plante** (assertion
  wlroots `wlr_scene_output_layout_add_output`) quand on change de mode à chaud avec `wlr-randr`.
- Rendu Chromium : `ANGLE (Mesa, Mali-G52 r1 (Panfrost), OpenGL ES 3.1)` ; Weston : `GL renderer: Mali-G52 r1
  (Panfrost)`.

### Résultats

**Carré témoin** (`animation-temoin.mjs`) : **60,3 img/s**, écart médian 16,7 ms, **0** écart > 25 ms. Pendant
l'animation, l'adresse balayée alterne entre **trois** tampons : bascule vraie, triple tampon. ⇒ Sous Weston, on
a à la fois 60 img/s **et** la bascule, ce que Xorg ne donne pas (§ 5 de `test_habillage_urban_trail.md`).

**Habillage Urban Trail** (`habillage.mjs`). Cette fois en **vrai plein écran 1080p** ; les mesures X11 portaient
sur une fenêtre de 945×1060.

| Élément | img/s en animation | CPU chromium |
|---|---|---|
| chronos | 57,8 | 70 % |
| bandeau | 45,4 | 58 % |
| vitesse | 47,2 | 51 % |
| lieu | 56,3 | 51 % |
| dénivelé | 54,1 | 140 % |
| carte | 48,5 | 138 % |
| tête de course | 46,4 | 96 % |
| portique | 55,9 | 71 % |
| classement | 54,1 | 80 % |
| classement centré | 45,3 | 88 % |
| départs | 58,5 | 61 % |
| **séquence (6 éléments)** | **42,9** (X11 : 23,9 en recopie, 27,6 en bascule) | 170 % |

GPU : 1 à 11 % de charge moyenne, 46 % au plus.

**MotionMark 1.3.1** (`motionmark.mjs`, browserbench.org, 1920×1080, dpr 1) : **114,01 @ 45 fps ± 3,75 %**,
en 362 s.

| Multiply | Canvas Arcs | Leaves | Paths | Canvas Lines | Images | Design | Suits |
|---|---|---|---|---|---|---|---|
| 148,07 | 202,69 | 86,13 | 1570,56 | 1984,34 | 7,80 | 22,74 | 19,99 |

Pas encore de point de comparaison mesuré au même banc (X11/libmali, Pi 5).

### Erreur de manipulation, consignée

À la remise en état, `pkill -f "/opt/pxl-noble"` a tué **la session ssh qui l'exécutait** : la chaîne figurait
dans sa propre ligne de commande. C'est le piège du hook `pas-de-pkill-f` de PXL-Switcher. On arrête par
`systemctl stop <unité>`, jamais par `pkill -f`.

### Sortie en 25p avec le serveur Node sur la box — mesuré le 01/10/2026

Question d'Eliott : limiter Chromium à 25 img/s, avec le serveur d'habillage sur la même box.

Montage :
- la sortie HDMI est réglée en **1920×1080@25** (`weston.ini`). La TV le déclare, et Chromium se cale sur la
  cadence de l'écran : il n'existe pas de drapeau pour plafonner Chromium ;
- serveur d'essai `serveur.js` actif ;
- banc `scripts/banc/serie-weston-hz.sh <Hz>`. Un **accroc** y est un écart supérieur à 1,5 image : 60 ms en
  25p, 25 ms en 60p.

| | 25p : img/s | 25p : accrocs | 60p : img/s | 60p : accrocs |
|---|---|---|---|---|
| bandeau · vitesse · lieu · portique · départs | 25,1 à 25,4 | **0** | 54,7 à 58,5 | 2 à 8 |
| chronos · classement · classement centré · dénivelé | 24,0 à 25,0 | 0 à 2 | 47,2 à 57,3 | 8 à 29 |
| tête de course · carte | 23,0 · 24,4 | 2 · 4 | 47,0 · 51,0 | 10 · 45 |
| **séquence complète (6 éléments)** | **22,9** | **24** | 41,4 | **123** |

Charge processeur, sur 400 % (4 cœurs) :

| | 25p | 60p |
|---|---|---|
| Chromium, séquence | **107 %** | 168 % |
| Chromium, éléments seuls | 27 à 75 % | 49 à 134 % |
| serveur Node | **18 à 26 %** (repos : 23 %) | 19 à 24 % |
| box entière, au pire | **145 / 400** | 204 / 400 |

Température : 69-71 °C en 25p, 71-74 °C en 60p.

⇒ **En 25p, un élément seul est fluide**, à 0-4 accroc pour ~9 s. La séquence complète garde des accrocs, à
peu près 9 % des images, contre ~26 % en 60p. Ils viennent sans doute de l'entrée simultanée des 6 éléments,
qui fait un pic de mise en page (déduit). Le serveur Node coûte un cinquième de cœur et ne gêne pas.
