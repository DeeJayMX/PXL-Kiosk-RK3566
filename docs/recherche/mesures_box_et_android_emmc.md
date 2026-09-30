# Mesures sur la box TurboNode et lecture de l'Android d'origine (eMMC)

*Relevé du 30/09/2026 sur `turbonode` (X88Pro20 / HS86 Pro20, RK3566), par SSH
sur le tailnet. Tout en **lecture seule** : l'eMMC a été lue via des loop
`losetup -r` et des montages ext4 `ro,noload`, défaits en sortie. État vérifié
après coup : 0 loop, 0 montage `mmcblk2`, répertoire temporaire supprimé, aucun
module chargé. Tags : **[M]** mesuré ici · **[L]** lu dans un fichier de la box ·
**[D]** déduit.*

## 1. Le Linux qui tourne (Armbian ophub, amorcé sur microSD)

- [M] Armbian 26.08 bookworm, noyau `6.1.141-rk35xx-ophub` (BSP Rockchip),
  racine sur `/dev/mmcblk0p2` (microSD, 15 Go). Compatible DT :
  `rockchip,rk3566-x88pro20`, `rockchip,rk3566`.
- [M] GPU : module `panfrost` chargé, Mesa Debian **22.3.6** ; Mesa **25.0.7**
  disponible en `bookworm-backports`.
- [M] 🔴 **Le noyau ophub n'a PAS le pilote Mali propriétaire** :
  `# CONFIG_MALI_BIFROST is not set`, aucun module `mali`/`kbase` dans
  `/lib/modules`. ⇒ [D] **libmali est impossible sur ce noyau** sans le
  recompiler : Panfrost est la seule pile GPU disponible telle quelle.
- [M] Vidéo : pas de `/dev/video*`, seulement `/dev/mpp_service` (MPP). ⇒ [D]
  un Chromium standard (Debian 151) n'a aucun décodeur vidéo matériel
  utilisable ici.
- [M] Aucun serveur X ni Wayland installé. Candidats apt : chromium 151
  (21 paquets à installer), cage 0.1.4 (14 paquets), weston 10.0.1.
- [M] Affichage actuel : `turbohq-present` est le **maître DRM** de `card0`. Sortie
  HDMI-A-1 en **3840x2160p60** (dclk 594 MHz, `YUV8_1X24`, BT.709 limited), avec :
  - **Esmart0-win0** en NV12 1920x1080, agrandi ×2 vers 3840x2160 par le VOP2 ;
  - **Smart0-win0** en XR24 412x102 (OSD).

  ⇒ **zéro composition GPU** : c'est la référence d'efficacité sur cette box.
- [M] Horloges (`clk_summary`) : `aclk_vop` 500 MHz, `dclk_vop0` 594 MHz,
  `clk_gpu` 166 MHz (GPU au repos, aucun client GL), `clk_ddr1x` 464 MHz.
  [D] Cette dernière valeur n'est pas forcément la fréquence DRAM réelle : la
  DDR est pilotée par le firmware de confiance.
- [M] 🔴 **La mise à l'échelle DDR est éteinte sous Armbian.** Le nœud DT
  `dmc` est `status = "disabled"` ; sa table d'OPP ne déclare qu'un point à
  **1560 MHz**, et aucun nœud `devfreq/dmc`. ⇒ [D] la DDR tourne à la fréquence
  posée par le loader, inconnue à ce jour. **À mesurer**, par le log série du
  loader ou un banc mémoire : c'est la bande passante qui nourrit à la fois le
  balayage 4K60 et le GPU.
- [M] Gouverneurs : CPU `schedutil` (1,8 GHz max) ; GPU `simple_ondemand`
  (200-800 MHz).
- [M] Mémoire : 3,7 Go de RAM, CMA 800 Mo (769 Mo libres).

## 2. L'Android 14 d'origine sur l'eMMC (`mmcblk2`, 31,27 Go)

- [M] Partitions GPT : `security` · `uboot` · `trust` · `misc` · `dtbo` · `vbmeta` ·
  `boot` (64 Mio) · `recovery` (96 Mio) · `backup` · `cache` · `metadata` ·
  **`baseparameter`** (1 Mio) · **`super`** (2400 Mio) · `userdata` (26,4 Gio).
- [M] `super` : métadonnées « dynamic partitions » LP v10.0, 2 slots, non A/B.
  Contenu : `system` (1004 Mio), `system_ext`, `vendor` (252 Mio), `vendor_dlkm`,
  `odm`, `product` (351 Mio), toutes en **ext4**, chacune en une seule extent
  linéaire.
- [L] `ro.rksdk.version=ANDROID14_MS_RKR4`, `ro.board.platform=rk356x`,
  `ro.build.version.release=14`. L'empreinte de build est usurpée
  (`google/redfin…`).
- [L] ⭐ **Le constructeur rend l'interface en 1080p, pas en 4K** :
  - `vendor/build.prop` : `persist.vendor.framebuffer.main=1920x1080@60` (et
    `.aux` idem) ;
  - `vendor/etc/display_settings.xml` : `local:0` `forcedWidth="1920"`
    `forcedHeight="1080"` `forcedDensity="240"` ;
  - `baseparameter` (magic `BASP` v2.1) : **1920×1080 @ 60** dans les deux copies.

  ⇒ [D] Sur ce Mali-G52, la pile de référence Rockchip compose en 1080p et
  confie l'agrandissement à la sortie. C'est aussi ce que fait `turbohq-present`.
