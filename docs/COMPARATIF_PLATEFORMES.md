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
