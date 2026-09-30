# Décodage vidéo matériel dans Chromium sur RK3566/RK3568 (Linux), et accès aux plans matériels — état au 30/09/2026

> Conventions : **[mesuré par la source]** = la source rapporte un essai ; **[lu]** = lu dans du code, un paquet ou une doc ; **[déduit]** = mon inférence. Puce / noyau / version de Chromium sont indiqués à chaque fait ; ⚠️ TRANSPOSITION signale un fait établi sur une autre puce que la RK3566.
> Limites d'accès (30/09/2026) : le proxy a refusé (403 « host not in allowlist ») issues.chromium.org, groups.google.com, forum.armbian.com, forum.radxa.com, www.collabora.com, www.cnx-software.com, lkml.org, lore.kernel.org, patchwork.kernel.org, git.kernel.org, bugzilla.mozilla.org. Pour ces hôtes, seul l'extrait du moteur de recherche est cité, marqué « (extrait de recherche) ». Seuls github.com / raw.githubusercontent.com et launchpad.net étaient lisibles ; le code de Chromium et de Linux a été lu sur leurs miroirs GitHub (`chromium/chromium` main, `torvalds/linux` master = **7.3-rc5**) le 30/09/2026. Le budget de recherche web de la session (200 requêtes) a été épuisé en cours de travail.

## 1. Le Chromium Rockchip de JeffyCN (V4L2 via le plugin libv4l2 libv4l-rkmpp) : versions, X11/Wayland, paquets 2025-2026, RK3566, Panfrost ou libmali ?

### Takeaway
Les correctifs Chromium de Rockchip (Jeffy Chen) sont **vivants** : la couche Yocto `meta-rockchip` porte Chromium **148 à 152** (152 ajouté le 17/09/2026), en X11 et en Wayland. En revanche, les **paquets Debian/Ubuntu** qui en dérivent sont figés : Radxa livre encore le binaire Rockchip **111** (2023), et la PPA d'amazingfate s'arrête à **132** (05/03/2025). Aucun paquet ne vise la RK3566 sur Debian bookworm. Tous les essais publiés portent sur RK3588 ou RK3568 avec libmali ou Panfork. Rien ne montre ce build tourner sur Panfrost/Mesa amont avec une RK3566.

### Cited Findings
**Ce que c'est (code, [lu])**
- libv4l-rkmpp se décrit comme « A V4L2 plugin that wraps rockchip-mpp for the chromium's V4L2 video decoder/VEA (requires custom patches to enable those features) ». Il avertit : « There're a lot of chromium related hacks in it, might not work for other apps ». Il a été testé sur « rk3588 EVB » avec un Chromium sur mesure et exige des nœuds factices `/dev/video-dec0` et `/dev/video-enc0` [lu, RK3588] — [README libv4l-rkmpp](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/README.md)
- Le correctif principal `0002-HACK-media-Support-V4L2-video-decoder.patch` (Jeffy Chen, 14/12/2023, reconduit en 152) porte l'en-tête « Tested on RK3588 EVB with: 1/ Install libmali, v4l-rkmpp, mpp and custom v4l-utils. 2/ Run "echo dec > /dev/video-dec0" » [lu, RK3588, libmali] — [patch 0002, meta-rockchip chromium_152.0.7977](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium_152.0.7977/0002-HACK-media-Support-V4L2-video-decoder.patch)
- Ce même correctif fait trois choses [lu, Chromium 152] — [patch 0002](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium_152.0.7977/0002-HACK-media-Support-V4L2-video-decoder.patch) :
  - il force sous Linux les noms de périphériques de ChromeOS (« HACK: We are using chromeos style devices », `/dev/video-dec`, `/dev/video-enc`) ;
  - il refuse les formats « slice » (les décodeurs sans état) hors ChromeOS (« Slice is not supported ») et force `IsV4L2DecoderStateful()` à false ;
  - il élargit `use_av1_hw_decoder` à tout Linux.
