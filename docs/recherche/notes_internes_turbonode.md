# Notes internes TurboNode : ce qu'elles disent d'un kiosque Chromium accéléré sur RK3566

*Digest du 30/09/2026.*

- **Corpus.** Tous les `.md` de `TurboNode/`, dont `JOURNAL.md` lu en entier, plus `bench/` et `noeud/` quand une note y renvoie.
- **Méthode.** Lecture seule : aucun SSH, aucun réseau, aucun test lancé.
- **Chemins.** Ils sont relatifs à `/home/user/PXL-TurboHQ/TurboNode/`.

## Marques de provenance

Les trois marques du labo (README.md:99-103) :

- **[M]** : mesuré sur cette box.
- **[D]** : lu dans une doc ou du code, donc à vérifier.
- **[C]** : calculé.

Marques ajoutées pour ce digest :

- **[H]** : hypothèse que la note déclare elle-même non tranchée.
- **[lu 30/09]** : lecture faite pour ce digest dans `box_extract/`, hors des notes. Ce n'est pas une mesure.
- **[sœur 30/09]** : fait relevé le 30/09 sur la box vivante par un autre agent, dans `mesures_box_et_android_emmc.md` (même dossier). Je ne le cite que lorsqu'il complète ou contredit le corpus.

Une date accolée est celle de la mesure ou de la note.

## Portée du corpus

Les notes servent un **récepteur vidéo** (TurboHQ), pas un kiosque navigateur :

- **Toutes les mesures Chromium ont été faites sous Android** (WebView 113 et Cromite 148).
- Sous Linux, aucun navigateur, aucun compositeur Wayland et aucun serveur X n'a jamais tourné sur la box.
- Côté affichage Linux, tout ce qui existe est écrit en C/C++ sur libdrm, avec MPP et GStreamer.

---

## L'essentiel pour décider

1. **Sous Android, la page devient une seule fenêtre DRM.**
   - Le GPU compose la vidéo dans un tampon ARGB/AFBC plein écran, avec la page, sur `Cluster0-win0`.
   - Conséquence : la vidéo 60p plafonne à environ 27 img/s. Moteurs et versions n'y changent rien : WebView 113 donne 27,1, Cromite 148 donne 26,2.
   - Le plein écran DOM ne change rien.
   - Seul le 1080p30 via MSE tient.
   - Sources : RECEPTEUR_H264.md:417-427, 686-728, 861-912 ; 23/08 [M].
2. **Le même matériel tient 60,0/60 dès que la vidéo a son propre plan.**
   - SurfaceView + MediaCodec (TurboPlayer) : 60,0/60, GPU 0 %, 41 % de CPU.
   - Page WebView transparente **au-dessus** d'une SurfaceView (PXLdisp) : 59,9/60, GPU 0 %.
   - Sources : JOURNAL.md:524-542, 582-593 ; 23/08 [M].
3. **Sur le DTB par défaut, le VOP2 n'expose que trois fenêtres réelles.**

   | Fenêtre | Plan | Rôle et limites |
   |---|---|---|
   | Smart0 | 58 | Primaire, RGB 8 bits linéaire |
   | Esmart0 | 82 | Seul plan à prendre du NV12/NV15 linéaire. Scaler ×8 maximum, entrée ≤ 4096 |
   | Cluster0 | 98 | **AFBC obligatoire, même pour du RGB 8 bits** |

   - Sources : MULTIVIEW.md:14-43 ; DIX_BITS.md:95-125 ; 23-24/08 [M].
   - Conséquence : une page ARGB linéaire et une vidéo NV12 se disputent Smart0 et Esmart0.
   - Seule issue connue : que le GPU rende en AFBC pour Cluster0. Android le fait (RECEPTEUR_H264.md:417-421) ; sous Linux, **jamais essayé**.
4. **Deux plans composés par le VOP2 ne coûtent rien.**
   - Mesure : 16,67 ms contre 16,72 ms, zéro sous-débit (JOURNAL.md:1864-1873 ; 23/08 [M], compilation revérifiée le 08/09 : banc-deux-plans.c:4).
   - Mais le `zpos` doit être posé explicitement : un primaire XR24 opaque au-dessus de la vidéo donne un écran noir (MULTIVIEW.md:337-352).
5. **Il n'y a qu'un seul maître DRM par périphérique.**
   - Un bail (lease) fonctionne, mais le noyau sérialise les commits : 60,0 → 52,6 img/s.
   - Deux montages tiennent 57 à 60,5 img/s : un seul processus qui commite tout, ou une application qui passe ses DMA-BUF au compositeur par SCM_RIGHTS.
   - Sources : CAPTURE_DIRECTE.md:547-632, 754-829, 907-1041 ; 25/08 [M].
6. **Le Linux actuel n'offre aucun décodeur matériel à un Chromium stock.**
   - Système : Armbian ophub, noyau `6.1.141-rk35xx-ophub`, sur microSD à 50 MHz.
   - Ligne de commande noyau : `video=HDMI-A-1:1280x720@60 mem=3838M`.
   - **Aucun nœud V4L2** : tout le décodage passe par `/dev/mpp_service` (CODECS.md:8-26).
   - libv4l-rkmpp n'a jamais été évalué.
7. **Le corpus ne dit rien de Panfrost ni de libmali.**
   - Le noyau Android est kbase : `CONFIG_MALI_BIFROST=y`, Panfrost absent [lu 30/09].
   - ophub, lui, charge Panfrost + Mesa 22.3.6, sans kbase [sœur 30/09].
   - Aucune mesure GL, Vulkan ou WebGL n'existe sous Linux.
8. **La thermique est le mur annoncé.**
   - Seuils : 75, 85 et 115 °C.
   - La box atteint 82 à 85 °C sous charge vidéo et le CPU plafonne alors à 1608 MHz.
   - Aucune donnée sous charge GPU soutenue.
   - Sources : JOURNAL.md:2172-2176, 2577-2588 ; MULTIVIEW.md:457-473.

---

## 1. Contrôleur d'affichage (VOP2)

### 1.1 Fenêtres réelles, formats, mise à l'échelle

**L'état atomique [M 24/08]** (MULTIVIEW.md:14-22) montre trois plans :

- **Plan 58, `Smart0-win0`** : XR24 AR24 XB24 AB24 RG24 BG24 RG16 BG16, linéaire, RGB seulement.
- **Plan 82, `Esmart0-win0`** : NV12 NV16 NV24 NV15 NV20 NV30 YVYU VYUY, plus le RGB, linéaire.
- **Plan 98, `Cluster0-win0`** : YU08 YU10 YUYV Y210, plus le RGB, **AFBC seulement**.

**Le message de boot « ment par généricité » [M 24/08]** (MULTIVIEW.md:24-28).

- Il annonce « full plane mask: Cluster0|Cluster1|Esmart0|Esmart1|Smart0|Smart1 ».
- Or le RK3566 est un RK3568 réduit : « trois fenêtres, un seul port vidéo ».
- Il faut donc compter les plans dans `/sys/kernel/debug/dri/0/state`, pas dans dmesg.

**Le balayage de formats `banc-formats.c` [M 23/08]** (DIX_BITS.md:95-111 ; JOURNAL.md:1825-1842) :

- Esmart0 accepte NV15 NV20 NV30 NV12 NV16 NV24 XR24 AR24 XB24 AB24 YVYU VYUY, sans aucun incident noyau.
- Smart0 n'accepte que du RGB 8 bits.
- Cluster0 n'accepte **rien en linéaire** :
  - `SetPlane` rend EINVAL sur les huit formats essayés, XR24 compris ;
  - `drm.debug=0x06` imprime `[drm:vop2_plane_atomic_check] *ERROR* Unsupported linear format at Cluster0-win0` (DIX_BITS.md:113-125).
- La note conclut que XR30 et Y210 exigent la RGA3 (absente) ou une sortie compressée du VPU. **Le GPU comme producteur d'AFBC n'est pas envisagé.**

**Preuve qu'on peut remplir Cluster0 avec de l'AFBC venu du GPU [M 22-23/08, Android].**

- Sous SurfaceFlinger, on lit : `Cluster0-win0: ACTIVE … format: AB24 (ARGB8888) _AFBC-16x16 … 1920 x 1080` (RECEPTEUR_H264.md:417-421).
- YouTube TV occupe **`Cluster0-win0` et `Cluster0-win1`** (RECEPTEUR_H264.md:697-699).
- Le Cluster a donc deux sous-fenêtres sous le noyau Android. Sous Armbian, seul `Cluster0-win0` (plan 98) est exposé.

**Propriétés des plans [M 24/08]** (MULTIVIEW.md:35-43) :

- `alpha` global (0 à 65535) ;
- `pixel blend mode`, Pre-multiplied ou Coverage ;
- `zpos` (0 à 7) ;
- `rotation` ;
- colorkey sur Smart0 et Esmart0 ;
- sur Esmart0 : `INPUT_WIDTH` ≤ 4096 et `SCALE_RATE` ≤ 8 ;
- aucun format vidéo à alpha sur Esmart0.

**Couleur des plans [M 23/08]** (DIX_BITS.md:133-161) :

- `COLOR_ENCODING` (BT.601=0, BT.709=1, BT.2020=2) et `COLOR_RANGE` (limited=0, full=1) sont exposés avec leurs enums.
- Le défaut vaut 0, soit BT.601 limited.
- kmssink ne les pose jamais.

**Mise à l'échelle matérielle :**

- [M 23/08] Sous Android, `wm size 1280x720` rend src 1280x720 → dst 1920x1080, agrandi par le VOP (RECEPTEUR_H264.md:490-498).
- [sœur 30/09] Esmart0 agrandit du NV12 1080p ×2 vers 3840x2160.

**Décodeur → AFBC → plan Cluster sans RGA [D 24/08] : « ouvert et jamais essayé »** (MULTIVIEW.md:30-33 ; TRESORS_ROCKCHIP.md:76-81).

- Le tampon AFBC du décodeur fait 1920x1104 (MULTIVIEW.md:158-162).
- Il n'est pas lisible par le CPU (MULTIVIEW.md:177-178).

### 1.2 Deux plans à la fois, `zpos`

