# Test rapide — Chromium Radxa 126 (patché Rockchip) sur la TurboNode

*Mesuré le 30/09/2026, 20 h 12 - 20 h 40, sur `turbonode` (X88Pro20, RK3566), à la
demande d'Eliott. Affichage PGM coupé pendant le test (`turbohq.service` arrêté),
puis tout restauré et vérifié : sélections dpkg identiques, fichiers du
manifeste supprimés, unités turbohq/pxl identiques, `summary` identique
(3840x2160p60, Esmart0 NV12 1080p→4K + Smart0 OSD), `turbohq-present` de
nouveau maître DRM, `/opt/pxl-chrome-test` supprimé. Tags : [M] mesuré · [L] lu
· [D] déduit.*

## Montage

- `chromium-x11` **126.0.6478.126** du dépôt Radxa `rk3588-bookworm` (le dépôt
  en propose donc une plus récente que la 111 installée sur la Rock 5B) et
  `libv4l-rkmpp` 1.7.0 : **décompressés** dans `/opt/pxl-chrome-test`, pas
  installés. [M] Le binaire n'a aucune dépendance manquante : il embarque ses
  bibliothèques.
- MPP : celui compilé à la main dans `/usr/local/lib` (non remplacé).
- Serveur X : `xserver-xorg-core` + `xinit` + `x11-xserver-utils` (17 paquets
  apt, purgés à la fin). Sortie forcée en **1920x1080@60** par `xrandr`.
- Prérequis `libv4l-rkmpp` posés comme le script Radxa, mais avec la liste
  `rk356x` : `/dev/video-dec0` (VP8:VP9:H.264:H.265, 3840x2160), `/dev/video-enc0`,
  `/usr/lib/libv4l2.so`, `/usr/lib64 → lib`, le greffon dans
  `libv4l/plugins/`.
- Drapeaux : ceux du lanceur Radxa (`--use-gl=angle --use-angle=gles-egl
  --enable-gpu-rasterization --enable-accelerated-video-decode …`) +
  `--enable-features=AcceleratedVideoDecoder,VaapiVideoDecoder`, `--kiosk`.
- Mesure : page `<video>` plein écran, 20 s après 6 s de chauffe, par le
  protocole DevTools (`getVideoPlaybackQuality` + `requestVideoFrameCallback`) ;
  CPU système par `/proc/stat` ; preuve du décodage matériel par
  `/proc/mpp_service/sessions-summary` (`turbohq` arrêté ⇒ toute session
  `rkvdec` serait celle de Chromium).

## Résultats

| Étape | Fait |
|---|---|
| Rendu | [M] `ANGLE (Panfrost, Mali-G52 r1 (Panfrost), OpenGL ES 3.1)`, glamor + DRI3 actifs dans Xorg |
| libv4l2 Debian (`1.22.1-5+b2`) | [M] le décodeur V4L2 s'initialise puis `mmap() failed: No such device` ⇒ repli logiciel |
| libv4l2 **Radxa** (`1.22.1-5`, épinglée à 1001 sur la Rock 5B : version patchée) | [M] **MPP décode** : `put frame … fd`, `rkmpp_expbuf … export buf` réussis |
| Étape suivante, côté Chromium | [M] 🔴 `gbm_wrapper.cc: Failed to export buffer to dma_buf` ×16-32, `Frame converter returns null frame`, `SharedImageStub: Unable to create shared image`, **le processus GPU plante une fois**, puis repli sur le décodage **logiciel** |
| Mesa 25.0.7 (backports, via `LD_LIBRARY_PATH`) | [M] ANGLE tombe sur **llvmpipe** : `DRI3: Could not get DRI3 device` (client Mesa 25 face à un Xorg lié à Mesa 22.3). **Test non concluant**, pas un verdict sur Mesa 25 |

⇒ [D] **Le verrou n'est ni MPP ni `libv4l-rkmpp`** : ils marchent. C'est
l'allocation ou l'import GBM des tampons NV12 par Chromium sur **Panfrost / Mesa
22.3.6**. C'est le défaut décrit par crbug 372630272 (lu en extrait) : le
Chromium Rockchip est conçu et testé avec **libmali**, dont le GBM sait faire du
NV12.

## Cadence en décodage logiciel (repli effectif)

Chromium 126, X11, Panfrost/Mesa 22.3.6, sortie 1080p60 :

