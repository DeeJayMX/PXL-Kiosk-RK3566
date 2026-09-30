# Alternatives à Chromium, réglages système et règles de page pour un kiosque HDMI sur RK3566 (état au 30/09/2026)

> **Légende.** [mesuré par la source] : chiffre produit par la source, sur son matériel à elle. [lu] : lu dans une doc ou dans du code. [déduit] : mon inférence ; un calcul est marqué « [déduit, calcul] ». La portée matérielle ou logicielle est donnée entre crochets en tête de chaque puce. ⚠ RK3566 ≠ RK3568 ≠ RK3588 ≠ Raspberry Pi : toute transposition est signalée.
> **Accès.** Le proxy a refusé (403 « Host not in allowlist ») : wpewebkit.org, blogs.igalia.com, webkitgtk.org, doc.qt.io, wiki.qt.io, web.dev, developer.chrome.com, chromium.googlesource.com, cnx-software.com, collabora.com, pine64.org, forum.armbian.com, lkml.iu.edu, androidpctv.com, chrislord.net, forum.cool-pi.com et greenchapel.dev. Quand c'était possible, j'ai lu la **source primaire sur GitHub** : sources du site wpewebkit.org, dépôts WebKit, Chromium, Linux, Qt, Buildroot et web.dev. Sinon, la puce cite l'extrait du moteur de recherche, marqué « extrait ». En fin de parcours, le budget de recherches web de la session était épuisé (200/200).

## 1. WPE WebKit (+ Cog / API WPEPlatform) : backend DRM/KMS sans compositeur, vidéo, perfs vs Chromium, compat web, packaging

### Takeaway
WPE 2.54 (16/09/2026) apporte en natif une sortie DRM/KMS sans compositeur (`WPE_PLATFORM=drm`). Son API WPEPlatform est désormais stable, tandis que Cog et libwpe sont dépréciés. Le nouveau compositeur Skia suit les zones endommagées : sur Raspberry Pi 4, il obtient un meilleur score avec 30 à 45 % de charge GPU en moins. En revanche, le backend DRM ne pilote **qu'un plan primaire (+ curseur)**, et WebKit n'a **aucun quirk « hole-punch » Rockchip**. Une vidéo y reste donc composée par le GPU : c'est exactement le goulot mesuré sous Android. Le gain attendu porte sur les pages surtout statiques, pas sur la vidéo plein écran en 4K. Enfin, aucune mesure publique WPE contre Chromium sur RK356x n'existe.