**Coût d'un second plan [M 23/08, compilation revérifiée le 08/09]** (`bench/banc-deux-plans.c`, 300 poses en 1080p60 ; JOURNAL.md:1864-1873 ; banc-deux-plans.c:37-49) :

| Configuration | Moyenne | Pire cas | Débordements |
|---|---|---|---|
| Vidéo seule | 16,72 ms | 33,27 ms | 1 |
| Vidéo + boîte opaque 424×92 sur le primaire | 16,67 ms | 16,94 ms | 0 |

- ⇒ Un second plan ne coûte rien.
- L'OSD va sur le **primaire** (Smart0), parce que c'est le seul autre plan utilisable (banc-deux-plans.c:45-49).
- Le `zpos` est « le seul réglage qui compte » (banc-deux-plans.c:255-257).

**Pose synchrone ou atomique :**

- [M 23/08] `drmModeSetPlane` est **synchrone** : il attend le vsync, soit environ 16,7 ms (banc-deux-plans.c:40-43).
- [M 24/08] Dans le quad : `SetPlane` bloque 5,03 ms, contre 0,26 ms pour un commit atomique `NONBLOCK|PAGE_FLIP_EVENT` en triple tampon (MULTIVIEW.md:436-455 ; JOURNAL.md:2306-2330).

**Ordre des plans dans le quad [M 24/08]** (MULTIVIEW.md:337-352 ; JOURNAL.md:2261-2264) :

- Smart0 (`zpos 5`, normalisé 1) est **devant** Esmart0 (`zpos 4`, normalisé 0).
- `SetCrtc` avec du NV12 sur le primaire → EINVAL.
- Primaire XR24 opaque → **écran noir**. Primaire AR24 à alpha nul → transparent.
- `pixel_blend_mode` : premultiplied.

**Le présentateur et kmssink [M 23/08] :**

- `turbohq-presente` pose l'OSD sur Smart0 (XR24, `zpos 3`, 412x92 en [45,943]) au-dessus de la vidéo sur Esmart0 (NV12, `zpos 2`). Résultat : 59,87 img/s pour 17,1 % d'un cœur, contre 28,1 % avec kmssink et un OSD incrusté par le CPU (JOURNAL.md:1846-1862).
- Dans kmssink, `plane-properties` est **inerte** : un `zpos=3` demandé reste à 2 (JOURNAL.md:1846-1851). La vidéo passait alors au-dessus de la console (noeud/README.md:112-127).

**Le VOP2 est un vrai compositeur de balayage [D/M 23/08] :**

- Il mélange pixel par pixel selon le `zpos`, avec `DRM_MODE_BLEND_PREMULTI` (DIX_BITS.md:196-197).
- Il compose trois plans au vsync sans le GPU (BULLES_ET_PLANS.md:28-39).

### 1.3 Un seul maître DRM, le bail, le protocole de surfaces

**Un seul maître [M 23/08]** (BULLES_ET_PLANS.md:100-128 ; JOURNAL.md:1670-1675) :

- `modetest -M rockchip -P 98@74:640x360+120+120@AR24` rend `failed to enable plane: Permission denied` tant que kmssink tient le maître.
- Sous Android, « SurfaceFlinger EST ce maître unique ».

**Trois architectures pesées** (BULLES_ET_PLANS.md:120-124) :

- un programme maître unique : « le seul qui tienne » ;
- écrire dans fb0 sans être maître : possible, mais Smart0 est alors SOUS la vidéo ;
- un kmssink par plan : échoue.

**Le bail (lease) [M 25/08]** (CAPTURE_DIRECTE.md:547-632 ; bench/banc-deux-vp.cpp:6-11) :

- Le maître est **par périphérique**, pas par CRTC.
- `drmModeCreateLease` prête VP0 : crtc 74, connecteur 177 et 5 plans. Le locataire ne voit que ce qu'on lui prête.
- Mais le noyau **sérialise les commits** : le chemin direct tombe de 60,0 à 52,6 img/s, et le flip passe de 0,28 à 7,8 ms.

**Un seul commit pour deux CRTC [M 25/08]** (CAPTURE_DIRECTE.md:653-706, 785-809) :

- Même FB sur deux CRTC dans un commit : 58,8/s.
- Deux FB différents dans un commit : 60,5/s.
- `EBUSY` signifie qu'un flip est en vol : il faut attendre (banc-deux-vp.cpp:258-261).

**Protocole de surfaces `turbohq_surface.h` [M 25-26/08]** :

- Une application rend dans des DMA-BUF. Chaque descripteur passe **une seule fois**, par socket Unix et SCM_RIGHTS ; ensuite, seul un index circule (CAPTURE_DIRECTE.md:811-829, 907-944).
- Débits sur le plan 122 : NV12 57,2, AR24 57,6, XR24 53,3 img/s.
- Deux surfaces par application (vidéo NV12 et habillage AR24), à cadences indépendantes, livrées dans le même commit (CAPTURE_DIRECTE.md:994-1041).
- La note juge que cette architecture « mérite d'être construite » (CAPTURE_DIRECTE.md:754-781). C'est le modèle à reprendre si un navigateur doit coexister avec le présentateur.

**Cycle de vie des tampons [M 23-25/08]** :

- Ne jamais réécrire un tampon que le VOP balaie : garder l'actuel et le précédent, donc trois tampons au minimum (CAPTURE_DIRECTE.md:821-824 ; JOURNAL.md:1877-1883).
- Prendre les strides dans la FRAME.
- Mettre les FB en cache par **inode** de DMA-BUF.
- Un `EBUSY` sur `drmSetMaster` veut dire qu'un autre processus tient le maître. Nommer le coupable via /proc : c'est souvent un orphelin (JOURNAL.md:2066-2073).

### 1.4 DTB « VP1 » : second port vidéo et partage des fenêtres

**Ce que donne `rk3566-x88pro20-vp1.dtb` [M 25/08]** (CAPTURE_DIRECTE.md:384-455, 594-615) :

- Deux CRTC : 74 = VP0 sur HDMI, 98 = VP1 sur un DSI fantôme.
- Writeback `possible_crtcs 0x3`.
- **Six plans** : 58 Smart0, 82 Esmart0, 106 Smart1, 122 Esmart1, 138 Cluster0, 154 Cluster1. Seuls les deux Esmart prennent du NV12 linéaire.

**Contraintes relevées :**

- Les masques de plans sont tout ou rien : il faut attribuer les six (`0x3f`), sinon le noyau répond « use default plane mask » (CAPTURE_DIRECTE.md:424-435).
- Un DSI en échec **fait tomber tout l'affichage, HDMI compris**, et `bpc` est obligatoire (CAPTURE_DIRECTE.md:437-448).
- Un VP sans encodeur garde un dclk résiduel d'environ 9 MHz (CAPTURE_DIRECTE.md:407-418).

**L'écran vert [M 26/08]** (BULLES_ET_PLANS.md:151-240 ; noeud/turbohq-mode-video:13-40) :

- Donner Esmart0 à VP1 casse VP0 : la console XR24 y est lue comme du NV12.
- L'écran reste vert même avec `video=DSI-1:d`.
- Aucune erreur n'est levée. Seul le writeback l'a vu.
- [H] Hypothèse de la note : trois fenêtres seulement sont câblées, Esmart1 est « vraisemblablement un fantôme », donc « un seul plan accepte du NV12 linéaire sur cette puce ». **Non tranché** : il faudrait une mire sur Esmart1 en mode simple (BULLES_ET_PLANS.md:238-240).

**Bascule et retour arrière :**

- `turbohq-mode-video [simple|duplex]` réécrit `fdtfile` et `extraargs` (BULLES_ET_PLANS.md:209-213).
- `pxl-retour-arriere.timer` remet le DTB d'origine et redémarre 6 minutes après le boot, sauf s'il est désarmé (CAPTURE_DIRECTE.md:492-495).

### 1.5 Writeback : la box relit sa propre sortie

**Mise en route [M 24/08]** (WRITEBACK.md:32-68) :

- Poser le cap `ATOMIC` **avant** `WRITEBACK_CONNECTORS`, sinon EINVAL.
- Le connecteur 119 reste caché jusque-là, et modetest ne le montre pas.
- Il se déclare connecté, avec des modes : il faut l'exclure du choix d'écran, sinon l'écran reste noir.

**Formats [M 24/08]** :

- BG24, AR24, RG16 et NV12 seulement (WRITEBACK.md:72-87).
- AR24 échoue quand le CRTC sort du YUV : `YUV2RGB is not supported by writeback`.
- Ni 10 bits, ni autre YUV que du 4:2:0 (CAPTURE_DIRECTE.md:859-873).

**Commit [M 24/08]** :

- Le commit doit porter l'état complet avec `ALLOW_MODESET`, connecteur HDMI compris (WRITEBACK.md:100-117).
- La fence tombe au vblank suivant. L'attendre dans la boucle d'affichage divise la cadence par deux : 30,2 img/s (JOURNAL.md:2471-2494).
- La cadence de capture doit venir du vblank. Sinon, on obtient le bug à 7,4 img/s (WRITEBACK.md:179-209).

**Plage [M 25/08]** (CAPTURE_DIRECTE.md:715-750) :

- Le writeback **écrête à 16-235**, sans aucune matrice.
- Une interface en pleine plage perd donc ses noirs et ses blancs, sans rien dire.
- Réserve faite de cet écrêtage, c'est une capture d'écran automatique utilisable pour un kiosque.

### 1.6 HDMI : modes, EDID, console, veille

**Sous Android [M 22-23/08] :**

- Le connecteur propose 3840x2160 et 4096x2160, mais Android tourne en 1920x1080@60.00 (AUDIT_SINCERITE_HS86_PRO20.md:255-259).
- `dumpsys display` ne liste qu'un mode, 1080p60, et `frameRateOverride` est vide : **aucun ajustement de la fréquence au contenu** (RECEPTEUR_H264.md:574-580).
- Timing : dclk 148500, 2200×1125, soit exactement 60,0000 Hz [C]. Bus `RGB888_1X24`, SDR, BT.709 Full (RECEPTEUR_H264.md:399-411).
- [sœur 30/09] Le constructeur **force** l'interface en 1080p, par `persist.vendor.framebuffer.main`, `display_settings.xml` et `baseparameter`.