| Clip | Présentées/s | Décodées/s | Perdues en 20 s | Média avancé en 20 s | CPU (sur 400 %) | Temp. |
|---|---|---|---|---|---|---|
| H.264 High 1080p30 | **30,0** | 30,0 | 0-2 | 20,0 s | **246 %** | 82 °C |
| H.264 High 1080p60 | **39,1** | 45,9 | **199** | 15,4 s (ne tient pas le temps réel) | **380 %** (saturé) | 84 °C |
| HEVC Main 1080p60 | 0 | 0 | — | — | — | — |
| HEVC Main 2160p30 | 0 | 0 | — | — | — | — |

- [M] **HEVC : `MEDIA_ERR_DECODE` (code 3)** sur les deux clips. Chromium n'a
  pas de décodeur HEVC logiciel ; sans décodage matériel, le HEVC ne lit pas du
  tout.
- [M] Le 1080p30 H.264 tient, mais au prix de **2,5 cœurs sur 4** et de 82 °C.
  Le 1080p60 ne tient pas.
- [M] Premier essai (libv4l2 Debian, avant le plantage GPU) : ~104 % de CPU pour
  le même 1080p30. Le repli logiciel observé ensuite coûte donc plus cher,
  peut-être à cause du plantage du processus GPU. **Non tranché.**

## Ce que ça change

1. Le **décodage matériel dans Chromium est à portée** sur ce noyau : MPP +
   `libv4l-rkmpp` + libv4l2 Radxa fonctionnent. Il manque le maillon GBM NV12.
2. Trois façons de le fournir, chacune à mesurer :
   - (a) **Mesa ≥ 25 pour tout le système** (Xorg compris, ou sous Wayland
     sans X), pour vérifier si Panfrost importe le NV12 ;
   - (b) **libmali** + un noyau avec `MALI_BIFROST`, la cible pour laquelle ce
     Chromium est écrit ;
   - (c) le patch Rockchip d'une version récente (148-152), à recompiler, qui
     peut avoir changé ce chemin.
3. Sans décodage matériel : H.264 ≤ 1080p30 uniquement, et **pas de HEVC**.

## Ajout du 30/09 au soir — piste C : Mesa 25.0.7 pour tout le système

*Même banc, mais Mesa 25.0.7 (bookworm-backports, avec libdrm 2.4.123) installée
pour tout le système, donc cohérente entre Xorg et Chromium. Vérifié avant :
aucun service turbohq ne charge Mesa, `turbohq-presente` ne charge que
`libdrm`. Restauré ensuite à l'identique : **toutes les versions de paquets
identiques** (redescente exacte à 22.3.6-1+deb12u2 / 2.4.114-1+b1), sélections,
unités et `summary` identiques, `turbohq-present` maître DRM.*

- [M] Rendu : `ANGLE (Mesa, Mali-G52 r1 (Panfrost), OpenGL ES 3.1)`, glamor et
  DRI3 actifs. La cohérence du système règle bien le repli llvmpipe de l'essai
  précédent.
- [M] 🔴 **Même verrou** : `gbm_wrapper.cc: Failed to get fd for plane` /
  `Failed to export buffer to dma_buf` ×16, `Frame converter returns null frame`
  ×38, `SharedImageStub: Unable to create shared image` ×4. Aucune session
  `rkvdec` pendant la lecture.
- [M] Cadences en repli logiciel, identiques à 22.3.6 aux écarts de mesure près :

  | Clip | Présentées/s | Perdues en 20 s | CPU | Temp. |
  |---|---|---|---|---|
  | H.264 1080p30 | 30,0 | 0 | 264 % | 81 °C |
  | H.264 1080p60 | 35,9 | 223 | 380 % | 84 °C |
  | HEVC 1080p60 / 2160p30 | illisible (`MEDIA_ERR_DECODE`) | — | — | — |

⇒ [D] **Piste C fermée pour Mesa 25.0** : le GBM de Panfrost ne rend pas le fd
du plan chroma d'un tampon NV12. Ce n'est pas un défaut de 22.3 corrigé ensuite.
Restent la **piste B** (libmali + noyau `MALI_BIFROST`, la cible pour laquelle ce
Chromium est écrit) et un Mesa plus récent (26.x) non packagé pour bookworm.

## Ajout du 30/09 au soir — piste B : pilote kbase + libmali

*Autorisé explicitement par Eliott (arrêt des services, changement de pilote
GPU). Filet posé avant : `kernel.panic=10`, `panic_on_oops=1`. Tout est restauré
ensuite : kbase → panfrost, versions, modules, unités et `summary` identiques,
sysctl remis à 0. Reste sur la box : `/opt/pxl-mali` (sources et module
compilé), réutilisable.*

