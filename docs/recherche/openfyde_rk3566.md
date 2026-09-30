# openFyde / FydeOS sur RK3566 (Mali-G52 MP2 Bifrost, VOP2, rkvdec2) — état au 30/09/2026

> Recherche **web uniquement** (aucune mesure sur box, aucun test, aucun SSH), 30/09/2026.
> Balises : **[mesuré par la source]** = la source dit avoir mesuré/testé · **[lu]** = lu dans un
> dépôt, un listing ou une annonce · **[déduit]** = mon inférence, à vérifier.
>
> ⚠️ **Hôtes refusés par le proxy (HTTP 403 « not in allowlist ») — non contournés, extraits de
> moteur de recherche utilisés à la place** : `community.fydeos.com`, `community.fydeos.io`,
> `fydeos.io`, `forum.radxa.com`, `docs.radxa.com`, `wiki.fydetabduo.com`, `wiki.xpressreal.io`,
> `www.cnx-software.com`, `lkml.org`, `lkml.iu.edu`, `ratatoskr.run`,
> `chromium.googlesource.com`. **Tout ce qui vient de ces hôtes n'est connu que par un extrait de
> recherche** — traiter comme [lu, de seconde main].
>
> ⚠️ **Piège de dates rencontré** : l'outil de lecture de GitHub a rendu les dates des *releases*
> openFyde **avec un an de retard** (ex. « r144 — 18 mars 2025 » alors que Chromium 144 n'existe
> qu'en janvier 2026, et que la recherche donne « R144 released on March 18, 2026 »). Les dates de
> release ci-dessous sont donc **corrigées d'un an [déduit]**, recoupées par : les numéros de
> Chromium, le journal de commits (« update to r132-dev » le 06/06/2025) et le lancement de
> l'XpressReal T3 (août 2025). Les dates de *commits* et de *mise à jour de dépôt* ne sont pas
> concernées.

---

## Verdict court

- **Aucune image OFFICIELLE openFyde/FydeOS pour RK3566/RK3568** — ni overlay dans l'organisation
  GitHub `openFyde` (28 dépôts `overlay-*` listés, aucun rk356x), ni ticket « rk3566 » dans
  `openFyde/issues` [lu, 30/09/2026].
- **Il existe UNE image COMMUNAUTAIRE rk356x en r120** (ROCK 3 A/B/B+/C, ZERO 3W/3E, + RK3528A),
  postée sur le forum FydeOS chinois, binaires sur Baidu Pan, **Android et Crostini hors service**,
  2 Go minimum « avec saccades », 4 Go recommandés [lu, extrait de recherche — page elle-même
  bloquée]. Date du post inconnue ; r120 ⇒ vraisemblablement 2024 [déduit].
- **Tout le RK3588 openFyde est bâti sur le noyau BSP Rockchip (5.10, puis 6.1) + libmali Valhall
  propriétaire + MPP via plugin libv4l** [lu, listings de dépôts]. Porter ça au RK3566 = changer de
  libmali (Bifrost G52), de DTB/U-Boot, de table de codecs MPP ; le reste de la pile est la même
  famille de BSP [déduit].
- **Indice le plus encourageant** : ChromeOS **officiel** tourne sur le **même GPU** (Mali-G52
  2EE MC2) dans les Chromebooks MediaTek MT8186 « Corsola » [lu]. Le GPU n'est donc pas
  disqualifiant pour la pile ChromeOS en soi [déduit].

---

## 1. Overlays / images openFyde-FydeOS pour RK3566 / RK3568

| Cible | Nature | Version | Date | Source |
|---|---|---|---|---|
| ROCK 3A/3B/3B+/3C, ZERO 3W/3E (RK3566/RK3568) + RK3528A | **Communautaire**, binaires Baidu Pan + MD5 | openFyde **r120** | inconnue (post du forum) | https://community.fydeos.com/t/topic/46279 [lu, extrait de recherche — hôte bloqué] |
| Orange Pi 3B, Quartz64, Firefly ROC-RK3566/3568, box TV | **Rien trouvé** | — | — | recherches EN/ZH, 30/09/2026 |

Détails du post communautaire (extraits de recherche uniquement, 30/09/2026) :
- « openFyde a déjà des adaptations RK3399 et RK3588 ; RK3568 et RK3528A sont *relativement
  faciles à adapter*, avec une performance qui supporte Chrome » [lu].
- Problèmes connus : **curseur souris invisible au démarrage** (réglage à changer), **Terminal /
  Penguin (Crostini) indisponible**, **Android indisponible** [lu].
- RAM : **2 Go minimum avec saccades occasionnelles, 4 Go recommandés** ; support TF (Samsung EVO
  128 G conseillée) ou eMMC [lu].
- **Rien dans les extraits sur le GPU (libmali Bifrost ou Panfrost), le décodage matériel, ni sur
  un dépôt source.** Sans overlay publié, l'image n'est pas reconstructible ni auditable [déduit].
  🔴 **À lire en entier depuis un poste qui atteint `community.fydeos.com` avant toute décision.**

Recherches négatives (même jour) :
- `github.com/openFyde/issues/issues?q=rk3566` ⇒ **0 résultat** [lu].
- La seule issue remontée sur « rk3568 OR rock 3 OR rk3399 OR new board » est #3 « openfyde
  doesn't boot on orangepi 5 », close le 02/04/2026 [lu].
- Liste complète des overlays de l'org (https://github.com/orgs/openFyde/repositories?q=overlay,
  lue le 30/09/2026) : amd64 (×5 variantes), arm64 vmware, rpi4, rpi5, cutiepi, **rock5b,
  orangepi5, edge2, fydetab_duo, inaugural** (RK3588/RK3588S), **xpressreal** (Realtek
  RTD1619B), **rock4cp, rockpi4b** (RK3399), **firefly_itx3588j, firefly_rk3588spc** (RK3588).
  **Aucun RK356x, aucun RK3576** [lu].