**Sous Armbian :**

- [M 23/08] VP0 : `HDMI-A-1` en 1920x1080p60, BT.709, RGB888 (JOURNAL.md:1093-1099).
- Mais la ligne de commande force `video=HDMI-A-1:1280x720@60` (noeud/armbianEnv.txt:11). Conséquences :
  - l'émulation fbdev reste en 1280x720 (`/sys/class/graphics/fb0/virtual_size`) pendant que DRM tourne en 1080p60 ;
  - quand le maître est rendu, **fbcon reprend l'écran et DRM restaure le 1280x720** (JOURNAL.md:2639-2655, 3846-3867).

**4K :**

- [sœur 30/09] Sortie actuelle : **3840x2160p60**, dclk 594 MHz, `YUV8_1X24`, BT.709 limited.
- C'est le premier 4K60 relevé sur la box. Dans le corpus, rien n'est mesuré. Seul chiffre, calculé : balayer un tampon 4K coûte 746 Mo/s, contre 187 en 1080p (MULTIVIEW.md:108-112 [C]).

**Choix du mode par le présentateur [M 23-24/08]** (JOURNAL.md:1937-1963 ; noeud/turbohq-presente.cpp:880-882, 907-933) :

- Il cherche `WxH@Hz` dans l'EDID d'abord, puis dans une table CEA-861.
- La table couvre 2160p30/25/24, 1080p60/50/30/25/24, 720p60/50, 576p50 et 480p60. **Pas de 2160p60** : ce mode ne peut venir que de l'EDID.
- Un mode hors EDID (720x576@50) est accepté par le noyau.

**Changement de mode :**

- Il est protégé par un **retour automatique**. Le compte à rebours tourne dans le présentateur, parce que « si le mode est noir, l'invite l'est aussi » (noeud/turbohq-presente.cpp:118-146).
- [M 08-10/09] Une seule bascule HDMI a coûté 24 modesets et pris 95 % d'un cœur dans le tuyau audio (JOURNAL.md:4946-4953).

**Veille [M 31/08]** (JOURNAL.md:3827-3877) :

- Pas de suspend matériel.
- `blank=4` (FB_BLANK_POWERDOWN) sur fb0 fonctionne, une fois le présentateur arrêté.
- L'écriture sysfs `dpms` rend Permission denied.
- `/dev/cec0` existe, mais son adresse physique vaut `f.f.f.f` et la TV ne répond pas.

**EDID et DDC [M 31/08]** (DDC_CI_ROCKCHIP.md:24-59, 102-127 ; JOURNAL.md:4012-4031) :

- L'EDID se lit dans `/sys/class/drm/card0-HDMI-A-1/edid` (256 octets).
- Le DDC/CI refuse de passer par l'I2C interne de dw-hdmi (EOPNOTSUPP). Il marche via l'overlay `pxl-ddc-i2c5`.

### 1.7 Couleur, plage, 10 bits

**10 bits de bout en bout [M 23/08]** :

- NV15 sur Esmart0 (pitch 2496, `zpos 2`) avec un lien `RGB101010_1X30` (DIX_BITS.md:14-26 ; JOURNAL.md:1887-1898).
- `color_depth=10` ne prouve rien : c'est `bus_format`, dans `dri/0/summary`, qui fait foi (DIX_BITS.md:58-82).
- Le VOP convertit gratuitement un plan YUV vers un lien RGB 10 bits (DIX_BITS.md:80-82).

**Format du lien [M 23/08]** (JOURNAL.md:1914-1933) :

- `THQ_FORMAT_LIEN` et `THQ_PROFONDEUR` se posent **avant** le modeset.
- `bus_format` ne distingue pas le 4:2:2 du 4:4:4, et l'infoframe AVI n'est pas exposée.

**Plage [D/M 23/08]** : elle n'est pas déclarable sur le lien HDMI. L'enum `Colorspace` ne porte que des matrices (DIX_BITS.md:184-188).

**Retour arrière** : `modetest -M rockchip -w 121:color_depth:8`, où 121 était l'id du connecteur ce jour-là (DIX_BITS.md:283-290).

**Limites de la chaîne :**

- kmssink de GStreamer 1.22 ne connaît pas le NV15 (DIX_BITS.md:224-238).
- Le RK3566 n'a qu'une RGA2 : pas de RGA en 10 bits (DIX_BITS.md:206-213).
- Un dumb buffer à 10 bpp reçoit un pitch de 3840, pas de 2400 (DIX_BITS.md:259-263).

### 1.8 Diagnostic, et ce qui n'est pas documenté

**Outils :**

- Premier geste : `echo 0x6 > /sys/module/drm/parameters/debug` (WRITEBACK.md:244-250).
- `dri/0/summary` se lit sans être maître, pendant qu'un flux tourne (DIX_BITS.md:66-68).

**Pièges de diagnostic :**

- La numérotation `cardN` dépend de l'ordre de probe : si l'affichage ne se lie pas, `card0` devient un codec (CAPTURE_DIRECTE.md:470-474). `drm-inventaire` balaie 4 cartes pour cette raison.
- Vérifier le `boot_id` avant de lire un journal (CAPTURE_DIRECTE.md:461-466).
- Lire `/sys/kernel/debug/pinctrl/*/pinmux-pins` **fait segfaulter ce noyau** (JOURNAL.md:4058-4060).

**Non documenté ou seulement lu :**

- **Plans curseur** : rien dans le corpus.
- **VRR, `LINE_FLAG1`, `DRM_IOCTL_ROCKCHIP_GET_VCNT_EVENT`** : lus dans le BSP RK3588 [D], jamais vérifiés sur la box (SOUS_TRAME_ET_GENLOCK.md:395-440, 547-552 ; DOSSIER_LATENCE_GLASS_TO_GLASS.md:136-148).
- **`DRM_MODE_PAGE_FLIP_ASYNC`** : seulement [D] (DOSSIER_LATENCE_GLASS_TO_GLASS.md:903-912).
  - La ligne 118 le marque bien [M] « 28 → 60 img/s ».
  - Mais la mesure citée est celle de la file placée après le décodeur (JOURNAL.md:1621-1637), pas celle d'un flip asynchrone. C'est ma lecture, à vérifier.

---

## 2. GPU Mali-G52

### Matériel

- RK3566 = 4×A55 + **Mali-G52 2EE** (RECEPTEUR_H264.md:927).
- [lu 30/09] `box.dtb` : `gpu@fde60000`, compatible `arm,mali-bifrost`, OPP à 200/300/400/600/700 MHz.
- [sœur 30/09] Sous Armbian : gouverneur `simple_ondemand` de 200 à 800 MHz ; `clk_gpu` à 166 MHz au repos.

### Charge sous Android [M 23/08]

**WebView, MSE, 1080p60** (JOURNAL.md:470-480) :

- GPU à 37 %, à 600 MHz sur 700 disponibles : « le gouverneur ne monte même pas ».
- Le coût est ailleurs : rendu à environ 150 % de CPU, décodage à 12-17 % d'un cœur.

**Comparaison des chemins** :

| Chemin | Charge GPU | Source |
|---|---|---|
| MSE + `<video>` | 22-37 % | RECEPTEUR_H264.md:861-868 |
| WebCodecs + WebGL | 0 % | RECEPTEUR_H264.md:861-868 |
| Cromite | 32 % | RECEPTEUR_H264.md:907-912 |
| WebView | 29 % | RECEPTEUR_H264.md:907-912 |
| TurboPlayer | 0 % | JOURNAL.md:524-534 |
| PXLdisp | 0 % | JOURNAL.md:582-593 |

- Contradiction : la peinture WebGL coûte environ 20 ms par image (RECEPTEUR_H264.md:779-801, 829-835), mais le GPU affiche 0 %. La façon de mesurer la charge GPU n'est écrite nulle part.

**`dumpsys gfxinfo`, WebView en 1080p30, 25 s** (RECEPTEUR_H264.md:432-450) :

| Indicateur | Valeur |
|---|---|
| Images | 787 |
| Janky | 69,5 % |
| Temps d'image p50 / p90 / p95 / p99 | 20 / 28 / 32 / 42 ms |
| Missed Vsync | 0 |
| CPU | 161 % user + 119 % sys, sur 400 % |

**Avec `wm size 1280x720`** (le VOP agrandit) (RECEPTEUR_H264.md:490-527) :

- p99 à 36 ms, janky à 48,4 %, CPU en baisse de 42 points.
- Le budget de 33 ms reste dépassé.

**Coût de composition** :

- « RK3566 paie 150 % de CPU pour 12 % de décodage ».
- La Shield (Tegra X1), elle, compose la même page 1080p bien sous 16,7 ms (JOURNAL.md:494-499 ; RECEPTEUR_H264.md:915-935).

### Sous Linux

- [M 08/09] Le VOP compose seul et « le GPU ne touche pas un pixel vidéo » : toute la box tient dans environ 66 % d'UN cœur (JOURNAL.md:4596-4625).
- Aucune mesure GPU sous Linux.

### Pile pilote

**Dans le corpus** : aucune mention de Panfrost, Lima, Mesa, libmali ou kbase. Seul un « shader Mali » de dithering est évoqué, pour le RK3588 d'AirLink (CROISEMENT_AIRLINK.md:43-45).

**[lu 30/09] Noyau Android** (`box_extract/kconfig.txt`, en-tête « Linux/arm64 6.1.157 ») :

| Ligne | Option |
|---|---|
| 4385 | `CONFIG_MALI_BIFROST=y` |
| 4396 | `# CONFIG_MALI_CSF_SUPPORT is not set` |
| 4397 | `CONFIG_MALI_BIFROST_DEVFREQ=y` |
| 4366 | `CONFIG_MALI_MIDGARD=y` |
| 4354-4355 | `CONFIG_MALI400/450=y` |
| 4347 | `# CONFIG_DRM_PANFROST is not set` |
| 4346 | `# CONFIG_DRM_LIMA is not set` |

**[sœur 30/09]** :

