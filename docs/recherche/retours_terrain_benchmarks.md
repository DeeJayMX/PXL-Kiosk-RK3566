# Navigateurs (Chromium d'abord) sur RK3566 / RK3568 : chiffres mesurés, retours terrain, piles des lecteurs d'affichage dynamique

*Relevé du 30/09/2026. Légende : **[mesuré par la source]** = chiffre produit par l'auteur cité · **[lu]** = affirmation, doc, spec ou discours de fabricant · **[déduit]** = mon inférence.*

*Règle de provenance : seules les sources marquées **(lu en entier)** ont été lues en entier (GitHub). Tout le reste vient du résumé du moteur de recherche, parce que la page était refusée par le proxy d'egress (HTTP 403 « Host not in allowlist ») ou n'a pas été ouverte. Confiance moindre, attribution parfois floue. Le marqueur **(extrait)** signale explicitement ces cas quand le chiffre ou l'attribution est fragile.*

*Hôtes refusés au fetch pendant ce relevé : cnx-software.com, phoronix.com, openbenchmarking.org, forum.armbian.com, forum.radxa.com, forum.manjaro.org, wiki.pine64.org, docs.radxa.com, wiki.friendlyelec.com, gitlab.freedesktop.org, chromium.googlesource.com, patchew.org, account.xibosignage.com, jeffgeerling.com, jamesachambers.com, magazinmehatronika.com, pavelp.cz, ivonblog.com, clehaxze.tw et web.archive.org (miroir refusé aussi). github.com et raw.githubusercontent.com passaient ; les sources GitHub ci-dessous ont été lues en entier. api.github.com a été refusé (« GitHub access to this repository is not enabled for this session ») et je n'ai pas insisté.*

*Rappel de périmètre : RK3566 et RK3568 = Cortex-A55 ×4 + Mali-G52 « 2EE » (Bifrost, ID 0x7402). RK3588 = Mali-G610 (Valhall) et un autre décodeur. Tout chiffre RK3588 cité ici est marqué **NON TRANSPOSABLE**.*

## Q1 — Chiffres publiés sur cartes et box RK3566/RK3568, ventilés par pile

### Takeaway
Il existe **très peu de chiffres navigateur publiés** sur RK3566/RK3568. Le seul relevé complet de CNX Software (ODROID-M1S, RK3566, BSP 5.10 + libmali Wayland, 02/2024) donne :
- glmark2-es2-wayland ≈ 496 ;
- **WebGL Aquarium à 1 fps** ;
- **YouTube 4K30 à plus de 50 % d'images perdues**, et le 1080p30 guère mieux ;
- le navigateur n'y a ni WebGL ni décodage matériel.

Partout ailleurs, le même motif revient : **GPU correct en natif** (glmark2 ~400-500 sous Wayland/Panfrost), **navigateur sans décodage vidéo matériel** tant qu'on n'utilise pas un Chromium patché (libv4l-rkmpp sur noyau BSP) ou un chemin V4L2 stateless encore expérimental sur mainline. Aucun MotionMark, Basemark ni Speedometer 3 n'a été trouvé pour ces puces.

### Cited Findings

#### Tableau récapitulatif des chiffres trouvés