### Cited Findings
**État des API et recommandations Igalia (2025-2026)**
- [WPE 2.54, toutes plateformes] Selon le billet, WPEPlatform est « now enabled by default and its API is considered stable ». libwpe est « officially deprecated », ce qui « also applies to Cog, which will not have stable releases beyond the 0.18.x series ». L'option `ENABLE_WPE_LEGACY_API=OFF` retire l'API legacy à la compilation. [lu] — [WPE WebKit 2.54 highlights, 16/09/2026](https://wpewebkit.org/blog/2026-09-16-wpewebkit-2.54.html), lu via [la source du site sur GitHub](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2026-09-16-wpewebkit-2.54.md)
- [WPE ≥ 2.54] WPE fournit trois implémentations intégrées :
  - Wayland (`WPEDisplayWayland`), qui exige un compositeur ;
  - DRM/KMS (`WPEDisplayDRM`), qui « renders web content directly on screen through the display controller, with no compositor at all. This is very common on kiosk and appliance products » ;
  - headless.

  Le choix se fait par `WPE_PLATFORM=wayland|drm|headless`, sans libwpe ni backend externe. [lu] — [FAQ WPE (page non datée, contenu post-2.54)](https://wpewebkit.org/about/faq.html) via [source GitHub](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/about/faq.md) ; [Architecture](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/about/architecture.md)
- [Igalia, recommandation 2026] Pour un nouveau projet, Igalia recommande d'écrire son propre lanceur plutôt que d'utiliser Cog : « prefer writing a small launcher against the WPEPlatform API instead ». La FAQ donne un lanceur complet d'une dizaine de lignes (`webkit_web_view_load_uri` + `g_main_loop_run`, pkg-config `wpe-webkit-2.0` et `wpe-platform-2.0`). [lu] — FAQ ci-dessus
- [WPE 2.52, 18/03/2026] Ce billet annonçait le retrait (« sunset ») de libwpe à partir de 2.54 et décrivait Cog comme « no longer in active development ». [lu] — [WPE 2.52 highlights](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2026-03-18-wpewebkit-2.52.md)
- [Igalia, 06/01/2023, marketing] Le billet présente WPE comme adapté à la signalétique « specially for the low-end market … in the less powerful devices like the ones based on the Raspberry Pi ». [lu] — [Use Case: WPE in digital signage](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2023-01-success-digital-signage.md)
- [Matériel validé] La page « Supported Hardware » (configurations **pré-2.54**) ne liste côté Rockchip que le RK3399 : Mali-T860 sous Panfrost (backend fdo, Cog en `wl`) et Mali propriétaire. Aucun RK356x n'y figure. Côté Raspberry Pi : RPi 3 en vc4 (Cog `wl`, `drm`, `headless`) et RPi 4 en v3d (`wl`). [lu] — [supported-hardware](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/about/supported-hardware.md)

**Packaging (2025-2026)**
- [Buildroot master, lu le 30/09/2026] `WPEWEBKIT_VERSION = 2.50.5` et `COG_VERSION = 0.18.5`. Buildroot n'est donc pas encore en 2.54. [lu] — [wpewebkit.mk](https://github.com/buildroot/buildroot/blob/master/package/wpewebkit/wpewebkit.mk), [cog.mk](https://github.com/buildroot/buildroot/blob/master/package/cog/cog.mk)
- [Flux OpenWrt `video`] Le passage à WPE 2.54.0 a été fusionné le 29/09/2026 :
  - `ENABLE_WPE_LEGACY_API=OFF` ;
  - libwpe, wpebackend-fdo **et cog retirés**, avec pour motif « Nothing depends on the libwpe API any more » ;
  - nouvelle dépendance libatomic.

  [lu] — [openwrt/video PR #146](https://github.com/openwrt/video/pull/146)
- [Yocto] Igalia maintient la couche `meta-webkit`. Une distribution Yocto (meta-moonforge) remplace cog par un « wpe-simple-launcher ». [lu, extrait] — [meta-webkit wiki](https://github.com/Igalia/meta-webkit/wiki/WPE), [meta-moonforge PR #23](https://github.com/moonforgelinux/meta-moonforge/pull/23)
- [Build] Contraintes de compilation :
  - GCC 12.2 minimum depuis 2.50 ;
  - Clang recommandé plutôt que GCC depuis 2.46, à cause de Skia ;
  - Ninja obligatoire en 2.54, le générateur Makefile n'étant plus supporté.

  [lu] — [2.50](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2025-11-27-wpewebkit-2.50.md), [2.46](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2024-10-07-wpewebkit-2.46.md), [2.54](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2026-09-16-wpewebkit-2.54.md)

**Rendu et performances**
- [WPE 2.54] Le compositeur du web process est réécrit sur Skia et remplace TextureMapper :
  - listes d'affichage rejouées sur le thread de composition, peinture groupée de plusieurs couches ;
  - filtres et masques généralement sans surface intermédiaire ;
  - l'option Cairo est **supprimée**, et le rendu des tuiles ne se fait plus qu'en thread ;
  - la composition est restreinte aux rectangles endommagés, et la propagation des dommages à la plateforme est activée par défaut (préférence `DamageRectangleThreshold`).

  [lu] — 2.54 highlights
- [Raspberry Pi 4 / VideoCore VI (Mesa v3d), tableau de bord perf WPE] Comparaison entre les dernières révisions TextureMapper et les révisions actuelles :

  | Banc | Score avant → après | Charge GPU avant → après |
  |---|---|---|
  | MotionMark 1.3.1 @30 fps | 246 → 334 (+36 %) | 56 % → 39 % |
  | Variante « Composition » | 131 → 189 (+45 %) | 47 % → 26 % |

  [mesuré par la source] — 2.54 highlights ; tableau de bord : [wpe-perf-dashboard.igalia.com](https://wpe-perf-dashboard.igalia.com/) (non consulté). ⚠ Ce n'est pas un RK3566. La source note elle-même que MotionMark anime presque tout l'écran, donc n'exerce pas le suivi de dommages.
- [WPE 2.54] Les animations CSS en `steps()` et `linear()` tournent désormais sur le thread de composition ; auparavant, elles forçaient le thread principal. [lu] — 2.54
- [WPE 2.46, 07/10/2024] Skia remplace Cairo, mais le rendu **CPU** est le défaut, car « our testing with common embedded SoCs has shown that the way WPE WebKit works may result in slightly worse performance in some cases than letting Skia use the CPU ». [lu] — 2.46
- [WPE 2.48, 11/04/2025] Les tuiles sont rendues dans des worker threads GPU. Le rendu GPU n'est « not yet the default » ; on l'active avec `WEBKIT_SKIA_ENABLE_CPU_RENDERING=0`. [lu] — [2.48](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2025-04-11-wpewebkit-2.48.md)
- [WPE 2.50, billet du 27/11/2025] Trois nouveautés :
  - un mode hybride GPU/CPU expérimental ;
  - la propagation des dommages au compositeur système, activée ;
  - `WPEScreenSyncObserver`, qui permet de cadencer le rendu sur la synchro écran.

  [lu] — 2.50
- [WPE 2.52, 18/03/2026] Le canvas 2D accéléré enregistre ses opérations pour les rejouer en lot. La taille des tuiles dépend désormais du mode, rendu GPU ou non. [lu] — 2.52
- [Historique, 2022, avant Skia] Selon l'extrait, un ingénieur Igalia notait que sur RPi les scores MotionMark de WPE « fall markedly behind Chromium, which has a more advanced rendering architecture that better makes use of the GPU ». [lu, extrait ; page bloquée, non vérifié] — [Chris Lord, « WebKit frame delivery », 19/04/2022](https://www.chrislord.net/2022/04/19/webkit-frame-delivery/)
- [Historique, i.MX6D / Vivante, Yocto Rocko, 2018] Sur un benchmark canvas, WPE faisait ~15 fps avec accélération 2D et ~10 fps sans, contre ~45 fps pour Qt WebEngine (Chromium 54). [mesuré par la source] — [WPEWebKit issue #528, 20/08/2018](https://github.com/WebPlatformForEmbedded/WPEWebKit/issues/528). ⚠ Ère Cairo, obsolète.

**Backend DRM de WPEPlatform (code WebKit `main`, lu le 30/09/2026)**
- Conditions d'ouverture :
  - le backend exige les *universal planes* ;
  - il passe en atomique, sauf si `WPE_DRM_DISABLE_ATOMIC` est défini ;
  - il utilise les modificateurs si `DRM_CAP_ADDFB2_MODIFIERS` est présent ;
  - il prend le **DRM master** (`drmSetMaster`).

  [lu] — [WPEDisplayDRM.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WPEPlatform/wpe/drm/WPEDisplayDRM.cpp)
- Présentation d'une image :
  - **un seul plan primaire** (+ plan curseur optionnel), en commit atomique `DRM_MODE_ATOMIC_NONBLOCK | DRM_MODE_PAGE_FLIP_EVENT` ;
  - avec `FB_DAMAGE_CLIPS` et `IN_FENCE_FD` ;
  - import du dmabuf par `gbm_bo_import(..., GBM_BO_USE_SCANOUT)` ;
  - refus d'un buffer dont le couple (format, modificateur) n'est pas accepté par le plan ;
  - repli legacy `drmModePageFlip`, sans curseur.

  [lu] — [WPEViewDRM.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WPEPlatform/wpe/drm/WPEViewDRM.cpp)
- Choix du mode et de l'échelle :
  - le mode est le mode **courant** du CRTC s'il est déjà programmé, sinon le mode `PREFERRED` du connecteur, sinon le plus grand ; **aucune variable ne permet de choisir le mode** ;
  - l'échelle devinée est 1×, sauf écran de 1200 px de haut ou plus **et** de plus de 192 dpi ; `WPE_DRM_SCALE` la surcharge ;
  - le plan primaire reçoit `crtc_w/h` égal au mode et `src_w/h` égal à la taille du buffer.

  [lu] — [WPEScreenDRM.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/WPEPlatform/wpe/drm/WPEScreenDRM.cpp), WPEDisplayDRM.cpp, WPEViewDRM.cpp
- [Cog 0.18, legacy] Le plugin DRM de Cog, lui, sait choisir le mode : `COG_PLATFORM_DRM_VIDEO_MODE` (nom de mode) et `COG_PLATFORM_DRM_MODE_MAX=WxH@R`. Il propose les renderers `modeset` ou `gles` et passe en atomique par défaut, avec repli. [lu] — [cog-platform-drm.c](https://github.com/Igalia/cog/blob/master/platform/drm/cog-platform-drm.c)

**Vidéo**
- [Concept, 2019, ancien] Le hole punching consiste à dessiner un rectangle transparent dans la page et à poser la vidéo sur un plan d'affichage situé dessous. Deux variantes existent upstream : le hole punch GStreamer et le hole punch externe. [lu, extrait] — [« Hole punching in WPE », M. Gómez, 26/02/2019](https://blogs.igalia.com/magomez/2019/02/26/hole-punching-in-wpe/), [WebKit bug 193715](https://bugs.webkit.org/show_bug.cgi?id=193715)
- [WPE ≥ 2.46] Les options de compilation par plateforme sont remplacées par deux variables d'environnement, `WEBKIT_GST_QUIRKS` et `WEBKIT_GST_HOLE_PUNCH_QUIRK` ; la valeur `help` liste les choix. Les options retirées sont notamment `USE_GSTREAMER_HOLEPUNCH`, `USE_WPEWEBKIT_PLATFORM_RPI`, `USE_WPEWEBKIT_PLATFORM_AMLOGIC` et `USE_WESTEROS_SINK`. [lu] — 2.46
- [WebKit `main`, 30/09/2026] Les quirks présents dans le code :
  - quirks GStreamer : AmLogic, BcmNexus, Broadcom, OpenMAX, Qualcomm, Realtek, Rialto, Westeros ;
  - quirks hole-punch : BcmNexus, Rialto, Westeros (+ Fake).

  **Aucun ne vise Rockchip.** [lu] — [Source/WebCore/platform/gstreamer](https://github.com/WebKit/WebKit/tree/main/Source/WebCore/platform/gstreamer)
- [WPE 2.48] Le sink GStreamer-GL accepte la mémoire DMA-BUF. WebCodecs honore `prefer-hardware` en tentant d'abord des éléments GStreamer matériels, avec repli logiciel. [lu] — 2.48
- [WPE 2.54] Nouveautés multimédia :
  - limites de décodage respectées dans MediaCapabilities, surchargeables par `WEBKIT_GST_VIDEO_DECODING_LIMIT` ;
  - pipelines des vidéos muettes et invisibles arrêtés ;
  - sur bas de gamme, pages avec média exclues du cache back-forward ;
  - décodage matériel Qualcomm ajouté (`qtic2vdec`).

  Rien ne concerne Rockchip. [lu] — 2.54
- [RK356x, plugin GStreamer Rockchip `mppvideodec`, miroir « pour GStreamer 1.22.9 »] Propriétés utiles et variables d'environnement qui changent leur défaut :

  | Propriété | Défaut | Rôle | Variable d'environnement |
  |---|---|---|---|
  | `dma-feature` | FALSE | expose la caps `memory:DMABuf` | `GST_MPP_DEC_DMA_FEATURE=1` |
  | `arm-afbc` | FALSE | « Prefer ARM AFBC compressed format » | `GST_MPP_VIDEODEC_DEFAULT_ARM_AFBC` |
  | `fast-mode` | TRUE | mode de décodage rapide | — |
  | `ignore-error` | TRUE | ignore les erreurs MPP | — |

  [lu] — [gstmppdec.c](https://github.com/Meonardo/gst-rockchip/blob/master/gst/rockchipmpp/gstmppdec.c), [gstmppvideodec.c](https://github.com/Meonardo/gst-rockchip/blob/master/gst/rockchipmpp/gstmppvideodec.c)
- [RPi 4, 2019, ancien] Une vidéo FullHD sous WPE + Cog (fdo), avec décodeurs OMX, donnait un « high CPU % ». Le ticket ne donne pas de chiffres et n'a pas reçu de réponse. [lu] — [meta-webkit #127, 22/09/2019](https://github.com/Igalia/meta-webkit/issues/127)
- [Noyau mainline, pas le BSP] La voie V4L2 (GStreamer v4l2codecs, FFmpeg v4l2-request) est encore limitée sur RK3566/RK3568 :
  - seul le Hantro VDPU2 est upstream (MPEG-2, VP8, H.264 plafonné à FullHD) ;
  - le pilote `rkvdec` du master 7.3-rc5 ne déclare que rk3288/3328/3399/3588/3576 ;
  - le **VDPU346** (H.264/HEVC 4K du RK356x) n'est **pas fusionné** au 30/09/2026.

  [lu] — [rockchip_vpu_hw.c](https://github.com/torvalds/linux/blob/master/drivers/media/platform/verisilicon/rockchip_vpu_hw.c), [rkvdec.c](https://github.com/torvalds/linux/blob/master/drivers/media/platform/rockchip/rkvdec/rkvdec.c). Des patchs VDPU346 (« single core, 4K60, H264 L5.1 ») ont circulé en déc. 2025–janv. 2026 et ont été testés sur 6.19-rc4 [lu, extraits] — [CNX Software, 27/02/2026](https://www.cnx-software.com/2026/02/27/rockchip-rk3588-rk3576-h-264-and-h-265-video-decoders-mainline-linux/), [Collabora](https://www.collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html)

**Compat web (limites connues)**
- [WPE 2.54] **WebRTC est désactivé** en 2.54 : transition de GstWebRTC vers LibWebRTC, dont l'activation par défaut est prévue en 2.56, vers mars 2027. GstWebRTC reste activable (`-DUSE_GSTREAMER_WEBRTC=ON`), sans support. [lu] — 2.54, FAQ
- [WPE] État des API :
  - ManagedMediaSource (MSE) activé en 2.50 ; `SourceBuffer.changeType()` expérimental en 2.54 ;
  - processus GPU pour WebGL construit mais désactivé par défaut en 2.48 (flag `UseGPUProcessForWebGL`) ;
  - statut détaillé par API : page WPT/BCD.

  [lu] — [2.50](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2025-11-27-wpewebkit-2.50.md), 2.54, [2.48](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2025-04-11-wpewebkit-2.48.md), [WPT status](https://wpewebkit.org/wpt-status/)
- [WPE] L'EME exige une licence de CDM (plugin Thunder OCDM ou équivalent). [lu] — FAQ

### Inferences
- [déduit] Sur la box (BSP 6.1, Panfrost, Mesa 22.3.6), `WPE_PLATFORM=drm` produirait **une seule image composée par le GPU, vidéo comprise**. C'est la même structure que Chromium ou la WebView sous Android, qui plafonne à 27 fps sur de la 60p. Sans développement, WPE ne met pas la vidéo sur son propre plan : il n'a ni quirk Rockchip, ni gestion de plan overlay ou de zpos dans son backend DRM.
- [déduit] WPE peut réellement gagner sur une page majoritairement statique, avec de petites zones animées. Le suivi de dommages y joue de bout en bout (repeint partiel, puis `FB_DAMAGE_CLIPS` au scanout), et la charge GPU baisse (−30 à −45 % mesuré sur RPi 4). Reste à vérifier sur Mali-G52 : le défaut Skia GPU ou CPU en 2.54 n'est pas documenté dans ce que j'ai lu.
- [déduit] Vidéo matérielle sous WPE sur le BSP : WebKit construit lui-même son pipeline GStreamer. Les propriétés de `mppvideodec` se règlent donc par l'environnement, avec `GST_MPP_DEC_DMA_FEATURE=1`. Le NV12 en DMA-BUF est alors importé par le GL sink (≥ 2.48) : zéro copie au décodage, mais la composition GPU de l'image entière demeure. `arm-afbc` n'est à tenter que si Panfrost importe l'AFBC produit par le VPU.
- [déduit] Deux voies pour obtenir vraiment « la vidéo sur un plan » avec WPE, chacune au prix d'une intégration lourde :
  - (a) écrire une implémentation WPEPlatform (en sous-classant `WPEDisplay`, ce que l'API prévoit) ou un quirk hole-punch qui pose le NV12 sur Esmart0 **dans le même processus maître DRM**. Un `kmssink` séparé ne pourrait pas commiter, puisqu'il n'y a qu'un maître ;
  - (b) passer par Wayland (Weston ou Cage), avec la vidéo en sous-surface que le compositeur place sur un plan.
- [déduit] WPEPlatform n'a pas de variable pour sortir en 1080p. Mais comme il reprend le mode courant du CRTC, il suffit de fixer ce mode avant son lancement, par exemple avec `video=HDMI-A-1:1920x1080@60` sur la ligne de commande noyau, que fbcon programme. À vérifier. Avec Cog legacy, `COG_PLATFORM_DRM_VIDEO_MODE` suffit.
- [déduit] `WPE_DRM_SCALE=2` sur un mode 4K ne réduit **pas** le coût : le buffer reste en 3840×2160, l'échelle agit comme un device pixel ratio. Pour rendre en 1080p sur une sortie 4K avec upscaling par le plan VOP2, il faudrait patcher la taille du buffer ; le code pose déjà `src` = buffer et `crtc` = mode.
- [déduit] Si la page kiosque est un viewer TurboHQ en WebCodecs, WPE route WebCodecs vers GStreamer avec l'indice `prefer-hardware`. `mppvideodec` pourrait alors être retenu, ce qui n'est pas vérifié. En revanche, WebRTC est indisponible en 2.54.
- [déduit] Debian bookworm ne livre vraisemblablement pas de WPE 2.54. Il faudrait la construire soi-même (le GCC 12.2 de bookworm atteint tout juste le minimum ; Clang recommandé ; Ninja) ou passer par Buildroot ou Yocto.

### Gaps
- Je n'ai trouvé aucune mesure publique WPE contre Chromium sur RK356x ou Mali-G52, ni sur i.MX8 ou RK3588. Les seuls chiffres récents concernent le RPi 4, et WPE seul.
- Le défaut CPU ou GPU du raster Skia en 2.50–2.54 n'est pas confirmé : CPU en 2.46, GPU en option à partir de 2.48.
- Le comportement de Panfrost (Mesa 22.3.6) avec le compositeur Skia de 2.54 est inconnu.
- Je n'ai pas pu lire les billets Igalia de septembre 2026 sur le compositeur Skia (blogs.igalia.com bloqué) : [C. García Campos, 21/09/2026](https://blogs.igalia.com/carlosgc/2026/09/21/skia-compositor-for-wpe-webkit-and-webkitgtk/) et [N. Zimmermann, 21/09/2026](https://blogs.igalia.com/nzimmermann/posts/2026-09-21-skia-compositor-damaging/). Leurs extraits confirment seulement le chiffre de +36 % et le principe d'une passe « damage » suivie d'une passe « paint ».
- La version de WPE dans Debian bookworm ou ses backports n'est pas vérifiée (sites Debian bloqués).

## 2. Qt WebEngine + eglfs (KMS) sur RK356x

### Takeaway
Qt WebEngine, c'est Chromium dont le compositeur (Viz) produit une image que Qt Quick **recompose** ensuite via RHI. Cela fait une passe GPU plein écran de plus que Chromium seul, sur une surface EGL/KMS unique. Son unique décodage vidéo matériel sous Linux passe par VA-API : pas de V4L2, et donc rien pour le MPP Rockchip. Pour ce kiosque, c'est a priori plus lourd que Chromium nu, et sans issue côté vidéo.

### Cited Findings
- [Qt WebEngine, branche dev, doc lue le 30/09/2026] La doc décrit une double composition : « The actual rendering is performed by Chromium, and the final image is produced by Chromium's compositor … This final image is then imported by Qt WebEngine into the Qt rendering pipeline using GPU interoperability … passed to the Qt Quick Scene Graph, which also performs hardware-accelerated rendering through the Qt Rendering Hardware Interface (RHI) ». Elle indique aussi :
  - le repli logiciel par `QTWEBENGINE_CHROMIUM_FLAGS=--disable-gpu` ou `QT_QUICK_BACKEND=software` ;
  - le diagnostic par `chrome://gpu` et la catégorie de log `qt.webenginecontext`.

  [lu] — [qtwebengine-features.qdoc](https://github.com/qt/qtwebengine/blob/dev/src/core/doc/src/qtwebengine-features.qdoc)
- [Qt WebEngine dev] La seule option de décodage matériel est la fonctionnalité `webengine-vaapi` (« Enables support for VA-API hardware acceleration ») :
  - auto-détectée si GBM, libva et Vulkan sont présents ;
  - Linux uniquement ;
  - incompatible avec la libvpx système.

  Chromium y est construit avec `ozone_platform="qt"`, un Ozone externe piloté par Qt. [lu] — [configure.cmake](https://github.com/qt/qtwebengine/blob/dev/src/core/api/configure.cmake), [BUILD.root.gn.in](https://github.com/qt/qtwebengine/blob/dev/src/core/configure/BUILD.root.gn.in)
- [Qt wiki, non daté] « Qt WebEngine does not currently support hardware accelerated decoding of videos ». [lu, extrait ; page bloquée, sans doute antérieure à l'option VA-API ; contredit par le configure actuel sur x86/VA-API] — [QtWebEngine/VideoAcceleration](https://wiki.qt.io/QtWebEngine/VideoAcceleration)
- [RK356x, forum Toybrick de Rockchip] Rockchip n'a pas de licence Qt et ne supporte pas Qt officiellement. T-Firefly cite Qt 5.12.2 en EGLFS. [lu, extrait] — [t.rock-chips.com, fil 4136](https://t.rock-chips.com/forum.php?mod=viewthread&action=printable&tid=4136)
- [TI AM335x/AM437x, pas Rockchip] QtWebEngine consomme plus de 50 % de CPU au défilement, en LinuxFB comme en EGLFS. [mesuré par la source, extrait] — [TI E2E](https://e2e.ti.com/support/processors-group/processors/f/processors-forum/1016757/processor-sdk-am437x-qtwebengine-consumes-more-than-50-cpu-with-linuxfb-as-well-as-eglfs-on-am335x-and-am437x-evm)
- [Qt Forum] Des utilisateurs essaient `--enable-gpu-rasterization --enable-zero-copy --ignore-gpu-blacklist` dans `QTWEBENGINE_CHROMIUM_FLAGS`, avec peu d'effet par rapport à Chrome natif. [lu, extrait] — [forum.qt.io/topic/159558](https://forum.qt.io/topic/159558/webengineview-performance-issues-vs-native-chrome)
- [i.MX6D / Vivante, 2018, ancien] Qt WebEngine (Chromium 54) faisait ~45 fps contre ~15 fps pour WPE sur un benchmark canvas. [mesuré par la source] — [WPEWebKit #528](https://github.com/WebPlatformForEmbedded/WPEWebKit/issues/528)

### Inferences
- [déduit] Qt WebEngine cumule le coût de Chromium et une composition Qt Quick plein écran. En 4K sur Mali-G52 MP2, cela ajoute ~33 Mo écrits puis relus par image (voir §5) : c'est pire que Chromium seul pour notre usage.
- [déduit] Il n'existe aucune voie de décodage matériel Rockchip : pas de pilote VA-API pour MPP, et un `libva-v4l2-request` exigerait le noyau mainline tout en restant marginal. La vidéo serait donc décodée en logiciel sur les 4 Cortex-A55.
- [déduit] Le seul intérêt de Qt WebEngine apparaît si l'application doit mêler QML et web. Une vidéo native Qt Multimedia (GStreamer + mpp) sous la page est possible, mais c'est un hole-punch applicatif, pas un atout du moteur.

### Gaps
- Je n'ai trouvé aucun banc Qt WebEngine sur RK3566 ou RK3568.
- La configuration eglfs_kms (choix du plan, `QT_QPA_EGLFS_KMS_CONFIG`) n'est pas vérifiée (doc.qt.io et wiki.qt.io bloqués).

## 3. Android sur la même box en kiosque (Fully Kiosk, WebView maison) : limites HWC et astuces pour mettre `<video>` sur son propre plan

### Takeaway
Le code de Chromium explique très probablement les 27 fps.
- **Côté Chromium.** Sur un appareil qui se déclare « TV », Chromium limite la file AImageReader à une seule image. Cela **désactive SurfaceControl, donc toute promotion de la vidéo en overlay matériel**. En M113, la version de la WebView de la box, il n'existe aucune échappatoire. En 2026, on peut lever la limite depuis les Flags de WebView DevTools : désactiver `LimitAImageReaderMaxSizeToOne`, `WebViewSurfaceControlForTV` étant actif par défaut. Ce déverrouillage n'est pas testé.
- **Côté silicium.** Le VOP2 du RK3566 n'a que **3 fenêtres indépendantes** (Cluster0, Esmart0, Smart0), dont une seule, Esmart0, accepte du YUV linéaire. Au mieux, on obtient donc un overlay vidéo plus l'UI.
- **Solution garantie.** Une app native (MediaCodec → SurfaceView, déjà mesurée à 60 fps) avec une WebView transparente par-dessus.

### Cited Findings
**Chromium / WebView : conditions d'accès aux overlays (code)**
- [Chromium `main`, lu le 30/09/2026] Les trois interrupteurs des overlays et leur défaut :

  | Feature | Rôle | Défaut |
  |---|---|---|
  | `kAndroidSurfaceControl` | overlays Android, Chrome | **activé** |
  | `kWebViewSurfaceControl` | « Hardware Overlays for WebView » | **désactivé** |
  | `kWebViewSurfaceControlForTV` | overlays WebView sur TV | **activé** |

  [lu] — [gpu_finch_features.cc](https://github.com/chromium/chromium/blob/main/gpu/config/gpu_finch_features.cc)
- [Chromium `main`] `IsAndroidSurfaceControlEnabled()` renvoie faux si `LimitAImageReaderMaxSizeToOne()` est vrai, car « SurfaceControl requires at least 3 frames in flight ».
  - Sur TV (`is_tv()`), cette limite est vraie (« Always limit image reader to 1 frame for Android TV. Many TVs doesn't work with more than 1 frame »).
  - Elle ne tombe que si le SoC, le fabricant ou l'appareil figure en liste d'assouplissement, ou si elle est **surchargée en ligne de commande**. Défauts des listes : `*Broadcom*` ; `*Broadcom*|*Google*` ; `G08|G10|G17|BRAVIA_CT1`.
  - La WebView exige en plus le « thread-safe media », qui suppose un AImageReader d'au moins 2 images.

  [lu] — idem
- [Chromium `main`] SurfaceControl exige Android 10 (Q), et Android 11 sur les appareils Samsung. [lu] — [android_surface_control_compat.cc](https://github.com/chromium/chromium/blob/main/ui/gfx/android/android_surface_control_compat.cc)
- [Chromium **M113** = WebView de la box] `LimitAImageReaderMaxSizeToOne()` renvoie vrai **sans condition** dès que `is_tv()`, sans surcharge possible : SurfaceControl est donc désactivé. `kWebViewSurfaceControl` y est aussi désactivé par défaut. [lu] — [gpu_finch_features.cc @113.0.5672.163](https://github.com/chromium/chromium/blob/113.0.5672.163/gpu/config/gpu_finch_features.cc)
- [M113] `isTV` vaut `UiModeManager.getCurrentModeType() == UI_MODE_TYPE_TELEVISION`. [lu] — [BuildInfo.java @113](https://github.com/chromium/chromium/blob/113.0.5672.163/base/android/java/src/org/chromium/base/BuildInfo.java)
- [WebView 2026] Les Flags de WebView DevTools, utilisables sur un appareil de production (build « user »), exposent :
  - `WebViewSurfaceControl` (« Is not supported for TV ») ;
  - `WebViewSurfaceControlForTV` (« Only supported on TV ») ;
  - `AndroidYuvOverlayEvenAlignment` (« to prevent odd-coordinate display scaling rejections ») ;
  - `LimitAImageReaderMaxSizeToOne` (« If disabled allows acquiring more than one image from the AImageReader ») ;
  - `RelaxLimitAImageReaderMaxSizeToOne`.

  [lu] — [ProductionSupportedFlagList.java](https://github.com/chromium/chromium/blob/main/android_webview/java/src/org/chromium/android_webview/common/ProductionSupportedFlagList.java), [developer-ui.md](https://github.com/chromium/chromium/blob/main/android_webview/docs/developer-ui.md). Le fichier `/data/local/tmp/webview-command-line`, lui, ne vaut que sur les builds userdebug/eng [lu] — [commandline-flags.md](https://github.com/chromium/chromium/blob/main/android_webview/docs/commandline-flags.md)
- [WebView M113] La liste de flags exposait `WebViewSurfaceControl`, `WebViewThreadSafeMedia` et `WebViewVulkan`, mais **pas** `LimitAImageReaderMaxSizeToOne`. [lu] — [ProductionSupportedFlagList.java @113](https://github.com/chromium/chromium/blob/113.0.5672.163/android_webview/java/src/org/chromium/android_webview/common/ProductionSupportedFlagList.java)
- [Chrome Android, `main`] Deux interrupteurs médias :
  - `kOverlayFullscreenVideo`, activé par défaut, est « Only used for disabling overlay fullscreen (aka SurfaceView) in Clank » ;
  - `kUseAndroidOverlayForSecureOnly` est désactivé par défaut.

  [lu] — [media_switches.cc](https://github.com/chromium/chromium/blob/main/media/base/media_switches.cc)
- [Chrome Android / WebView, fil android-webview-dev non daté] La vidéo plein écran et la vidéo EME inline passent par une SurfaceView séparée. Le fil note qu'il est « impossible to support all HTML/CSS features correctly when using SurfaceView » ; la préférence `use_view_overlay_for_all_video` existe sans API publique. [lu, extrait] — [android-webview-dev](https://groups.google.com/a/chromium.org/g/android-webview-dev/c/hS_dNQXQLcY)
- [AOSP] Une TextureView est toujours composée en GL, alors qu'une SurfaceView peut passer sur un overlay matériel, qui consomme moins de bande passante. [lu, extrait] — [AOSP, TextureView](https://source.android.com/docs/core/graphics/arch-tv)
- [Chromium] Ticket de suivi « Use SurfaceControl for video overlays on Android ». [lu, extrait] — [issue 40595450](https://issues.chromium.org/issues/40595450)

**Silicium : VOP2 du RK3566**
- [RK3566, pas RK3568] Le pilote décrit ainsi les fenêtres Smart1, Esmart1 et Cluster1 : « On RK3566 these windows don't have an independent framebuffer. They can only share/mirror the framebuffer with smart0, esmart0 and cluster0 respectively ». [lu] — [rockchip_drm_vop2.c, `vop2_is_mirror_win()`](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c). Même constat dans les fils de 2023-2025 [lu, extraits] — [linux-rockchip 12/2023](https://lists.infradead.org/pipermail/linux-rockchip/2023-December/043829.html), [dri-devel v16](https://www.mail-archive.com/dri-devel@lists.freedesktop.org/msg533140.html)
- [RK356x, pilote mainline] Formats et agrandissement par type de fenêtre :

  | Fenêtre | Formats | Agrandissement max |
  |---|---|---|
  | Smart | RGB seulement | ×8 |
  | Esmart | RGB + YUV **linéaire** (NV12, NV21, NV15, NV16, NV24…) | ×8 |
  | Cluster | RGB (dont 10 bits) + YUV **en AFBC seulement** | ×4 |

  [lu] — [rockchip_vop2_reg.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_vop2_reg.c)

**Kiosque Android**
- [Fully Kiosk Browser] Les vidéos ne jouent qu'en mode d'accélération graphique « Hardware », qui est le défaut. [lu, extrait] — [4escape Help Center](https://help.4escape.io/en/articles/259199-live-hardware-with-fully-kiosk-browser-for-android)

### Inferences
- [déduit] Si la ROM de la X88Pro20 se déclare en mode UI « télévision », WebView 113 et Cromite 148 composent la vidéo comme une texture GL dans un unique buffer. C'est cohérent avec le plafond de ~27 fps mesuré, et avec les 60 fps de YouTube (app native, SurfaceView). Deux commandes le vérifient : `adb shell dumpsys uimode`, puis `dumpsys SurfaceFlinger` pour savoir si la couche vidéo est en composition DEVICE ou CLIENT.
- [déduit, à tester] Chemin WebView sans root, en quatre gestes :
  1. installer une Android System WebView récente, si la version d'Android l'accepte ;
  2. dans WebView DevTools → Flags, passer `LimitAImageReaderMaxSizeToOne` à **Disabled** et laisser `WebViewSurfaceControlForTV` (ou `WebViewSurfaceControl` si la box n'est pas vue comme TV), éventuellement avec `AndroidYuvOverlayEvenAlignment` ;
  3. tuer puis relancer l'app kiosque ;
  4. contrôler la couche dans le HWC.

  Deux risques : le scintillement, qui est la raison même de la limite, et un rejet du HWC pour une question d'échelle ou d'alignement.
- [déduit] Même en cas de succès, le RK3566 n'a qu'un seul plan YUV linéaire (Esmart0), donc une seule vidéo matérielle à la fois. L'UI reste composée par le GPU, mais seulement quand elle change.
- [déduit] Chemin garanti : une app kiosque maison. La vidéo passe par ExoPlayer/MediaCodec vers une SurfaceView (déjà mesuré : 60,0 fps, 0 % GPU). L'habillage vient d'une WebView transparente posée par-dessus, et un pont JS pilote la vidéo : c'est un hole-punch applicatif.
- [déduit] Fully Kiosk Browser s'appuie sur la WebView système (non sourcé ici). Il hérite donc exactement des mêmes limites que la WebView installée.
- [déduit] API Fullscreen : dans Chrome (Clank), la vidéo en plein écran passe en SurfaceView (`kOverlayFullscreenVideo`). Dans une WebView, cela dépend de la gestion de `onShowCustomView` par l'app. Non vérifié.

### Gaps
- La politique du HWC2 Rockchip sous Android RK3566 m'est inconnue (quelles couches il accepte en overlay : YUV, mise à l'échelle, AFBC). Aucune source n'était accessible.
- Je ne connais ni la version d'Android de la X88Pro20, ni son `uimode`, ni la **résolution de son framebuffer UI**. Sur les box Rockchip, l'UI est souvent en 1080p mise à l'échelle vers la 4K, affirmation non sourcée. Ce point change le calcul de bande passante du §5.
- On ignore si une WebView de 2026 s'installe sur la box : le plancher Android de Chromium en 2026 n'est pas vérifié.
- Je n'ai trouvé aucun retour d'expérience avec `LimitAImageReaderMaxSizeToOne` désactivé sur un SoC Rockchip.

## 4. Autres moteurs (Ultralight, Servo, Ladybird, Firefox) : maturité en 2026

### Takeaway
Aucun de ces moteurs n'est un meilleur choix que Chromium ou WPE pour ce kiosque en 2026 :
- **Ultralight** est un moteur de rendu à embarquer, pas un kiosque, et ne documente aucun décodage vidéo matériel ;
- **Servo** publie des LTS mais reste avant la 1.0 ;
- **Ladybird** vise une première alpha Linux/macOS en 2026 ;
- **Firefox** n'a de décodage matériel sur ARM que par V4L2. Cette voie est inutilisable sur le BSP MPP ; en mainline, elle se limite au H.264 ≤ 1080p via Hantro, et encore à condition d'avoir le v4l2-request.

### Cited Findings
- [Ultralight 1.4, 2025] Cœur WebKit 615.1.18.100.1, binaires Linux ARM64. Deux renderers au choix : CPU, ou GPU qui rend dans une texture que l'application intègre elle-même. La 1.4.1 annonce filtres GPU, `backdrop-filter` et composition accélérée. [lu, extrait] — [« Ultralight 1.4 Out Now »](https://ultralig.ht/blog/ultralight-1-4-out-now)
- [Servo] Versions récentes :
  - 0.4.0 le 31/07, re-taguée v0.4.0 le 04/08 ;
  - v0.5.0 le 31/08 ;
  - v0.6.0 « LTS » le 29/09, avec SpiderMonkey passé d'ESR 140 à ESR 153.

  La page n'affiche pas l'année ; 2026 est déduite de l'ESR 153. Les binaires couvrent Linux ARM64, Android et OpenHarmony. [lu] — [servo/servo releases](https://github.com/servo/servo/releases). Une LTS sort tous les 6 mois, avec ~9 mois de support [lu, extrait] — [Phoronix](https://www.phoronix.com/news/Servo-Embed-Crates-LTS)
- [Ladybird] Calendrier annoncé :
  - première alpha Linux/macOS visée à l'été 2026, bêta en 2027, stable en 2028 ;
  - pull requests publiques fermées en juin 2026 en vue de l'alpha ;
  - rien sur ARM.

  [lu, extraits] — [ladybird.org](https://ladybird.org/), [linuxiac](https://linuxiac.com/ladybird-browser-closes-public-pull-requests-ahead-of-first-alpha/), [PiunikaWeb, 05/06/2026](https://piunikaweb.com/2026/06/05/ladybird-browser-closes-public-contributions/)
- [Firefox, RPi 4] Décodage matériel H.264 en V4L2-M2M (stateful) depuis Firefox 116 (2023). [lu, extrait] — [OMG! Linux](https://www.omglinux.com/firefox-hardware-acceleration-raspberry-pi/), [bug 1833354](https://bugzilla.mozilla.org/show_bug.cgi?id=1833354)
- [Firefox, RPi 5] HEVC stateless via FFmpeg `v4l2-request` en cours ; le décodeur n'y sort que du SAND (NC12/NC30). [lu, extrait] — [bug 1969297](https://bugzilla.mozilla.org/show_bug.cgi?id=1969297)
- [FFmpeg] La série « V4L2 Request API hwaccels » (MPEG-2, H.264, HEVC) de J. Karlman en est à sa v2 (août 2024). Utilisée par LibreELEC depuis 2018, sa fusion upstream n'est pas confirmée. [lu, extrait] — [ffmpeg-devel 08/2024](https://ffmpeg.org/pipermail/ffmpeg-devel/2024-August/332034.html)
- [Firefox Wayland, 2025-2026] La fenêtre est composée de sous-surfaces, ce qui permet d'envoyer les images vidéo directement à l'écran. [lu, extrait] — [M. Stransky, 23/01/2026](https://mastransky.wordpress.com/2026/01/23/firefox-linux-in-2025/). Côté compositeur, une vidéo en sous-surface peut finir sur un plan KMS (underlay), GPU éteint, si le décodage est matériel [lu, extrait] — [X. Hugl (KDE), 23/10/2025](https://planet.kde.org/xavers-blog-2025-10-23-more-kms-offloading-with-overlay-planes/)

### Inferences
- [déduit] Sur le BSP 6.1 (MPP seul, aucun nœud décodeur V4L2), Firefox, Servo et Ultralight décodent la vidéo en logiciel. Servo passe par GStreamer, mais sans intégration `mppvideodec` connue.
- [déduit] Firefox avec un compositeur Wayland (Weston ou wlroots) est la seule pile grand public conçue pour poser la vidéo sur un plan. La condition qui manque sur RK3566 hors mainline est justement un décodage matériel en dmabuf.

### Gaps
- Aucune mesure sur RK3566 pour Servo, Ladybird, Ultralight ou Firefox.
- La licence d'Ultralight et son support vidéo ne sont pas vérifiés (site accessible uniquement par extrait).

## 5. Réglages système sur RK3566 : gouverneurs, DDR/DMC, thermique, mémoire, services, mode HDMI

### Takeaway
- **DDR.** Sur le BSP 6.1, le nœud **DMC est désactivé par défaut**, d'où l'absence de devfreq DDR. La DDR tourne donc à la fréquence laissée par le loader, qu'il faut **mesurer** : le blob Rockchip standard vise 1056 MHz, mais au moins une pile RK3566 démarre à 528 MHz.
- **Mode HDMI.** Le bus 32 bits en LPDDR4 à 1056 MHz offre ≈ 8,4 Go/s théoriques. Une composition GPU plein écran en 4K à 60 i/s y est quasi impossible, et coûte 4× moins en 1080p : le mode HDMI est le premier levier.
- **Gouverneurs.** Passer CPU et GPU en `performance` supprime la latence de montée en fréquence, au prix de la chaleur.
- **Thermique.** Le BSP bride CPU et GPU à partir de 85 °C (seuil passif) et coupe à 115 °C.

### Cited Findings
**Fréquences et gouverneurs**
- [BSP 6.1 Armbian `rk-6.1-rkr6.1`, rk356x.dtsi] OPP CPU de 408 à 1800 MHz ; OPP GPU de 200, 300, 400, 600, 700 et 800 MHz. [lu] — [rk356x.dtsi](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr6.1/arch/arm64/boot/dts/rockchip/rk356x.dtsi)
- [BSP 6.1] Le nœud `dmc` (`rockchip,rk3568-dmc`) est en **`status = "disabled"`**. Une fois activé, il porte :
  - les tables `vop-bw-dmc-freq`, `vop-frame-bw-dmc-freq` et `cpu-bw-dmc-freq`, qui choisissent 324, 528 ou 780 MHz selon la bande passante ;
  - `upthreshold = 40` et `downdifferential = 20` ;
  - les niveaux `SYS_STATUS_VIDEO_4K → DMC_FREQ_LEVEL_MID_HIGH` et `SYS_STATUS_PERFORMANCE → HIGH` ;
  - `auto-min-freq = 324000`.

  [lu] — idem
- [BSP 6.1, rk3566.dtsi] LPDDR4 et LPDDR4X ont `freq_0 = <1056>`, avec le commentaire « freq_0 is final frequency ». [lu] — [rk3566.dtsi](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr6.1/arch/arm64/boot/dts/rockchip/rk3566.dtsi)
- [rkbin] Le loader RK3566 embarque `rk3566_ddr_1056MHz_v1.26.bin`, contre `rk3568_ddr_1560MHz_v1.26.bin` pour le RK3568. [lu] — [RK3566MINIALL.ini](https://github.com/rockchip-linux/rkbin/blob/master/RKBOOT/RK3566MINIALL.ini)
- [RK3566] Le contrôleur mémoire est un **32 bits** DDR3/DDR3L/DDR4/LPDDR4/LPDDR4X. [lu, extrait] — [RK3566 Brief Datasheet (Rockchip)](https://www.rock-chips.com/uploads/pdf/2022.8.26/192/RK3566%20Brief%20Datasheet.pdf)
- [RK3566 : consoles Powkiddy RGB30 et Anbernic RG353P ; noyau 6.18.13 + patchs ROCKNIX ; ATF v1.45 ; 4-6/03/2026] Mesures DMC :
  - OPP DMC à 324, 528, 780 et 1056 MHz, dont **528 MHz = « boot rate »** ;
  - `simple_ondemand` avec upthreshold 15 % et polling 100 ms ;
  - balayage des fréquences DDR : 0,08 W d'écart au total, « bandwidth matching, not power savings » ;
  - le gist rapporte un arrêt thermique à 95 °C avec le DMC verrouillé à 1056 MHz en `performance`, conditions de charge non précisées.

  [mesuré par la source] — [gist aenertia (ROCKNIX)](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7)
- [BSP 6.1, Panfrost] Le devfreq GPU est en `simple_ondemand`, avec `upthreshold = 45`, `downdifferential = 5` et `polling_ms = 50` (« ~3 frames »). [lu] — [panfrost_devfreq.c](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr6.1/drivers/gpu/drm/panfrost/panfrost_devfreq.c)
- [Panfrost, 01/2021] Les seuils par défaut de `simple_ondemand` (90/5) fonctionnaient mal. Des seuils ajustés ont fait passer glmark2 de 114 à 151, contre 153 à fréquence maximale. [mesuré par la source, extrait ; matériel non identifié dans l'extrait ; page bloquée] — [LKML, « drm/panfrost: Add governor data with pre-defined thresholds »](https://lkml.iu.edu/hypermail/linux/kernel/2101.2/07035.html)
- [Linux, doc cpufreq] `performance` demande la fréquence la plus haute permise par `scaling_max_freq`. `schedutil` suit l'utilisation PELT du scheduler, et monte au maximum pour les classes RT et deadline. [lu] — [cpufreq.rst](https://github.com/torvalds/linux/blob/master/Documentation/admin-guide/pm/cpufreq.rst)
- [Mali-G52 / Panfrost] Panfrost est conforme OpenGL ES 3.1 (Khronos) sur Mali-G52 (date non relevée). [lu, extrait] — [Collabora](https://www.collabora.com/news-and-blog/news-and-events/panfrost-achieves-opengl-es-3.1-conformance-on-mali-g52.html), [Mesa docs](https://docs.mesa3d.org/drivers/panfrost.html)

**Thermique**
- [BSP 6.1] Zone `soc-thermal` :
  - seuils passifs à 75 °C (threshold) et **85 °C** (target), avec cooling maps vers le CPU **et** le GPU ;
  - seuil critique à 115 °C ;
  - `sustainable-power = 905` mW et `polling-delay-passive = 20` ms.

  La zone `gpu-thermal` n'a qu'un seuil critique, à 115 °C. [lu] — rk356x.dtsi BSP ci-dessus
- [Mainline, rk356x-base.dtsi] `cpu-thermal` et `gpu-thermal` : seuils passifs à 70 et 75 °C, critique à 95 °C. [lu] — [rk356x-base.dtsi](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk356x-base.dtsi). Patch d'origine de 2021 pour le GPU (70/75/95) [lu, extrait] — [LKML 2111.3](https://lkml.rescloud.iu.edu/2111.3/04490.html)
- [RK3566, consoles, 03/2026] Températures relevées selon la fréquence et la charge :

  | Condition | Température |
  |---|---|
  | CPU 1416 MHz | 73 °C |
  | CPU 1608 MHz, tensions d'origine | 85 °C puis **reset** |
  | CPU 1800 MHz, undervolt « L3 », stress combiné | 71 °C |
  | Charge GPU (émulation N64), résolution native | 86 °C |
  | Même charge, à mi-échelle | 67 °C (**−19 °C**) |

  L'undervolt fait gagner 17 à 18 °C et environ 1 W. [mesuré par la source] — gist aenertia. ⚠ Consoles avec leur propre dissipation, pas une box TV.

**Mémoire**
- [Armbian] Le zram est activé par défaut (`ENABLED=true`), avec `ZRAM_PERCENTAGE=50` et `MEM_LIMIT_PERCENTAGE=50` (lignes commentées, donc valeurs par défaut) et le commentaire « Seems lzo is best choice on ARM ». [lu] — [armbian-zram-config](https://github.com/armbian/build/blob/main/packages/bsp/common/etc/default/armbian-zram-config.dpkg-dist)
- [RK356x] Le VOP2 a sa propre IOMMU (`vop_mmu`), de même que le VPU (`vdpu_mmu`). [lu] — rk356x-base.dtsi mainline

**Échelle**
- [Chromium] `--force-device-scale-factor` « Overrides the device scale factor for the browser UI and the contents ». [lu] — [display_switches.cc](https://github.com/chromium/chromium/blob/main/ui/display/display_switches.cc)

### Inferences
- [déduit, calcul] Une image ARGB pèse 3840×2160×4 o = 33,2 Mo en 4K, contre 8,3 Mo en 1080p. Le scanout seul à 60 Hz lit donc 1,99 Go/s en 4K, contre 0,50 Go/s en 1080p.
- [déduit, calcul] La crête théorique de la DDR vaut 1056 MHz × 2 transferts × 4 o = 8,45 Go/s, ou 4,2 Go/s à 528 MHz.
  - Composer par GPU une couche plein écran 4K à 60 i/s coûte : lecture de la source (≥ 2 Go/s) + écriture (2 Go/s) + scanout (2 Go/s) ≈ 6 Go/s, soit ≈ 70 % de la crête théorique. Il faut encore ajouter le CPU, le décodeur et les tuiles : c'est intenable.
  - Vers ~30 i/s, on tombe à ≈ 3 Go/s, ce qui est cohérent avec le plafond de 27 fps mesuré sous Android, **si** l'UI y était bien composée en 4K (voir le trou du §3).
- [déduit] Priorité n°1 à mesurer : la fréquence DDR réelle, soit par la bannière DDR du loader sur la console série, soit dans `clk_summary` en debugfs, ainsi que le débit avec `tinymembench`. Si la box reste à 528 MHz, la moitié du débit manque.
- [déduit] Activer le DMC du BSP (`&dmc { center-supply = <&vdd_logic>; status = "okay"; }`) n'apporte rien en performance si le loader laisse déjà 1056 MHz. Il sert surtout à économiser, et ses tables `vop-bw` remontent déjà en 4K. On ne le tente que si la DDR est bloquée basse, et avec le bon régulateur.
- [déduit] Gouverneurs : passer le CPU en `performance` et le GPU aussi (`echo performance > /sys/class/devfreq/fde60000.gpu/governor`) supprime la latence de montée. Le polling GPU de 50 ms représente ≈ 3 images, ce qui pénalise les animations intermittentes.
  - Surveiller `/sys/class/thermal/thermal_zone*/temp` : la box est passive, et le seuil BSP de 85 °C bride le CPU **et** le GPU.
  - Alternative plus douce : garder `simple_ondemand` en relevant le `min_freq` du GPU, par exemple à 600 MHz.
- [déduit] Sortir en HDMI 1080p60 divise par 4 le travail de composition et de scanout, et le téléviseur se charge de l'agrandissement. La mesure ROCKNIX (−19 °C à mi-échelle sur une charge GPU) laisse aussi espérer une nette marge thermique.
  - Pour garder une sortie 4K, il faudrait rendre l'UI en 1080p et laisser le plan VOP2 l'agrandir : ×4 sur Cluster, ×8 sur Esmart ou Smart.
- [déduit] Les 800 Mo de CMA sont larges pour quelques tampons 4K (33 Mo en ARGB, ~12 Mo en NV12). Comme le VOP2 et le VPU ont une IOMMU, le scanout n'exige pas de CMA. Le zram d'Armbian (50 %, lzo) suffit pour une page unique ; il faut éviter tout swap sur l'eMMC.
- [déduit] Services : sur une box kiosque, désactiver ce qui réveille le CPU ou la mémoire (indexation, `unattended-upgrades` en journée, bureau ou compositeur inutiles quand on sort directement en DRM). Gain non chiffré.

### Gaps
- Je n'ai trouvé aucune mesure de throttling publiée pour la X88Pro20 elle-même (revue AndroidPCtv bloquée). Le type et la fréquence réels de sa DDR sont inconnus.
- La fréquence DDR effective quand le DMC est désactivé dépend du loader de la box. Elle n'est pas documentée : la valeur de 528 MHz vient d'une autre pile (ROCKNIX, mainline + ATF v1.45).
- Le matériel du banc Panfrost de 2021 n'est pas confirmé (page LKML bloquée).

## 6. Écrire une page peu coûteuse pour un Mali bas de gamme, et la mesurer

### Takeaway
Tout ce qui oblige à repeindre ou à recomposer de grandes surfaces coûte en proportion des pixels. Sur RK3566 en 4K :
- n'animer que `transform` et `opacity`, sur des éléments de taille modeste ;
- garder peu de couches : chaque couche est une texture, et 4096² en ARGB pèse 64 Mio ;
- bannir flous, `backdrop-filter`, ombres animées et grands dégradés animés ;
- préférer la vidéo aux GIF ou à Lottie, **seulement si** le décodage vidéo est matériel ;
- cadencer volontairement à 30 i/s stables plutôt que subir 27 à 40 i/s ;
- mesurer avec `--show-fps-counter`, `--show-surface-damage-rects`, Perfetto et l'API LoAF.

### Cited Findings
- [web.dev, 2015, toujours en ligne] Seuls `transform` et `opacity` sont traités par le compositeur seul. L'article conseille de promouvoir les éléments animés (`will-change`, `translateZ`), mais « avoid overusing promotion rules; layers require memory and management », et de ne pas promouvoir sans profiler. [lu, extrait ; web.dev bloqué] — [Stick to compositor-only properties and manage layer count](https://web.dev/articles/stick-to-compositor-only-properties-and-manage-layer-count)
- [Chromium, doc de conception] Blink regroupe (« squashing ») les couches qui recouvrent une couche composée, pour éviter une « layer explosion ». [lu, extrait] — [GPU Accelerated Compositing in Chrome](https://www.chromium.org/developers/design-documents/gpu-accelerated-compositing-in-chrome/)
- [web.dev, 2020, mis à jour 2022] `content-visibility: auto` saute style, layout et paint du contenu hors écran. Sur la démo de l'article, le rendu initial est ×7 plus rapide (232 ms → 30 ms), et `contain-intrinsic-size` évite les sauts au défilement. [mesuré par la source, machine de dev] — [content-visibility (source)](https://github.com/GoogleChrome/web.dev/blob/main/src/site/content/en/blog/content-visibility/index.md)
- [web.dev, 2018, mis à jour 2022] Un GIF de 3,7 Mo tombe à 551 Ko en MP4 et 341 Ko en WebM ; l'article le remplace par `<video autoplay loop muted playsinline>`. [mesuré par la source] — [Replace animated GIFs with video (source)](https://github.com/GoogleChrome/web.dev/blob/main/src/site/content/en/fast/replace-gifs-with-videos/index.md)
- [Lottie] Des tickets signalent un usage CPU élevé et des saccades, et comparent canvas et SVG sur mobile. [lu, titres des tickets] — [lottie-web #2153](https://github.com/airbnb/lottie-web/issues/2153), [#1327](https://github.com/airbnb/lottie-web/issues/1327)
- [Firefox] Le bug 1718471 s'intitule « backdrop-filter: blur is laggy when many elements are rendered ». [lu, titre du bug] — [bug 1718471](https://bugzilla.mozilla.org/show_bug.cgi?id=1718471)
- [WPE 2.54] Les animations CSS en `steps()` et `linear()` sont désormais composables. La composition est limitée aux zones endommagées, car « usually a small area of the page is changing while everything else stays still ». [lu] — [2.54 highlights](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2026-09-16-wpewebkit-2.54.md)
- [Chromium, cc] `--show-fps-counter` affiche un HUD avec les images par seconde et la mémoire GPU, et écrit aussi dans la console avec `--enable-logging=stderr --vmodule="head*=1"`. Autres interrupteurs utiles : `--show-composited-layer-borders`, `--show-surface-damage-rects`, `--show-layer-animation-bounds`, `--show-screenspace-rects`. [lu] — [cc/base/switches.cc](https://github.com/chromium/chromium/blob/main/cc/base/switches.cc)
- [Perfetto] On enregistre une trace Chrome depuis ui.perfetto.dev (« Record new trace », cible « Chrome », choix des catégories), par l'extension navigateur ou en ligne de commande. [lu] — [chrome-tracing.md](https://github.com/google/perfetto/blob/main/docs/getting-started/chrome-tracing.md)
- [Chrome ≥ 123] L'API Long Animation Frames signale les mises à jour de rendu retardées de plus de 50 ms, avec attribution des scripts. [lu, extrait] — [« LoAF has shipped »](https://developer.chrome.com/blog/loaf-has-shipped)
- [WebKit ≥ 2.46 / 2.50] Sysprof reçoit des marques et des compteurs (cadence, mémoire) pour profiler WPE. [lu] — [2.46](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2024-10-07-wpewebkit-2.46.md), [2.50](https://raw.githubusercontent.com/Igalia/wpewebkit.org/master/blog/2025-11-27-wpewebkit-2.50.md)
- [Qt WebEngine / Chromium] La page `chrome://gpu` donne le « Graphics Feature Status » (WebGL, etc.). [lu] — [qtwebengine-features.qdoc](https://github.com/qt/qtwebengine/blob/dev/src/core/doc/src/qtwebengine-features.qdoc)

### Inferences
- [déduit, calcul] La mémoire d'une couche vaut L × H × 4 o : 4096² = 64 Mio, un plein écran 4K = 33 Mo. Un `will-change` laissé sur dix blocs plein écran immobilise ~330 Mo de textures, sur une box à 3,7 Go partagés entre CPU et GPU.
- [déduit] En 4K, un fond animé (dégradé, particules, vidéo décorative plein écran) consomme toute la bande passante. Mieux vaut un fond statique et de petites zones animées : c'est ce que le suivi de dommages de WPE et la réutilisation des tuiles de Chromium récompensent.
- [déduit] Cadence : viser 30 i/s stables (sauter un rAF sur deux, ou `steps()` pour les animations discrètes) plutôt que 60 i/s non tenus. Une cadence régulière paraît plus fluide qu'une cadence irrégulière entre 27 et 40 i/s.
- [déduit] `devicePixelRatio` : sur une sortie 4K, un DPR de 2 (ou `--force-device-scale-factor`) change la mise en page, pas le nombre de pixels peints. Seul le mode de sortie 1080p, ou un buffer réduit agrandi par le plan VOP2, baisse le coût.
- [déduit] Vidéo contre GIF ou Lottie : la vidéo n'est « gratuite » que si le décodage est matériel. Sous Chromium Linux sans V4L2 ni VA-API, le cas du BSP MPP, elle est décodée en logiciel sur les A55. Il faut alors préférer des animations CSS en `transform`/`opacity`, ou un petit `<canvas>`.
- [déduit] Canvas 2D contre WebGL : WebGL passe par la voie GPU directe, et Panfrost G52 est conforme GLES 3.1. Un grand canvas 2D redessiné à chaque image coûte cher en raster. Dans les deux cas, borner la taille du canvas et éviter `getImageData` par image.
- [déduit] Images : les servir à leur taille d'affichage (pas un 4K réduit à 400 px), et les décoder avant affichage (`decoding="async"`, `img.decode()`) pour ne pas décoder sur le thread principal pendant une animation.

### Gaps
- Je n'ai trouvé aucun banc publié mesurant des règles CSS sur Mali-G52 ou Panfrost.
- Les articles web.dev et developer.chrome.com n'ont été lus que par extraits ou via les sources GitHub (sites bloqués).
- Les constats sur `backdrop-filter` et Lottie reposent sur des titres de tickets et des blogs secondaires, pas sur des mesures.