- Espace utilisateur Android : `libGLES_mali.so` 32 bits, DDK `g25p0-00eac0` ; `vulkan.rk356x.so` ; GLES 3.2 ; `ro.hwui.use_vulkan=true`.
- Armbian ophub : `panfrost` chargé, Mesa 22.3.6 (25.0.7 en backports), `# CONFIG_MALI_BIFROST is not set`. libmali y est donc impossible sans recompiler le noyau.

### WebGL, WebGPU, WebNN

**WebGL [M 22-23/08, Android]** :

- `turbohq_viewer_webgl.html` peint le `VideoFrame` dans un canvas WebGL. En 720p30 : 33 ms, zéro perte (JOURNAL.md:370-380).
- En 30p, rAF tourne à 57,9 Hz (RECEPTEUR_H264.md:242).
- En 60p : 29,6 images décodées sur 60 reçues, 575 jetées, et rAF décroche à 46,9/s (RECEPTEUR_H264.md:646-653, 664, 768-770).
- La peinture WebGL, environ 20 ms par image, est le goulot (RECEPTEUR_H264.md:779-801, 829-835).

**WebGPU : jamais essayé sur la box.**

- Seulement sur PC (RTX 3060 + Chrome 151, CODEC_JPEG_WEBGPU.md:28, 641-650) et en VM sous SwiftShader [VM], pour la justesse seulement.
- Pièges déjà payés :
  - un device perdu ne lève aucune erreur, les commandes sont ignorées en silence (CODEC_JPEG_WEBGPU.md:131-136) ;
  - SwiftShader headless ne sait pas présenter un canvas WebGPU (CODEC_JPEG_WEBGPU.md:152-159) ;
  - le banc refuse de publier des chiffres sur un adaptateur logiciel (BRIEF_BANC_REEL_CODEC_WEBGPU.md:115-117).

**Codecs, JPEG et WebNN [D 28/08]** :

- WebCodecs n'a pas de MJPEG. `ImageDecoder` en jpeg passe par le décodeur logiciel de Blink.
- Le JPEG matériel de Chromium est réservé à ChromeOS, au seul chemin de capture (CODEC_JPEG_WEBGPU.md:236-268).
- WebNN n'a aucun backend vers le NPU Rockchip (RKNN seulement) et retombe en silence sur XNNPACK, donc sur le CPU (CODEC_JPEG_WEBGPU.md:1167-1175, 1212-1221).

### Température

- Au repos : SoC 55,5 °C, GPU 53,1 °C (AUDIT_SINCERITE_HS86_PRO20.md:292-293).
- Après les bancs : SoC 82 °C, GPU 78 °C (JOURNAL.md:2103).
- Rien sous charge GPU soutenue.

---

## 3. Chromium, WebView, Cromite et autres navigateurs

### 3.1 Inventaire

**Android d'usine [M 22/08]** :

- **Aucun navigateur** : `resolve-activity VIEW` ne trouve aucune activité.
- Seul `com.android.webview` est présent, en 113.0.5672.136 (JOURNAL.md:201-208 ; PREMIER_FLUX.md:344-355).

**Ce WebView [M 23/08]** (RECEPTEUR_H264.md:895-902) :

- C'est un WebView AOSP de mai 2023, armeabi-v7a.
- Son `lastUpdateTime` est la date d'usine.
- Il est **le seul fournisseur valide**, et le Play Store ne peut pas le mettre à jour.
- La Shield, elle, a un WebView Google arm64 à jour.
- [sœur 30/09] Fichier : `product/app/webview/webview.apk`, 90,9 Mo.

**Cromite [M 22/08]** (PREMIER_FLUX.md:99-113) :

- `org.cromite.cromite` 148.0.7778.168, `arm_ChromePublic.apk` armeabi-v7a (170 Mo).
- **L'APK arm64 s'installe mais refuse de démarrer** : l'espace utilisateur est en 32 bits.
- Vérifier le code natif avec `aapt2 dump badging`.

**Autres :**

- PXLdisp (`com.pxl.virtualsurface`) est une app Capacitor, donc un WebView. Son manifeste n'a que MAIN/LAUNCHER (JOURNAL.md:214-216, 332-345 ; PREMIER_FLUX.md:362-364).
- Un APK Google Chrome est cité comme option, **jamais essayé** (PREMIER_FLUX.md:461-468).
- **Linux : aucun navigateur n'a jamais été installé.** [sœur 30/09] apt propose `chromium` 151 (21 paquets), `cage` 0.1.4 et `weston` 10.0.1 ; ni X ni Wayland ne sont installés.

### 3.2 Lancer, piloter, contourner (Android)

**Premier lancement de Cromite [M 22/08]** (PREMIER_FLUX.md:118-130) :

- Trois écrans se franchissent par `input tap` : bienvenue, moteur de recherche, puis l'interstitiel « doesn't support secure connection ».
- Cromite force le HTTPS-First.

**Lancement :**

```
am start -a android.intent.action.VIEW -d URL -n org.cromite.cromite/com.google.android.apps.chrome.IntentDispatcher
```

(bench/box_clean_run.sh:45)

**Pilotage par CDP, sans activation, grâce à `ro.debuggable=1` [M 22/08]** :

- Sockets : `@chrome_devtools_remote` (Cromite) ou `@webview_devtools_remote_<pid>` (WebView), puis `adb forward tcp:9222 localabstract:…` (PREMIER_FLUX.md:142-152 ; RECEPTEUR_H264.md:137-158 ; bench/cdp.mjs:9-14).
- `bench/cdp.mjs` a quatre modes : eval, shot, navigate et console (cdp.mjs:44-92).
- `Runtime.evaluate` avec `userGesture:true` est le seul moyen de simuler un geste pour `play()` (cdp.mjs:44-49).
- `Security.setIgnoreCertificateErrors` garde l'origine « sécurisée » (cdp.mjs:62-70).
- logcat ne relaie pas `console.log` (cdp.mjs:71-92).
- `location.reload()` via CDP ne recharge pas : utiliser `Page.navigate` vers une URL différente (RECEPTEUR_H264.md:373-389).

**Les drapeaux de ligne de commande sont ignorés [M 22/08]** (PREMIER_FLUX.md:326-338) :

- `/data/local/tmp/chrome-command-line` n'est lu que si l'APK est debuggable, ou si `ro.build.type` vaut eng ou userdebug.
- Or la box est `ro.build.type=user` avec `ro.debuggable=1`.
- `--ignore-certificate-errors` et `--autoplay-policy=no-user-gesture-required` sont donc inutilisables.

**Lecture automatique [M 22/08]** (PREMIER_FLUX.md:132-177, 332-338) :

- Le `<video>` démarre en pause à chaque ouverture de page (`NotAllowedError`), même muet, parce que `srcObject` est posé plus tard depuis MSTG.
- Parades : un `input tap` après chargement, ou CDP avec `userGesture:true`.
- La note renvoie la décision au kiosque : « à trancher au moment du kiosque ».

**Contexte sécurisé obligatoire [M 22-30/08]** pour `VideoDecoder`, `VideoEncoder` et `crypto.subtle` (PREMIER_FLUX.md:221-251) :

- En http depuis une autre machine, la page charge et compte les images, mais n'affiche rien (CAPTURE_DIRECTE.md:328-366 ; JOURNAL.md:2517-2523).
- WSS refuse un certificat auto-signé, même après acceptation de l'interstitiel (PREMIER_FLUX.md:313-316).
- Un CN seul est refusé : il faut un SAN (CAPTURE_DIRECTE.md:347-356).
- `localhost` est exempté. Capacitor sert `http://localhost`, donc WebCodecs y marche sans TLS (RECEPTEUR_H264.md:51-55).
- Solution retenue : un vrai certificat Let's Encrypt via `tailscale cert`, renouvelé chaque semaine par un timer (JOURNAL.md:3341-3375).
- Le magasin d'AC système d'Android 14 est dans l'APEX, pénible à modifier (PREMIER_FLUX.md:318-324).

**Réseau [M 22/08]** : le tailnet sous Android fait passer la latence affichée de 20 à 34 ms (+14 ms de WireGuard en espace utilisateur et de TLS) (PREMIER_FLUX.md:297-309).

### 3.3 Codecs selon le moteur

**`VideoDecoder.isConfigSupported`, testé par CDP [M 22-23/08]** (RECEPTEUR_H264.md:26-49 ; JOURNAL.md:283-295, 332-345) :

| Moteur | avc1 (42c01f / 4d401f / 640028) | hev1 | vp09 |
|---|---|---|---|
| WebView 113 | oui | oui | oui |
| Cromite 148 | non | non | oui |

- Cromite est dégooglisé : pas de codec propriétaire dans WebCodecs.
- Mais son `<video>` et son MSE acceptent h264, hevc et aac (PREMIER_FLUX.md:443-448).

**MJPEG [M 22/08]** :

- Chemin `createImageBitmap`, 720p à 6-7 img/s, 20 ms (PREMIER_FLUX.md:181-187).
- Borné par le CPU du récepteur (CODEC_JPEG_WEBGPU.md:266-268).

### 3.4 Performances mesurées (Android, HDMI 1080p60)

**Trois viewers comparés [M 22-23/08]** (RECEPTEUR_H264.md:61-127, 233-278 ; JOURNAL.md:350-435) :

| Viewer | Résultat |
|---|---|
| `MediaStreamTrackGenerator` → `<video>` | **96 % jeté à la présentation** (4697 images, 4526 jetées), image figée |
| WebGL | Correct en 720p30, 33 ms |
| **MSE (`turbohq_viewer_ios.html`), le meilleur** | 30,0 présentées/s, 0 jetée, 20-27 ms. Cadencé sur le vsync par la pile vidéo native. Marche aussi dans Cromite, sans WebCodecs |

**Plafond d'environ 30 présentées/s, quelle que soit la résolution [M 23/08]** (RECEPTEUR_H264.md:318-371) :

- En 720p60 comme en 1080p60, on présente 30 images/s, avec une vitesse média de 2,00 à 2,32.
- C'est donc un plafond de **cadence**, pas de débit de pixels.

**60p en détail [M 23/08]** (RECEPTEUR_H264.md:646-653, 861-885 ; JOURNAL.md:524-534) :

- MSE : 27,1/60, avec 7 gels de 370 à 450 ms ; `MediaCodec` à 17 %, app + renderer à 152 % de CPU, GPU à 22-37 %.
- WebGL : 575 images jetées.

