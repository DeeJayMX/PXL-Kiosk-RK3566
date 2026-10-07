# Comparatif des plateformes pour la box v2 (07/10/2026, à instruire APRÈS l'Urban Trail)

Demande d'Eliott, 07/10 : *« tout RK à tester, ou y aurait d'autres modèles plus easy, pour ce qu'on veut faire ? »*
**Rien n'est mesuré ici.** Toutes les sources web ont été lues **en extrait** (proxy de la session) ; elles sont citées
pour être relues en entier avant un achat. Le seul fait mesuré de la colonne RK3566 renvoie au `README.md`.

## Les cinq critères qui décident (ceux de la box actuelle)

1. Chromium avec **décodage vidéo matériel** sous Linux (pages, viewer TurboHQ).
2. **Encodeur matériel** H.264 / HEVC (flux TurboHQ du programme).
3. Sortie **1080i50** (régies, convertisseurs SDI).
4. **Linux maintenu**, recette reproductible.
5. Petit, peu cher, idéalement sans ventilateur.

## Ce que disent les sources

| Plateforme | Décodage dans Chromium | Encodeur matériel | 1080i50 | Verdict |
|---|---|---|---|---|
| **RK3566** (actuelle) | ✅ **mesuré** (`README.md`) : noyau vendeur + MPP + Chromium patché | ✅ mesuré | ✅ mesuré (`pxl-mode`) | prouvée |
| **Mini-PC Intel N100/N150** | 🟡 VA-API, mais **par drapeaux** (`VaapiVideoDecodeLinuxGL`, `--ignore-gpu-blocklist`) ; un rapport d'octobre 2025 sur un N4500 retombe quand même en logiciel [1][2] | ✅ Quick Sync (lu) | 🔴 **NON** : entrelacé **retiré** de l'affichage Intel Gen 12+ (patch « Prune Interlace modes for Display >=12 », janv. 2023 ; Alder Lake-N = Gen 12) [3] | facile, **sans 1080i** |
| **Raspberry Pi 5** | 🟡 HEVC seul en matériel ; **plus de décodage H.264 matériel** [4] | 🔴 **aucun encodeur matériel**, retiré volontairement (« a mm² too far ») [4] | non vérifié | ❌ pas de flux TurboHQ |
| **Amlogic** (S905X4…) | 🔴 aucune source sur Chromium ; pilote V4L2 libre ancien (S905/S912) ou **RFC 2026** sans état (H.264 1080p, famille S4) [5] | non vérifié | non vérifié | ❌ trop immature |
| **RK3588** (Rock 5, Orange Pi 5…) | ✅ noyau vendeur : Chromium via `libv4l-rkmpp` (H.264, HEVC, VP8, VP9 ; pas AV1) [6][7] · 🟡 **mainline** : décodeurs fusionnés (Collabora, 02/2026) ; un auteur rapporte Chromium **150 de série** qui décode en V4L2 sans état sur noyau 7.1 (rapport isolé) [8][9] | ✅ (lu ; dossier PXL-Switcher) | ✅ le VOP2 est de la même famille — **à mesurer** | monter en gamme, recette proche |
| **RK3576** | voir `PISTE_RK3576.md` | ✅ 4K60 (lu) | à mesurer | compromis, moins mûr |

## Lecture

- **Le 1080i50 tranche** : il élimine le N100 et toute plateforme Intel récente pour une sortie entrelacée. Le N100 reste
  le candidat « facile » pour un client qui sort en **progressif** (1080p50) — à condition de vérifier le décodage
  matériel dans Chromium, qui n'est **pas** automatique sous Linux.
- **L'encodeur tranche** : il élimine le Raspberry Pi 5.
- **Rockchip reste la voie qui coche les cinq cases**, avec deux montées possibles : RK3588 (mûr) et RK3576 (moins cher).

## Proposition de banc (après la course)

Deux candidats, le **même** banc que la box actuelle (`scripts/banc/`, `test_habillage_urban_trail.md`, viewer TurboHQ en
HTTPS, flux writeback, 1080i50) :
1. **Mini-PC N100** — la voie facile, en progressif ;
2. **Carte RK3588** (ou RK3576) — la voie puissante, entrelacé compris.

## ⚠️ Précision apportée à `PISTE_RK3576.md` (même jour)