- [L] ⭐ **`vendor.gralloc.disable_afbc=1`** : le constructeur désactive l'AFBC
  dans gralloc sur cette puce. ⇒ [D] ne pas compter sur l'AFBC comme levier sur
  RK3566.
- [L] GPU côté Android :
  - `ro.hardware.egl=mali` ;
  - `ro.opengles.version=196610` (= GLES 3.2) ;
  - `ro.hwui.use_vulkan=true` (l'interface Android est rendue en Vulkan) ;
  - `vendor/lib/egl/libGLES_mali.so`, **32 bits**, 33,6 Mo, version DDK
    **`g25p0-00eac0`** (« Bifrost », « Mali-G52 ») ;
  - `vendor/lib/hw/vulkan.rk356x.so`.
- [L] Noyau Android (config extraite le 22/08, `box_extract/kconfig.txt`) :
  `CONFIG_MALI_BIFROST=y`, `CONFIG_MALI_BIFROST_DEVFREQ=y`,
  `CONFIG_EROFS_FS=y`, noyau 6.1.157. ⇒ [D] libmali g25p0 est lié à ce noyau
  kbase et à bionic : **non transplantable** sur l'Armbian glibc.
- [L] Composition Android :
  - service `android.hardware.graphics.composer3-service.rockchip` (HWC3
    AIDL), plus `hwcomposer.rk30board.so` et `vendor.rockchip_hwcproxy_aidl` ;
  - `vendor.hwc.compose_policy` passe de 1 à 2 à l'init ;
  - `vendor.hwc.device.primary=HDMI-A` ;
  - `HwComposerEnv.xml` v1.2.0 `Enable="0"` (mode « split » désactivé).
- [L] ⭐ **Android pilote la DDR selon le besoin de l'affichage** : l'init donne à
  `system` le nœud `/sys/class/devfreq/dmc/vop_bandwidth`. ⇒ [D] sous Android,
  la fréquence DDR suit le besoin du VOP ; sous Armbian, `dmc` est éteint
  (§ 1).
- [L] WebView : `product/app/webview/webview.apk`, 90,9 Mo,
  `lib/armeabi-v7a/libwebviewchromium.so`. C'est le WebView AOSP déjà mesuré en
  113.0.5672.136 (voir `RECEPTEUR_H264.md`).

## 3. Ce qui se récupère, et ce qui ne se récupère pas

| Élément Android | Récupérable pour un kiosque Linux ? |
|---|---|
| Choix « compose en 1080p, sortie 4K agrandie » | ✅ **la recette** : même principe que `turbohq-present` [D] |
| AFBC désactivé par le constructeur | ✅ comme information : levier probablement vide sur RK3566 [D] |
| `libGLES_mali.so` g25p0 | ❌ bionic 32 bits + kbase du noyau Android [D] |
| DMC avec retour de bande passante VOP | ⚠️ le **principe** : le nœud `dmc` existe dans le DT ophub mais il est désactivé [M] |
| DTB / DTBO d'Android | déjà extrait (`box_extract/box.dtb`, 22/08) |
| WebView 113 | ❌ déjà mesuré : plafond à ~27 img/s en vidéo 60p (composition GPU) |

## 4. Questions ouvertes nées de ce relevé

1. **Fréquence DDR réelle sous Armbian** (dmc éteint) : à mesurer.
2. **Une DMC réactivée** (DT + pilote) change-t-elle la marge du GPU et du
   balayage 4K ? Question de noyau, à peser.
3. **Un noyau avec `MALI_BIFROST`** (autre build Armbian vendor) plus libmali
   Linux : gain réel face à Panfrost + Mesa 25 ? Seule une mesure le dira.

## 5. Errata (ajoutés le 30/09, le texte ci-dessus est laissé tel quel)

- 🔴 **« le constructeur compose en 1080p et confie l'agrandissement à la sortie »
  (§ 2, [D]) — FAUX sur la moitié « agrandissement ».** Le labo avait **mesuré** le
  lien HDMI d'Android en **1080p60** (dclk 148,5 MHz, `RECEPTEUR_H264.md:399-411`) :
  sous Android, **c'est la TV qui agrandit**, pas le VOP2. Seul le présentateur
  Linux sort en 4K agrandie par Esmart0. *Mécanisme : j'ai prêté à Android le
  schéma de `turbohq-present`, que j'avais sous les yeux le même jour, sans relire
  la mesure du mode HDMI qui existait déjà.* La recette « composer en 1080p »
  tient ; ce qui en sort diffère.
- 🔴 **« ne pas compter sur l'AFBC comme levier sur RK3566 » (§ 2, [D]) — tiré trop
  vite d'une propriété.** `vendor.gralloc.disable_afbc=1` est bien lu, mais le labo
  avait **mesuré** la fenêtre de la WebView sous Android en `AB24 _AFBC-16x16` sur
  **Cluster0** (`RECEPTEUR_H264.md:399-427`) : la cible de SurfaceFlinger EST en
  AFBC. Une propriété lue ne dit pas ce que le pipeline fait. La question reste
  **ouverte** : Panfrost → AFBC → Cluster0 sous Linux n'a jamais été essayé.
- ⚠️ Et la même inférence erronée a nourri une explication fausse dans deux notes
  de recherche (« 27 img/s = DDR saturée en 4K ») : Android compose et sort en
  1080p, et le plafond est identique en 720p — **ce n'est pas un plafond de
  débit**. Le rapport de synthèse le consigne.