- Le chargement du plugin passe par `0005-media-gpu-v4l2-Support-libv4l2-plugins.patch`, écrit à l'origine par Damian Hobson-Garcia (IGEL, 2018) : il fait un `dlopen` de `/usr/lib64/libv4l2.so` ou `/usr/lib/libv4l2.so` et « Depends on custom libv4l2 with mmap & munmap » [lu] — [patch 0005](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium_152.0.7977/0005-media-gpu-v4l2-Support-libv4l2-plugins.patch)
- Le lot 152 compte 18 correctifs, dont plusieurs contournements propres à Mali [lu] — [répertoire chromium_152.0.7977](https://github.com/JeffyCN/meta-rockchip/tree/master/dynamic-layers/recipes-browser/chromium/chromium_152.0.7977) :
  - `0001` Revert « Remove HEVC code for stateful video decoder » (24/07/2026) ;
  - `0003` « HACK: Enable V4L2 VEA » ;
  - `0011` « The Mali's implicit external sync seems broken » (31/05/2021) ;
  - `0015` « Force disabling modifiers — It crashes somehow » (07/08/2023) ;
  - `0016` « Fix config choosing error with Mali DDK » en X11 (22/05/2024) ;
  - `0017` « Prefer rockchip drm render node » en Ozone/Wayland (12/09/2025).

  **Aucun** de ces correctifs ne touche aux overlays ni aux plans matériels.
- La recette `chromium-%.bbappend` (réglages de compilation) [lu] — [chromium-%.bbappend](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium-%25.bbappend) :
  - `PACKAGECONFIG ??= "use-egl use-v4l2 use-v4lplugin proprietary-codecs"`, `use_v4lplugin=true` ;
  - arguments `--no-sandbox --gpu-sandbox-start-early --ignore-gpu-blocklist` ;
  - `--enable-features=AcceleratedVideoEncoder,AcceleratedVideoDecoder`.
- Il existe des surcouches pour `chromium-ozone-wayland` et pour `chromium-x11` [lu] — [répertoire recettes](https://github.com/JeffyCN/meta-rockchip/tree/master/dynamic-layers/recipes-browser/chromium)

**Versions (datées, [lu])**
- Historique de `meta-rockchip` [lu] — [commits meta-rockchip/chromium](https://github.com/JeffyCN/meta-rockchip/commits/master/dynamic-layers/recipes-browser/chromium) :
  - « Drop R96 and R97 » (02/04/2024) ;
  - 119 (15/12/2023), 120 (02/04/2024), 121 (07/04/2024), 122 (08/05/2024), 124 et 125 (27/06/2024), 126 (23/07/2024) ;
  - 129 (11/10/2024), 130 (08/11/2024), 131 (25/12/2024), 132 (07/03/2025), 136 (30/07/2025, mis à jour le 12/09/2025) ;
  - « Drop old versions » puis 148 (09/06/2026), 149 (16/06/2026), 150 (20/07/2026), « Support HEVC » (24/07/2026), 151 (04/09/2026), 152 (17/09/2026) ;
  - correctifs notables : « Fix SIGTRAP during dynamic video resolution switching » (10/02/2026), « Fix video decoding error » (06/03/2026).
- Le profil GitHub de JeffyCN donne les dates de mise à jour suivantes [lu] — [dépôts JeffyCN](https://github.com/JeffyCN?tab=repositories) :
  - `meta-rockchip` et `mirrors` : 22/09/2026 ;
  - `weston` (« hacks for Rockchip Linux SDK ») : 15/09/2026 ;
  - `libv4l-rkmpp` : 30/04/2025 ;
  - `v4l-utils` (« tailored for Rockchip SDK ») : 12/05/2025.
- **Radxa** : `radxa-pkg/chromium-x11` = « Rockchip prebuilt Chromium ». Son script `fixup` reconditionne `chromium-x11_111.0.5563.147_arm64.deb` avec `patchelf --replace-needed libmali.so.1 libgbm.so.1` et ajoute la dépendance `libc++1` [lu, Chromium 111] — [README](https://github.com/radxa-pkg/chromium-x11) · [fixup](https://github.com/radxa-pkg/chromium-x11/blob/main/fixup)
- La page des publications Radxa liste 111.0.5563.147 et 111.0.5563.147-2 (2023), avec la note « This old Chromium version is picked specifically for better VPU support » [lu] — [releases chromium-x11](https://github.com/radxa-pkg/chromium-x11/releases)
- **PPA d'amazingfate (Jianfeng Liu)**, séries Noble et Jammy [lu] — [paquets chromium de la PPA](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia/+packages?field.name_filter=chromium) :
  - `chromium …+rkmpp` (base Debian) : 122 (05/2024), 125 et 126 (07/2024 ; 126 reste publié pour Jammy), 130 (16/11/2024), puis **132.0.6834.159-1~deb12u1+rkmpp (Noble, 05/03/2025, dernière publiée)** ;
  - `chromium-browser` (base Ubuntu) : 105 (12/2022), 110 (01/2023), 114.0.5735.35 (Jammy 08/2023, Noble 05/2024).
- La même PPA contient aussi [lu] — [PPA rockchip-multimedia](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia) :
  - `libv4l-rkmpp` 1.7.0 (15/05/2024) ;
  - `mpp` 1.5.0+git20240612 ;
  - `gstreamer1.0-rockchip` 1.14-4+git240423 ;
  - `ffmpeg` 6.1.1+git240504 ;
  - `rockchip-multimedia-config` 1.0.2.
- Les sources de ces paquets sont dans le dépôt `amazingfate/chromium-debian-build`. Branches `rockchip-rkmpp-130` (16/11/2024) et `rockchip-rkmpp-132` (05/03/2025) [lu] — [branches](https://github.com/amazingfate/chromium-debian-build/branches/all) · [rules rkmpp-132](https://github.com/amazingfate/chromium-debian-build/blob/rockchip-rkmpp-132/debian/rules) · [default-flags rkmpp-132](https://github.com/amazingfate/chromium-debian-build/blob/rockchip-rkmpp-132/debian/etc/default-flags) :
  - compilation arm64 : `use_v4l2_codec=true use_vaapi=false use_v4lplugin=true` ;
  - correctifs `rkmpp/0001…0015` repris de JeffyCN ;
  - drapeaux par défaut `--ozone-platform-hint=wayland` (commentaire « Use ozone wayland for vpu decoding ») et `--enable-features=AcceleratedVideoDecoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL`.
- Selon l'annonce de la PPA sur le forum Radxa, celle-ci « was tested on 5.10 kernel on both rk3568 and rk3588 » [lu, RK3568/RK3588, BSP 5.10] (extrait de recherche) — [Radxa forum, intro PPA](https://forum.radxa.com/t/introduction-to-rockchip-multimedia-ppa-for-ubuntu-jammy/14537)
- **Armbian**, PR configng #887 (21-24/04/2026, fusionnée) [lu] — [armbian/configng #887](https://github.com/armbian/configng/pull/887) :
  - installe depuis `ppa:liujianfeng1994/rockchip-multimedia`, épinglée en priorité 1001, les paquets « chromium (hardware-accelerated), libv4l-rkmpp, gstreamer1.0-rockchip, libwidevinecdm0, rockchip-multimedia-config » ;
  - **uniquement** pour la combinaison Noble + RK3588 + noyau vendor.
- **ubuntu-rockchip** (Joshua Riek) [lu] — [ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip) :
  - dépôt archivé le 29/04/2026 ;
  - son README annonçait « Chromium browser with smooth 4k youtube video playback » et « 3D hardware acceleration support via panfork » (Ubuntu 22.04 avec noyau Rockchip 5.10, 24.04 avec 6.1).
- Le 01/07/2025, un utilisateur y écrit que Chromium 130 est « working well on this image. Any version above does not working properly » [mesuré par la source, RK3588 probable] — [discussion #271](https://github.com/Joshua-Riek/ubuntu-rockchip/discussions/271)
- **Arch Linux ARM** (`7Ji-PKGBUILDs/chromium-mpp`, fondé sur les correctifs meta-rockchip) : « You must run on X11 + mali blob driver + panfork mesa + 5.10 BSP kernel » [lu, RK3588] — [chromium-mpp](https://github.com/7Ji-PKGBUILDs/chromium-mpp)

**Couverture RK3566, et Panfrost face à libmali**
- Création des nœuds factices, deux scripts différents [lu] :
  - `create-chromium-vda-vea-devices.sh` d'amazingfate teste `*rk356*` dans `/proc/device-tree/compatible` et écrit `codecs=VP8:VP9:H.264:H.265`, `max-width=3840`, `max-height=2160`. Une règle udev le lance quand `mpp_service` apparaît — [script](https://github.com/amazingfate/rockchip-multimedia-config/blob/main/create-chromium-vda-vea-devices.sh) · [règles udev](https://github.com/amazingfate/rockchip-multimedia-config/blob/main/99-rk-device-permissions.rules) ;
  - `rockchip-chromium-prep` de Radxa teste `*rk3568*`, sinon écrit seulement `dec`. Il crée aussi `/usr/lib/libv4l2.so` (« The chromium using fixed pathes for libv4l2.so ») et le lien `/usr/lib64`. Dernière version 0.2.3 (11/06/2024) — [rockchip-chromium-prep](https://github.com/radxa-pkg/rockchip-chromium-x11-utils/blob/main/usr/bin/rockchip-chromium-prep) · [changelog](https://github.com/radxa-pkg/rockchip-chromium-x11-utils/blob/main/debian/changelog)
- Issue libv4l-rkmpp #18 (amazingfate, 08/04/2024), Chromium 121 + Panfork sur noyau 6.1.43 [lu/mesuré par la source, RK3588 probable] — [issue #18](https://github.com/JeffyCN/libv4l-rkmpp/issues/18) :
  - titre : « chromium v121 can't use egl to render video output » ;
  - erreur : « Could not find SharedImageBackingFactory with params: usage: DisplayRead|Scanout, format: NV12_LEGACY » ;
  - sans la ligne de correctif incriminée, Chromium repasse par le processeur d'image libyuv (NV12 → AR24).
- ubuntu-rockchip #692 (05/04/2024), **Radxa Zero 3W (RK3566)** : « Chromium: No GPU Video acceleration », avec « Failed to export buffer to dma_buf: No such file or directory » et « Failed to query video capabilities: Inappropriate ioctl for device ». Fermée « not planned » [mesuré par la source, RK3566] — [issue #692](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/692)
- Jianfeng Liu a fait entrer dans le Chromium officiel de Debian le correctif `fixes/libsync-rk3588-panthor.patch` (132.0.6834.110-1~deb12u1, 22/01/2025). Motif : « Chromium will crash with panthor gpu driver on rk3588 when running with ozone wayland » (issue amont 343592370) [lu, RK3588, Panthor] — [changelog Debian (miroir)](https://github.com/amazingfate/chromium-debian-build/blob/bookworm/debian/changelog) · [correctif](https://github.com/amazingfate/chromium-debian-build/blob/mainline-v4l2-138/debian/patches/fixes/libsync-rk3588-panthor.patch)

### Inferences
- **Versions qui existent** [déduit des sources ci-dessus] :
  - binaire Rockchip 111 (reconditionné par Radxa) ;
  - PPA : 105, 110, 114 (base Ubuntu), puis 122 à 132 (base Debian) ;
  - correctifs Yocto de 119 à 136 (2023-2025), puis 148 à 152 (2026).

  Il n'existe donc **aucun paquet .deb à jour** : 132 date de mars 2025 et 111 d'avril 2023, soit des mois ou des années de correctifs de sécurité manquants. En 2026, il faut **compiler soi-même** à partir de `meta-rockchip`, sur le modèle des branches `rockchip-rkmpp-13x`.
- **RK3566** [déduit] :
  - MPP traite RK3566 et RK3568 à l'identique (question 2), et le script d'amazingfate cible `rk356*`. La voie est donc **plausible** sur RK3566, mais **aucune source ne publie un essai réussi** sur RK3566 ; le seul signalement RK3566 (#692) est un échec.
  - ⚠️ TRANSPOSITION : `rockchip-chromium-prep` de Radxa teste `*rk3568*`. Une carte RK3566 déclare en général `rockchip,rk3566`, donc le script tombe sur le cas par défaut `dec` : pas de liste de codecs, et libv4l-rkmpp annonce sa table complète, **AV1 jusqu'à 7680×4320 compris**, alors que la RK3566 ne décode pas l'AV1 (question 2). Il faut réécrire `/dev/video-dec0` avec la liste « rk356* » d'amazingfate.
- **Panfrost ou libmali** [déduit] : le code n'exige pas libmali (Radxa remplace même `libmali.so.1` par `libgbm.so.1`), et ubuntu-rockchip l'a fait tourner avec Panfork. Mais :
  - Rockchip teste avec libmali, et quatre correctifs visent le pilote Mali (DDK) ;
  - le chemin « NV12 affiché sans copie » a échoué avec Panfork (#18) ;
  - l'ensemble Panfrost amont + Mesa 22.3.6 + RK3566 + ce Chromium n'est documenté nulle part.

  Il faut s'attendre, au mieux, à une conversion NV12 → AR24 par le CPU (libyuv) si l'import EGL NV12 échoue.
- **X11 ou Wayland** [déduit] : Rockchip compile les deux. amazingfate impose Wayland (« Use ozone wayland for vpu decoding »). 7Ji exige X11 avec le pilote libmali. Le choix dépend donc de la pile GPU : libmali marche avec X11, Mesa semble demander Wayland.
- **Le build rkmpp ne sait parler qu'à libv4l-rkmpp** [déduit du correctif 0002] : il refuse les formats « slice » hors ChromeOS et ne cherche que `/dev/video-dec*`. Il **ne peut pas** utiliser les décodeurs V4L2 sans état du noyau amont. Réciproquement, un Chromium de distribution ne cherche que `/dev/videoN` et `/dev/mediaN` et ne charge pas de plugin libv4l2 ; il ne peut donc pas utiliser libv4l-rkmpp.

### Gaps
- Aucun chiffre publié (images perdues, cadence) pour le Chromium rkmpp sur RK3566 ou RK3568.
- Impossible de vérifier que le noyau vendor de la box RK3566 (Armbian 6.1.141) déclare bien `rockchip,rk3566` : je n'ai pas lu le DTS de la carte. Le piège Radxa reste donc une inférence.
- La dépendance exacte de la PPA à libmali ou à Mesa, et l'existence d'une compilation pour Debian bookworm, n'ont pas pu être vérifiées. Le paquet Noble (glibc 2.39) ne s'installerait vraisemblablement pas sur bookworm (glibc 2.36) [déduit, non vérifié].
- Le forum Radxa est inaccessible (proxy 403). Les messages d'amazingfate sur la RK3566 n'ont pu être lus qu'en extrait.

## 2. libv4l-rkmpp : maintenance, MPP et noyau requis, codecs et résolutions sur RK3566, problèmes connus

### Takeaway
libv4l-rkmpp est **en sommeil** : dernière version 1.8.0 le 08/01/2025, dernier commit le 30/04/2025. Elle exige un noyau **BSP** (`/dev/mpp_service`, absent de Linux amont), la bibliothèque MPP et une libv4l2 corrigée. Elle ne sort que du **NV12 8 bits**, sans chemin 10 bits. Sa table par défaut plafonne H.264, HEVC et VP9 à 4K. La RK3566 n'a matériellement pas d'AV1.

### Cited Findings
- Versions [lu] — [historique des commits libv4l-rkmpp](https://github.com/JeffyCN/libv4l-rkmpp/commits/master) · [debian/changelog](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/debian/changelog) :
  - 1.5.0 (14/09/2022), 1.5.1 (08/11/2022), 1.6.0 (15/12/2023), 1.7.0 (25/03/2024), 1.7.1 (18/06/2024), 1.8.0 (08/01/2025) ;
  - derniers commits le 30/04/2025 : « dec: Fix decoding error after seeking » et « dec: Apply special alignment for VP9 » ;
  - décodage AV1 ajouté le 30/01/2023 ;
  - prise en charge du « chromium V4L2 stateful video decoder » en décembre 2023 et mars 2024 ;
  - encodage MJPEG en décembre 2024.
- Dépendances [lu] — [debian/control](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/debian/control) · [meson.build](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/meson.build) · [README](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/README.md) :
  - à la compilation, `librockchip-mpp-dev` et `libv4l-dev`, sans version imposée ; `meson` déclare `dependency('rockchip_mpp')` sans contrainte ;
  - le README exige v4l-utils corrigé par `0001-libv4l2-Support-mmap-to-libv4l-plugin.patch` ;
  - en cas d'erreur, il conseille la branche MPP release ou develop, « or the commit with the closest commit date ».
- `/dev/mpp_service` est créé par le pilote BSP `drivers/video/rockchip/mpp` (`#define MPP_SERVICE_NAME "mpp_service"`). Ce pilote est présent dans `rockchip-linux/kernel` develop-5.10 et develop-6.1 et dans le noyau vendor d'Armbian `linux-rockchip` rk-6.1-rkr5.1 ; il est **absent** de `torvalds/linux` master (7.3-rc5) [lu] — [mpp_service.c, BSP 6.1](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_service.c) · [Armbian rk-6.1-rkr5.1](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr5.1/drivers/video/rockchip/mpp/mpp_service.c)
- Table de décodage par défaut de libv4l-rkmpp [lu] — [libv4l-rkmpp-dec.c](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/src/libv4l-rkmpp-dec.c) · [libv4l-rkmpp.c](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/src/libv4l-rkmpp.c) :
  - un seul format de sortie : NV12 (`MPP_FMT_YUV420SP`, 12 bits/pixel) ;
  - AV1 48 à 7680×4320 ; H.265 48 à 3840×2160 ; H.264 48 à 3840×2160 ; VP8 48 à 3840×2160 ; VP9 48 à 3840×2176 ;
  - les options `codecs=`, `max-width=` et `max-height=` du nœud factice réduisent cette table.
- Le décodeur déclare VP9 profils 0 à 2, mais aucun format de sortie 10 bits. L'issue #21 « Handling 10-bit HEVC/VP9/AV1 videos? » (nyanmisaka, 25/04/2024) est **toujours ouverte** [lu] — [libv4l-rkmpp-dec.c](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/src/libv4l-rkmpp-dec.c) · [issues](https://github.com/JeffyCN/libv4l-rkmpp/issues)
- Autres problèmes signalés [lu] :
  - issue #5 « some videos are displayed all green » (date non lue) — [issue #5](https://github.com/JeffyCN/libv4l-rkmpp/issues/5) ;
  - issue #18, rendu EGL du NV12 avec Panfork (question 1) — [issue #18](https://github.com/JeffyCN/libv4l-rkmpp/issues/18).
- Capacités matérielles selon MPP (`rockchip-linux/mpp` develop, `osal/mpp_soc.c`) : « rk3566/rk3567/rk3568 has codec: 1 - vpu2 for jpeg encoder and decoder, 2 - RK H.264/H.265/VP9 4K decoder, 3 - RK H.264/H.265 4K encoder, 3 - RK jpeg decoder » [lu, RK3566 = RK3568] — [mpp_soc.c](https://github.com/rockchip-linux/mpp/blob/develop/osal/mpp_soc.c) :
  - `vdpu34x` : AVC, HEVC, VP9 ; sortie AFBC_V2 ou raster ; 10 bits ; un seul cœur ;
  - `vdpu2` : MPEG-2, H.263, MPEG-4, AVC, MJPEG, VP8, AVS ; `cap_4k = 0`.
- Le décodeur VDPU346 (RK3566/RK3568) « is similar to VDPU381 but with a single core and limited to 4K60 media », « limited to H264 L5.1 and omits AV1 and AVS2 » [lu, RK356x] (extrait de recherche, lettre de présentation de C. Hewitt, 01/2026) — [LKML v3 0/3](https://lkml.org/lkml/2026/1/10/140)
- MPP reste maintenu : la branche `mpp-dev` du miroir JeffyCN date du 08/09/2026, `gstreamer-rockchip` du 26/08/2026 [lu] — [branches JeffyCN/mirrors](https://github.com/JeffyCN/mirrors/branches/all)

### Inferences
- Ce qu'on peut attendre sur RK3566 par cette voie [déduit] :
  - H.264 et HEVC 8 bits jusqu'à 3840×2160, VP9 profil 0 jusqu'à 3840×2176, via `vdpu34x` ;
  - VP8 via `vdpu2`, sans 4K côté MPP, alors que libv4l-rkmpp annonce 3840×2160 par défaut ;
  - **pas d'AV1**, et **pas de HEVC ni VP9 10 bits** (sortie NV12 seule, issue #21 ouverte).
- Le paquet Radxa `libv4l-rkmpp 1.5.1` de la Rock 5B du labo, **s'il correspond au tag du 08/11/2022**, est antérieur à l'ajout de l'AV1 (30/01/2023). La liste « AV1 » écrite par `rockchip-chromium-prep` serait alors sans effet [déduit ; version Debian exacte non vérifiée].
- Rythme de maintenance : pas de publication depuis 20 mois et pas de commit depuis 17. Chaque nouveau Chromium doit donc être recollé par Rockchip, dans `meta-rockchip`, et non par ce plugin [déduit].

### Gaps
- Pas de fiche technique RK3566 consultée : le budget de recherche était épuisé. Les cadences exactes (4K60 H.264 ? VP8 1080p60 ?) viennent seulement de l'extrait LKML et du commentaire MPP.
- Version minimale de MPP : non documentée ; seul le conseil « commit le plus proche en date » existe.
- Le correctif « mmap » de libv4l2 est-il entré dans v4l-utils amont ? Non vérifié.

## 3. Voie amont (noyau Linux) : état de hantro, rkvdec et VDPU346 pour RK356x ; Chromium de distribution et V4L2 sans état en 2026 ; ponts VA-API ; Firefox en comparaison

### Takeaway
Dans Linux amont (**7.3-rc5**, 30/09/2026), la RK3566/RK3568 n'a que **hantro VDPU2** : H.264 et MPEG-2 ≤ 1920×1088, VP8 ≤ 3840×2160. Le pilote rkvdec amont gère VDPU381 (RK3588) et VDPU383 (RK3576) en H.264 et HEVC, mais **ne connaît pas `rk3568-vdec`** : la série VDPU346 de C. Hewitt (v3, 01/2026) n'est pas dans l'arbre de Linus. **Armbian edge** (6.18 / 7.2 / 7.3) pallie ce manque par un DT maison qui pilote le VDPU346 comme un `rk3588-vdec`. Côté navigateur, Chromium de distribution (Debian, Arch ARM, xtradeb) **sait** décoder en V4L2 sans état sur Linux en 2026, avec `--enable-features=AcceleratedVideoDecoder` et, en pratique, une session Wayland ; c'est mesuré sur RK3588, et esquissé sur RK3566 (issue Armbian).

### Cited Findings
**Noyau amont (lu dans `torvalds/linux` master, `Makefile` = 7.3-rc5)**
- Le pilote rkvdec a quitté staging pour `drivers/media/platform/rockchip/rkvdec/` [lu, 7.3-rc5] — [rkvdec.c](https://github.com/torvalds/linux/blob/master/drivers/media/platform/rockchip/rkvdec/rkvdec.c) · [Makefile rkvdec](https://github.com/torvalds/linux/blob/master/drivers/media/platform/rockchip/rkvdec/Makefile) :
  - compatibles : `rockchip,rk3288-vdec`, `rk3328-vdec`, `rk3399-vdec`, `rk3588-vdec` (vdpu381), `rk3576-vdec` (vdpu383) — **aucun rk3568 ni rk3566** ;
  - vdpu381 et vdpu383 : H.264 et HEVC uniquement (fichiers `rkvdec-vdpu381-h264/hevc`, `-vdpu383-h264/hevc`), HEVC jusqu'à Main10 ;
  - VP9 n'existe que pour l'ancien rkvdec.
- `rk356x-base.dtsi` amont ne décrit que `vpu: video-codec@fdea0400` (`rockchip,rk3568-vpu`) et `vepu` (`rockchip,rk3568-vepu`), **aucun nœud rkvdec** [lu, 7.3-rc5] — [rk356x-base.dtsi](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk356x-base.dtsi)
- hantro, variante `rk3568_vpu_variant` : décodeurs MPEG-2, VP8 et H.264, formats `rockchip_vdpu2_dec_fmts`. `H264_SLICE` et `MPEG2_SLICE` ≤ FHD, `VP8_FRAME` ≤ UHD, avec FHD = 1920×1088 et UHD = 3840×2160 [lu, 7.3-rc5] — [rockchip_vpu_hw.c](https://github.com/torvalds/linux/blob/master/drivers/media/platform/verisilicon/rockchip_vpu_hw.c) · [hantro_hw.h](https://github.com/torvalds/linux/blob/master/drivers/media/platform/verisilicon/hantro_hw.h)
- Collabora a annoncé la fusion amont de VDPU381/VDPU383 (H.264 et HEVC, RK3588/RK3576), avec pour suite « multi-core support on RK3588, AV1 support on RK3576, VP9 code support on RK3588, and also add support for the VDPU346 decoder » [lu, RK3588/RK3576] (extraits de recherche) — [Collabora](https://www.collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html) · [CNX, 27/02/2026](https://www.cnx-software.com/2026/02/27/rockchip-rk3588-rk3576-h-264-and-h-265-video-decoders-mainline-linux/)
- Série VDPU346 de Christian Hewitt [lu, RK356x] (extraits de recherche) — [v1](https://lkml.org/lkml/2025/12/6/191) · [v2](https://lkml.org/lkml/2025/12/26/206) · [v3 0/3](https://lkml.org/lkml/2026/1/10/140) · [v3 3/3](https://lkml.org/lkml/2026/1/10/143) :
  - v1 le 06/12/2025, v2 le 26/12/2025, v3 le 10/01/2026, intitulée « media: rockchip: rkvdec: add support for the VDPU346 variant » ;
  - la v3 apporte « correct .max_width/.max_height from TRM » et des Tested-by ;
  - le correctif DT 3/3 s'intitule « Add the vdpu346 Video Decoders on RK356X ».
- Armbian, noyau edge [lu] — [rk356x-add-rkvdec2-support.patch](https://github.com/armbian/build/blob/main/patch/kernel/archive/rockchip64-7.3/rk356x-add-rkvdec2-support.patch) · [media-0003-rk3568-disable-hantro-h264.patch](https://github.com/armbian/build/blob/main/patch/kernel/archive/rockchip64-7.3/media-0003-rk3568-disable-hantro-h264.patch) :
  - `patch/kernel/archive/rockchip64-{6.18,7.2,7.3}` porte `rk356x-add-rkvdec2-support.patch` (amazingfate, 28/07/2024). Ce correctif DT ajoute une SRAM et un nœud décodeur de compatible **`rockchip,rk3588-vdec`** sur RK356x, et passe le VPU hantro en `rockchip,rk3328-vpu` ;
  - il porte aussi `media-0003-rk3568-disable-hantro-h264.patch` (« disable hantro g1 h264 decoder on rk356x ») ;
  - `armbian/build` HEAD du 29/09/2026.
- PR Armbian #6804 (fusionnée le 28/07/2024, noyau edge 6.10) [mesuré par la source, RK3568] — [armbian/build #6804](https://github.com/armbian/build/pull/6804) :
  - tests dans Chromium : H.264 1080p et 2160p, VP8 1080p, sur Rock 3A (RK3568) ;
  - `cma=256M` fixé par `rk356x.txt`.
- Issue Armbian #9175 (07/01/2026), **Orange Pi 3B (RK3566)**, noyau edge **6.18.3** [mesuré par la source, RK3566, mainline 6.18] — [armbian/build #9175](https://github.com/armbian/build/issues/9175) :
  - Chromium xtradeb `143.0.7499.169` : chrome://gpu affiche « Video Decode: Software only. Hardware acceleration disabled » ;
  - `--enable-features=AcceleratedVideoDecoder` rétablit l'accélération ;
  - la version `135.0.7049.84-1~deb12u1+narmbian1` l'avait d'office ; même comportement avec xtradeb sur Trixie.
- Sur Orange Pi 3B (RK3566) avec un noyau 6.9, « chromium can decode 4K H264 video with hardware acceleration », grâce au correctif DT d'amazingfate [mesuré par la source, RK3566, 6.9] (extrait de recherche) — [Armbian forum, sujet 32020](https://forum.armbian.com/topic/32020-orange-pi-3b-graphic-acceleration-driver/)
- ⚠️ ANCIEN (2023) : sur PineTab 2 (RK3566), seul hantro existait en amont (« no mainline driver » pour rkvdec2) ; le H.264 passait par GStreamer compilé soi-même, Clapper ou µPlayer [lu, RK3566, amont 2023] (extrait de recherche) — [clehaxze.tw, 17/09/2023](https://clehaxze.tw/gemlog/2023/09-17-hardware-accelerated-playback-on-pinetab2.gmi) · [wiki PINE64](https://wiki.pine64.org/wiki/Mainline_Hardware_Decoding)

**Chromium amont (lu dans `chromium/chromium` main, 30/09/2026)**
- `media/gpu/args.gni` [lu] — [args.gni](https://github.com/chromium/chromium/blob/main/media/gpu/args.gni) :
  - `use_v4l2_codec = false` par défaut (« used for all CrOS platforms ») ;
  - `use_vaapi = is_linux && !is_castos && (ozone_platform_x11 || ozone_platform_wayland) && (target_cpu == "x86" || "x64" || "arm64")` ;
  - `use_linux_video_acceleration = use_vaapi || use_v4l2_codec` ;
  - `use_av1_hw_decoder = is_chromeos || (is_linux && use_vaapi) || is_win || is_apple`.
- Commits correspondants [lu] — [historique args.gni](https://github.com/chromium/chromium/commits/main/media/gpu/args.gni) :
  - « Introduce use_linux_video_acceleration GN flag » (01/05/2025) ;
  - « media/gpu/v4l2: Allow enabling AV1 support on Linux » (rmader, 12/06/2025) ;
  - « media: Allow VA-API on arm64/aarch64. » (21/03/2026).
- L'issue « Improve V4L2 hardware decoding on Linux » (372630272) : l'AV1 est laissé « enabled by default for VA-API but disabling it for V4L2 » [lu] (extrait de recherche) — [crbug 372630272](https://issues.chromium.org/issues/372630272)
- Fonctionnalités de `media_switches.cc` [lu] — [media_switches.cc](https://github.com/chromium/chromium/blob/main/media/base/media_switches.cc) :
  - `kAcceleratedVideoDecodeLinux`, nom **"AcceleratedVideoDecoder"**, commentaire « Enable vaapi/v4l2 video decoding on linux. This is already enabled by default on chromeos, but needs an experiment on linux » ; active par défaut **seulement si `USE_VAAPI`**, sinon inactive ;
  - `kAcceleratedVideoDecodeLinuxGL` : active ;
  - `AcceleratedVideoEncoder` : inactive ;
  - `kPreferV4L2VideoAcceleration` : inactive.
- `gpu_mojo_media_client_linux.cc` [lu] — [gpu_mojo_media_client_linux.cc](https://github.com/chromium/chromium/blob/main/media/mojo/services/gpu_mojo_media_client_linux.cc) :
  - sans `AcceleratedVideoDecoder`, `kUnknown` (pas de décodage matériel) ;
  - V4L2 avec un contexte GL exige `AcceleratedVideoDecodeLinuxGL` ;
  - `kAcceleratedVideoDecodeLinuxZeroCopyGL` est active par défaut et rend le NV12 affichable directement si `supports_nv12_gl_native_pixmap` (« Importing NV12 and P010 buffers requires EGL_EXT_image_dma_buf_import. GLX can only import native pixmap of format AR24 »).
- Recherche des périphériques hors ChromeOS [lu] — [v4l2_device.cc](https://github.com/chromium/chromium/blob/main/media/gpu/v4l2/v4l2_device.cc) · [v4l2_utils.cc](https://github.com/chromium/chromium/blob/main/media/gpu/v4l2/v4l2_utils.cc) :
  - `/dev/video0` à `/dev/video255` (« On mainline Linux we need to check a much larger number of devices, mainly because the device pattern is shared with ISP devices ») ;
  - `/dev/media0` à `/dev/media9`, appariés par `bus_info` (« Some devices, namely the RK3399, have multiple hardware decoder blocks ») ;
  - `IsV4L2DecoderStateful()` choisit la voie « avec état » si le premier décodeur expose H.264, VP8 ou VP9 sous forme non « slice ».
- L'encodeur V4L2 (VEA) n'est compilé que pour ChromeOS (« Encoders use hack for passing offset within a DMA-buf, which is not supported upstream ») [lu] — [v4l2/BUILD.gn](https://github.com/chromium/chromium/blob/main/media/gpu/v4l2/BUILD.gn)
- Activité 2026 sur `media/gpu/v4l2` [lu] — [commits media/gpu/v4l2](https://github.com/chromium/chromium/commits/main/media/gpu/v4l2) :
  - John Cox (Raspberry Pi), septembre 2026 : « Fix V4L2 stateful decoder instance counting », « mt21_compressor: Make compile for arm on linux » ;
  - rmader (Collabora) : 19/05/2026 ;
  - amazingfate : 08/05/2026 ;
  - « Default to LINEAR modifier for non-tiled V4L2 formats » (22/06/2026) ;
  - « Map stateful HEVC to the HEVC profile control » (14/08/2026).
- Régression M153 (crbug 563075803) : en HEVC matériel sous Linux Wayland, une recherche dans la vidéo réaffiche des images d'avant le saut. La cause est dans le `H265Decoder` commun ; reproduit avec VA-API (Intel, Qualcomm) [lu] (extrait de recherche) — [crbug 563075803](https://issues.chromium.org/issues/563075803)

**Chromium de distribution**
- Debian, chronologie du miroir `bookworm` [lu] — [changelog](https://github.com/amazingfate/chromium-debian-build/blob/bookworm/debian/changelog) :
  - 105.0.5195.102-1 (05/09/2022) : « Enable v4l2 for arm platforms. This also disables VA-API on arm64 » ;
  - retiré en 107 (28/10/2022), remis en 109.0.5414.119-1 (25/01/2023) ;
  - `statelessV4L2.patch` porté de 115 à 116, puis « merged upstream » en 117 (13/09/2023).
- Debian 138.0.7204.49-1~deb12u1 [lu] — [rules](https://github.com/amazingfate/chromium-debian-build/blob/bookworm/debian/rules) · [default-flags Debian](https://github.com/amazingfate/chromium-debian-build/blob/bookworm/debian/etc/default-flags) :
  - arm64 compilé avec `use_v4l2_codec=true use_vaapi=false` ;
  - `default-flags` **n'ajoute pas** `AcceleratedVideoDecoder`.
- Branches `mainline-v4l2-130` à `-138` d'amazingfate (dernière en 07/2025) [lu] — [default-flags mainline-v4l2-138](https://github.com/amazingfate/chromium-debian-build/blob/mainline-v4l2-138/debian/etc/default-flags) · [correctif HEVC](https://github.com/amazingfate/chromium-debian-build/blob/mainline-v4l2-138/debian/patches/v4l2/0001-media-gpu-v4l2-Enable-HEVC-stateful-video-decoder-on.patch) :
  - même compilation que Debian, plus `--ozone-platform-hint=wayland` et `--enable-features=AcceleratedVideoDecoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL` ;
  - en 130 : correctifs « enable v4l2 av1 decoder for linux », « support multi v4l2 decoder devices », « revert implicit sync interop », « enable NV12 direct rendering » ;
  - en 138, il ne reste que « Enable HEVC stateful video decoder only for linux », transmis en amont (CL 6059495, 04/12/2024).
- **Mesuré sur RK3588 (Rock 5B+)**, dépôt mis à jour le 27/07/2026 [mesuré par la source, RK3588, amont 7.1 + correctifs] — [dongioia/rock5bplus-rkvdec2](https://github.com/dongioia/rock5bplus-rkvdec2) :
  - noyau amont 7.1, branche Collabora `rockchip-v7.1`, plus des correctifs hors arbre (VP9 VDPU381, NV15 10 bits) ;
  - Chromium **150.0.7871.46 d'origine d'Arch Linux ARM** (« HW decode compiled in ») ;
  - drapeaux `--enable-features=AcceleratedVideoDecoder,AcceleratedVideoDecodeLinuxGL --ignore-gpu-blocklist --enable-zero-copy` ;
  - « The older name `AcceleratedVideoDecodeLinuxV4L2` no longer exists… and is silently ignored » ; « HW decode also needs a **Wayland** session » ;
  - l'artefact vert en VP9 venait de l'intégration d'ANGLE livrée avec 150 (décalage du plan de chroma) ;
  - vérification dans `chrome://media-internals` : `kVideoDecoderName: V4L2VideoDecoder`, `kIsPlatformVideoDecoder: true` ;
  - pile graphique Mesa 26.1.3 / Panthor, `cma=512M`.
- Guide Armbian (RK3588, amont, Debian 13) : même drapeau `AcceleratedVideoDecoder`, ancien nom ignoré en 150, vérification par `chrome://media-internals` et `fuser /dev/video*`, et `cma=1G` pour le 4K@30 [mesuré par la source, RK3588] (extrait de recherche) — [Armbian forum, sujet 61497](https://forum.armbian.com/topic/61497-guide-system-wide-in-browser-hw-video-decode-on-rk3588-mainline-debian-13-trixie-%E2%80%94-and-the-4k30-cma-gotcha-nobody-warns-you-about/)
- Pour la Raspberry Pi 5, des correctifs pour Chromium 147 ajoutent le HEVC sans état via `rpi-hevc-dec`, sous Wayland et Mesa v3d, avec les modificateurs SAND128 [lu, ⚠️ TRANSPOSITION BCM2712] — [sslivins/chromium-rpi-hevc](https://github.com/sslivins/chromium-rpi-hevc)
- Google Chrome **arm64 Linux** est disponible depuis juillet 2026 (annonce du 12/03/2026) [lu] — [OMG! Ubuntu, 07/2026](https://www.omgubuntu.co.uk/2026/07/chrome-arm64-linux-available) · [9to5Google](https://9to5google.com/2026/03/12/chrome-arm64-linux/) · [CNX, 17/08/2026](https://www.cnx-software.com/2026/08/17/google-chrome-is-now-available-for-arm-linux-we-tested-it-on-a-raspberry-pi-5/)

**Ponts VA-API, et Firefox pour comparaison**
- `cajomar/libva-v4l2_request` [lu, RK3399/RK3588] — [cajomar/libva-v4l2_request](https://github.com/cajomar/libva-v4l2_request) :
  - codecs MPEG-2, H.264, HEVC, VP8, VP9, AV1 ; testé sur RK3399 (Pinebook Pro) et RK3588 (Orange Pi 5+) ;
  - « on RK3588 it's impossible to support HEVC decoding using VA-API… due to major, un-workaroundable API mismatch » ; « HEVC on decoders that require the full SPS reference picture set tables… is declined » ;
  - Firefox : son bac à sable RDD bloque l'accès aux périphériques.
- `defcom5-rockchip/rockchip-vaapi`, pont VA-API vers MPP sur noyau BSP [lu/mesuré par la source, RK3588] — [rockchip-vaapi](https://github.com/defcom5-rockchip/rockchip-vaapi) :
  - SoC testés : RK3588 et RK3588S ; RK3576 « likely » ; **RK3566/RK3568 non cités** ;
  - codecs : H.264, HEVC 8 et 10 bits, VP9 profils 0 et 2, VP8 ; AV1 « not implemented » ;
  - export DRM PRIME sans copie en NV12 ; Firefox 128+ ;
  - « Chromium on Pi Desktop: Uses `libv4l-rkmpp`, not this driver » ;
  - mesure : VP9 profil 2 en 4K60, « 97 → 1 dropped frames » en v2.2.0-rc1.
- Firefox (source main) décode via FFmpeg avec un « V4L2-DRM FFmpeg decoder » (codec matériel FFmpeg de type v4l2m2m, sortie `AV_PIX_FMT_DRM_PRIME`). Aucune voie « request » (sans état) n'y apparaît [lu] — [FFmpegVideoDecoder.cpp](https://github.com/mozilla-firefox/firefox/blob/main/dom/media/platforms/ffmpeg/FFmpegVideoDecoder.cpp)
- Firefox 116 a ouvert le V4L2-M2M pour le H.264 de la Raspberry Pi 4. Le bug 1969297 vise le HEVC « v4l2-stateless » de la Pi 5 [lu, ⚠️ TRANSPOSITION Broadcom] (extraits de recherche) — [OMG! Linux](https://www.omglinux.com/firefox-hardware-acceleration-raspberry-pi/) · [bug 1969297](https://bugzilla.mozilla.org/show_bug.cgi?id=1969297)

### Inferences
- **Box RK3566 du labo** (Armbian bookworm, BSP 6.1.141, pas de `/dev/video*`, Chromium Debian 151 en attente d'installation) [déduit] :
  - Si Debian compile encore 151 comme 138 (`use_v4l2_codec=true`, `use_vaapi=false`), ce Chromium cherche `/dev/videoN` et `/dev/mediaN`. Il n'en trouvera **aucun** : **aucune accélération possible**, quels que soient les drapeaux.
  - Il ne sait pas charger libv4l-rkmpp (ni `use_v4lplugin`, ni noms `/dev/video-dec`).
  - Compilé sans VA-API, il ne peut pas non plus passer par rockchip-vaapi.
- **Deux issues réalistes pour la RK3566** [déduit] :
  - **(a) Rester en BSP** et compiler un Chromium corrigé Rockchip (148 à 152) avec libv4l-rkmpp : H.264, HEVC et VP9 8 bits jusqu'à 4K, sans AV1 ni 10 bits.
  - **(b) Passer au noyau edge d'Armbian** (6.18 / 7.x), avec le DT RK356x qui pilote le VDPU346 en `rk3588-vdec` : H.264 et HEVC par rkvdec, VP8 et MPEG-2 par hantro, **pas de VP9** (le code vdpu381 amont ne l'a pas), pas d'AV1. On utilise alors Chromium Debian ou xtradeb avec `--enable-features=AcceleratedVideoDecoder`, et Wayland conseillé.
- En (b), c'est un DT non amont, et les relecteurs de la série VDPU346 ont justement discuté des différences de registres et de tailles de tampons entre VDPU346 et VDPU381. Ce pilotage approximatif peut rater certains flux [déduit].
- **Google Chrome arm64** : compilé depuis mars 2026, il a VA-API par défaut, donc `AcceleratedVideoDecoder` actif d'office. Sur un noyau BSP, un pont VA-API vers MPP (rockchip-vaapi) pourrait lui donner du décodage matériel. **Personne ne l'a vérifié sur RK3566** [déduit].
- **YouTube** : faute de VP9 en (b), YouTube servira du VP9 ou de l'AV1, donc en logiciel, sauf à forcer le H.264 (extensions du type « h264ify »). En (a), le VP9 8 bits est matériel [déduit].
- Le Chromium 150 d'Arch Linux ARM décode l'**AV1** par `V4L2VideoDecoder` sur RK3588 (dongioia). Or `use_av1_hw_decoder` n'est vrai sous Linux que si `use_vaapi` l'est. Ce build compile donc probablement **VA-API et V4L2 ensemble**, ce que permet `use_linux_video_acceleration` depuis 05/2025 ; ou bien il porte un correctif. À l'inverse, un build « V4L2 seul » comme celui de Debian (`use_vaapi=false`) n'a pas le délégué AV1 V4L2 [déduit du code d'`args.gni` et de `v4l2/BUILD.gn`].

### Gaps
- La série VDPU346 est-elle dans linux-next, ou prévue pour 7.4 ? Non vérifiable : git.kernel.org et lore sont bloqués.
- Réglages de compilation du Chromium Debian **151** sur arm64 : le miroir s'arrête à 138 (salsa.debian.org est bloqué).
- Build de Google Chrome arm64 : `use_vaapi` vaut-il vraiment true, `use_v4l2_codec` est-il présent ? Non vérifié.
- Réglages de compilation du Chromium d'Arch Linux ARM (`use_vaapi` et `use_v4l2_codec` ensemble ?), et règle d'arbitrage entre VA-API et V4L2 quand les deux sont compilés : je n'ai trouvé que l'existence de `kPreferV4L2VideoAcceleration` (inactive par défaut), pas la fonction `ActiveLinuxVideoDecoderType()`.
- Aucun chiffre de cadence ni d'images perdues pour la voie amont sur RK3566/RK3568. Seul « 4K H.264 marche » (Orange Pi 3B, 6.9) et l'essai 1080p/2160p sur Rock 3A existent, sans mesure.
- Extrait de recherche **non vérifié**, provenance introuvable : « rkvdec2 does not support VIDIOC_EXPBUF… decoded frames never reach the compositor ». Je ne l'ai retrouvé ni dans `cajomar/libva-v4l2_request` ni dans l'issue #7 d'`iconidentify`. Ne pas le citer comme fait.
- État du bug Firefox 1969297 (version de sortie) : inconnu.

## 4. Une fois décodée, la vidéo peut-elle aller sur un plan matériel (overlay) dans une configuration Linux de Chromium, ou est-elle toujours composée par le GPU ? Chiffres d'images perdues

### Takeaway
Sous Linux, l'image décodée (dmabuf NV12) est **importée comme texture EGL et composée par le GPU**. En **X11, jamais d'overlay** (le code installe un processeur d'overlay factice). En **Wayland**, une seule porte : `--enable-features=WaylandOverlayDelegation`, **désactivée par défaut**. Elle exige un compositeur qui offre single-pixel-buffer et `wp_viewporter`, et qui **n'offre pas** fractional-scale-v1. La vidéo part alors en `wl_subsurface`, et c'est **le compositeur** qui décide du plan KMS. **ChromeOS (Ozone/DRM)** utilise, lui, les plans matériels. Aucune source ne montre une vidéo Chromium sur un plan matériel avec une RK356x sous Linux.

### Cited Findings
- `overlay_processor_interface.cc` : « In tests and Ozone/X11, we do not expect a buffer queue for the root render pass », d'où `OverlayProcessorStub`, un processeur d'overlay factice [lu, Chromium main] — [overlay_processor_interface.cc](https://github.com/chromium/chromium/blob/main/components/viz/service/display/overlay_processor_interface.cc)
- `ui/ozone/common/features.cc` : `BASE_FEATURE(kWaylandOverlayDelegation, base::FEATURE_DISABLED_BY_DEFAULT)` — « Overlay delegation is required for delegated compositing. This doesn't enable delegated compositing, but rather allows usage of subsurfaces for delegation » [lu] — [features.cc](https://github.com/chromium/chromium/blob/main/ui/ozone/common/features.cc)
- `WaylandConnection::ShouldUseOverlayDelegation()` : fonctionnalité active **et** absence de `fractional_scale_manager_v1()` **et** présence de `single_pixel_buffer()`. Commentaires : « …isn't present on any non-exo Wayland compositors », « Even though only video overlays can be supported on Linux… » [lu] — [wayland_connection.cc](https://github.com/chromium/chromium/blob/main/ui/ozone/platform/wayland/host/wayland_connection.cc)
- Côté plateforme, `supports_overlays = ShouldUseOverlayDelegation() && viewporter()` [lu] — [ozone_platform_wayland.cc](https://github.com/chromium/chromium/blob/main/ui/ozone/platform/wayland/ozone_platform_wayland.cc)
- Si `supports_overlays` est vrai, les stratégies d'overlay par défaut sont `kFullscreen`, `kSingleOnTop` et `kUnderlay`. Sinon, `--enable-hardware-overlays=…` les impose [lu] — [renderer_settings_creation.cc](https://github.com/chromium/chromium/blob/main/components/viz/host/renderer_settings_creation.cc)
- FOSDEM 2024 : la composition déléguée (« each quad/overlay is represented by its own wl_subsurface ») n'est active que sur LaCrOS/exo, car « Linux doesn't support many protocols that are required ». Un dmabuf peut servir d'« HW overlay when it's attached to wl_surface/wl_subsurface » [lu] (extrait de recherche) — [FOSDEM 2024, Delegated Compositing](https://archive.fosdem.org/2024/events/attachments/fosdem-2024-3177-delegated-compositing-utilizing-wayland-protocols-for-chromium-on-chromeos/slides/22799/Delegated_Compositing_b3OqHfM.pdf)
- Un CL « ozone/wayland: disable WaylandOverlayDelegation on Linux » existe (date non lisible) [lu] (extrait de recherche) — [ozone-reviews](https://groups.google.com/a/chromium.org/g/ozone-reviews/c/-3IYmgHuW1A)
- `build/config/ozone.gni` : Linux compile `x11` et `wayland` ; `ozone_platform_drm = true` seulement pour ChromeOS. La plateforme DRM possède un `DrmOverlayManagerGpu` [lu] — [ozone.gni](https://github.com/chromium/chromium/blob/main/build/config/ozone.gni) · [ozone_platform_drm.cc](https://github.com/chromium/chromium/blob/main/ui/ozone/platform/drm/ozone_platform_drm.cc)
- Chemin d'une image décodée sous Linux [lu] — [gpu_mojo_media_client_linux.cc](https://github.com/chromium/chromium/blob/main/media/mojo/services/gpu_mojo_media_client_linux.cc) · [gpu_init.cc](https://github.com/chromium/chromium/blob/main/gpu/ipc/service/gpu_init.cc) :
  - `VideoDecoderPipeline`, puis `MailboxVideoFrameConverter` (SharedImage) ;
  - NV12 sans copie si `CanImportNativePixmap(kNV12)` ;
  - sinon un processeur d'image (libyuv) convertit en AR24, comme l'a constaté l'issue #18 [lu] — [issue #18](https://github.com/JeffyCN/libv4l-rkmpp/issues/18).
- Le Chromium Rockchip 152 n'active pas la délégation d'overlay : ses drapeaux se limitent à `AcceleratedVideoEncoder,AcceleratedVideoDecoder`, plus l'IME Wayland [lu] — [chromium-%.bbappend](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium-%25.bbappend) · [ozone-wayland bbappend](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium-ozone-wayland_%25.bbappend)
- **Chiffres disponibles** (tous ⚠️ TRANSPOSITION RK3588) :
  - Firefox + rockchip-vaapi, VP9 profil 2 en 4K60 : « 97 → 1 dropped frames » ; blit RGA HDR 4K « about 3.8 ms on one RGA3 core » [mesuré par la source, RK3588, BSP] — [rockchip-vaapi](https://github.com/defcom5-rockchip/rockchip-vaapi) ;
  - revues de cartes RK3588 : Orange Pi 5 Plus en fenêtre, « near perfect playback with only a few dropped frames » ; Mixtile Blade 3 en 4K, quelques pertes au départ puis « near perfect ». Build Chromium non précisé [mesuré par la source, RK3588] (extraits de recherche) — [the-diy-life, Orange Pi 5 Plus](https://the-diy-life.com/orange-pi-5-plus-test-review/) · [the-diy-life, Blade 3](https://the-diy-life.com/mixtile-blade-3-test-review/) ;
  - Rock 5B+, amont, Chromium 150 : « clean picture » en VP9, H.264, HEVC et AV1, sans compte d'images [mesuré par la source, RK3588] — [dongioia](https://github.com/dongioia/rock5bplus-rkvdec2).

### Inferences
- **Box RK3566** [déduit] : quelle que soit la voie de décodage (rkmpp ou amont), sans délégation d'overlay chaque image vidéo est composée par la Mali-G52 dans la surface de Chromium, en X11 comme en Wayland. C'est exactement le schéma mesuré sous Android : WebView et Cromite plafonnaient à ~27 fps en 60p parce que la page est composée par le GPU. Il faut donc s'attendre au **même plafond sous Linux** tant que la vidéo ne sort pas vers un plan.
- **Seule piste Linux pour un plan matériel** [déduit] : Chromium Ozone/Wayland + `--enable-features=WaylandOverlayDelegation`, avec un compositeur qui :
  - (1) offre `wp_single_pixel_buffer_manager_v1` et `wp_viewporter` ;
  - (2) n'offre **pas** `wp_fractional_scale_manager_v1` ;
  - (3) promeut un `wl_subsurface` dmabuf NV12 vers un plan VOP2.

  Weston (backend DRM) sait affecter des vues dmabuf aux plans. Les compositeurs wlroots (cage, labwc, sway) exposent souvent fractional-scale, ce qui **désactive** la délégation côté Chromium.
- À valider sur la carte, dans l'ordre [déduit] :
  - que les plans Esmart ou Smart du VOP2 de la RK3566 acceptent le NV12 linéaire ;
  - que le tampon du décodeur n'est pas en AFBC, puisque Rockchip force aussi « disabling modifiers » ;
  - que la page ne recouvre pas la vidéo, sinon Chromium passe en « underlay », ce qui exige la transparence du plan principal.
- Poser `--enable-hardware-overlays=single-fullscreen,single-on-top,underlay` sans que la plateforme déclare `supports_overlays` ne servira à rien en X11 (processeur factice) [déduit du code].

### Gaps
- Aucune source n'a mesuré ni montré une vidéo Chromium passée par `WaylandOverlayDelegation` vers un plan KMS sur Rockchip, ni ailleurs hors ChromeOS/LaCrOS.
- Weston (versions 13/14, ou fork Rockchip `JeffyCN/weston`) offre-t-il single-pixel-buffer, et **pas** fractional-scale ? Non vérifié : le budget de recherche était épuisé et wayland.freedesktop.org est bloqué.
- Aucun chiffre d'images perdues publié pour Chromium sur RK3566 ou RK3568 sous Linux, en 1080p60 comme en 4K60, avec l'une ou l'autre voie.
- Les chiffres « RK3588 » ne transposent pas : GPU G610 contre G52, décodeur VDPU381 contre VDPU346, bande passante mémoire différente.

## 5. Quelles API web profitent du décodage matériel dans ces builds (<video> MP4, MSE/HLS.js, WebCodecs VideoDecoder, WebRTC) ?

### Takeaway
Dans Chromium Linux, `<video>`, MSE (donc HLS.js), WebCodecs et WebRTC passent tous par le **même** décodeur de plateforme (`VideoDecoderPipeline` sur V4L2 ou VA-API). Un build qui décode en matériel pour `<video>` le fait donc aussi, en principe, pour les trois autres, à deux nuances près : WebRTC repasse en logiciel sous 320×240 quand il y a beaucoup d'instances, et l'encodage V4L2 n'existe en amont que sous ChromeOS. Aucune mesure propre à RK356x n'a été trouvée.

### Cited Findings
- Tout décodeur de plateforme Linux (`kVaapi`, `kV4L2`) est construit comme `VideoDecoderPipeline` avec `PlatformVideoFramePool` et `MailboxVideoFrameConverter`, dans le processus GPU, via `GpuMojoMediaClient` [lu, Chromium main] — [gpu_mojo_media_client_linux.cc](https://github.com/chromium/chromium/blob/main/media/mojo/services/gpu_mojo_media_client_linux.cc)
- WebCodecs `VideoDecoder` : `hardwareAcceleration` se traduit en `HardwarePreference`. En `kPreferHardware`, il vérifie « asynchronously… for a hardware decoder » via les GPU factories et rapporte `decoder.IsPlatformDecoder()` [lu] — [webcodecs/video_decoder.cc](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/modules/webcodecs/video_decoder.cc)
- WebRTC `RTCVideoDecoderAdapter` : `kMinResolution {320, 240}` hors ChromeOS (`{2, 2}` sous ChromeOS). En dessous, « We fall back to a software decoder if there are many instances » [lu] — [rtc_video_decoder_adapter.h](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/platform/peerconnection/rtc_video_decoder_adapter.h) · [rtc_video_decoder_adapter.cc](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/platform/peerconnection/rtc_video_decoder_adapter.cc)
- L'encodeur V4L2 (VEA) est réservé à ChromeOS en amont [lu] — [v4l2/BUILD.gn](https://github.com/chromium/chromium/blob/main/media/gpu/v4l2/BUILD.gn). Les builds Rockchip l'activent : correctif « HACK: media/gpu/v4l2: Enable V4L2 VEA » et `--enable-features=AcceleratedVideoEncoder` [lu] — [chromium-%.bbappend](https://github.com/JeffyCN/meta-rockchip/blob/master/dynamic-layers/recipes-browser/chromium/chromium-%25.bbappend)
- Pour vérifier le décodage réel, lire `chrome://media-internals` (`kVideoDecoderName: V4L2VideoDecoder`, `kIsPlatformVideoDecoder: true`) et non chrome://gpu [lu, RK3588] — [dongioia](https://github.com/dongioia/rock5bplus-rkvdec2)
- La PPA d'amazingfate fournit `libwidevinecdm0` et un correctif « enable widevine on arm64 linux platform » [lu] — [configng #887](https://github.com/armbian/configng/pull/887) · [séries mainline-v4l2-130](https://github.com/amazingfate/chromium-debian-build/blob/mainline-v4l2-130/debian/patches/series)

### Inferences
- `<video>` MP4, MSE et HLS.js (qui repose sur MSE) empruntent le même `MojoVideoDecoder` que le pipeline média. Si `media-internals` montre `V4L2VideoDecoder` pour un MP4, il en ira de même pour HLS.js, à codec et profil égaux [déduit].
- WebCodecs : avec `hardwareAcceleration: "prefer-hardware"`, `isConfigSupported()` échouera pour AV1 sur RK3566 ; il n'y a pas d'AV1 matériel, et en voie V4L2 amont hors VA-API le délégué AV1 n'est même pas compilé [déduit].
- Surcoût caché : même avec WebCodecs, dessiner le `VideoFrame` dans un canvas ou un WebGL passe par le GPU. La question 4 s'applique donc aussi [déduit].

### Gaps
- Aucune mesure publiée de WebCodecs ou de WebRTC en décodage matériel sur RK3566, RK3568 ou RK3588 avec ces builds.
- Comportement du décodage chiffré (Widevine L3 sur Linux arm64) sur ce chemin : non vérifié.

## 6. GStreamer (mppvideodec, V4L2) pour les moteurs alternatifs (WPE WebKit) — bref

### Takeaway
Un moteur WebKit/WPE s'appuie sur GStreamer, qui a les deux voies. En BSP, `mppvideodec` de `gstreamer-rockchip` ; son miroir Rockchip bouge encore en 2026. En amont, les éléments V4L2 sans état de GStreamer. C'est la voie historiquement la plus directe sur RK3566, mais je n'ai trouvé aucune source qui l'associe à WPE sur cette puce.

### Cited Findings
- La PPA publie `gstreamer1.0-rockchip` 1.14-4+git240423 (14/05/2024) et `ffmpeg` 6.1.1 avec rkmpp [lu] — [PPA rockchip-multimedia](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia)
- La branche `gstreamer-rockchip` du miroir JeffyCN est mise à jour le 26/08/2026 [lu] — [branches JeffyCN/mirrors](https://github.com/JeffyCN/mirrors/branches/all)
- ⚠️ ANCIEN (2023), RK3566 : le H.264 matériel passait par GStreamer compilé soi-même, ou par Clapper et µPlayer, à l'époque du seul hantro en amont [lu] (extrait de recherche) — [clehaxze.tw, 17/09/2023](https://clehaxze.tw/gemlog/2023/09-17-hardware-accelerated-playback-on-pinetab2.gmi)

### Inferences
- WPE WebKit sur BSP RK3566 (MPP) ou sur amont (v4l2sl*) hériterait du décodage matériel de GStreamer. La question de la composition GPU s'y pose différemment : un « video sink » ou un « hole-punch » peut viser un plan dédié. C'est à confirmer par le chercheur chargé de WPE [déduit].

### Gaps
- Aucune source consultée sur WPE et Rockchip (hole-punch, waylandsink ou kmssink sur VOP2). Le budget de recherche était épuisé.