| Puce | Carte | Pile (OS / noyau / GPU / navigateur) | Chiffre | Date | Tag |
|---|---|---|---|---|---|
| RK3566 | ODROID-M1S | Ubuntu 20.04 Hardkernel, noyau 5.10 BSP, libmali Bifrost Wayland ; navigateur : version non relevée | glmark2-es2-wayland **496** (RPi 5 : 2036) | 02/2024 | [mesuré par la source] (extrait) |
| RK3566 | ODROID-M1S | idem | WebGL Aquarium **1 fps** à 500 poissons, dans Chromium comme dans Firefox | 02/2024 | [mesuré par la source] (extrait) |
| RK3566 | ODROID-M1S | idem | YouTube 4K30 : **> 50 % d'images perdues** ; 1080p30 « not much better » | 02/2024 | [mesuré par la source] (extrait) |
| RK3566 | ODROID-M1S | idem | Speedometer 2.0 : Chromium ≈ **+30 %** sur Firefox (≈ 11 runs/min d'après un extrait, **non vérifié**) | 02/2024 | [mesuré par la source] (extrait) |
| RK3568 | Youyeetoo YY3568 | Lubuntu 20.04 constructeur (BSP) | glmark2 **115** ; une vidéo YouTube dans Chromium « no issues » (résolution non relevée) | 09/2023 | [mesuré par la source] (extrait) |
| RK3566 | Quartz64 B / SOQuartz | mainline + Panfrost, KDE Plasma Wayland à 4K / GNOME | glmark2 **> 400** (01/2023) ; glmark2-wayland **> 500** (03/2023) | 2023 | [mesuré par la source] (extrait) |
| RK3566 | inconnu (forum Manjaro) | inconnue | glmark2-es2 **150** pour un utilisateur, **500** (wayland) pour un autre | ? | [mesuré par la source] (extrait) |
| RK3566 | inconnu (forum Armbian) | passage à Mesa **25.0.1-2** | glmark2-es2-wayland **450+ → 200** | 2025 | [mesuré par la source] (extrait) |
| RK3566 | NanoPi R3S LTS (2 Go) | Armbian 26.11 trunk, noyau 6.18.50, lecteur Anthias Qt6 (ffmpeg logiciel) | H.264 1080p à **2,56×** le temps réel, HEVC 1080p à **1,15×** ; CPU **200-240 %/400 %** à 1080p30, **100-130 %** à 720p30 ; RSS ≈ **990 Mio** | 09/2026 | [mesuré par la source] |
| RK3566 | Orange Pi 3B | noyau **6.9** + rkvdec2 (patch), Chromium (build non précisé) | **4K H.264 décodé en matériel** dans Chromium (aucun fps publié) | 06/2024 | [mesuré par la source] (extrait) |
| RK3566 | Radxa Zero 3W | Debian 12, noyau **6.1.84-10-rk2410** (BSP Radxa), **Mesa 24.2 git (PPA oibaf)**, glmark2 en 1280×720 et 1920×1080 | chiffres **inaccessibles** (openbenchmarking.org bloqué) | 26/12/2025 [déduit de l'ID] | [lu] (extrait) |

#### A. Noyau BSP Rockchip + libmali (piles constructeur)

**ODROID-M1S (RK3566)** — [revue CNX Software partie 2, 09/02/2024](https://www.cnx-software.com/2024/02/09/odroid-m1s-review-ubuntu-20-04-benchmarks-features-testing/), (extrait) :
- glmark2-es2-wayland = **496** sur l'écran ODROID-Vu8S 8 pouces, « slightly lower than the Raspberry Pi 4 », contre 2036 pour le Raspberry Pi 5. [mesuré par la source]
- WebGL Aquarium à **1 fps** avec 500 poissons, sous Chromium comme sous Firefox ; « the official image doesn't support WebGL ». [mesuré par la source]
- YouTube 4K30 « unwatchable », **plus de 50 % d'images perdues** faute d'accélération matérielle dans le navigateur ; le 1080p30 n'est « not much better ». [mesuré par la source]
- Speedometer 2.0 : Chromium environ **30 % au-dessus** de Firefox. Un autre extrait parle de « 11 runs per minute » ; valeur **non vérifiée**, l'extrait mélangeait les chiffres. [mesuré par la source]
- Verdict de l'auteur : le décodage vidéo matériel marche sous GStreamer, la 3D marche sous glmark2-es2, mais « neither has been implemented in Chromium ». [lu]

**Pile de cette image M1S** : Ubuntu 20.04, noyau **5.10 BSP**, pilote Mali Bifrost propriétaire **Wayland seulement** (`libmali-bifrost-g52-r25p0-wayland`), bureau GNOME Wayland. [lu] (extrait) — sources : [wiki ODROID-M1S, image Ubuntu 20231030](https://wiki.odroid.com/odroid-m1s/os_images/ubuntu/20231030) ; [forum ODROID, Ubuntu 22.04 sur M1S](https://forum.odroid.com/viewtopic.php?t=48030). ⚠️ Pile obsolète : Ubuntu 20.04 et noyau 5.10.

**Youyeetoo YY3568 (RK3568)** — [revue CNX, 21/09/2023](https://www.cnx-software.com/2023/09/21/review-rockchip-rk3568-sbc-lubuntu-20-04-rknpu2-ai-sdk/), (extrait) :
- glmark2 = **115 points**, « a bit on the low side, but 3D graphics hardware acceleration is enabled ». [mesuré par la source]
- Une vidéo YouTube lue dans Chromium : « no issues with video and audio playback ». Résolution non donnée dans l'extrait. [mesuré par la source]
- La [partie 1 de la revue (Android 11, 25/08/2023)](https://www.cnx-software.com/2023/08/25/youyeetoo-yy3568-devkit-review-part-1-unboxing-specifications-and-android-11-testing/) existe ; aucun chiffre récupéré.

**glmark2 plafonné par la vsync sous libmali** : un utilisateur signale des tests glmark2-es2 « locked to vsync » avec libmali sur RK3568. Cela suffirait à expliquer un 115 face à 496. [lu] (extrait ; attribution ambiguë entre [le fil Radxa « Rock 3A/3B RK3568 GPU Drivers »](https://forum.radxa.com/t/rock-3a-3b-rk3568-gpu-drivers/20646) et [le forum ODROID « Accellerated X11 driver for M1 »](https://forum.odroid.com/viewtopic.php?t=44348)). Dans le même fil Radxa, un utilisateur n'obtient **aucune accélération GL/GLES sur ROCK 3A (RK3568) avec les images Armbian Debian**, en essayant libmali puis Panfrost. [lu] (extrait)

**Chromium des SDK et images constructeur (RK356x)** :
- **SDK Linux Rockchip RK356x** ([notes de version, miroir TinkerBoard](https://github.com/TinkerBoard/rockchip-linux-bsp-internal_doc-en/blob/linux5.10-rk356x/RK3566_RK3568_Linux4.19_SDK_Note.md)) [lu] (lu en entier) :
  - v0.2.0 (26/02/2021) : Chromium 87.0.4280.141 ;
  - v1.0.0 (10/04/2021) : Chromium 88.0.4324.150 ;
  - v1.2.0 (30/09/2021) : `chromium-x11` 91.0.4472.164 ;
  - v1.3.0 (20/06/2022) : **Chromium-wayland 101.0.4951.54** ;
  - v1.4.0 (20/07/2023) : aucune mise à jour de Chromium.
  - ⚠️ Branches d'une obsolescence critique en sécurité : Chromium 87 à 101.
- **Weston du SDK Buildroot** : Weston 10 en backend DRM par défaut, multi-écran, hot-plug, mise à l'échelle par le VOP et par la RGA. [lu] — [résumé de la recherche SDK](https://dl.xkwy2018.com/downloads/RK3568/RK356X/Rockchip_RK356X_Linux_SDK_Release_V1.3.0_20220620_EN.pdf) (extrait) ; [Weston patché par Rockchip, dépôt JeffyCN](https://github.com/JeffyCN/weston).
- **FriendlyELEC RK3568** (Debian 11 / Ubuntu 20, noyau `linux-5.10-gen-rkr9`) : Chromium passé en **130 stable**, avec mise à jour de `libv4l-rkmpp`, `mpp`, `xserver`, `libmali`. [lu] (extrait) — [journal des mises à jour RK3568](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3568-UpdateLog). Date non relevée, postérieure à 10/2024 puisque Chromium 130 est sorti en 10/2024. [déduit]
- **Firefly (ROC-RK3568-PC, AIO-3568J)** : le bureau Ubuntu « uses GPU + RGA for 2D acceleration », OpenGL et OpenCL sur le Mali, « video hard codec support based on Rockchip VPU + Mpp » ; Ubuntu 20.04 est la version maintenue. [lu] (extrait) — [wiki Firefly, bureau Ubuntu](https://wiki.t-firefly.com/en/ROC-RK3568-PC/ubuntu_desktop_support.html)

**Comment ces Chromium obtiennent le décodage matériel** : par `libv4l-rkmpp`, « a rockchip-mpp V4L2 wrapper plugin for chromium V4L2 VDA/VEA ». [lu] (extrait) — [README JeffyCN/libv4l-rkmpp](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/README.md). Limites écrites par le mainteneur :
- décodeur seulement ;
- mémoire `V4L2_MEMORY_MMAP` / `USERPTR` seulement ;
- **« Switching resolutions would not work »**, faute d'événement POLLPRI ;
- l'erreur « Failed creating a VDA » impose le lien `/usr/lib/libv4l2.so`.

**PPA « rockchip-multimedia »** (Jianfeng Liu / amazingfate) : il fournit un `chromium-browser` accéléré, « maintained for rockchip legacy kernel », **testé sur noyau 5.10 avec RK3568 et RK3588**. [lu] (extrait) — [Launchpad](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia) ; [présentation sur le forum Radxa](https://forum.radxa.com/t/introduction-to-rockchip-multimedia-ppa-for-ubuntu-jammy/14537)

**ubuntu-rockchip (Joshua-Riek), [discussion #271](https://github.com/Joshua-Riek/ubuntu-rockchip/discussions/271)** [lu] (lu en entier) :
- le mainteneur : « Chromium requires a hack to support the GPU on this platform… I use a custom build » ;
- version livrée **110.0.5481.4**, périmée ;
- un Chromium standard **≥ 115 n'a pas le décodage matériel**, et v115 a rendu le portage difficile ;
- un Chromium installé en Flatpak n'hérite pas du décodage matériel.

#### B. Noyau BSP 6.1 + Panfrost (la famille de la pile du labo)

**Radxa Zero 3W (RK3566)** — [OpenBenchmarking 2512263-NE-ARMMALIG569](https://openbenchmarking.org/result/2512263-NE-ARMMALIG569) :
- noyau **6.1.84-10-rk2410-nocsf** (BSP Radxa), **Mesa 24.2~git2407100600 (PPA oibaf)**, Debian 12 ;
- glmark2 en 1280×720 et 1920×1080 ; le résumé indique que certains tests Vulkan n'ont rendu aucun résultat.
- [lu] (extrait) — valeurs numériques **inaccessibles**, le site est bloqué par le proxy.

**Armbian, [PR linux-rockchip #500](https://github.com/armbian/linux-rockchip/pull/500) « Add support for X88 PRO RK3566 TV box »** (ouverte le 11/06/2026, fusionnée le 15/07/2026, branche vendeur **`rk-6.1-rkr5.1`**) [lu] (lu en entier) :
- déclarés fonctionnels : HDMI, **Mali-G52 via Panfrost**, RGA, blocs VPU/MPP, RKNPU, Ethernet gigabit, Wi-Fi SDIO ;
- **problèmes connus** : « DMC/devfreq governor currently fails to initialize », « **HDMI EDID/DDC may report warnings on some displays** », régulateurs incomplets.

**ophub (amlogic-s9xxx-armbian)** : la X88Pro20 (RK3566) figure avec `rk3566-x88pro20.dtb`, sous les branches de noyau **`stable`** (mainline) **et `rk35xx`** (BSP Rockchip). Autres RK3566 listées : Panther-X2, Station-M2, Orange-Pi-3B, Rock-3C. [lu] (lu en entier) — [README ophub](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/README.md) ; ⚠️ la signification exacte des deux branches est [déduit].

**Radxa Zero 3W, [issue ubuntu-rockchip #692](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/692)** (05/04/2024) [lu] (lu en entier) :
- Chromium **sans accélération vidéo GPU** ;
- journaux : « Failed to export buffer to dma_buf », « Failed to query video capabilities: Inappropriate ioctl for device », « GetVSyncParametersIfAvailable() failed », échecs d'initialisation EGL et Vulkan ;
- close sans réponse du mainteneur (« not planned ») ; dépôt archivé le 29/04/2026.

**Radxa Zero 3W, spécification** : un seul micro-HDMI, **1080p60 maximum** alors que le décodage monte à 4K60. [lu] — [page produit Radxa](https://radxa.com/products/zeros/zero3w/) ; [product brief](https://dl.radxa.com/zero3/docs/hw/3w/radxa_zero_3w_product_brief.pdf).

#### C. Mainline + Panfrost

**Quartz64 / SOQuartz (RK3566)** [mesuré par la source] (extrait) — [contenus de balbes150 sur le forum Armbian](https://forum.armbian.com/profile/1215-balbes150/content/page/14/?type=forums_topic_post) :
- glmark2 **> 400** sous KDE Plasma Wayland **en 4K** (janvier 2023) ;
- SOQuartz + GNOME, glmark2-wayland **> 500** (mars 2023).

**Plebian (Debian bookworm pour Quartz64 et SOQuartz), [RUNNING.md](https://github.com/Plebian-Linux/quartz64-images/blob/main/RUNNING.md)** [lu] (lu en entier) :
- « If you want to get graphics acceleration, you must use **Wayland**. Panfrost is not really tested on X11 » ;
- Firefox avec `MOZ_ENABLE_WAYLAND=1` et WebRender ;
- le Hantro ne décode que VP8, MPEG-2 et H.264 **jusqu'en 1080p** ; ni H.264 4K, ni VP9, ni HEVC ;
- v4l2-requests : « limited browser support ». FFmpeg upstream ne le prenait pas en charge ;
- seuls certains modes HDMI fonctionnent (dont 1080p60), et **la 4K n'est pas prise en charge**.
- ⚠️ Document non daté (ère 2022-2023) ; la partie HDMI est périmée depuis Linux 6.12 (voir Q4).

**PineTab2 (RK3566), mainline** [lu] (extrait) — sources 2023 : [Ivon, « My setups of PineTab 2 »](https://ivonblog.com/en-us/posts/my-pinetab-2-setup/) ; [« Hardware accelerated playback on PineTab 2 », 17/09/2023](https://clehaxze.tw/gemlog/2023/09-17-hardware-accelerated-playback-on-pinetab2.gmi) :
- « Firefox and Chromium run painfully slow » ;
- le noyau mainline de l'époque ne décodait ni HEVC ni VP9, formats par défaut de YouTube, donc YouTube passe en logiciel ;
- en revanche, 1080p60 « perfectly smooth » en accélération matérielle dans **mpv** configuré, sur formats compatibles.

**Orange Pi 3B (RK3566), noyau 6.9 + rkvdec2** : Jianfeng Liu confirme que le pilote rkvdec2 fonctionne sur RK356x et que « **Chromium can decode 4K H264 video with hardware acceleration** ». [mesuré par la source] (extrait) — [LKML, rkvdec2, juin 2024](https://lkml.iu.edu/2406.3/03806.html). Aucun chiffre d'images perdues publié.

**Anthias sur NanoPi R3S LTS (RK3566, 2 Go)** — [PR Screenly/Anthias #3332](https://github.com/Screenly/Anthias/pull/3332), fusionnée le 15/09/2026 [mesuré par la source] (lu en entier) :
- conditions : image `Armbian_community_26.11.0-trunk.44_Nanopi-r3s_trixie_current_6.18.50`, relevée dans [la PR #3331](https://github.com/Screenly/Anthias/pull/3331) ; clips 1080p30 bruités de 20 s ;
- rendu Qt6 Multimedia (`libffmpegmediaplugin.so`), **décodage logiciel libavcodec seulement** : les wrappers stateful `*_v4l2m2m` ne correspondent pas au rkvdec stateless ;
- H.264 1080p à **2,56× le temps réel**, accepté ; HEVC 1080p à **1,15×**, rejeté ; H.264 plafonné à 1920×1080 ;
- CPU du conteneur lecteur : **200-240 % sur 400 %** en 1080p30, **100-130 %** en 720p30 ; RSS ≈ **990 Mio** pour un plafond de 1,54 Gio ;
- pertes d'images **non mesurées** : « Neither the Qt path nor this board exposes a frame-drop counter ».

[FAQ Anthias](https://anthias.screenly.io/faq/) : « images and web pages are fine, **720p video is comfortable**, and **1080p plays but uses well over half the board and drops frames** on demanding content ». [lu] (extrait)

#### D. Android (TV box et mini-PC RK3566)

**Zidoo M6 (RK3566, Android 11)** — [CNX, 15/10/2021](https://www.cnx-software.com/2021/10/15/rockchip-rk3566-benchmarks-in-android-11-zidoo-m6/) et [aperçu du 17/10/2021](https://www.cnx-software.com/2021/10/17/zidoo-m6-review-android-11/), (extrait) :
- « video output can be set to 4K, but the **UI is still limited to 1920×1080** ». [lu]
- score 3D du Mali-G52 **11 132** contre 6 292 pour l'Allwinner H6 (Mali-T720), vraisemblablement Antutu 6. [mesuré par la source]
- ⚠️ 2021, firmware Android 11 d'origine.

**X88 Pro 20 (RK3566)** — [revue AndroidPCtv](https://androidpctv.com/review-x88-pro-20-opinion/), 2021, (extrait) [lu] :
- mémoire vive annoncée « 4/8 GB DDR3 » ;
- **pas de HDR** ;
- vidéos 4K lues « without any problems », mais « YouTube 4K resolution may have some delay ».

**H96 Max / H96 Max V56 (RK3566)** : discours identique, 4K via HDMI 2.0a, « YouTube 4K may have some delay ». La V56 tourne sous Android 12. [lu] — [TVPAO, revue H96 Max V56](https://tvpao.com/h96-max-v56-smart-tv-box-review/) ; [CNX, 04/03/2021](https://www.cnx-software.com/2021/03/04/rockchip-rk3566-tv-box-h96-max-android-11/)

**Mécanique de WebView** (utile pour lire le plafond de ~27 fps mesuré au labo) :
- Le fil android-webview-dev discute d'étendre la « external video surface » (un SurfaceView) à **toutes** les vidéos HTML5 en ligne. Il constate qu'un SurfaceView ne peut pas honorer tout le HTML et le CSS, d'où un usage réservé à l'EME, « a compromise that WebView developers aren't especially happy with ». [lu] (extrait) — [fil « Using external video surface for all HTML5 inline videos »](https://groups.google.com/a/chromium.org/g/android-webview-dev/c/hS_dNQXQLcY)
- Hors EME, la vidéo en ligne de WebView passe donc par une texture composée par GL. [déduit]
- Chrome est passé de TextureView à **SurfaceView** pour sa surface de composition. Un TextureView est « always composited using GL », un SurfaceView peut être porté par un **plan overlay matériel**. [lu] (extrait) — [graphics-dev « Use TextureView as compositing surface on Android? »](https://groups.google.com/a/chromium.org/g/graphics-dev/c/Z0yE-PWQXc4) ; [AOSP, TextureView](https://source.android.com/docs/core/graphics/arch-tv)

#### E. Mises en garde sur glmark2

- « glmark2 is not a great benchmark… FPS numbers are so high that it mostly tests the display server/compositor and job submission latency ». [lu] (extrait) — [forum Radxa, fil Zero2](https://forum.radxa.com/t/talk-about-zero2/9566?page=4). Le fil porte sur un Amlogic, mais la remarque est générale.
- Écarts de 150 à 500 selon la pile, et une régression **450+ → 200 après Mesa 25.0.1-2** sur RK3566. [mesuré par la source] (extrait) — [forum Manjaro](https://forum.manjaro.org/t/can-someone-share-rk3566-gpu-benchmark/126583) ; [contenus de DreamDreams sur le forum Armbian](https://forum.armbian.com/profile/3921-dreamdreams/content/?type=forums_topic_post)

### Inferences
- [déduit] **Pour la X88Pro20 du labo (BSP 6.1.141 + Panfrost + Mesa 22.3.6)**, les sources publiées annoncent :
  - composition GPU sous Wayland plausible ;
  - aucun décodage vidéo matériel dans le Chromium Debian standard ;
  - un glmark2 qui devrait tomber dans la fourchette 400-500 (Wayland, 1080p) si la pile est saine.

  **Aucune source ne publie de chiffre navigateur pour cette combinaison** : les mesures du labo seraient une première.
- [déduit] Le résultat Android du labo s'emboîte avec la mécanique documentée : ~27 fps en WebView et en Cromite contre 60 fps et 0 % de GPU en MediaCodec → SurfaceView. La vidéo d'une page passe par une composition GL (TextureView/SurfaceTexture), la vidéo native par un plan overlay.

  Le même clivage se retrouve sous Linux :
  - lecteurs natifs (mpv, GStreamer + MPP) fluides ;
  - navigateur en décodage logiciel (M1S : > 50 % de pertes en 4K30 ; Anthias : 1080p limite).
- [déduit] Le 115 du YY3568 face au 496 du M1S ne compare probablement pas des GPU : il compare X11 + libmali plafonné par la vsync à Wayland + libmali. Les chiffres glmark2 de RK356x ne sont comparables que **à pile identique**.

### Gaps
- **Aucun MotionMark, Basemark Web ni Speedometer 3** trouvé pour RK3566/RK3568, sous Linux comme sous Android. Le seul Speedometer (2.0, M1S) n'est connu que de manière relative (+30 %).
- **Aucun fps WebGL Aquarium avec accélération GPU effective** sur RK3566/RK3568. Une vidéo constructeur [« RK3576 vs RK3566 vs RK3588: WebGL Aquarium & Architecture 3D » (18/11/2025)](https://www.youtube.com/watch?v=0jk0oH7VAn8) existe, mais aucun chiffre n'a pu être extrait (YouTube n'est pas lisible ici).
- Valeurs glmark2 de l'entrée OpenBenchmarking Radxa Zero 3W : inaccessibles (proxy).
- Versions exactes de Chromium et de Firefox des revues CNX : inconnues (pages bloquées).
- Aucune mesure tierce publiée du **taux d'images de la vidéo en WebView ou en Chrome Android** sur RK3566.
- Rien trouvé de chiffré pour Firefly Station M2 / ROC-RK3566-PC, Radxa ROCK 3A/3B/3C/3E, Radxa Zero 3E, Banana Pi (RK3568) ni pour une box H96 Max V56 sous Linux.

## Q2 — Ce que disent les relecteurs de référence (CNX, ExplainingComputers, Geerling, Phoronix/OpenBenchmarking, Collabora)

### Takeaway
- **CNX Software** est la seule source à publier des chiffres navigateur sur RK356x : M1S (2024), YY3568 (2023), Purple Pi OH (2024), Zidoo M6 (2021), avec une conclusion récurrente sur Linux : « pas d'accélération dans le navigateur ».
- **ExplainingComputers** et **Jeff Geerling** ont couvert ROCK 3C, Orange Pi 3B, SOQuartz et Radxa CM3 sans chiffre navigateur retrouvé.
- **Phoronix** documente surtout le mainline (4K@60 HDMI arrivé avec Linux 6.12, testé sur RK3568).
- **Collabora** a certifié Panfrost GLES 3.1 sur Mali-G52 (2021) et pousse en 2025-2026 le décodeur VDPU346 des RK356x en mainline.

### Cited Findings

**CNX Software** (pages bloquées, tout est en extrait) :
- **ODROID-M1S (RK3566)**, 02/2024 : voir Q1 — glmark2-es2-wayland 496, WebGL 1 fps, YouTube 4K30 à plus de 50 % de pertes, pas d'accélération dans le navigateur. [mesuré par la source] — [lien](https://www.cnx-software.com/2024/02/09/odroid-m1s-review-ubuntu-20-04-benchmarks-features-testing/)
- **Purple Pi OH / OH Pro (RK3566, 2 Go/16 Go et 4 Go/32 Go)**, 20/03/2024 [mesuré par la source] — [lien](https://www.cnx-software.com/2024/03/20/review-purple-pi-oh-2gb-16gb-purple-pi-oh-pro-4gb-32gb-wireless-tag/) :
  - YouTube 4K lu en **720p, 1080p, 1440p et 2160p**, pour mesurer la consommation ;
  - la version Pro consomme **10 à 25 % de plus**, attribué à la mémoire plus grande.
  - Taux d'images non récupéré.
- **Youyeetoo YY3568 (RK3568)**, 09/2023 : glmark2 115 ; YouTube dans Chromium sans problème (résolution inconnue). [mesuré par la source] — [lien](https://www.cnx-software.com/2023/09/21/review-rockchip-rk3568-sbc-lubuntu-20-04-rknpu2-ai-sdk/)
- **Zidoo M6 (RK3566, Android 11)**, 10/2021 : interface limitée à 1080p même en sortie 4K. [lu] — [lien](https://www.cnx-software.com/2021/10/17/zidoo-m6-review-android-11/)

**ExplainingComputers** [lu] :
- revue du **ROCK 3C (RK3566)**, 11/06/2023 : démonstrations Debian et Ubuntu, sysbench contre Pi 3B+ et Pi 4 — [YouTube](https://www.youtube.com/watch?v=M6OX8HUmK3s) ; [DesignSpark/RS](https://www.rs-online.com/designspark/explaining-computers-reviews-rock-3c) ;
- l'extrait RS indique « HDMI 2.0 port supporting displays **up to 1080p** » pour le ROCK 3C, **à vérifier** ;
- revue de l'**Orange Pi 3B**, 2023 : Debian et Orange Pi OS, stockage comparé au ROCK 3C — [Class Central](https://www.classcentral.com/course/youtube-orange-pi-3b-low-cost-m-2-arm-sbc-207690) ;
- **aucun chiffre navigateur** récupéré.

**Jeff Geerling** [lu] :
- SOQuartz (RK3566) et Radxa CM3 examinés comme remplaçants du CM4 : compatibles broche à broche, mais **un seul HDMI** là où le CM4 en a deux, logiciel « early » ([blog, 2021](https://www.jeffgeerling.com/blog/2021/pine64-and-radxas-new-pi-cm4-compatible-boards/)) ;
- les issues GitHub [#336 SOQuartz (05/12/2021)](https://github.com/geerlingguy/raspberry-pi-pcie-devices/issues/336) et [#327 Radxa CM3](https://github.com/geerlingguy/raspberry-pi-pcie-devices/issues/327) ne contiennent **aucun résultat** GPU ou navigateur, du moins dans la partie restituée (lu en entier).

**Phoronix** [lu] (extrait) :
- « For **Linux 6.12**, the Rockchip HDMI encoder support will now be able to power **4K displays at 60Hz**… Last year the driver was extended to be able to drive **4K@30**… tested on the Rockchip RK3399 and **RK3568** » — [Phoronix](https://www.phoronix.com/news/Rockchip-Linux-6.12-4K-60Hz)
- Série correspondante de Jonas Karlman (Kwiboo) : plafond TMDS porté à **594 MHz** ; patch 12 « Enable 4K@60Hz mode on RK3399 and RK356x », issu de noyaux ChromeOS et vendeur utilisés « in LibreELEC distro for the past few years » — [dri-devel, patch 12/13](https://www.mail-archive.com/dri-devel@lists.freedesktop.org/msg497616.html) ; [v2, 09/2024](https://patchew.org/linux/20240908145511.3331451-1-jonas@kwiboo.se/)

**OpenBenchmarking** : entrée Radxa Zero 3W (Debian 12, noyau 6.1.84 rk2410, Mesa 24.2 oibaf) ; valeurs non accessibles. [lu] (extrait) — [lien](https://openbenchmarking.org/result/2512263-NE-ARMMALIG569)

**Collabora et Mesa** :
- « **Panfrost achieves OpenGL ES 3.1 conformance on Mali-G52** » (2021) ; Panfrost est conforme sur Mali-G52, G57 et G610. [lu] — [Collabora](https://www.collabora.com/news-and-blog/news-and-events/panfrost-achieves-opengl-es-3.1-conformance-on-mali-g52.html) ; [documentation Mesa, Panfrost](https://docs.mesa3d.org/drivers/panfrost.html)
- Identifiant Mesa « G52 1-Core-2EE (RK3568/RK3566) », ID 0x7402. [lu] — [mesa-commit](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg116463.html)
- Décodeur des RK356x en mainline (**VDPU346**) [lu] (extrait) — [Pine64, Mainline Hardware Decoding](https://pine64.org/documentation/General/Mainline_Hardware_Decoding/) ; [série v2, 12/2025](https://ratatoskr.run/linux-media/2025/12/3346401/t) ; [série v3, 01/2026](https://ratatoskr.run/linux-devicetree/2026/01/3361486/t) :
  - variante mono-cœur du VDPU381, « **limited to 4K60** » et à **H.264 L5.1** ;
  - séries 12/2025 et 01/2026 pour H.264, HEVC et VP9, dépendantes du support VDPU381 ;
  - VP9 jusqu'en 1080p étendu aux RK356x, en revue en 08/2025.
- Le VDPU381 des RK3588/RK3576 a été fusionné upstream en 2026. **NON TRANSPOSABLE** aux RK356x. [lu] — [Collabora](https://www.collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html) ; [CNX, 27/02/2026](https://www.cnx-software.com/2026/02/27/rockchip-rk3588-rk3576-h-264-and-h-265-video-decoders-mainline-linux/)

### Inferences
- [déduit] Sur mainline RK356x à l'automne 2026, la **sortie** 4K60 est acquise depuis 6.12, mais le **décodage** HEVC/VP9/H.264-4K dépend de séries VDPU346 dont la fusion n'est pas établie ici. Un Chromium mainline sur RK3566 reste donc, par défaut, en décodage logiciel au-delà du H.264 1080p du Hantro.
- [déduit] L'absence de chiffres navigateur chez Geerling et ExplainingComputers suggère que RK356x n'est pas traité en poste de bureau ou multimédia par ces relecteurs. Le peu de chiffres navigateur vient de CNX.

### Gaps
- Aucun article Phoronix de benchmark navigateur ou Panfrost dédié au RK3566/RK3568 n'a été trouvé.
- Aucune démonstration Collabora de Chromium sur RK356x.
- Contenu chiffré des vidéos ExplainingComputers : non accessible.
- Statut de fusion des séries VDPU346 au 30/09/2026 : non établi.

## Q3 — Affichage dynamique sur RK3566/RK3568 : produits, plateformes et piles réellement utilisées

### Takeaway
Le **matériel d'affichage dynamique** RK3566/RK3568 vendu en série tourne presque exclusivement sous **Android 11** (parfois 12 ou 13). La vidéo passe par le lecteur natif et le HTML par une **WebView** ; les promesses « 4K@60 » portent sur le décodeur natif, pas sur la vidéo dans une page.

Côté Linux, les deux piles ouvertes documentées sur RK3566 en 2026 plafonnent au 720p confortable et au 1080p limite :
- **Anthias** (Qt6 WebEngine + Qt Multimedia en décodage logiciel) ;
- les nouveaux **lecteurs Xibo open source** (Chromium kiosque, Electron, Qt6 WebEngine, aarch64).

Aucun déploiement **WPE WebKit** sur RK356x n'a été trouvé.

### Cited Findings

**Matériel commercial (tout est [lu], discours de fabricant)** :
- **Geniatech APC390K** — [boutique Geniatech](https://shop.geniatech.com/product/apc390k/) ; [fiche Geniatech](https://www.geniatech.com/product/apc390k/) :
  - RK3566, **Android 11**, 2 Go LPDDR4 (4 ou 8 en option), 8 Go eMMC (jusqu'à 128) ;
  - **sortie HDMI 4K60**, **entrée HDMI 4K30**, HDCP 1.4/2.2, incrustation (PiP), 4G en option.
  - Une variante est vendue sous le nom **« NoviSign APC390K »** ([boutique Geniatech US](https://shop.geniatech.us/product/novisign-apc390k/)) : c'est vraisemblablement un partenariat avec l'éditeur NoviSign. [déduit]
- **Ranboda** — boîtiers RK3566 sous **Android 11** « Digital Signage Media Player with RTC », avec la promesse « H.265, H.264, VP9 decoding up to 4K@60fps ». [lu] — [produit R117](https://www.ranboda.com/product/r117-rk3566-android-tv-box/) ; [page solution RK3566](https://www.ranboda.com/rockchip-rk3566-solution/)
- **SUNCHIP** — cartes RK3566 et RK3568 pour kiosque et affichage, Android. [lu] — [RK3566](https://www.sunchip-tech.com/products/rk3566-android-board/) ; [RK3568](https://www.sunchip-tech.com/products/rk3568-android-board/)
- **Portworld** — écrans d'affichage RK3568 « with 4K output ». [lu] — [lien](https://portworld-solu.com/rockchip-rk3568-based-digital-signage-display-with-4k-output/)
- **RKM V7** (RK3568) — Android 11 avec options propres à l'affichage : rotation d'écran, mise sous tension à distance. [lu] (extrait) — [guide Alibaba](https://electronics.alibaba.com/buyingguides/android-rockchip-mobile-guide-rk3576-vs-rk3588)
- **Tanix / SZTomato** — revendiquent un fonctionnement 24/7 « without overheating » et une lecture 4K « smooth and consistent » en affichage dynamique. [lu] — marketing non chiffré : [Tanix](https://www.tanixtvbox.com/rockchip-rk3566-android-tv-box-performance-guide/) ; [SZTomato](https://www.sztomato.com/news/Rockchip-RK3566-SoC-Explained-1-TOPS-NPU-4K-Video-and-Flexible-Embedded-Applications.html)
- **Firefly** (AIO-3568J, ROC-RK3568-PC) — Android 11 et Ubuntu 18.04/20.04, bureau accéléré GPU + RGA + MPP. [lu] — [AIO-3568J](https://en.t-firefly.com/product/industry/aio3568j) ; [wiki Firefly](https://wiki.t-firefly.com/en/ROC-RK3568-PC/ubuntu_desktop_support.html)
- **SDK officiel Rockchip RK3566** — Linux 4.19/5.10 et Android 11/12. [lu] — [SZTomato](https://www.sztomato.com/news/Rockchip-RK3566-SoC-Explained-1-TOPS-NPU-4K-Video-and-Flexible-Embedded-Applications.html)
- **Boardcon** suit dans son dépôt BSP RK3566 le correctif Anthias ; il cite des clients d'affichage « in elevators, trains, and transit systems » et un motif de capacités « applicable to RK3568/RK3588 ». [lu] (lu en entier) — [Owen-Boardcon/bsp-rk3566 #13, 18/09/2026](https://github.com/Owen-Boardcon/bsp-rk3566/issues/13)

**Plateformes logicielles** :
- **Xibo pour Android** : « uses a web view to play any embedded or web page media ». La vidéo HTML5 y dépend de la WebView ; Xibo dit l'avoir vue fonctionner « on very few devices… down to the firmware on the device and the implementation of the web view ». [lu] — [Xibo, HTML5 Video on Android](https://account.xibosignage.com/docs/setup/html5-video-on-android) ; [fil communauté](https://community.xibo.org.uk/t/html5-video-on-android/4370)
- **Xibo et H.265** : la lecture passe par un **surface view**, au prix de captures d'écran CMS **noires**. [lu] — [communauté Xibo, « H265 Videos & Texture View »](https://community.xibo.org.uk/t/h265-videos-texture-view/15391)
- **Xibo pour Linux** (snap) : « optimized for x86 » ; un portage ARM serait limité au texte et aux images, faute de liaison avec le décodeur matériel. Une demande ARM de 2024 cite le RK3588 et l'Orange Pi 5 Pro. [lu] — [communauté Xibo, 2024](https://community.xibo.org.uk/t/arm-based-player-for-linux-2024-revisit/31878) ; [CNX, 2019](https://www.cnx-software.com/2019/06/04/xibo-player-for-linux-released-open-source-digital-signage-player/)
- **Nouveaux lecteurs Xibo open source (organisation xiboplayer, dépôts actifs en 09/2026)** [lu] (lu en entier) — [xiboplayer](https://github.com/xiboplayer) ; [xiboplayer-kiosk](https://github.com/xiboplayer/xiboplayer-kiosk) :
  - variantes : Electron (« GPU acceleration »), **Chromium kiosque** (« uses system Chromium, ~5 MB »), PWA, **arexibo** (Rust + **Qt6 WebEngine**), et Kiosk OS (**GNOME Kiosk** + « session holder… health monitoring and auto-restart ») ;
  - architectures **x86_64 et aarch64** (Raspberry Pi 4 et 5 citées) ;
  - accélération « VA-API GPU acceleration + mesa-dri fallback » ;
  - FPS, mémoire et layout observables par le protocole DevTools (ports 9222/9223).
- **Anthias (Screenly OSS)** [lu] — [README](https://github.com/Screenly/Anthias/blob/master/README.md) ; [FAQ](https://anthias.screenly.io/faq/) :
  - l'installeur traite tout hôte ARM 64 bits non-Pi comme `arm64` (Armbian sur Rock Pi, Orange Pi, Banana Pi…) ;
  - « Hardware video decode varies per SoC and isn't wired up out of the box… expect software decode (smooth at 720p, stutter-prone at 1080p, CPU-heavy at 4K) » ;
  - la page web est rendue par **Qt6 WebEngine** (paquets Debian `qt6-webengine`) ; chiffres RK3566 en Q1.
- **Yodeck** : une page « Tested and Approved Android Devices » existe ; son contenu (et donc la présence de RK356x) n'a pas pu être lu. [lu] — [Yodeck](https://www.yodeck.com/docs/user-manual/tested-and-approved-android-devices/)
- **WPE WebKit** : présenté comme adopté en affichage dynamique et en décodeurs TV (via recettes Yocto `meta-webkit`) ; **aucune référence RK356x** trouvée. [lu] — [matériel pris en charge par WPE](https://wpewebkit.org/about/supported-hardware.html)

### Inferences
- [déduit] « 4K HTML5 playback » dans les fiches des fabricants RK356x désigne en pratique la lecture native (MediaCodec/ExoPlayer sous Android), pas une balise `<video>` dans une WebView. C'est cohérent avec les réserves de Xibo sur la vidéo en WebView et avec la mesure du labo (27 contre 60 fps).
- [déduit] L'accélération « VA-API » des nouveaux lecteurs Xibo ne mordra pas sur Rockchip : aucun pilote VA-API natif pour rkvdec/MPP n'est cité dans les sources. Sur RK356x, ces lecteurs retomberont sur le décodage logiciel, comme Anthias.
- [déduit] Le binôme mesuré par Anthias (720p OK, 1080p limite en logiciel, sur 2 Go) est le plancher réaliste d'un lecteur Linux « navigateur + vidéo » sur RK3566 qui n'exploite pas MPP.

### Gaps
- Aucune information RK356x trouvée pour **OptiSigns, signageOS, PiSignage, ScreenCloud, Rise Vision** ; la liste des appareils approuvés de Yodeck est illisible.
- Aucun écran professionnel de marque (Philips, iiyama, BenQ, ViewSonic) identifié avec un SoC RK3566/RK3568.
- Aucune mesure indépendante de la vidéo HTML dans la WebView d'un lecteur d'affichage RK3566.
- Aucun produit WPE/cog sur RK356x.

## Q4 — Pièges rapportés (GPU, vidéo dans le navigateur, HDMI/EDID, hotplug, thermique, mémoire, stockage, 24/7)

### Takeaway
Les pièges les plus coûteux, dans l'ordre :
1. **Chromium standard sans décodage vidéo matériel** sur Rockchip, sur BSP comme sur mainline. Les chemins de contournement sont fragiles : Chromium patché et périmé, `libv4l-rkmpp` sans changement de résolution, V4L2 stateless bloqué par l'allocation NV12 de Panfrost.
2. **Régressions Mesa** (22.3 et 25.0) et **mélange libmali/Panfrost**.
3. **HDMI** : 4K60 seulement depuis Linux 6.12 en mainline, chaîne dw-hdmi « a little borked » en refonte ; DTB de la mauvaise variante qui donne un écran noir ; avertissements EDID/DDC sur box.
4. **Compositeurs Wayland qui perdent la sortie** au hotplug HDMI.
5. **Thermique** : RK3566 qui redémarre à 1,6-1,8 GHz sans dissipation.

**Aucune entrée Linux de la liste de blocage GPU de Chromium ne vise le Mali-G52 ni Panfrost.**

### Cited Findings

**Liste de blocage GPU de Chromium (source primaire, lue le 30/09/2026 sur la branche `main` du miroir GitHub)** [lu] (lu en entier) :
- `software_rendering_list.json` ([miroir](https://github.com/chromium/chromium/blob/main/gpu/config/software_rendering_list.json)) compte **84 entrées**. Côté Linux, il ne bloque que :
  - les rendus logiciels (`llvmpipe|softpipe`) ;
  - de vieux pilotes Intel, AMD et NVIDIA/nouveau ;
  - VMware, VirtualBox, GLX indirect.
- Les entrées Mali visent **Android** (Mali-4xx, Mali-T604 du Nexus 10, DrDc désactivé sur « Mali-G57 MC2 ») ou **ChromeOS** (l'entrée 137 bloque la rastérisation GPU sauf « Mali-T8 / Mali-G »).
- **Aucune entrée Linux ne vise Mali-G52 ni Panfrost.**
- `gpu_driver_bug_list.json` ([miroir](https://github.com/chromium/chromium/blob/main/gpu/config/gpu_driver_bug_list.json)) applique sous Linux un seul contournement « Mali.* » : entrée 478, `disable_program_caching_for_transform_feedback`. [lu]

**Décodage vidéo dans Chromium sous Linux** :
- Chromium ≥ 115 standard sans décodage matériel sous ubuntu-rockchip ; Chromium patché bloqué en 110. [lu] — [ubuntu-rockchip #271](https://github.com/Joshua-Riek/ubuntu-rockchip/discussions/271)
- `libv4l-rkmpp` : « Switching resolutions would not work ». [lu] — [README](https://github.com/JeffyCN/libv4l-rkmpp/blob/master/README.md)
- Chemin V4L2 de Chromium sur Linux avec Panfrost [lu] (extrait) — [Chromium issue 372630272](https://issues.chromium.org/issues/372630272) :
  - « Panfrost doesn't support **NV12 GBM allocation**… pool initialization [fails] silently and the pipeline… **fall[s] back to software decode** » ;
  - repli LibYUV NV12 → ARGB : **~13 ms/image en 720p** (fluide), **~23 ms/image en 1080p** (saccade à 30 fps) ;
  - le chemin MMAP + `VIDIOC_EXPBUF` zéro-copie fonctionne « with stock Mesa ».
  - Mesures faites sur **RK3588 / Mali-G610 / Mesa 26.0.4 — NON TRANSPOSABLE tel quel**. L'allocateur NV12 GBM de Panfrost est en revanche commun. [déduit]
- **Chromium 150 sur RK3588 (NON TRANSPOSABLE)** [lu] (lu en entier) — [dongioia/rock5bplus-rkvdec2](https://github.com/dongioia/rock5bplus-rkvdec2) :
  - la fonctionnalité qui arme le décodage est `AcceleratedVideoDecoder` ; l'ancienne `AcceleratedVideoDecodeLinuxV4L2` « no longer exists in 150 and is silently ignored » ;
  - « HW decode also needs a **Wayland** session » ;
  - drapeaux utilisés : `--ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy` ;
  - l'artefact vert en VP9 sur Mali (Valhall) est corrigé par la mise à jour d'ANGLE livrée avec Chromium 150 (12/07/2026).

**Mesa et pilotes** :
- **Mesa 22.3.6** (celui du labo, version de Debian bookworm d'après le contexte du labo) : ⚠️ ancien. bookworm-backports fournit **24.2.8-1~bpo12+1** puis **25.0.7-2~bpo12+1**. [lu] (extrait) — [packages.debian.org](https://packages.debian.org/source/bookworm-backports/mesa) ; [debian-x, 24.2.8](https://www.mail-archive.com/debian-x@lists.debian.org/msg145355.html)
- **Debian #1024762** (fin 2022) : Mesa **22.2.4 et 22.3.0-rc3** « break GTK4 and Qt apps » sous Panfrost ; constaté sur PinePhone Pro, Mali-T860. [lu] — [lien](https://groups.google.com/g/linux.debian.bugs.dist/c/QZ8vaszKrAk)
- **Debian #1099032** (2025) [lu] — [lien](https://www.mail-archive.com/debian-bugs-rc@lists.debian.org/msg711663.html) :
  - scintillement avec Mesa **25.0.0**, régression par rapport à 24.3.4 ;
  - machine touchée : BananaPi CM4 (Amlogic A311D, Mali-G52) ; **non reproduit sur PineTab2 RK3566** ;
  - cause probable : un contrôleur d'affichage qui gère mal certains formats **AFBC**, et non Panfrost.
- **Mesa 25.0.1-2 sur RK3566** : glmark2-es2-wayland 450+ → 200. [mesuré par la source] (extrait) — [forum Armbian](https://forum.armbian.com/profile/3921-dreamdreams/content/?type=forums_topic_post)
- **Panfrost sur noyau BSP** : Orange Pi CM4 (RK3566), noyau **5.10.160-rockchip-rk356x** + Mesa 24.0.7 sous Debian Trixie, encore sur **llvmpipe**. [lu] — [mesa-users, 05/2024](https://lists.freedesktop.org/archives/mesa-users/2024-May/001731.html)
- **Bascule libmali ↔ Panfrost** : oublier de réinstaller le paquet propriétaire Rockchip peut donner un bureau qui « flash » ou des couleurs inversées. [lu] (extrait) — [Radxa Docs, Switch GPU driver](https://docs.radxa.com/en/som/cm/cm5/radxa-os/mali-gpu) ; doc écrite pour RK3588.
- **Panfrost sous X11** : « not really tested » ; utiliser Wayland. [lu] (lu en entier) — [Plebian RUNNING.md](https://github.com/Plebian-Linux/quartz64-images/blob/main/RUNNING.md)
- **Armbian, Radxa Zero 3W/3E** : Chromium et Firefox cassés après une mise à jour du système. [lu] (extrait) — [forum Armbian](https://forum.armbian.com/topic/46848-radxa-zero-3w-3e-chromium-and-firefox-fail/)

**Sortie HDMI** :
- Mainline : **4K@30 en 2023, 4K@60 à partir de Linux 6.12**, testé sur RK3568. [lu] — [Phoronix](https://www.phoronix.com/news/Rockchip-Linux-6.12-4K-60Hz)
- Plebian (avant 6.12) : seuls certains modes, 1080p60 compris ; 4K non prise en charge. [lu] — [RUNNING.md](https://github.com/Plebian-Linux/quartz64-images/blob/main/RUNNING.md)
- **LibreELEC LE13** [lu] (extrait ; date du message non relevée, 2025-2026) — [forum LibreELEC](https://forum.libreelec.tv/thread/29953-le13-testing-for-rk3288-rk3328-rk3399-rk3566-rk3568-rk3576-rk3588/?pageNo=10) :
  - la chaîne HDMI des puces dw-hdmi (RK3288/3328/3399/**3566/3568**) est « **probably a little borked** » sur les noyaux récents ;
  - une refonte de **150+ patches** est en cours (« ~3/8 series submitted ») ;
  - les fonctions 4K et HDR risquent de **régresser** d'ici là.
- Séries dw_hdmi 2026 (« Misc… », v3 à v7, avril-mai 2026) : notamment une **mise à jour de l'EDID après hotplug**, testée sur RK3328/RK3399/**RK3568**. [lu] (extrait) — [série v3](https://ratatoskr.run/dri-devel/2026/04/3498218/t) ; [série v6](https://ratatoskr.run/lkml/2026/05/9013256/t)
- **Box X88 PRO sur BSP 6.1 (Armbian)** : « HDMI EDID/DDC may report warnings on some displays ». [lu] — [PR #500](https://github.com/armbian/linux-rockchip/pull/500)
- **Piège du DTB de variante (Armbian)** [mesuré par la source] (lu en entier) — [Anthias PR #3331, 15/09/2026](https://github.com/Screenly/Anthias/pull/3331) :
  - U-Boot charge `rk3566-nanopi-r3s.dtb` (HDMI désactivé) au lieu de `-lts.dtb` ;
  - symptôme : « the kernel brings up the VOP but no encoder », **écran noir**, système joignable par le réseau ;
  - remède : `fdtfile=rockchip/rk3566-nanopi-r3s-lts.dtb` dans `/boot/armbianEnv.txt`, sans préfixe `/boot/dtb`.
- **Limites de carte** : Radxa Zero 3W, micro-HDMI **1080p60 maximum** par spécification. [lu] — [Radxa](https://radxa.com/products/zeros/zero3w/)

**Hotplug HDMI et kiosque** :
- **labwc 0.20.1** : un écran qui perd brièvement le hotplug (TV éteinte puis rallumée) peut rester désactivé ; plus aucune sortie, **écran noir jusqu'au redémarrage**. Corrigé en 0.20.2 ; rapporté sur Raspberry Pi. [lu] — [raspberrypi/trixie-feedback #105](https://github.com/raspberrypi/trixie-feedback/issues/105)
- **Kiosque Wayland (cage)** : Wayland « quits » au débranchement HDMI. [lu] (extrait) — [forums Arch](https://bbs.archlinux.org/viewtopic.php?id=296089)

**Thermique (RK3566)** [mesuré par la source] (lu en entier) — [gist aenertia, du 04 au 06/03/2026](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7) :
- matériel : consoles Powkiddy RGB30 et Anbernic RG353P, sans dissipateur de box ; noyau **6.18.13** ;
- à tension d'origine : **1416 MHz → 73 °C** ; **1608 MHz → 85 °C puis reset** (bridé à 1416) ; **1800 MHz → reset** ;
- avec sous-voltage L3 : **−17 °C**, 1800 MHz tenable à 71 °C ;
- arrêt matériel à 95 °C ; repos 1,69 W ;
- DMC : pas de DDR 324/528/780/1056 MHz, 780 jamais choisi par le gouverneur.
- Le discours inverse existe : « maintains consistent clock speeds for over an hour without noticeable throttling when passively cooled ». [lu], billet non chiffré — [dev.to](https://dev.to/jasonliu112/why-rk3566-continues-to-be-a-practical-choice-for-embedded-sbc-designs-9kh)

**Mémoire** :
- Lecteur Anthias à ≈ 990 Mio de RSS sur une carte de 2 Go (plafond 1,54 Gio). [mesuré par la source] — [PR #3332](https://github.com/Screenly/Anthias/pull/3332)
- X88 Pro 20 vendue en « 4/8 GB » (« DDR3 » d'après AndroidPCtv). [lu] — [AndroidPCtv](https://androidpctv.com/review-x88-pro-20-opinion/)

**Stockage et 24/7** :
- Armbian propose **overlayroot** : racine en lecture seule, couche tmpfs, via armbian-config → Storage, ou `overlayroot="tmpfs"`. Présenté pour les kiosques et contre l'usure des cartes. [lu] — [Armbian, Advanced Features](https://docs.armbian.com/User-Guide_Advanced-Features/)
- Chiens de garde de kiosque [lu] :
  - [kiosk-monitor](https://github.com/extremeshok/kiosk-monitor) : Chromium plein écran « self-healing », détection de gel par écran, relance automatique ; labwc d'abord, repli X11 ; conçu pour Raspberry Pi ;
  - [xiboplayer-kiosk](https://github.com/xiboplayer/xiboplayer-kiosk) : « session holder », service utilisateur systemd avec limites de ressources, reconnexion Wi-Fi automatique.
- **Box RK3566 sur noyau mainline récent** : « [JPTV RK3566 8GB RAM eMMC 32GB] not working since 6.6 ». [lu, titre seul] — [armbian/build #10707](https://github.com/armbian/build/issues/10707)

### Inferences
- [déduit] Puisque rien ne bloque Panfrost dans la liste de Chromium, un `chrome://gpu` dégradé sur RK3566 vient d'ailleurs : échec EGL/GBM (issue #692), X11 au lieu de Wayland, ou llvmpipe (Panfrost non chargé sur un noyau BSP à kbase). Pas d'une mise en liste noire. Un `--ignore-gpu-blocklist` ne réparera pas ces causes.
- [déduit] Pour un kiosque 24/7 sur box RK3566, la combinaison sûre ressort ainsi :
  - figer Mesa (≥ 24.2 via backports) **après** validation, car les régressions 25.0 sont documentées ;
  - choisir un compositeur dont le comportement au hotplug est vérifié ;
  - ajouter un chien de garde au niveau de la session ;
  - fixer la tension ou la fréquence si le boîtier est sans ventilateur (reset à 1,6-1,8 GHz sur appareils peu dissipés).
- [déduit] La pile du labo (BSP 6.1 + Panfrost) évite le chantier HDMI de la refonte dw-hdmi mainline ; le VOP2 et le HDMI Rockchip du BSP gèrent la 4K60. Elle hérite en revanche de l'avertissement EDID/DDC vu sur la X88 PRO et d'un couplage Panfrost-sur-BSP moins éprouvé que libmali-sur-BSP ou Panfrost-sur-mainline.

### Gaps
- Chromium/Panfrost sur Bifrost : aucun rapport de « GPU hang » ou de « job timeout » propre au RK3566 trouvé ; les rapports de scintillement pointent l'AFBC du contrôleur d'affichage.
- Aucune mesure thermique publiée pour une **box** RK3566 (X88 Pro 20, H96 Max) en charge soutenue.
- Aucune mesure publiée d'usure eMMC ni de durée de vie de kiosques RK356x.
- Comportement EDID/hotplug de la X88Pro20 sous BSP 6.1 face à une TV éteinte : non documenté.
- Contenu des fils Armbian « X88 PRO 20 RK3566 » ([48381](https://forum.armbian.com/topic/48381-x88-pro-20-rk3566/), [18846](https://forum.armbian.com/topic/18846-x88-pro-20-rk3566-set-top-box/)) : illisible (proxy).

## Q5 — Recommandations communautaires 2024-2026 pour un kiosque navigateur sur RK3566/RK3568

### Takeaway
Il n'existe pas de « recette officielle » unique. Les recommandations convergent pourtant :
- **Wayland obligatoire pour Panfrost** ;
- **Mesa récent** ;
- **Chromium patché** (PPA rockchip-multimedia, builds constructeur FriendlyELEC ou Firefly) **seulement sur noyau BSP 5.10** si l'on veut la vidéo matérielle dans le navigateur ;
- la **vidéo hors du navigateur** (mpv, GStreamer, ffmpeg-rkmpp) dès qu'on veut du 1080p60 ou de la 4K ;
- et, pour l'affichage clé en main sous Linux, s'attendre au décodage logiciel (Anthias : 720p sûr, 1080p limite).

Aucun fil Reddit exploitable n'a été trouvé.

### Cited Findings

**Pine64 / Plebian** : utiliser **Wayland** (Plasma Wayland) pour avoir l'accélération ; Firefox avec `MOZ_ENABLE_WAYLAND=1` et WebRender activé. [lu] (lu en entier) — [RUNNING.md](https://github.com/Plebian-Linux/quartz64-images/blob/main/RUNNING.md)

**Radxa, Zero 3W** : décodage matériel H.264/H.265/VP9 jusqu'en 4K par ffmpeg compilé avec rkmpp, en Wayland ou KMS, « smooth » à faible CPU ; chaîne d'outils « less plug-and-play ». [lu] (extrait) — [forum Radxa](https://forum.radxa.com/t/zero-3w-hardware-decoding-and-encoding-wayland-kms/20088) ; [Easy-Going Nerd, revue 2026](https://easygoingnerd.com/review/radxa-zero-3w-review/)

**Chromium accéléré sur noyau BSP** : `chromium-browser` du PPA rockchip-multimedia, noyau 5.10, testé RK3568 et RK3588. [lu] (extrait) — [forum Radxa](https://forum.radxa.com/t/introduction-to-rockchip-multimedia-ppa-for-ubuntu-jammy/14537) ; [Launchpad](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia). Les images constructeur font de même : FriendlyELEC avec Chromium 130 + `libv4l-rkmpp` ; Rockchip avec `chromium-wayland` 101.

**Kiosque de base (tutoriel DesignSpark, ROCK 3A — RK3568)** : `~/.config/autostart/chromium.desktop` appelle un script qui lance `chromium --kiosk` après une temporisation (attendre le service affiché, ici Grafana). S'assurer de l'accès SSH avant, parce qu'on sort difficilement du mode kiosque. [lu] (extrait) — [DesignSpark](https://www.rs-online.com/designspark/how-to-set-up-a-grafana-analytics-dashboard-based-on-radxa-rock-3a)

**Affichage dynamique clé en main sous Linux, Anthias sur Armbian arm64** [lu] — [README](https://github.com/Screenly/Anthias/blob/master/README.md) ; [FAQ](https://anthias.screenly.io/faq/) ; [PR #3331](https://github.com/Screenly/Anthias/pull/3331) :
- décodage logiciel attendu ;
- accélération matérielle par carte inscrite à la feuille de route (issue #2849) ;
- vérifier le DTB de variante.

**Armbian pour box RK3566** :
- support vendeur 6.1 de la X88 PRO avec Panfrost, fusionné le 15/07/2026. [lu] (lu en entier) — [PR #500](https://github.com/armbian/linux-rockchip/pull/500)
- listes de box ophub (`stable` et `rk35xx`). [lu] (lu en entier) — [README ophub](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/README.md)
- overlayroot pour les kiosques. [lu] — [docs Armbian](https://docs.armbian.com/User-Guide_Advanced-Features/)

**Mainline, décodage dans Chromium** : fonctionnel sur Orange Pi 3B (noyau 6.9 + rkvdec2 patché) en H.264 4K. [mesuré par la source] (extrait) — [LKML](https://lkml.iu.edu/2406.3/03806.html). Le chemin V4L2 stateless générique de Chromium dépend toutefois encore, en 2026, du correctif NV12 et Panfrost. [lu] — [issue 372630272](https://issues.chromium.org/issues/372630272)

**Utilisateurs sans solution** : le fil DietPi « OrangePi 3B - rk3566 - Has anyone hardware accelerated video playback working? » témoigne de la difficulté persistante. [lu, titre et extrait] — [DietPi](https://dietpi.com/forum/t/orangepi-3b-rk3566-has-anyone-hardware-accelerated-video-playback-working/25102)

### Inferences
- [déduit] Pour le projet (une box RK3566 affichant du HTML **et** de la vidéo 60p), l'ensemble des retours publiés pointe vers une architecture où **la vidéo ne passe pas par la balise `<video>` de Chromium**. Deux façons de l'obtenir :
  - un lecteur natif (MPP/GStreamer, ou MediaCodec → SurfaceView sous Android) sur un plan dédié, avec le navigateur pour l'habillage ;
  - un Chromium BSP patché (`libv4l-rkmpp`), à accepter avec sa version ancienne et ses limites (pas de changement de résolution).

  C'est ce que le labo a déjà constaté côté Android (60 fps natif contre 27 fps en WebView).
- [déduit] Si l'on reste sur Chromium Debian standard + Panfrost : Wayland (cage ou labwc, dont la version est vérifiée pour le hotplug), Mesa des backports validé, et une vidéo limitée à ce que le CPU décode (≈ 720p30-1080p30 H.264, d'après Anthias sur RK3566).

### Gaps
- Aucun fil Reddit (r/SBCs, r/SingleBoardComputers) ni Stack Exchange trouvé avec une recommandation chiffrée pour un kiosque RK3566/RK3568.
- Aucune recommandation officielle Armbian ou Radxa « browser kiosk » propre aux RK356x ; seulement des tutoriels généraux et la page DesignSpark (RK3568).
- Aucune comparaison publiée Chromium contre Firefox contre WPE sur la même carte RK356x, à pile constante.