**Cause : une seule fenêtre DRM [M 23/08]** (RECEPTEUR_H264.md:417-427, 454-462, 686-714) :

- La page occupe `Cluster0-win0` (AB24 AFBC 1920x1080). « Chaque image décodée est composée par le GPU dans un buffer ARGB/AFBC plein écran avec la page ».
- YouTube TV passe par une SurfaceView, donc deux fenêtres.

**Le plein écran ne change rien [M 23/08]** (RECEPTEUR_H264.md:716-728) :

- `requestFullscreen()` répond « fullscreen OK », mais les plans DRM restent identiques.
- Le WebView d'Android ne promeut pas une vidéo MSE en SurfaceView, comme le fait Chrome.
- « Aucun réglage de page ne fera sortir la vidéo du WebView. »

**Hypothèses réfutées [M 23/08]** (RECEPTEUR_H264.md:887-912 ; JOURNAL.md:484-490) :

- « WebCodecs copie davantage que MSE » : faux, les deux coûtent environ 135 % en 1080p30.
- « WebView 113 est trop vieux » : faux, Chromium 148 présente 26,2 img/s, contre 27,1.

**Cadence [M 23/08]** :

- `requestVideoFrameCallback` sur du 30p en 60 Hz : 10,6 % des images tombent au mauvais intervalle (RECEPTEUR_H264.md:548-562).
- Pas d'ajustement de fréquence au contenu, alors que la Shield bascule sa sortie (RECEPTEUR_H264.md:574-580, 915-935).

**La taille de la couche d'interface compte [M 23/08]** : ramener l'interface de 1920x1080 à 1020x77 supprime la recomposition plein écran 60 fois par seconde (JOURNAL.md:540-542).

### 3.5 Verdicts du labo

**Navigateur sur la box : 1080p30 via MSE** (RECEPTEUR_H264.md:676-680).

**Natif** :

- TurboPlayer : 60,0/60, 41 % de CPU contre 152 % pour le navigateur, GPU 0 % (JOURNAL.md:524-542, 4643-4664).
- PXLdisp, WebView transparent sur SurfaceView : 59,9/60, GPU 0 %, 81,8 % d'un cœur (JOURNAL.md:582-593 ; BULLES_ET_PLANS.md:23-26).

**Doctrine** :

- « Publier depuis un navigateur, oui ; afficher dans un navigateur quand la latence compte, non » (CHEMINS_ET_TIERS_LATENCE.md:192-194).
- La « classe 5-8 ms » est inaccessible au navigateur : son rAF est quantifié et il passe par un compositeur (PREMIER_FLUX.md:366-369 ; RECEPTEUR_H264.md:174-179).

**Erratum de latence** (CHEMINS_ET_TIERS_LATENCE.md:115-122 ; DOSSIER_LATENCE_GLASS_TO_GLASS.md:35) :

- Le « navigateur récepteur 60-90 ms [D] » n'a jamais été mesuré.
- Mesuré : 20 ms en 30p et 23-27 ms en 60p. Métrique du viewer, pas de verre à verre.

### 3.6 Hygiène d'exploitation

**Une seule page qui décode.** Quatre onglets tombent à environ 7 img/s au total : le décodeur matériel est une ressource unique (JOURNAL.md:442-447 ; RECEPTEUR_H264.md:263-268).

**Une app en arrière-plan est gelée** (`do_freezer_trap`), et son WebView ne répond plus au CDP (JOURNAL.md:449-454).

**`bench/box_clean_run.sh`** (box_clean_run.sh:31-76 ; RECEPTEUR_H264.md:959-972) :

- tue tout, en deux passes ;
- vérifie que le relais ne voit plus aucun viewer ;
- lance UNE page ;
- repère le socket CDP (regex `@?(chrome|webview)_devtools_remote(_[0-9]+)?`) ;
- ferme les autres cibles par `/json/close/<id>`.

**Pièges de page :**

- Un 404 sur un module ES (`fmp4_muxer.js`) tue la page sans un mot (RECEPTEUR_H264.md:187-213 ; JOURNAL.md:393-396, 4492-4496).
- Le SourceBuffer MSE n'encaisse pas un changement de résolution (RECEPTEUR_H264.md:373-389).
- Garde du viewer : au-delà de `decodeQueueSize > 3`, on jette jusqu'à l'IDR suivante. Passer d'un GOP de 60 à un GOP de 6 ramène le gel maximal de 1 s à 0,1 s (RECEPTEUR_H264.md:779-816 ; JOURNAL.md:470-480).

### 3.7 Linux : prévu, pas fait

**Phase 2 du plan distro** (BRIEF_DISTRO.md:92-105, 145-147) :

- « Navigateur en kiosque sur un plan ARGB, vidéo sur un plan NV12 — c'est exactement ce que le VOP fait déjà ».
- Qualifiée de RÉÉCRITURE, pas de portage.
- Conditionnée au succès de la phase 1 (TurboPlayer natif).

**Options de rendu ARGB** (BULLES_ET_PLANS.md:49-65) :

- un navigateur headless qui écrit dans un DMA-BUF (« le plus fidèle, le plus lourd ») ;
- un rendu direct par code (`pxl-logo.py`) ;
- Cairo ou Skia.

**Pose prévue sur le plan 98** (`drmModeAddFB2` + `drmModeSetPlane`, ou kmssink `plane-id=98`) : **caduque en linéaire**, le Cluster étant AFBC seulement (voir 1.1).

**Entrées** : lire `/dev/input/*`, le « vrai coût de la migration ».

**Ordre prévu** (BULLES_ET_PLANS.md:142-147) : d'abord un compositeur minimal, puis le rendu, les entrées en dernier.

---

## 4. L'Android d'origine

### Identité [M 22/08]

(AUDIT_SINCERITE_HS86_PRO20.md:22-88 ; JOURNAL.md:17-23)

- HS86 Pro20 = Hugsun X88 Pro 20 (README.md:264).
- Compatible `rockchip,rk3566-hugsun-x88pro20-box-demo-v10`.
- Android 14 (SDK 34), noyau 6.1.157, 3,99 Go de RAM.
- `ro.debuggable=1`, `ro.secure=1`. `adb root` donne `u:r:su:s0`, et **SELinux est permissif**.
- **Espace utilisateur 32 bits** (`armeabi-v7a,armeabi`, `zygote32`, pas de `/system/lib64`) sur un noyau arm64 avec `CONFIG_COMPAT`.
- Empreinte usurpée : `google/redfin`.
- Chemin de build `hugsun_a14_rkr4_rk3566_atv` : c'est un **build Android TV** (DOSSIER_WIFI_SWT6621S.md:85-95).
- [sœur 30/09] `ro.rksdk.version=ANDROID14_MS_RKR4`.

### eMMC et partitions

- `mmcblk2` fait 31,27 Go, plus `boot0`/`boot1`, sur `sdhci@fe310000` (AUDIT_SINCERITE_HS86_PRO20.md:25, 267-271).
- `boot.img`, 64 Mo, est `mmcblk2p7` (FACADE_HT1628.md:100-102).
- `mmcblk2p8` porte un en-tête `ANDROID!` (JOURNAL.md:3989-3992, 4062-4065 ; DDC_CI_ROCKCHIP.md:68-82) :
  - le DTB y est à l'offset 88 674 304, après noyau, ramdisk, second **et recovery_dtbo** ;
  - oublier recovery_dtbo donne un faux DTB de 4 Ko qui a l'air valide.
- [sœur 30/09] Table GPT :
  - `security`, `uboot`, `trust`, `misc`, `dtbo`, `vbmeta` ;
  - `boot` (64 Mio), `recovery` (96 Mio) ;
  - `backup`, `cache`, `metadata` ;
  - `baseparameter` (1 Mio) ;
  - `super` (2400 Mio, non A/B, ext4) ;
  - `userdata` (26,4 Gio).
- [C, mon recoupement] Dans cet ordre, p7 = boot et p8 = recovery. Le DTB extrait le 31/08 viendrait alors de l'image **recovery**. À vérifier.

### Sauvegarde [M 23/08]

- `noeud/sauver-android.sh` a produit `/mnt/ssd/x88pro20-android-20260823/emmc-mmcblk2.img` : 31 268 536 320 octets, la taille exacte de l'eMMC. Plus `boot0.img` et `boot1.img`.
- **Les sommes de contrôle restent à confirmer : la vérification a été coupée** (JOURNAL.md:1574-1582 ; noeud/sauver-android.sh:13-43).

### Démarrage [M 23/08]

(JOURNAL.md:1052-1058)

- L'U-Boot d'origine essaie la carte SD avant l'eMMC.
- Retirer la carte ramène Android.
- La méthode Multitool, qui efface l'eMMC, n'est pas nécessaire.

### Artefacts `box_extract/` [22/08]

(box_extract/README.md:6-23)

- `box.dtb` (164 Ko, lu dans `/sys/firmware/fdt`).
- `kconfig.txt` (`/proc/config.gz`).
- `skwfw.tar` et `skwko.tar` : les `.ko` sont liés au vermagic Hugsun.

**[lu 30/09] `kconfig.txt`, hors GPU :**

| Ligne | Option |
|---|---|
| 4155 | `CONFIG_DRM_ROCKCHIP=y` |
| 4159 | `CONFIG_ROCKCHIP_VOP2=y` |
| 4322 | `CONFIG_DRM_DW_HDMI_CEC=y` : le CEC existe côté Android |
| 6038 | `CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y` |
| 6028-6031 | Gouverneurs devfreq : simple_ondemand, performance, powersave, userspace |
| 5646-5651 | Tas DMA-BUF : system et CMA |
| 7409 | `CONFIG_CMA_SIZE_MBYTES=16` : la vraie taille vient probablement du DT |
| 4469 | `CONFIG_ROCKCHIP_MULTI_RGA=y` |

**[lu 30/09] `box.dtb`, par `strings`, avec la fragilité de cette méthode :**