- [M] **Module kbase compilé hors arbre pour le noyau ophub** (sans recompiler le
  noyau) : sources `unifreq/linux-6.1.y-rockchip` `drivers/gpu/arm/bifrost`
  (**g29p1**, UK 11.47), en-têtes du paquet `linux-headers-6.1.141-rk35xx-ophub`,
  3 min 37 sur la box. `vermagic 6.1.141-rk35xx-ophub`, aucun symbole indéfini.
  Recette :
  - forcer la `version_compat_defs.h` de l'arbre source
    (`KCFLAGS="-I… -include …/version_compat_defs.h"`), car l'ancienne des
    en-têtes ophub passe devant ;
  - 🔴 **ne pas écraser `EXTRA_CFLAGS`** : le Makefile du pilote y met ses
    `-DCONFIG_MALI_*`. Passer ses options par `KCFLAGS`.
- [M] `rmmod panfrost` + `insmod bifrost_kbase.ko` : `GPU identified as 0x2 arch
  7.4.0 r1p0`, `Probed as mali0`, `/dev/mali0`. `gpuinfo` : `Mali-G52 1 cores
  r1p0`.
- [M] 🔴 **Pas de table OPP utilisable** (`_of_add_opp_table_v2: no supported
  OPPs`, `Continuing without devfreq`) : **GPU figé à 166 MHz**, contre 200-800
  sous Panfrost. [D] Le DT ophub filtre ses OPP par `rockchip,supported-hw` pour
  le pilote Rockchip, et ce filtre ne passe pas ici. À régler avant toute mesure
  de performance sous kbase.
- [M] libmali Radxa `libmali-bifrost-g52-g13p0-x11-gbm` 1.9-1, décompressée (pas
  installée).
- [M] 🔴 **Xorg de Debian + glamor sur libmali : segfault** au démarrage
  (glamor s'initialise, DRI2 s'installe, puis `Segmentation fault`).
- [M] 🔴 **Xorg sans accélération + libmali pour Chromium seul** : `[MALI-HOOK]
  Native display ignored`, `eglInitialize … Failed to get system egl display`,
  puis repli **SwiftShader**. libmali X11 exige un écran **DRI2**, et le
  modesetting de Debian n'offre DRI2 qu'avec glamor.

⇒ [D] **La piste B bute sur le serveur graphique, pas sur le noyau.** Le pilote
kbase marche. libmali X11 veut le **Xorg patché de Rockchip** (glamor sur
libmali), absent de Debian et du dépôt Radxa (la Rock 5B est sous Mesa). Deux
suites possibles :
- (a) compiler le `xserver` Rockchip ;
- (b) une pile Wayland libmali (variante `wayland-gbm`, weston Rockchip) avec un
  Chromium ozone-wayland patché (meta-rockchip 148-152), c'est-à-dire refaire la
  pile de référence du SDK.

Dans les deux cas, régler d'abord l'OPP du GPU.

## ✅ Ajout du 30/09 au soir — le DÉCODAGE MATÉRIEL marche : kbase + libmali + Xorg Rockchip

*Même discipline : bascule autorisée par Eliott, puis restauration totale
vérifiée (Panfrost, paquets identiques à l'état d'avant tous les tests, 23
dépendances de compilation purgées, unités et `summary` identiques, sysctl à 0).
Restent sur la box, réutilisables : `/opt/pxl-mali` (module kbase) et
`/opt/pxl-xorg` (Xorg Rockchip compilé).*

- [M] **Xorg Rockchip** : `JeffyCN/xorg-xserver`, branche `rockchip/debian/21.1.7`
  (commit `7c9c81f`, 11/11/2025).
  - Compilé en meson sur la box, uniquement le serveur Xorg (`-Dglamor=true
    -Ddri2=true -Dglx=false`), en 9 min 39. Installé dans `/opt/pxl-xorg/inst`,
    le Xorg système n'est pas touché.
  - Dépendances : 21 paquets `-dev` plus `xfonts-utils` (sinon `fontutil not
    found`).
  - Lancé avec `-modulepath …/xorg/modules -xkbdir /usr/share/X11/xkb`, plus un
    lien `xkbcomp` dans son `bin/` : sans ça, erreur fatale XKB.
  - Configuration reprise du `20-modesetting.conf` de meta-rockchip : glamor,
    `DRI "2"`, `FlipFB always`.
- [M] Résultat : `glamor X acceleration enabled on Mali-G52` et `[DRI2] Setup
  complete`, **sans le segfault** du Xorg de Debian. Chromium 126 Radxa voit
  **`ANGLE (ARM, Mali-G52, OpenGL ES 3.2)`**.
- [M] **Décodage matériel effectif** : `V4L2VideoDecoder` en API stateful (H264
  et HEVC), 20 tampons NV12, **une session `rkvdec` ouverte dans MPP** pendant
  chaque lecture, **aucune** erreur `gbm_wrapper` ni `null frame`. Le verrou NV12
  de Panfrost est levé par le GBM de libmali.

