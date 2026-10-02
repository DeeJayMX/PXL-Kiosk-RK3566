# Flux TurboHQ de la sortie HDMI — writeback SANS COPIE (02/10/2026)

**Ce que c'est** : ce que la box affiche sur le HDMI, publié en canal TurboHQ. Le VOP2 écrit l'image qu'il envoie à
l'écran dans un tampon NV12 (writeback) ; l'encodeur matériel (MPP) lit ce même tampon. Aucune copie processeur, aucune
conversion. Réglage : `/admin` → « Habillage & écran » → « Flux TurboHQ de la sortie HDMI ». Le client TurboHQ (`thq-publish.js`) vient du dépôt TurboHQ, privé : il est posé à part dans `/usr/local/lib/pxl-kiosk/turbohq-client`, pas dans cette recette publique.

```
Weston (patché) ──writeback NV12, anneau de 4 tampons──▶ pxl-wb-enc (H.264 MPP) ──▶ thq-publish ──▶ relais TurboHQ
                  socket /run/pxl-preview/pxl-wb.sock : DMA-BUF une fois, puis « case n + barrière » par image
```

## Pourquoi un Weston patché (lu dans le code de Weston 13.0, 02/10)

La capture « writeback » de Weston (`weston_capture_v1`) existe, mais : un tampon **alloué à chaque image**
(`drm_fb_create_dumb`), une **recopie processeur** dans la mémoire du client (`pixman_copy_screenshot`), au **format de
la sortie** (XRGB8888, 4 o/px — que le writeback du RK3566 ne sait même pas écrire : BG24 AR24 RG16 NV12), et la
boucle d'affichage **bloquée** jusqu'à la fin du writeback (`drm_writeback_should_wait_completion`) — le ÷2 déjà vu sur
la TurboNode. Le patch (`installation/patches/weston-writeback-flux.patch`, drm-backend seul) :
- anneau de 4 tampons NV12 alloués une fois, DMA-BUF passés une fois à l'encodeur ;
- connecteur writeback attaché au CRTC **une seule fois** (ensuite seul `WRITEBACK_FB_ID` change, pas de modeset) ;
- Weston **n'attend pas** la barrière : elle part à l'encodeur, qui l'attend lui-même ;
- un minuteur force une recomposition à la cadence demandée (sinon un écran fixe ne produit pas d'images).

## Mesuré sur la box (02/10/2026, 1280×720p50, flux 25 img/s, H.264 6 Mbit/s CBR)

| | |
|---|---|
| cadence du flux | **24,8 img/s**, 0 image non capturée |
| modesets pendant le flux | **0** (`drm.debug=0x4`, `vop2_crtc_atomic_enable`) |
| écran (rAF de Chromium) | **49,0 img/s avec flux, 48,7 sans** — pire intervalle 40,1 ms dans les deux cas |
| encodeur | ≈ 6 ms/img d'encodage (+ ≈ 20 ms d'attente de barrière : le writeback finit au vblank suivant) |
| processeur (box entière) | 16 % pendant le flux |
| image | décodée par ffprobe : H.264 High 1280×720, couleurs justes (capture vérifiée à l'œil) |

## Suivre une mise à jour de Weston (Ubuntu)

Weston est tenu (`apt-mark hold weston libweston-13-0`) et notre module remplace celui d'Ubuntu par `dpkg-divert`.
`installer.sh` relance `weston-pxl.sh`, qui ne reconstruit que si la version de Weston ou le patch ont changé
(marqueur `/etc/pxl-kiosk/weston-pxl`). Pour prendre une mise à jour : `apt-mark unhold weston libweston-13-0 &&
apt-get install weston`, puis `weston-pxl.sh`. **Si le patch ne s'applique plus, le module d'Ubuntu est gardé** (l'écran
marche, le flux est indisponible) : fusionner le patch à la main. Retour arrière : `weston-pxl.sh --retirer`.