- `/dmc` en `rk3568-dmc`, avec `vop-bw-dmc-freq` et `vop-frame-bw-dmc-freq`.
- `vop@fe040000`, compatible `rockchip,rk3568-vop`.
- **Aucune** propriété `plane-mask` ni `primary-plane` : la répartition des fenêtres est celle par défaut.
- OPP CPU de 408 à 1800 MHz.
- `dtc` et `fdtget` sont absents de la VM de travail.
- Le parseur du labo `box_extract/dtb.mjs` perd les nœuds qui ont des enfants.

### Composition : SurfaceFlinger et HWC

**Ce qui est mesuré :**

- [M 23/08] SurfaceFlinger est le maître DRM unique (BULLES_ET_PLANS.md:100-116).
- [M 23/08] Une page WebView occupe une fenêtre, `Cluster0-win0` en AB24 AFBC. Une SurfaceView a sa propre fenêtre (RECEPTEUR_H264.md:417-427, 697-702). TurboPlayer et PXLdisp occupent Esmart0 en NV12 plus Cluster0 en AB24 (JOURNAL.md:582-593).
- [M 22/08] `screenrecord` ne produit rien sur un écran statique : 31 images en 10 s. C'est la version 1.3, sans `--codec` (JOURNAL.md:47-58).
- [M 22/08] `screencap`, lui, capture bien la vidéo (PREMIER_FLUX.md:175-177).
- [M 23/08] Avec `wm size 1280x720`, le mode reste 1080p60 et le VOP agrandit (RECEPTEUR_H264.md:490-498).

**[sœur 30/09] Ce qui est lu sur la box :**

- HWC3 AIDL (`composer3-service.rockchip`) et `hwcomposer.rk30board.so`.
- `vendor.hwc.compose_policy` passe de 1 à 2 à l'init.
- Mode « split » de `HwComposerEnv.xml` désactivé.
- `vendor.gralloc.disable_afbc=1` : contredit l'AFBC mesuré, voir 6.2.
- `system` reçoit `/sys/class/devfreq/dmc/vop_bandwidth`.
- Pas plus de détail sur la politique d'overlay de HWC.

### MPP et codecs sous Android [M 22-23/08]

(JOURNAL.md:783-931 ; AUDIT_SINCERITE_HS86_PRO20.md:227-251)

- MediaCodec :
  - décodeurs `OMX.rk.video_decoder.{avc,h263,hevc,m2v,m4v,vp8,vp9}` et `c2.rk.{avc,h263}.decoder` ;
  - encodeur `c2.rk.hevc.encoder` ;
  - encodeur AVC limité à 1920x1088@60 ;
  - **ni MJPEG ni AV1**.
- `/dev/mpp_service` est en `crw-rw-rw-`, contexte `video_device`.
- `public.libraries.txt` ne liste que `libOpenCL.so` : `dlopen(/vendor/lib/libmpp.so)` est refusé dans le namespace d'une app. La lib embarquée est `mpp_16_1.0`.
- Routes DMA-BUF → SurfaceView (JOURNAL.md:953-967) :
  - `AHardwareBuffer_createFromHandle` n'est pas publique ;
  - `ANativeWindow_lock` + memcpy est une copie ;
  - `EGL_LINUX_DMA_BUF_EXT` impose une passe GPU.
- L'ouverture de `/dev/mpp_service` tient au build userdebug/permissif : sur une tablette, EACCES (JOURNAL.md:1040-1046).

### Autres faits

- **Façade HT1628** : `/dev/LED_HT1628` n'est écrit que par `com.android.systemui` (FACADE_HT1628.md:76-98 ; JOURNAL.md:1414-1431).
- Pas de strace, pas de kprobes, ni kcore, ni kmem, ni mem.
- **Formule du labo** : « Sous Android on loue le matériel ; sous notre système on le possède » (JOURNAL.md:1433).
- **Version libmali/kbase** : non notée dans le corpus. [sœur 30/09] DDK `g25p0-00eac0`.

---

## 5. Armbian / Linux

### 5.1 Image, noyau, démarrage

**Image [M 23/08]** :

- `Armbian_26.08.0_rockchip_x88pro20_bookworm_6.1.141_server_2026.08.15.img.gz` (ophub) : DTB fourni, version serveur, sans bureau (BRIEF_DISTRO_ARCHI.md:181-193).
- Noyau `6.1.141-rk35xx-ophub`, aarch64 (JOURNAL.md:1060-1072).
- Carte écrite depuis le Rock 5B, sha256 vérifié (JOURNAL.md:1074-1081).

**`noeud/armbianEnv.txt`, copie versionnée :**

| Ligne(s) | Contenu |
|---|---|
| 1-3 | `verbosity=1`, `bootlogo=false`, `fdtfile=rockchip/rk3566-x88pro20.dtb` |
| 4-6 | rootfs ext4 en rw sur la SD |
| 7-9 | `earlycon=on`, `console=both`, `consoleargs=console=ttyS02,1500000 console=tty0` |
| 11 | `extraargs=quiet loglevel=1 vt.global_cursor_default=0 video=HDMI-A-1:1280x720@60 mem=3838M` |
| 13-15 | `overlay_prefix=rk3566`, `overlays=` vide, `user_overlays=` vide |

**Boot masqué [M 23-30/08]** :

- `bootlogo=false` coupe le logo U-Boot et le bootsplash (JOURNAL.md:2031-2034).
- `getty@tty1` est désactivé et `console=tty0` conservé.
- Le logo s'affiche sur Smart0, puis la vidéo par-dessus (noeud/README.md:112-127).

**Overlays U-Boot [M 25-31/08]** :

- Pour le plane-mask VP1, un overlay **échoue EN SILENCE**. U-Boot remet l'arbre d'origine, et seule la console série le montre. Remède : un DTB complet sous un autre nom, désigné par `fdtfile` (CAPTURE_DIRECTE.md:452-455).
- En revanche, l'overlay `pxl-ddc-i2c5` passe par `user_overlays` (JOURNAL.md:4012-4023, 4073-4074).
- Un overlay mal formé empêche le boot (JOURNAL.md:1649-1651).

**Écriture de `/boot/armbianEnv.txt`** : elle se fait désormais par fichier temporaire, vérification, sync puis mv, plus jamais par `sed -i` (JOURNAL.md:3632-3642).

### 5.2 Décodage, RGA, GStreamer

**Pas de V4L2 [M 23/08]** (CODECS.md:8-26) :

- Aucun `/dev/video*` ni `/dev/media*`, seulement `/dev/mpp_service`.
- Les recettes `v4l2h264dec`/`v4l2convert` ne s'appliquent donc pas.
- [sœur 30/09] Toujours vrai.

**Moteurs [M 23/08]** (JOURNAL.md:1085-1091 ; CODECS.md:30-52) :

- `/proc/mpp_service` liste `iep jpegd load rkvdec0 rkvenc vdpu vepu`.
- La charge par moteur se lit dans `/proc/mpp_service/load`.

**MPP compilé sur la box [M 23/08]** (JOURNAL.md:1139-1180, 1303-1307, 1342-1344 ; noeud/README.md:64-70) :

- Aucun paquet apt : `rockchip-linux/mpp` 1.1.0 est compilé sur place.
- Débits de `mpi_dec_test` : H.264 1080p à 234,5 img/s, MJPEG à 176 img/s.
- `gstreamer1.0-rockchip1` vient d'un .deb du dépôt Radxa rk3588.
- **`librga.so.2` a été copiée à la main** depuis Radxa OS. Il faudra la paqueter pour une flotte.

**Capacités du décodeur [D 29/08]** (MPP_DECODAGE_BOX.md:61-74, 344-357) :

- RKVDEC (vdpu34x) : AVC, HEVC et VP9 jusqu'en 4K, AFBC, 10 bits, **sans réduction d'échelle**, un seul cœur.
- rkjpegd : 4K.
- vdpu2 : MPEG2, H.263, MPEG4, AVC, MJPEG, VP8.
- **Pas d'AV1 sur le RK3566.**

**Débits mesurés [M 24-26/08]** :

- 4×1080p60 : H.264 AFBC à 116 img/s par flux, H.265 à 133 (MULTIVIEW.md:116-128).
- HEVC 1080p50 tout-Intra à 80 Mb/s : 50,8 img/s, zéro perte, SoC à 72-73 °C (JOURNAL.md:2546-2566).

**Pièges GStreamer [M 23/08] :**

- Les « 60 img/s » étaient comptés en entrée ; la réalité était 28,1. Sans `queue` après le décodeur, décodage et flip se sérialisent. Avec : 60,1 (JOURNAL.md:1621-1637 ; CODECS.md:84-92).
- `io-mode` : mmap donne 33,9, dmabuf-import + queue 4 donne 59,1 (CAPTURE_DIRECTE.md:43-60).
- kmssink `force-modesetting=true` échoue tant que fbcon tient l'affichage (JOURNAL.md:1281-1297).
- Un élément exige un tampon WRITABLE. Le tampon de mppjpegdec est retenu, donc copié, le pool s'épuise et le flux gèle (JOURNAL.md:1773-1786).
- Un `set_state` qui rend SUCCESS immédiatement sur un pipeline de sink doit alerter (JOURNAL.md:2044-2054).

**RGA2 et mémoire [M 23-24/08] :**

- La RGA2 a une **MMU 32 bits** : elle refuse les tampons au-dessus de 4 Go (`RGA_MMU unsupported memory larger than 4G`).
- Le banc de 256 Mo situé à 8,4 Go a donc été retiré par `mem=3838M` (MULTIVIEW.md:238-286 ; JOURNAL.md:2205-2227).
- Une source prise dans `/dev/dma_heap/system` est refusée : il faut `/dev/dma_heap/reserved`, en CMA.
- Une destination MPP passée par le DRM rockchip donne `swiotlb buffer is full` (JOURNAL.md:1810-1823).
- Le CMA de 800 Mo n'est utilisé qu'à 0,3 %, parce que MPP et GStreamer allouent dans le tas system (MULTIVIEW.md:288-301).

### 5.3 KMS : maître, présentation

**`turbohq-presente`** :

- Tient le maître et pose deux plans (JOURNAL.md:1846-1862).
- Affiche à l'arrivée, sans attendre le vblank (JOURNAL.md:2433-2434 ; DOSSIER_LATENCE_GLASS_TO_GLASS.md:386-395).
- `THQ_LOGO=fige` laisse la dernière image au balayage sans qu'aucun code ne tourne ; une image du pool reste alors immobilisée (JOURNAL.md:2024-2029).