Ce fichier-là déduit que *« le Chromium de bureau Linux n'embarque pas son décodeur V4L2 sans état »*. Une source trouvée
ensuite [9] rapporte le contraire sur RK3588 mainline (Chromium 150 de série, noyau 7.1). C'est **un rapport isolé, lu en
extrait** : la déduction n'est ni confirmée ni infirmée — elle devient une **question à mesurer**, pas un fait.

## Sources (extraits)

1. [Omarchy — drapeaux VA-API Chromium](https://github.com/basecamp/omarchy/issues/4773)
2. [CachyOS — N4500, VA-API retombé en logiciel (10/2025)](https://discuss.cachyos.org/t/va-api-hardware-acceleration-is-not-working-cachyos-intel-celeron-n4500/16783)
3. [Ubuntu kernel-team — Prune Interlace modes for Display >=12](https://lists.ubuntu.com/archives/kernel-team/2023-March/137416.html)
4. [Forum Jellyfin — Pi 5 sans encodeur matériel](https://forum.jellyfin.org/printthread.php?tid=1509) · [livre blanc Raspberry Pi, encodage H.264 sur Pi 5](https://pip-assets.raspberrypi.com/categories/685-app-notes-guides-whitepapers/documents/RP-010033-WP-1-H.264%20encoding%20performance%20on%20Raspberry%20Pi%205_series%20computers.pdf)
5. [LKML — RFC décodeur H.264 sans état Amlogic S4 (2026)](https://lkml.iu.edu/hypermail/linux/kernel/2602.1/06524.html)
6. [Forum Armbian — décodage matériel Chrome sur RK3588 (BSP)](https://forum.armbian.com/topic/61548-how-to-hardware-video-decode-in-google-chrome-firefox-on-rk3588-orange-pi-5b-ubuntu-rockchip-bsp/)
7. [libv4l-rkmpp](https://github.com/JeffyCN/libv4l-rkmpp)
8. [Collabora — décodeurs RK3588/RK3576 en amont](https://collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html)
9. [Forum Armbian — décodage dans le navigateur sur RK3588 mainline (Debian 13)](https://forum.armbian.com/topic/61497-guide-system-wide-in-browser-hw-video-decode-on-rk3588-mainline-debian-13-trixie-%E2%80%94-and-the-4k30-cma-gotcha-nobody-warns-you-about/)

## ✅ Ajout du 07/10 (soir) — l'entrelacé LU DANS LE CODE du noyau, Intel ET AMD

Demande d'Eliott après une annonce de mini-PC **Ryzen 5 3500U** (Vega 8, DCN 1.0). Lu dans **torvalds/linux** à `7b63ef2`
(07/10/2026), plus seulement en extrait :

- **AMD (`amdgpu`, Display Core) — aucun entrelacé, sur AUCUNE génération qui passe par DC** :
  `amdgpu_dm_connector.c` pose `aconnector->base.interlace_allowed = false` à la création de chaque connecteur
  (l. 3212), et `amdgpu_dm_connector_mode_valid()` **refuse** tout mode `DRM_MODE_FLAG_INTERLACE` (l. 2495). Un Ryzen
  3500U, comme toute APU AMD récente, **ne sort pas de 1080i sous Linux**. ⇒ le Ryzen ne passe pas devant le N100.
- **Intel (`i915`) — confirmé** : `intel_hdmi.c` n'autorise l'entrelacé que si `DISPLAY_VER(display) < 12` (l. 3151) ;
  Alder Lake-N (N100) est en version 12 ⇒ **pas d'entrelacé**. L'extrait [3] est donc vérifié dans le code.
- ⭐ **Conclusion qui dépasse ces deux machines** : sous Linux, **aucun mini-PC x86 récent** (Intel ≥ Gen 12, AMD avec
  DC) ne sort de 1080i. Le **1080i50 est un avantage propre au Rockchip** (VOP2 + notre `pxl-mode`, mesuré). Un client
  qui exige de l'entrelacé ⇒ Rockchip ; sinon un mini-PC x86 en progressif.

## ✅ Ajout du 07/10 (nuit) — « et Amlogic, et toutes les autres puces ? » : relevé dans le noyau MAINLINE

Lu dans **torvalds/linux** `7b63ef2` (07/10/2026), dossiers `drivers/gpu/drm` et `drivers/media`. ⚠️ Ce relevé dit ce que le
**noyau standard** sait faire ; les noyaux **vendeur** (comme celui de notre box, 6.1 Rockchip) peuvent faire plus ou moins.
« Autorisé dans le code » n'est pas « mesuré sur une sortie » : chaque ligne reste **à mesurer**.

**Sortie entrelacée (HDMI)** — pilotes qui l'autorisent (`interlace_allowed`) :

| Famille | Entrelacé HDMI | Preuve lue |
|---|---|---|
| **Amlogic** (meson : S905 / S905X / S905X2 / S905X3…) | ✅ **1080i50 et 1080i60 câblés en dur** | `meson_venc.c` : tables `1080i50` (VIC 20) et `1080i60` (VIC 5) ; `meson_encoder_hdmi.c` l. 403 |
| **Rockchip** (VOP2, mainline aussi) | ✅ | `rockchip_drm_vop2.c` programme la 2e trame (l. 1732, 1867) ; HDMI dw-hdmi l. 2594 |
| **Raspberry Pi** (vc4, Pi 4 / Pi 5) | ✅ autorisé | `vc4_hdmi.c` l. 587 |
| **MediaTek** (HDMI v1 et v2) | ✅ | `mtk_hdmi_v2.c` l. 1438 ; cas 1080i 74,25 MHz dans `mtk_hdmi.c` |
| **Allwinner** (dw-hdmi + TCON) | 🟡 le TCON gère l'entrelacé, à confirmer de bout en bout | `sun4i_tcon.c`, `sun8i_mixer.c` |
| Samsung Exynos, NXP via dw-hdmi | 🟡 autorisé côté HDMI | `exynos_hdmi.c`, `dw-hdmi.c` |
| **Intel** Gen ≥ 12 · **AMD** (DC) | 🔴 **interdit** | voir l'ajout précédent |

**Encodeur vidéo matériel dans le noyau STANDARD** (V4L2, H.264 / HEVC) — présents : Xilinx (allegro-dvt), NXP i.MX8
(amphion) et i.MX6 (coda), Chips&Media **wave5** (TI AM62A, StarFive JH7110…), **MediaTek**, Qualcomm (venus / iris),
Samsung (s5p-mfc), ST. **Absents** : Rockchip (encodeur seulement par MPP, noyau vendeur — c'est notre cas), **Amlogic**,
**Allwinner**, Raspberry Pi.

**Lecture :**
- 🎯 **Amlogic sort bien le 1080i50**, câblé en dur — mais **pas d'encodeur** dans le noyau standard (flux TurboHQ
  impossible, sauf noyau vendeur) et **aucune source** sur le décodage dans Chromium. ⇒ éliminé pour le flux, pas pour
  l'entrelacé.
- 🎯 **MediaTek coche les trois cases dans le noyau standard** (entrelacé, encodeur, décodeur V4L2 hérité de ChromeOS).
  Candidat sérieux à regarder : cartes **Genio** (MT8390 / MT8395). *Non chiffré, non mesuré, Chromium de bureau à vérifier.*
- 🎯 **Raspberry Pi 4** (pas le 5) : entrelacé autorisé, encodeur H.264 matériel **dans le noyau de la fondation**
  (pas le standard), Chromium de Raspberry Pi OS avec décodage matériel. Processeur faible. *À vérifier.*
- ⇒ **Rockchip reste la seule voie prouvée**. Les deux pistes nouvelles à mettre au banc, si on élargit : **MediaTek
  Genio**, puis **Raspberry Pi 4**.

## Ajout du 07/10 (nuit) — sixième critère : **Ethernet gigabit** (demande d'Eliott)

Aujourd'hui le flux TurboHQ du programme fait ~1-3 Mb/s (mesuré, `pxl-wb-enc`) : le gigabit n'est pas un besoin du flux
actuel, c'est une **marge** (flux All-Intra 80 Mb/s de TurboHQ, plusieurs flux, NDI, liens de régie chargés).
⚠️ Le piège des box TV : la puce a un contrôleur gigabit, mais le fabricant soude souvent une **PHY 100 Mb/s** — la fiche
du MODÈLE fait foi, pas celle de la puce.

| Candidat | Ethernet | Provenance |
|---|---|---|
| X88 Pro 20 (RK3566, actuelle) | 1 Gb/s | lu : `model_database.conf` d'ophub (`1Gb-Nic`) — débit réel **non mesuré** |
| NanoPi M5 (RK3576) | 2 × 1 Gb/s | lu : ophub |
| reComputer RK3576 | 2,5 Gb/s | lu : ophub |
| H96 Max M9 (RK3576) | 1 Gb/s | extrait : forum Armbian (varie selon les lots) |
| Mini-PC N100 de l'annonce | 2 × 1 Gb/s (« double gig ») | annonce |
| Mini-PC Ryzen 3500U de l'annonce | « double Ethernet », débit non précisé | annonce |
| Raspberry Pi 4 / 5, cartes RK3588, MediaTek Genio | gigabit ou plus selon la carte | **à vérifier modèle par modèle** |
| Box TV Amlogic | souvent **100 Mb/s** malgré une puce gigabit | à vérifier modèle par modèle |

Au banc : `iperf3` dans les deux sens vers une machine gigabit, pour chaque candidat.

## Ajout du 07/10 (nuit) — QUOI ACHETER, en carte de développement (demande d'Eliott : « qu'on achète le bon matos »)

Principe : **on n'achète en quantité qu'après un banc réussi** sur un exemplaire. Et le premier banc ne coûte rien :

0. 🎯 **La Rock 5B (RK3588) du dépôt PXL-Switcher existe déjà** (« la carte est un ROCK 5B », décision du 17/08 dans ce
   dépôt-là) : tout y a déjà été mesuré côté RGA / VOP2 / DDR, sous noyau Radxa vendeur 6.1. Et le Chromium de la box
   actuelle **vient justement du dépôt Radxa RK3588** (`README.md`, « Chromium 126 Radxa, dépôt `rk3588-bookworm` »).
   ⇒ **Premier banc : la page d'habillage + le viewer TurboHQ + le décodage dans Chromium sur cette carte**, avant tout achat.
   ⚠️ Elle sert le mélangeur PXL Switch : à faire seulement avec l'accord d'Eliott, sans toucher à son installation.

| Ordre | Carte | Puce | Pourquoi | Prix (extrait, date) | À vérifier avant achat |
|---|---|---|---|---|---|
| 1 | **Radxa ROCK 4D 8 Go** + module eMMC | RK3576 | même fabricant que les paquets Chromium/MPP qui marchent déjà ; Gigabit ; HDMI 2.1 ; noyau mainline **et** Radxa OS | ~58 $ (AliExpress, 2025) | Radxa OS à noyau **vendeur** disponible ? Chromium Radxa pour RK3576 ? |
| 2 | **Radxa ROCK 5B+** 8-16 Go | RK3588 | la voie puissante ; 2 HDMI 2.1 + **entrée HDMI** ; 2,5 GbE ; recette la plus proche du connu | 90-119 $ (2024) | eMMC proposée ? (annoncée « plus tard » en 2024) |
| 3 | **Radxa NIO 12L** 8 Go | MediaTek Genio 1200 | la piste MediaTek (entrelacé + encodeur + décodeur dans le noyau standard) ; **entrée HDMI** ; Gigabit ; Ubuntu certifié 5 ans | 119 $ (2024) | décodage matériel dans **Chromium** sous Ubuntu : AUCUNE source trouvée |
| — | Mini-PC N100 (annonce) | Intel | la voie progressive facile, 3 HDMI | ~150-200 € | redémarrage au retour du courant, 3 HDMI natives |

Rien de ce tableau n'est mesuré ; les prix sont des extraits datés. Sources : [Radxa ROCK 4D — doc](https://docs.radxa.com/en/rock4/rock4d) ·
[CNX — ROCK 4D](https://www.cnx-software.com/2025/05/28/radxa-rock-4d-sbc-raspberry-pi-lookalike-powered-by-rockchip-rk3576-edge-ai-soc/) ·
[CNX — ROCK 5B+](https://www.cnx-software.com/2024/07/27/radxa-rock-5b-plus-sbc-lpddr5-memory-emmc-flash-wifi-6-two-m-2-m-key-sockets-4g-lte-5g/) ·
[CNX — NIO 12L](https://www.cnx-software.com/2024/04/11/radxa-nio-12l-low-profile-mediatek-genio-1200-sbc-ubuntu-certification-5-years-software-updates/) ·
[RS Online — NIO 12L](https://uk.rs-online.com/web/p/rock-sbc-boards/2564701?gb=s)
