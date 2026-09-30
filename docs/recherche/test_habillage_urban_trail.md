# Habillage animé (Urban Trail 2026) dans le kiosque — mesuré le 01/10/2026

Question d'Eliott : *« je veux la vidéo et le rendu GPU de Chrome ultra fluide, pour jouer de l'habillage comme
https://pxl-aero.tailaee5f.ts.net/ »*. On a donc mesuré **la vraie page PGM** (`/overlay` du dépôt
`DeeJayMX/urban-trail-2026`, commit `3c135da`), et pas une page de démonstration.

## Montage

- **Serveur d'habillage d'ESSAI sur la box**, jamais celui de la régie : copie du dépôt dans
  `/opt/pxl-kiosk/urban-trail-2026`, unité `pxl-habillage-essai`,
  `PORT=8799 HOST=127.0.0.1 REJOUER=2025-10-11T19:50:00+02:00 VITESSE=1 node serveur.js config.chaumont2025.json`
  (rejeu de Chaumont 2025, sources ChronoPro joignables depuis la box). ⚠️ Ce serveur prend lui-même 35 % d'un
  cœur de la box pendant les mesures ; en exploitation il tourne sur une autre machine.
- Pile du dépôt, scripts **25 → 30 → 40**, GPU en gouverneur **`performance`** (800 MHz), sortie **1080p60**.
- Page : `http://127.0.0.1:8799/overlay?fond=%23707880`.
- Banc : `scripts/banc/habillage.mjs`. Il envoie chaque élément à l'antenne par l'API du serveur d'essai
  (`/api/gfx/<élément>/take`), attend 6 s, retire l'élément, attend 3 s, et mesure pendant tout ce temps :
  - images **dessinées** par le compositeur (`DrawFrame` de la trace Chromium), ramenées aux seules périodes où
    ça bouge (`draw_ips_en_animation`) ;
  - accrocs de `requestAnimationFrame` ;
  - CPU des processus chromium ;
  - charge et fréquence du GPU (devfreq).

  ⚠️ **Webcam non testée** : pas de caméra sur la box (l'élément « Dossard + webcam » refuse de partir sans elle).

## 1. Premier passage : tout plafonne à 30 img/s, et ce n'est PAS la page

Mesuré avec `conf/xorg-rk.conf` tel que livré (`FlipFB "always"`) :

| Élément | img/s en animation | CPU chromium (sur 400 %) | GPU charge moy / max |
|---|---|---|---|
| bandeau, vitesse, lieu, chronos | 31,6 à 32,9 | 45 à 54 % | 2-4 % / 18-19 % |
| tête, portique, classement, classement centré | 28,8 à 31,0 | 59 à 72 % | 4-7 % / 21-27 % |
| dénivelé, carte, départs | 30,0 à 30,5 | 71 à 92 % | 13-15 % / 21-30 % |
| **séquence** (chronos + bandeau + vitesse + lieu + dénivelé + carte) | **27,6** | 142 % | 18 % / 30 % |

Tout tient à 30, du plus léger au plus lourd, avec un GPU presque à vide. **Contrôle**
(`scripts/banc/animation-temoin.mjs`) : un carré qui glisse en CSS (`transform` seul) sort à **22 img/s**, et une
largeur animée ou un canvas en `requestAnimationFrame` à **30,4**. Le verrou est donc dans la chaîne
d'affichage, pas dans l'habillage.

État des fonctions GPU de Chromium, lu par `SystemInfo.getInfo` :
- `gpu_compositing: enabled`, `rasterization: enabled_force`, `canvas_oop_rasterization: enabled_on` ;
- `webgl`/`webgl2` actifs, `vulkan` coupé.

Le rendu GPU est donc bien actif.

## 2. Le verrou : `FlipFB "always"` — ⭐ mesuré

Même carré témoin, Xorg relancé à chaque variante :

| `conf/xorg-rk.conf` | transform | largeur | canvas rAF |
|---|---|---|---|
| `FlipFB "always"` (livré, repris de meta-rockchip) | 22,0 | 30,4 | 30,4 |
| `FlipFB "none"` | 42,8 ¹ | **60,4** | **60,5** |
| `FlipFB "none"` + `PageFlip "false"` | 42,8 ¹ | 60,3 | 60,4 |
| `FlipFB "transformed"` | 42,8 ¹ | 60,3 | 60,5 |

¹ Écart médian 16,7 ms et un seul écart > 25 ms : l'animation est fluide. Le compteur est plus bas parce que le
compositeur ne redessine pas aux extrémités de l'aller-retour. Déduit, non vérifié.

⇒ `FlipFB "always"` **coûte une image sur deux**. Mécanisme déduit, non vérifié dans le code : chaque échange
DRI2 est copié dans un tampon de bascule du fork Rockchip, puis on attend la fin de la bascule, ce qui fait deux
retours d'écran par image.

## 3. Rejeu de la page avec `FlipFB "none"`

| Élément | img/s en animation | avant | CPU chromium | GPU moy / max |
|---|---|---|---|---|
| bandeau | **59,8** | 31,6 | 54 % | 2 % / 17 % |
| lieu | **59,2** | 32,9 | 51 % | 2 % / 19 % |
| portique | **59,0** | 31,0 | 71 % | 5 % / 23 % |
| classement | **57,8** | 30,6 | 86 % | 6 % / 23 % |
| tête de course | **56,8** | 28,8 | 78 % | 5 % / 28 % |
| vitesse | 55,4 | 32,8 | 51 % | 2 % / 18 % |
| dénivelé | 54,9 | 30,5 | 164 % | 14 % / 23 % |
| chronos | 53,6 | 31,6 | 69 % | 4 % / 22 % |
| départs | 51,2 | 30,2 | 57 % | 3 % / 22 % |
| classement centré | 50,6 | 30,0 | 94 % | 7 % / 30 % |
| carte du parcours | 46,3 | 30,0 | 160 % | 23 % / 43 % |
| **séquence (6 éléments ensemble)** | 🔴 **23,9** | 27,6 | 161 % | 19 % / 31 % |

Un élément seul est désormais fluide ou presque. **La séquence complète ne l'est pas.** Pendant la séquence,
`top -H` montre :

| Fil | CPU |
|---|---|
| fil principal du **processus GPU** de Chromium | **99,9 %** |
| fil principal de la **page** (renderer) | **87 %** |
| `node` (le serveur d'essai, absent en exploitation) | 35 % |
| Xorg | 9 % |

Le GPU, lui, est à 19 % de charge moyenne. ⇒ **Le mur est côté processeur, sur deux fils, et pas dans le Mali** :
- le fil GPU passe son temps à préparer les commandes (ANGLE → GLES → libmali, sur un A55) ;
- le fil de la page passe le sien en mise en page, style et peinture.

Deux sources de coût probables dans `habillage.css` / `habillage.js` (lu, non isolé par la mesure) :
- les filtres : `drop-shadow` jusqu'à 40 px, `blur(2px)` sur l'ombre du tracé de la carte, `mix-blend-mode` ;
- les animations de `width`/`height` et de `clip-path`, qui repassent par la mise en page ou la peinture.

La carte et le dénivelé, les deux éléments à grand SVG filtré, sont les plus chers seuls (160 % de CPU).

## 4. 🔴 Ce que `FlipFB "none"` coûte peut-être : la déchirure

Avec `FlipFB "none"`, l'adresse du tampon balayé ne change **jamais** pendant l'animation : 15 relevés de
`/sys/kernel/debug/dri/0/summary`, tous à `0x232c000`. Xorg **recopie** donc chaque image dans un tampon unique au
lieu de basculer, et une recopie non calée sur le balayage peut **déchirer** l'image. Ça ne se voit pas dans un
compteur. Mire posée à l'écran pour un contrôle **à l'œil** : `scripts/banc/mire-dechirure.mjs` (barres verticales
qui défilent ; une barre cassée à une hauteur = déchirure).

⇒ **`conf/xorg-rk.conf` reste en `"always"` tant que ce contrôle n'est pas fait.** Le choix est entre 30 img/s
sans déchirure et 60 img/s peut-être déchirées. Troisième voie, non essayée : l'option `MaxFlipRate` du fork.

## Ce que ça change pour la suite

1. **Wayland n'était pas le premier verrou** : la moitié de la cadence se perdait dans un réglage de Xorg.
2. Pour la séquence complète, le levier est **la page**, puis les drapeaux de Chromium, et ni Wayland ni
   Buildroot ne le lèvent. Les deux fils saturés tournent sur l'A55 quel que soit le serveur d'affichage.
3. Reste à mesurer : déchirure à l'œil ; séquence sans le serveur d'essai sur la box ; séquence avec les
   filtres retirés (pour chiffrer leur part) ; la webcam.