**`turbohq-direct`** :

- Chaîne : EXPBUF de la carte de capture → `drmPrimeFDToHandle` → AddFB2 → Esmart0.
- 60,0 img/s pour 3,7 % d'un cœur (CAPTURE_DIRECTE.md:217-249 ; JOURNAL.md:2448-2469).

**Pièges KMS [M 25/08]** :

- `page_flip_handler2` v3 porte l'id du CRTC.
- L'`encoder_id` d'un connecteur éteint ne vaut rien : utiliser l'index du CRTC dans `possible_crtcs`.
- Une compilation échouée laisse l'ancien binaire en place.
- Sources : CAPTURE_DIRECTE.md:536-543, 692-706.

### 5.4 Gouverneurs, thermique, alimentation, mémoire

**Thermique [M 24-26/08]** :

- Seuils : 75 °C (passif), 85 °C (passif), 115 °C (critique). Le CPU va de 1416 à 1608 puis 1800 MHz selon la charge (JOURNAL.md:2577-2588).
- À 85 °C, il plafonne à 1608 MHz sur 1800 (MULTIVIEW.md:457-473 ; DUPLEX.md:194-213 ; JOURNAL.md:2172-2176).
- Après des heures de charge, la fréquence oscille de 11 %. Un écart inférieur à environ 1,6 ms n'est alors plus mesurable (JOURNAL.md:2332-2336).
- La note conclut : « le thermique sera le mur avant le réseau ou le silicium ».

**Alimentation [M 23/08]** (JOURNAL.md:1511-1536) :

- Pas de PMIC.
- `vdd_cpu` et `vdd_logic` sont des régulateurs PWM en boucle ouverte.

**[sœur 30/09] Gouverneurs et DDR** :

- CPU en `schedutil`.
- **`dmc` désactivé**, avec une seule OPP à 1560 MHz : la fréquence DDR réelle est inconnue.
- `clk_ddr1x` à 464 MHz.

**[D] Recette temps réel** (écrite pour le RK3588) : gouverneur performance, cpuidle limité au WFI, THP désactivé, SCHED_FIFO, mlockall (DOSSIER_LATENCE_GLASS_TO_GLASS.md:1832-1835, 1880-1893).

**Mémoire [M]** :

- 3725 Mo après `mem=3838M` (MULTIVIEW.md:238-286).
- 637 Mo utilisés le 08/09 (README.md:64-71).
- Une fuite de 3,4 Go dans `thq-mjpeg-pipe.mjs` a provoqué quatre « gels » : SSH timeoute à la bannière parce que le noyau évince les pages de sshd (JOURNAL.md:1467-1492, 1590-1619).
- Remèdes, dans `noeud/turbohq.service` : `MALLOC_ARENA_MAX=2` et `MALLOC_TRIM_THRESHOLD_` (l. 18-19), puis `MemoryMax=512M` (l. 44).
- **Pas de pile RTC** (JOURNAL.md:1586-1588).

### 5.5 Support de démarrage

**microSD [M 23/08]** (BRIEF_DISTRO.md:161-209 ; noeud/README.md:172-180 ; JOURNAL.md:1662) :

- 50 MHz, 4 bits, HS : 24,2 Mo/s.
- Le DTB ne déclare aucun `sd-uhs-*`, alors que le régulateur 1,8/3,3 V est câblé.
- L'overlay UHS `uhs-carte-sd.dts` est écrit, **pas appliqué**.

**Fragilité de la carte :**

- Un retrait à chaud provoque un kernel panic ; une carte mal enfoncée fait redémarrer sur Android (JOURNAL.md:1467-1492 ; WIFI_SEEKWAVE.md:313-333).
- La note tranche : « Un boîtier qui démarre depuis une carte amovible n'est pas un produit ».
- `/tmp` est un tmpfs, vidé à chaque reboot (JOURNAL.md:2271-2272).

### 5.6 Plan « distro TurboHQ » (non réalisé)

**Décision du 23/08** (README.md:318-325 ; BRIEF_DISTRO.md:9-71) :

- Android pour n'importe quelle box.
- Une distro pour nos boîtiers.
- Premier jalon sur microSD, eMMC intacte.

**Noyau** : le BSP vendeur 6.1 plutôt que le mainline, parce que les codecs décident. Construction par armbian-build (BRIEF_DISTRO.md:78-88 ; BRIEF_DISTRO_ARCHI.md:28-54).

**Disposition prévue** (BRIEF_DISTRO_ARCHI.md:56-130) :

- `boot_a/b` : 256 Mo en FAT.
- `rootfs_a/b` : 3 Go en **squashfs en lecture seule**.
- `data` en lecture-écriture, avec `/etc` en overlayfs.
- Mises à jour par RAUC, avec `bootcount`/`bootlimit=3` dans U-Boot.
- journald en volatile.

**Cartes de déploiement** : Orange Pi 3B ou ROCK 3C. La box ne sert qu'à valider, car un même nom ne garantit pas une carte identique (README.md:267-269 ; BRIEF_DISTRO_ARCHI.md:198-202 ; JOURNAL.md:1147-1160).

### 5.7 Services déployés et pilotage de l'écran

**Inventaire** : 21 unités versionnées (JOURNAL.md:4796-4799).

**`turbohq.service` → `turbohq-affiche`** (`Restart=always`) :

- `THQ_SORTIE` vaut `kms` par défaut (turbohq-affiche:222), ce qui lance `gst-launch … kmssink … sync=false qos=false render-rectangle plane-properties=p,zpos=2` (turbohq-affiche:206, 258).
- Avec `presentateur`, le script fait `exec turbohq-presente` (turbohq-affiche:232-246).
- [sœur 30/09] Le maître actuel s'appelle `turbohq-present`. C'est `turbohq-presente` tronqué par `comm` à 15 caractères : la box tourne donc en mode présentateur.

**Modèle de pilotage, un maître et des fichiers déposés dans `/run`** : le présentateur lit :

- `/run/turbohq-osd.bgra`, l'OSD ;
- `/run/turbohq-menu`, le verrou du menu ;
- `/run/turbohq-mode`, `-mode-ok` et `-mode-attente` ;
- `/run/turbohq-cadrage` ;
- `/run/turbohq-veille.bgra` ;
- `/run/turbohq-canal`.

(noeud/turbohq-presente.cpp:106-153, 673, 1563)

**Qui écrit quoi :**

- `turbohq-osd.py` écrit l'image BGRA, ou `/dev/fb0` en mode `--bandeau` (turbohq-osd.py:5-11, 61).
- `turbohq-logo` peint fb0 (noeud/README.md:47-56).

**Autres services :**

- `pxl-quad.service` : `Conflicts=turbohq.service`, puisqu'il n'y a qu'un maître (noeud/pxl-quad.service:7).
- `turbohq-console` : port 8088, en root, **sans mot de passe** (noeud/README.md:89-108 ; noeud/turbohq-console.service:7).
- `pxl-relais` : relais sur 8080 et 8443, certificat tailscale renouvelé chaque semaine (JOURNAL.md:3341-3375).

**Charge le 08/09** : environ 66 % d'UN cœur à 78 °C (JOURNAL.md:4596-4625).

**Entrées** : la numérotation `/dev/input/event*` change d'un boot à l'autre (dw_hdmi, gpio_ir_recv, macropad). Identifier chaque périphérique par ses capacités (JOURNAL.md:2715-2735).

**Touche POWER** : un appui long déclenche `poweroff` (JOURNAL.md:3837-3838).

**Modules :**

- Les en-têtes ophub sont compilés contre glibc 2.38, bookworm n'a que 2.36 : relancer `reparer-headers.sh` après chaque mise à jour du noyau (WIFI_SEEKWAVE.md:47-57 ; noeud/README.md:166-170).
- Le Wi-Fi est soit point d'accès, soit client, jamais les deux (DOSSIER_WIFI_SWT6621S.md:29-44).

---

## 6. Impasses, errata et pièges qu'un kiosque retrouvera

### 6.1 Pièges déjà payés

**Côté navigateur :**

1. **La page est une seule fenêtre composée par le GPU.** Plein écran, MSE contre WebCodecs, version du moteur : rien n'y change (RECEPTEUR_H264.md:686-728, 887-912). Sous Linux, la question se repose à l'identique : Chromium sait-il sortir la vidéo sur un plan dédié ?
2. **Compter ce qui est présenté, pas ce qui est reçu ou décodé.**
   - 58 images reçues, 27,1 présentées (RECEPTEUR_H264.md:861-868).
   - 60 comptées en entrée, 28,1 réelles (JOURNAL.md:1621-1637).
   - La moyenne cumulée de `ps %cpu` masque les pics (JOURNAL.md:4946-4953).
3. **Contexte sécurisé et certificats** (voir 3.2) :
   - WebCodecs n'existe pas hors contexte sécurisé ;
   - WSS refuse l'auto-signé ;
   - le SAN est obligatoire ;
   - `localhost` est exempté.
4. **Sous Android** (voir 3.1-3.3) :
   - les drapeaux sont ignorés ;
   - l'autoplay est bloqué ;
   - Cromite n'a pas de codecs propriétaires dans WebCodecs ;
   - un APK arm64 ne démarre pas.
5. **Exploitation** (voir 3.6) :
   - une seule page doit décoder ;
   - une app en arrière-plan est gelée ;
   - un 404 sur un module ES tue la page ;
   - `location.reload()` via CDP ne fait rien.
6. **WebGPU** : un device perdu ne dit rien, et SwiftShader ne présente pas. Les chiffres de VM ne valent rien (CODEC_JPEG_WEBGPU.md:131-159).

**Côté affichage :**

7. **Cluster0 est AFBC seulement.**
   - Le plan « bulles AR24 sur Cluster0 » (BULLES_ET_PLANS.md:17, 28-39) est caduc pour un tampon linéaire (DIX_BITS.md:113-125).
   - Sans `drm.debug`, l'EINVAL est nu.