- Radxa CM4-Nano : c'est une **carte porteuse** pour le **CM5 (RK3588S)**, pas un module RK3566 ;
  le projet « Make your own FydeOS board » tourne FydeOS v18 pour RK3588S
  (https://community.fydeos.io/t/topic/29828, extrait de recherche) [lu].

## 2. Les overlays RK3588 — ce qu'ils embarquent vraiment

### 2.1 Structure
- `overlay-rock5b-openfyde` (branche `main`, dernier push 18/03/2026) a pour parent
  **`inaugural-openfyde:base`** (fichier `profiles/base/parent`, lu en brut) [lu].
- Les paquets SoC sont dans `openFyde/foundation-rk3588` (branche `r120-dev`, dernier commit
  23/07/2024, 168 commits) : `baseboard-inaugural/`, `chipset-rk3588/`, `rk3588-image-maker/` [lu].
  https://github.com/openFyde/foundation-rk3588
- `overlay-inaugural` (maj 17/09/2026) = « notre première carte RK3588 conçue en interne » ;
  kconfigs `rk3588-5_10-def-r1` seulement [lu]. (Une première réponse de l'outil y voyait du
  rk3566/rk3576 : **faux**, démenti par le listing — hallucination d'outil, écartée.)

### 2.2 Noyau
- `chipset-rk3588/sys-kernel/chromeos-kernel-5_10` : ebuilds **5.10.160**, 5.10.160-r6,
  **5.10.198**, 9999 ⇒ **noyau BSP Rockchip 5.10** [lu].
- `overlay-rock5b-openfyde/kconfigs/` : `rock5b-5_10-def-r1`, `-r2`, **`rock5b-6_1-def-r1`** ;
  commit du 30/09/2025 « enable VHOST_VSOCK for kconfig/rock5b-6_1 » ⇒ les releases récentes
  (r138/r144) sont sur **BSP 6.1** [lu + déduit].
- **Aucun noyau mainline** dans ce qu'on a pu lister [lu].

### 2.3 GPU
- `chipset-rk3588/media-libs/` contient **`mali-drivers-valhall-bin`** (libmali propriétaire G610)
  et **`minigbm`** [lu].
- **Aucune trace de Panthor/Mesa** dans openFyde (recherche « openFyde panthor/panfrost » : ne
  renvoie que BredOS/Armbian sur FydeTab Duo) [lu, recherche négative 30/09/2026].

### 2.4 Décodage vidéo
- `media-libs/` contient **`rockchip-mpp`**, **`libv4l`**, **`libv4lplugins`** ;
  `chromeos-base/arc-codec-chipset-rk3588` pour Android [lu].
- ⇒ Chemin = **Chromium V4L2 (stateful) → libv4l plugin → MPP**, c.-à-d. le schéma
  `libv4l-rkmpp` de Jeffy Chen (Rockchip) [déduit du nom des paquets ; l'ebuild n'a pas pu être lu,
  404 en brut]. libv4l-rkmpp : « a lot of chromium related hacks », décodeur seulement,
  MMAP/USERPTR, testé sur EVB RK3588 [lu] https://github.com/JeffyCN/libv4l-rkmpp
- Notes de release rock5b : « AV1/HEVC hardware decoding », Widevine, OTA locale, overlays DT
  utilisateur [lu].
- **Plans matériels (overlays Ozone DRM) : AUCUNE information trouvée.** ChromeOS utilise Ozone/DRM
  avec promotion d'overlays quand minigbm + le pilote KMS le permettent, mais rien ne dit si
  openFyde RK3588 promeut la vidéo sur un plan VOP2 [déduit / non vérifié]. **Question ouverte.**

### 2.5 Versions publiées (rock5b) — années corrigées [déduit]
| Tag | Date | Chromium | Plateforme |
|---|---|---|---|
| r144 | 18/03/**2026** | 144.0.7559.* | 16503.20.22.* |
| r138-r1 | 28/11/**2025** (+ Rock 5B+ / 5T) | 138.0.7204.* | 16295.91.20.* |
| r138 | 16/10/**2025** | 138.0.7204.* | 16295.91.20.* |
| r132 | 16/06/**2025** | 132.0.6834.* | 16093.91.20.* |
| r126 | ~01/2025 | 126.0.6478.* | 15886.67.19.* |
| r120 | ~05/2024 | 120.0.6099.* | 15662.71.18.* |
https://github.com/openFyde/overlay-rock5b-openfyde/releases [lu]

### 2.6 Ce qui changerait pour un RK3566 / G52 [déduit]
1. **GPU** : `mali-drivers-valhall-bin` → un libmali **Bifrost G52** (`g52-g13p0` ou équivalent BSP)
   compatible avec le kbase du noyau choisi. ChromeOS a déjà un paquet `mali-drivers-bifrost`
   pour les MediaTek (MT8183 G72, MT8186 G52) [mémoire, non revérifié ce jour]. Alternative :
   Panfrost (Mesa gère Midgard **et Bifrost**, https://docs.mesa3d.org/drivers/panfrost.html [lu])
   — mais ce serait une pile qu'openFyde ne pratique pas.
2. **Décodage** : MPP connaît le rkvdec2 RK3566 (BSP) ; il faut la table de capacités du plugin
   libv4l (H.264/HEVC/VP9 jusqu'à 4K, **pas d'AV1**). En mainline, le VDPU346 (RK356x) n'est
   **pas encore fusionné** : série v3 de Christian Hewitt (01/2026), et Armbian le porte encore en
   **patch** sur 6.12/6.18/7.1/7.2 en août 2026 (https://github.com/armbian/build/pull/10455, lu).
   Le VDPU381/383 (RK3588/RK3576) est, lui, en mainline depuis la fenêtre 7.0 (Collabora, 02/2026,
   https://www.collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html) [lu].
3. **Affichage** : VOP2 est le même bloc sur RK3566 et RK3588 (moins de VP et de plans sur 3566)
   ⇒ le pilote DRM BSP est commun [déduit].
4. **DTB / U-Boot / image-maker** : à refaire (le post rk356x prouve que c'est faisable).
5. **RAM** : 2 Go = limite basse annoncée par le porteur communautaire.

## 3. Effort de portage

### Exigences de build (guide officiel)
https://github.com/openFyde/getting-started [lu, 30/09/2026 ; le guide cite R102 — il n'a pas été
réécrit pour r144] :
- hôte x86_64, 4+ cœurs, **≥ 16 Go RAM + swap**, **≥ 150 Go libres (200 Go conseillés)**,
  **> 30 Go de téléchargement** ;
- durée **5-6 h** sur une machine 4 cœurs / 16 Go / HDD, **44 min** sur Threadripper 128 Go
  [mesuré par la source] ;
- `repo init` du manifest ChromiumOS + manifest openFyde en `local_manifests`, `setup_board`,
  `build_packages`, `build_image`. Pour une nouvelle carte : « create your own board overlay »,
  en partant d'un overlay existant — **pas de guide de portage détaillé** [lu].
- Guides tiers (bloqués ici) : `wiki.fydetabduo.com/Available-OS/openFyde/openfyde-build/`,
  `wiki.xpressreal.io/guides/building-openfyde/`, vidéo Bilibili « openfyde for orange pi 5 固件构建教程 »
  https://www.bilibili.com/video/BV1qVymY1EsQ/ [lu, titres seulement].
- Ports non officiels déjà faits par *remplacement de DTB* : l'image Rock 5B tourne sur Rock 5A en
  remplaçant `rk3588-rock-5b.dtb` par `rk3588s-rock-5a.dtb` (forum Radxa, extrait) [lu]. ⇒ entre
  cartes du **même SoC**, le portage peut se réduire au DTB ; **entre SoC, non** (GPU, codecs,
  bootloader) [déduit].

### Précédents et leur sort
| Port | SoC | Dernière version | Date | Sort |
|---|---|---|---|---|
| openFyde `rock4cp` (Rock 4C+) | RK3399 | r96 (Chromium 96.0.4664.208) | dépôt maj 15/11/2022 | **abandonné** [lu] |
| openFyde `rockpi4b` | RK3399 | ? | dépôt maj 06/09/2022 | **abandonné** [lu] |
| openFyde Firefly ITX-3588J / ROC-RK3588S-PC | RK3588 | ? | maj 10/2022 et 08/2022 | **abandonnés** [lu] |
| ayufan `chromiumos-build` (RockPro64, Pinebook Pro) | RK3399 | **R77** (noyau 4.4.190) | 01/09/2019 | **abandonné**, « not ready for production » [lu] https://github.com/ayufan-rock64/chromiumos-build/releases |
| openFyde `xpressreal` (XpressReal T3) | **Realtek RTD1619B**, 4×A55 + **Mali-G57 MP1** | r144 | ~03/2026 | **vivant** — carte co-conçue par Fyde [lu] |
| openFyde rock5b / orangepi5 / edge2 / fydetab_duo | RK3588(S) | r144 | 18/03/2026 | **vivants** [lu] |

⭐ Lecture : **les ports survivent quand Fyde vend ou co-conçoit la carte** (FydeTab Duo, inaugural,
XpressReal) ou quand la carte est très populaire (Rock 5B, OPi5) ; les ports RK3399 ont été lâchés
au bout de ~1 an [déduit]. Un port RK3566 communautaire resterait **gelé à sa version** (r120),
c'est-à-dire aujourd'hui **24 versions de Chromium en retard** (120 vs 144) [déduit].

⭐ **XpressReal T3 est le plus proche analogue officiel d'une box RK3566** : 4×Cortex-A55 et un
petit GPU Mali (G57 **MP1**, Valhall) — et Fyde le juge assez puissant pour openFyde r144
(https://www.hackster.io/news/fydeos-developers-unveil-the-xpressreal-t3-a-radxa-zero-spin-off-designed-for-openfyde-e8f5365287b6,
annonce 08/2025) [lu]. ⚠️ Son décodeur vidéo est Realtek, pas rkvdec : il ne dit rien de notre
chemin vidéo [déduit].

## 4. Autres systèmes « à la ChromiumOS » sur RK3566

- **ChromeOS Flex** : **x86 uniquement** (Intel/AMD), pas d'ARM annoncé [lu, 2026]
  https://support.google.com/chromeosflex/answer/11513094
- **ChromeOS officiel sur Mali-G52 MC2** : Chromebooks MT8186 « Corsola » (Asus CM14, Lenovo
  300e Gen 4, Acer 311…) [lu] https://lava.pages.collabora.com/docs/boards/chromebooks/boards/corsola/
  — pas installable sur une box Rockchip, mais preuve que ChromeOS + G52 MC2 est une combinaison
  produite par Google [déduit].
- **Lacros** : abandonné par Google (2024) [mémoire, non revérifié ce jour] — sans objet.
- **Aluminium OS** (fusion Android/ChromeOS) : page Wikipédia existante, rien d'installable sur
  une box tierce [lu, titre seulement].
- **Google Chrome ARM64 Linux** : paquets .deb/.rpm officiels arrivés **en juillet 2026**, Widevine
  inclus (https://www.omgubuntu.co.uk/2026/07/chrome-arm64-linux-available) [lu]. Utilisable sur
  une Debian/Armbian RK3566 — c'est du Chrome Linux (Wayland/X11), pas du ChromeOS.
- **Chromium mainline + V4L2 stateless** : preuve récente sur **Rock 5B+ (RK3588)** —
  Linux 7.1/7.2-rc5, Panthor, **Chromium 150 stock** ArchLinuxARM,
  `--enable-features=AcceleratedVideoDecoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL`,
  **Wayland obligatoire** (X11 : pas de VPU) ; `AcceleratedVideoDecodeLinuxV4L2` **n'existe plus
  en Chromium 150** (ignoré en silence) ; bug VP9 vert sur Mali corrigé dans le roll ANGLE de
  Chromium 150 [mesuré par la source, dépôt maj 27/07/2026]
  https://github.com/dongioia/rock5bplus-rkvdec2
  ⇒ Transposable au RK3566 **seulement quand le VDPU346 sera en mainline** (ou avec le patch
  Armbian) et avec **Panfrost** (Bifrost) au lieu de Panthor [déduit].
- **Chromium `--ozone-platform=drm` hors ChromeOS** : possible à la compilation
  (`use_ozone`, `ozone_platform="drm"`), documenté par Google comme « Running ChromeOS UI on
  Linux » — c.-à-d. un outil de développeur, pas une cible supportée [lu, extrait de recherche ;
  page googlesource bloquée]. Tutoriel ancien RPi4 : https://dev.to/yaegashi/howto-building-chromium-on-ozone-gbm-for-rpi4-568e
  **Aucun projet de kiosque Ozone-DRM maintenu pour RK3566 trouvé** [recherche négative].

## 5. Questions ouvertes (à trancher par mesure, pas par lecture)
1. Le post r120 rk356x : quel noyau, quel GPU (libmali Bifrost ?), la vidéo est-elle décodée en
   matériel ? — lire https://community.fydeos.com/t/topic/46279 depuis un poste non filtré.
2. openFyde RK3588 promeut-il la vidéo sur un plan VOP2 (Ozone overlay) ou compose-t-il au GPU ?
   — `chrome://gpu` + `/sys/kernel/debug/dri/0/summary` pendant une lecture, sur une Rock 5B.
3. Le libmali Bifrost G52 du BSP expose-t-il les extensions EGL/GBM que minigbm + Chrome attendent
   (dma-buf import, `EGL_EXT_image_dma_buf_import_modifiers`) ? [non vérifié]

## Sources (toutes consultées le 30/09/2026)
- https://github.com/openFyde · https://github.com/orgs/openFyde/repositories?q=overlay
- https://github.com/openFyde/overlay-rock5b-openfyde (+ /releases, /commits/main, /tree/main/kconfigs, profiles/base/parent)
- https://github.com/openFyde/foundation-rk3588 (+ chipset-rk3588, media-libs, sys-kernel)
- https://github.com/openFyde/overlay-inaugural · https://github.com/openFyde/overlay-inaugural-openfyde
- https://github.com/openFyde/overlay-rock4cp-openfyde/releases · https://github.com/openFyde/overlay-rockpi4b-openfyde
- https://github.com/openFyde/overlay-xpressreal-openfyde/releases
- https://github.com/openFyde/getting-started · https://github.com/openFyde/issues
- https://community.fydeos.com/t/topic/46279 (bloqué, extraits) · https://community.fydeos.io/t/topic/29828 (bloqué, extraits)
- https://github.com/ayufan-rock64/chromiumos-build (+ /releases)
- https://github.com/JeffyCN/libv4l-rkmpp
- https://www.collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html
- https://github.com/armbian/build/pull/10455 · séries VDPU346 (lkml, bloqué, titres)
- https://github.com/dongioia/rock5bplus-rkvdec2
- https://support.google.com/chromeosflex/answer/11513094 · https://www.omgubuntu.co.uk/2026/07/chrome-arm64-linux-available
- https://lava.pages.collabora.com/docs/boards/chromebooks/boards/corsola/
- https://www.hackster.io/news/fydeos-developers-unveil-the-xpressreal-t3-a-radxa-zero-spin-off-designed-for-openfyde-e8f5365287b6
- https://docs.mesa3d.org/drivers/panfrost.html
