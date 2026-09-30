# Documents

Copiés le 30/09/2026 depuis `DeeJayMX/PXL-TurboHQ`, dossier
`TurboNode/research_notes/Chromium kiosque accéléré sur RK3566/` et `TurboNode/reports/`.
Les originaux y restent.

⚠️ **Les liens relatifs du rapport** (`../JOURNAL.md`, `../RECEPTEUR_H264.md`,
`../CAPTURE_DIRECTE.md`…) visent des fichiers de **`PXL-TurboHQ/TurboNode/`**, pas de ce
dépôt. Ils sont laissés tels quels, pour ne pas réécrire un document daté.

| Fichier | Contenu | Nature |
|---|---|---|
| [`RAPPORT_RECHERCHE.md`](RAPPORT_RECHERCHE.md) | synthèse : chemin recommandé en 9 étapes, matrice page × sortie, contradictions, mesures à faire | synthèse |
| [`recherche/test_chromium_radxa_126.md`](recherche/test_chromium_radxa_126.md) | **les essais sur la box**, dans l'ordre : Panfrost, puis Mesa 25, puis kbase + libmali, puis Xorg Rockchip | **mesuré** |
| [`recherche/test_habillage_urban_trail.md`](recherche/test_habillage_urban_trail.md) | **l'habillage animé** (page PGM d'Urban Trail) : le verrou `FlipFB`, puis le mur processeur de la séquence complète | **mesuré** |
| [`recherche/mesures_box_et_android_emmc.md`](recherche/mesures_box_et_android_emmc.md) | état de la box ; lecture de l'Android 14 d'origine sur l'eMMC (1080p forcé, AFBC, DMC) ; errata | mesuré + lu |
| [`recherche/notes_internes_turbonode.md`](recherche/notes_internes_turbonode.md) | ce que le labo avait déjà établi sur la box : plans VOP2, WebView, thermique | digest |
| [`recherche/pile_os_noyau_gpu.md`](recherche/pile_os_noyau_gpu.md) | BSP ou mainline, Panfrost ou libmali, versions de Mesa, PanVK, distributions | web |
| [`recherche/chemin_affichage_chromium.md`](recherche/chemin_affichage_chromium.md) | Ozone, compositeurs kiosque, balayage direct, plans RK3566, drapeaux | web + code |
| [`recherche/decodage_video_chromium.md`](recherche/decodage_video_chromium.md) | voies de décodage matériel de Chromium sur Rockchip | web + code |
| [`recherche/alternatives_et_reglages.md`](recherche/alternatives_et_reglages.md) | WPE, Qt WebEngine, Android ; gouverneurs, thermique ; règles de page | web |
| [`recherche/retours_terrain_benchmarks.md`](recherche/retours_terrain_benchmarks.md) | mesures publiées sur RK356x, lecteurs d'affichage dynamique | web |
| [`recherche/openfyde_rk3566.md`](recherche/openfyde_rk3566.md) | openFyde / ChromiumOS sur RK3566 | web |
| [`recherche/pile_libmali_x11_rk356x.md`](recherche/pile_libmali_x11_rk356x.md) | paquets SDK Rockchip, compatibilité libmali/kbase, OPP | web |

**Réserve commune aux notes web** : la session qui les a produites passait par un proxy
qui refusait beaucoup d'hôtes (forums Armbian et Radxa, CNX, Phoronix, freedesktop…). Ces
sources sont marquées « extrait » : seul le résumé du moteur de recherche a été lu.