8. **Primaire opaque au-dessus de la vidéo = écran noir.** Et le `zpos` de kmssink est inerte (voir 1.2).
9. **Un seul maître DRM** (voir 1.3) :
   - modetest pendant qu'un maître tourne rend Permission denied ;
   - un `EBUSY` sur SetMaster désigne souvent un orphelin ;
   - `pkill -f` et `pgrep -f` ont tué des sessions SSH. Utiliser `pgrep -x` et tuer par PID (JOURNAL.md:2066-2073, 2257-2259).
10. **Partage de plans par le DTB** : écran vert, sans aucune erreur (voir 1.4).
11. **fbdev contre DRM** : fbdev reste en 1280x720 pendant que DRM tourne en 1080p, et fbcon reprend l'écran dès que le maître est rendu (voir 1.6). Un kiosque qui plante laisse la console en 720p.
12. **Démarrage** :
    - un overlay U-Boot peut échouer en silence ;
    - un DSI en échec tue le HDMI ;
    - `cardN` n'est pas stable ;
    - vérifier le `boot_id` avant de lire un journal (voir 1.4, 1.8, 5.1).
13. **`pinmux-pins` fait segfaulter le noyau** (JOURNAL.md:4058-4060).
14. **Writeback** : il écrête la plage, et son connecteur se glisse dans la liste des écrans (voir 1.5).
15. **Veille** : `dpms` via sysfs est refusé ; seul `blank=4` fonctionne. Pas de suspend, et le CEC est inopérant (voir 1.6).

**Côté système :**

16. **RGA2 et mémoire au-dessus de 4 Go** (voir 5.2) : `mem=3838M` est la condition. Un tampon GPU ou navigateur qui passe par la RGA en hérite.
17. **Fuite et arènes glibc** : poser `MemoryMax` et `MALLOC_ARENA_MAX` (voir 5.4).
18. **CRLF** d'un déploiement Windows, et `/tmp` vidé au boot (JOURNAL.md:3660-3663, 2271-2272).
19. **Dérive thermique** : à chaud, les comparaisons à moins de 1,6 ms ne valent rien (JOURNAL.md:2332-2336).
20. **Méthode** : relire ses propres dossiers avant les sources (JOURNAL.md:3001-3005).

### 6.2 Contradictions internes au corpus

- **(a) Nombre de fenêtres.**
  - Trois : « trois fenêtres, un seul port vidéo » (MULTIVIEW.md:24-28), et « trois câblées, Esmart1 fantôme » (BULLES_ET_PLANS.md:225-236).
  - Six : « Le RK3566 n'a que six fenêtres » (noeud/turbohq-mode-video:8-9).
  - Pourtant, Esmart1 (plan 122) a été utilisé sur VP0 et mesuré à 57-63 img/s (CAPTURE_DIRECTE.md:575-581, 907-944, 1017-1022). Et deux CRTC existent avec le DTB VP1 (CAPTURE_DIRECTE.md:384-405).
  - Non tranché (BULLES_ET_PLANS.md:238-240).
- **(b) Habillage sur Cluster1.**
  - Un habillage AR24 linéaire a été posé sur le plan 154 (Cluster1 d'après CAPTURE_DIRECTE.md:594-615) et compté « 74 rendues ».
  - L'affichage n'a pas été vérifié à l'écran (CAPTURE_DIRECTE.md:1017-1033), et le plan a été choisi sur la seule liste de formats, sans modificateurs (noeud/turbohq-direct.cpp:736-756).
  - Or « le Cluster rejette tout linéaire » (DIX_BITS.md:113-125).
- **(c) AFBC sous Android.**
  - Mesuré : `AB24 _AFBC-16x16` sur `Cluster0-win0` (RECEPTEUR_H264.md:417-421).
  - [sœur 30/09] Pourtant `vendor.gralloc.disable_afbc=1`.
  - Peut-être que la cible client de SurfaceFlinger échappe à ce réglage. À éclaircir avant d'en conclure que l'AFBC est « vide » sur RK3566.
- **(d) CEC.**
  - « Pas compilé » (JOURNAL.md:1661 ; noeud/turbohq-presente.cpp:139-143).
  - Mais `/dev/cec0` existe, d'adresse physique `f.f.f.f` (JOURNAL.md:3869-3877).
  - Côté Android, `CONFIG_DRM_DW_HDMI_CEC=y` [lu 30/09, kconfig.txt:4322].
- **(e) Ordre Smart0/Esmart0.**
  - « Smart0 est SOUS la vidéo » (BULLES_ET_PLANS.md:120-124), et la vidéo passait au-dessus de la console sous kmssink (noeud/README.md:112-127).
  - Mais le primaire est **devant** Esmart0 dans le quad (MULTIVIEW.md:337-352).
  - L'ordre dépend des `zpos` posés par chaque programme : toujours le poser.
- **(f) Overlays U-Boot.**
  - « Échec silencieux » (CAPTURE_DIRECTE.md:452-455), mais `pxl-ddc-i2c5` fonctionne (JOURNAL.md:4012-4023, 4073-4074).
  - La copie versionnée de `armbianEnv.txt` a pourtant un `user_overlays=` vide (noeud/armbianEnv.txt:15).
- **(g) Les 20 ms du tier T2.**
  - CHEMINS_ET_TIERS_LATENCE.md:42 les attribue à kmssink natif.
  - Ils ont été mesurés dans Cromite sous Android (PREMIER_FLUX.md:5-8, 181-187).
- **(h) `screencap`.**
  - Le commentaire de `bench/cdp.mjs:5-6` dit qu'il rend la vidéo noire.
  - Le noir venait d'un `<video>` en pause (PREMIER_FLUX.md:132-177).
- **(i) H.264 High 10.**
  - « Passe » (JOURNAL.md:1900-1901).
  - « Non prouvé » (H264_SUR_RK.md:97-102 ; DIX_BITS.md:38-44).
- **(j) AV1.**
  - « Déclaré » par les caps de `mppvideodec` (CODECS.md:56-67).
  - Absent du RK3566 (MPP_DECODAGE_BOX.md:344-357 ; AUDIT_SINCERITE_HS86_PRO20.md:240-251).
- **(k) Latence.** Writeback à 5 ms contre viewer à 20 ms : l'écart n'est pas expliqué (CHEMINS_ET_TIERS_LATENCE.md:283-288).
- **(l) Partitions.** `boot.img` est donnée comme p7 (FACADE_HT1628.md:100-102), mais le DTB a été extrait de p8 (JOURNAL.md:3989-3992). Avec la GPT relevée par la note sœur, p8 serait recovery [C].
- **(m) Charge GPU.** 0 % mesuré pendant qu'une peinture WebGL coûte environ 20 ms par image (RECEPTEUR_H264.md:861-868 contre 779-801) : méthode inconnue.

---

## Ce qui manque encore

1. **Un navigateur sous Linux, sur cette box.**
   - Rien n'a été essayé : Chromium Debian 151, Chromium patché Rockchip, cage, weston, X.
   - Ni cadence mesurée, ni plans relevés.
2. **Panfrost contre libmali.**
   - Aucun banc GL, GLES ou Vulkan, aucun fps WebGL.
   - Aucun noyau Linux avec kbase + libmali Linux n'a été essayé (ophub n'a pas kbase [sœur 30/09]).
   - La version de Mesa est absente du corpus.
3. **Instruments de mesure.**
   - La méthode de mesure de la charge GPU n'est pas écrite, et on ne sait pas quoi lire sous Linux.
   - Fréquence DDR réelle inconnue, `dmc` désactivé [sœur 30/09].
4. **Réalité des fenêtres Esmart1, Smart1 et Cluster1** : mire sur Esmart1 en mode simple (BULLES_ET_PLANS.md:238-240).
5. **Cluster0 alimenté par de l'AFBC rendu par le GPU** (modificateurs AFBC de Mesa/Panfrost) : jamais essayé sous Linux. C'est le seul moyen connu d'obtenir un troisième plan utilisable pour une page.
6. **Plans curseur** : rien.
7. **4K60.**
   - Un seul instantané, celui de la note sœur.
   - Coût non mesuré d'une page composée en 4K contre 1080p agrandi par le VOP, choix du constructeur Android [sœur 30/09].
   - Bande passante balayage + GPU non mesurée.
8. **Décodage matériel pour Chromium Linux.**
   - Il n'y a aucun nœud V4L2.
   - libv4l-rkmpp et le Chromium patché Rockchip n'ont jamais été évalués.
   - La promotion de `<video>` sur un plan DRM par un compositeur Wayland n'a pas été testée.
9. **Déchargement sur plans matériels sous Wayland.**
   - Ni weston (backend DRM) ni wlroots/cage n'ont été testés.
   - Faire cohabiter compositeur et présentateur suppose un bail ou le protocole de surfaces : non tenté avec un navigateur.
10. **Voie Android.**
    - APK Google Chrome jamais essayé.
    - Remplacement du fournisseur WebView sur ce build user/debuggable jamais tenté.
    - Mode kiosque Android non documenté : launcher, lock-task, lancement au boot.
    - Décision d'autoplay encore ouverte.
11. **Thermique sous charge GPU soutenue** (animations, WebGL) : non mesurée.
12. **Politique de HWC** (quand une couche reçoit un overlay, rôle de `compose_policy`) : non documentée.
13. **VRR, `LINE_FLAG1`, flip asynchrone** : seulement lus dans le BSP RK3588.
14. **Alimentation de l'écran.**
    - CEC inopérant.
    - DPMS par la propriété atomique `ACTIVE=0` jamais essayé.
    - Pas de suspend.
15. **Plage de couleur d'un plan RGB d'interface sur une sortie YUV limited** [sœur 30/09] : non vérifiée à l'œil ni au writeback.
16. **Entrées d'un kiosque** : télécommande IR (`gpio_ir_recv`), clavier, focus du navigateur. Non traité : seul le menu lit `/dev/input`.
17. **Démarrage d'un kiosque.**
    - Temps jusqu'à la première page non mesuré.
    - Installation eMMC, A/B et rootfs en lecture seule non faits.
    - Overlay UHS non appliqué.
18. **Sauvegarde eMMC** : sommes de contrôle non confirmées (JOURNAL.md:1574-1582). C'est un prérequis à tout flash de l'eMMC.
19. **Empreinte mémoire de Chromium** sur 3,7 Go de RAM, avec 800 Mo de CMA : jamais mesurée.