Mesures sur une sortie 1080p60, **GPU bloqué à 166 MHz** (pas d'OPP sous kbase) :

| Clip | Présentées/s | Décodées/s | CPU (sur 400 %) | Temp. | Repli logiciel (Panfrost) |
|---|---|---|---|---|---|
| H.264 1080p30 | **30,1** (0 perdue) | 30,0 | **133 %** | 71 °C | 30,0 à 246 %, 82 °C |
| H.264 1080p60 | **50,7** | **60,0** | 167 % | 74 °C | 39,1, CPU saturé, 84 °C |
| HEVC 1080p60 | **57,0** | **59,9** | 174 % | 72 °C | illisible |
| HEVC 2160p30 | 23,0 | **30,0** | 137 % | 72 °C | illisible |

⇒ [M] **Le décodeur tient partout la cadence de la source**, HEVC compris (qui
n'existait pas en logiciel). Le CPU baisse de moitié en 1080p30, et 10 °C de
moins.
⇒ [D] **Ce qui reste perdu en 60p et en 4K est côté composition et
présentation**, pas côté décodage. Le premier suspect est le **GPU à 166 MHz au
lieu de 800** : c'est le prochain verrou, avant toute conclusion sur la cadence.
Ensuite viendront X11 (pas d'overlay vidéo) et `FlipFB always`.

**Recette reproductible** (tout hors du système, sauf les paquets Xorg et `-dev`) :
1. module kbase g29p1 hors arbre (plus haut) ;
2. libmali Radxa `bifrost-g52-g13p0-x11-gbm` en `LD_LIBRARY_PATH` ;
3. Xorg Rockchip compilé ;
4. Chromium Radxa 126, `libv4l-rkmpp` 1.7.0 et **libv4l2 Radxa 1.22.1-5**
   (patch mmap) ;
5. `/dev/video-dec0` avec la liste de codecs RK356x.

**Suites** :
- (1) réparer l'OPP GPU sous kbase (overlay DT sans `opp-supported-hw`, ou kbase
  plateforme `rk`) ;
- (2) essayer la libmali **g29p1** du SDK, appariée au kbase ;
- (3) mesurer en 60p après (1).

## 🔴 Incident du 30/09, 23 h 16 - 23 h 34 — `rmmod bifrost_kbase` → Oops, box figée, labo coupé

*Écrit pour ne pas être refait.*

1. [M] Premier rejeu du dépôt réussi. `restaurer.sh` fait alors `rmmod
   bifrost_kbase` + `modprobe panfrost`, puis relance turbohq.
2. [M] `WARN` dans `clk_core_unprepare` au chargement de panfrost. Puis, au modeset
   du présentateur : **Oops** `Unable to handle kernel paging request` dans
   `rockchip_system_status_notifier` ← `vop2_set_system_status` ←
   `vop2_crtc_atomic_disable`. Le présentateur reste bloqué en D dans
   `drm_fb_release`.
3. [D] Mécanisme : avec les OPP actives (le correctif), kbase s'inscrit au moniteur
   système Rockchip. Le `rmmod` y laisse un pointeur vers le module déchargé, que le
   premier changement d'état du VOP2 appelle. ⚠️ `restaurer.sh` venait de remettre
   `panic_on_oops=0` : le filet était retiré **avant** la manœuvre risquée.
4. [M] Redémarrage forcé demandé à distance. La box met plus de 10 minutes à revenir,
   puis revient seule (aucune intervention physique).
5. [M] Pendant ce temps, **`pxl-tx` aussi est hors ligne**, alors qu'elle n'a pas
   redémarré (5 j de fonctionnement) : son accès passe par la TurboNode
   (`turbohq-dhcp`, `turbohq-dns`, `turbohq-routage`). ⇒ **toucher au noyau de la
   TurboNode peut couper le réseau du labo.**
6. [M] Après le retour : paquets, modules, unités et sysctl identiques. Mais le
   présentateur reste **en veille** : son `thq-video-pipe` était mort sur
   `EHOSTUNREACH 192.168.55.10:8720` pendant la coupure, et **n'est pas relancé**. Un
   `systemctl restart turbohq.service` le ramène, et l'affichage redevient identique
   à l'état initial. ⚠️ À remonter côté TurboHQ : **le pipe ne survit pas à une
   coupure du relais.**

**Corrections faites** : `restaurer.sh` ne décharge plus jamais kbase. Il purge,
garde le filet panic et **redémarre**, puis se relance pour vérifier.
