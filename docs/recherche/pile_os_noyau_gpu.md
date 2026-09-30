# Pile OS / noyau / pilote GPU pour un Chromium kiosque accéléré sur RK3566 (Mali-G52 « 2EE », Bifrost v7, VOP2)

> Relevé du 30/09/2026. Conventions : chaque fait porte **la puce** à laquelle il s'applique
> (`{RK3566}`, `{RK3568}`, `{RK356x}` = les deux, `{RK3588}`, `{Bifrost v7}` = tout Mali-G31/G51/G52/G76
> quel que soit le SoC) **et** la version noyau / Mesa / blob concernée, plus sa provenance :
> **[mesuré par la source]** (banc ou test rapporté), **[lu]** (code, doc, changelog, config),
> **[déduit]** (mon inférence). ⚠️ `{RK3588}` = Mali-G610 / Valhall v10 / Panthor : **autre lignée**,
> rien de ce qui la concerne ne se transpose au RK3566 sans le dire.
>
> Méthode et limites d'accès (à lire avant de peser l'absence d'un fait) :
> - Le proxy de la session **refuse** (`Host not in allowlist`) : docs.mesa3d.org, collabora.com,
>   forum.armbian.com, forum.radxa.com, forum.libreelec.tv, phoronix.com, cnx-software.com, khronos.org,
>   lore/lkml/patchew/spinics, chromium.googlesource.com, wiki.pine64.org, docs.radxa.com, dietpi.com,
>   wiki.postmarketos.org, lwn.net, git.kernel.org, gitlab.freedesktop.org. Pour ces sites je n'ai que
>   des **extraits de moteur de recherche** (signalés « extrait »).
> - Contournement **légitime** (miroirs publics autorisés, aucune désactivation du proxy) : le code
>   source a été lu directement — noyau sur `github.com/torvalds/linux` (tags v6.1 → v7.2, `master` =
>   **7.3-rc5** au 30/09/2026), BSP Rockchip via `github.com/armbian/linux-rockchip` (branche
>   `rk-6.1-rkr7.2`, **6.1.172**), Mesa via le miroir `gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa`
>   (`main` = **26.3.0-devel**, tags `mesa-22.3.6`…`mesa-26.2.0`, API GitLab pour l'historique des commits),
>   Chromium via `github.com/chromium/chromium` (`main` = **157.0.8080.0**).
> - Le budget de recherche web de la session (200 requêtes, partagé) a été **épuisé** en cours de
>   travail : la recherche de bancs comparatifs (Panfrost vs libmali) s'est arrêtée là. Voir Gaps Q6.

---

## Q1 — Noyau BSP Rockchip 6.1 vs mainline (6.12 LTS, 6.18 LTS, 7.x) sur RK3566/RK3568 : VOP2, HDMI, GPU, DDR devfreq — lequel pour un kiosque ?

### Takeaway
Pour **cette** box (X88Pro20), le BSP 6.1 reste le seul chemin clé en main : c'est le seul noyau qui porte sa DTS (ophub ne la construit qu'en `rk35xx/6.1.y`), le HDMI 2.0 complet (4K60 + YUV420/10 bits/HDR), MPP/rkvdec2 et un pilote DMC. Le mainline est devenu crédible pour le **rendu** — HDMI 4K60 RGB depuis **6.13**, API noyau Panfrost bien plus riche (1.4 en 6.18, 1.6 en 7.0+) —, mais il n'a toujours **ni rkvdec2 pour RK356x, ni devfreq DDR**. Le YUV420 et la couleur profonde n'arrivent qu'en **7.3** (rc au 30/09/2026). Sur RK3566, le VOP2 n'offre que **3 fenêtres utilisables sur 6**, dans les deux noyaux.

### Cited Findings

**Versions de référence au 30/09/2026**
- `{noyau}` La branche `master` de Linux est en **7.3-rc5** [lu] — [Makefile master](https://github.com/torvalds/linux/blob/master/Makefile). Les tags v6.19, v7.0, v7.1 et v7.2 existent [lu] — [v6.19 Makefile](https://github.com/torvalds/linux/blob/v6.19/Makefile).
- `{RK356x}` Armbian (`armbian/build` main) : `vendor` = **6.1** depuis `armbian/linux-rockchip`, branche `rk-6.1-rkr7.2`. `current` = **6.18**, `edge` = **7.2**, `bleedingedge` = **7.3** [lu] — [rk35xx.conf](https://github.com/armbian/build/blob/main/config/sources/families/rk35xx.conf) ; [rockchip64_common.inc](https://github.com/armbian/build/blob/main/config/sources/families/include/rockchip64_common.inc). L'arbre BSP est en **6.1.172** [lu] — [linux-rockchip rk-6.1-rkr7.2 Makefile](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/Makefile).
- `{RK3566}` ophub : la X88Pro20 (entrée `r308`) est décrite ainsi : `rk3566-x88pro20.dtb`, « 8GB-LPDDR4, 64G-eMMC », balise noyau **`rk35xx/6.1.y` seulement**. La Rock-3C, elle, est en `stable/6.18.y` (mainline) [lu] — [model_database.conf](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/armbian-files/common-files/etc/model_database.conf). La config ophub rk35xx est aujourd'hui en **6.1.174**, et ses noyaux « stable » en 6.12.110 et 6.18.54 [lu] — [ophub kernel config-6.1](https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1). Le noyau rk35xx d'ophub est copié de `unifreq/linux-6.1.y-rockchip` [lu] — [ophub/kernel README](https://github.com/ophub/kernel).

**VOP2 — ce que le RK3566 n'a pas**
- `{RK3566}` Mainline : « On RK3566 these windows don't have an independent framebuffer. They can only share/mirror the framebuffer with smart0, esmart0 and cluster0 respectively. » `vop2_is_mirror_win()` écarte `SMART1`, `ESMART1` et `CLUSTER1` : ces fenêtres ne sont **jamais enregistrées comme plans DRM**. Le RK3566 partage la version de VOP du RK3568 ; le pilote le distingue par `soc_id == 3566` [lu, 7.3-rc5] — [rockchip_drm_vop2.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c). C'est le cas depuis la série d'origine (2021-2022), qui « does not register windows which don't have their own framebuffer on RK3566 » [lu, extrait] — [LWN, RK356x VOP2 support](https://lwn.net/Articles/890751/).
- `{RK3566}` BSP 6.1 : le pilote Rockchip gère ces fenêtres comme des **miroirs** d'une fenêtre source (`WIN_FEATURE_MIRROR`, `vop2_mirror_win_get_src()`, `RK3566_MIRROR_PLANE_MASK`). Elles servent donc au clonage, pas à un plan indépendant [lu, 6.1.172] — [BSP rockchip_drm_vop2.c](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c).
- `{RK356x}` Mainline, les trois fenêtres utiles : Smart0 et Esmart0 sont de type `PRIMARY`, **LINEAR uniquement** (`format_modifiers = {LINEAR}`). Smart = RGB seulement ; Esmart = RGB + NV12/NV15/NV16/NV20/NV24… Cluster0 est de type `OVERLAY`, en modificateurs AFBC. Le pilote écrit : « **The cluster window on 3568 is AFBC-only** » [lu, 7.3-rc5] — [rockchip_vop2_reg.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_vop2_reg.c) ; [rockchip_drm_vop2.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c).
- `{RK356x}` Mainline, sortie maximale par Video Port : VP0 **4096×2304** (avec `VOP2_VP_FEATURE_OUTPUT_10BIT`), VP1 2048×1536, VP2 1920×1080 [lu] — [rockchip_vop2_reg.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_vop2_reg.c).

**HDMI**
- `{RK356x}` Dans **v6.1, v6.6 et v6.12**, `rk3568_chip_data.max_tmds_clock` n'est pas à 594000. En v6.12, il vaut **340000**, ce qui filtre le 4K60 (594 MHz). Il passe à **594000** en **v6.13**, avec une entrée PHY à 594 MHz et un filtrage des modes par la PLL (`hdmiphy_clk`) ; c'est inchangé en v6.18, v7.0 et v7.2 [lu, code aux tags] — [dw_hdmi-rockchip.c v6.12](https://github.com/torvalds/linux/blob/v6.12/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c) ; [v6.13](https://github.com/torvalds/linux/blob/v6.13/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c).
- `{RK356x}` Commits correspondants (Jonas Karlman « Kwiboo », fusionnés par mmind, datés 2024-08/09) : « drm/rockchip: dw_hdmi: Enable 4K@60Hz mode on RK3399 and RK356x », « Add phy_config for 594Mhz pixel clock », « Add max_tmds_clock validation », « Filter modes based on hdmiphy_clk » [lu] — [historique dw_hdmi-rockchip.c](https://github.com/torvalds/linux/commits/master/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c). La série a été **testée sur une Radxa ROCK 3A, donc un RK3568**, pas un RK3566 [lu, extrait] — [Patchew, série 4K@60Hz](https://patchew.org/linux/20240908145511.3331451-1-jonas@kwiboo.se/).
- `{RK356x}` Le `mode_valid` mainline rejette tout mode dont l'horloge `ref`/`vpll` ne sait pas produire le pixel clock à **0,1 %** près (`MODE_NOCLOCK`). Il rejette aussi tout mode au-delà de `max_tmds_clock` (`MODE_CLOCK_HIGH`) [lu] — [dw_hdmi-rockchip.c master](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c).
- `{RK356x}` **YUV420 et couleur profonde** en mainline : **absents de v7.2**. `master` (7.3-rc5) ajoute les formats de bus `RGB101010`, `YUV8/YUV10 1X24/1X30` et `UYYVYY8/10` (→ `ROCKCHIP_OUT_MODE_YUV420`), ainsi que `output_bpc` transmis au PHY [lu] — [dw_hdmi-rockchip.c master](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c). Ce travail vient de la série « drm: bridge: dw_hdmi: Misc… » (v3→v7, avril-mai 2026), qui « prepares for future support of YCbCr and Deep Color » [lu, extrait] — [Ratatoskr v7 00/23](https://ratatoskr.run/linux-rockchip/2026/05/16995575/t). Un commit « drm/rockchip: dw_hdmi: Set output_port for RK3568/RK3566 » date du 2026-06-02 [lu] — [historique](https://github.com/torvalds/linux/commits/master/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c).
- `{RK356x}` Côté LibreELEC (non daté, fil « LE13 testing ») : la chaîne HDMI du RK3568 utilise `dw-hdmi` (et non `dw-hdmi-qp`). Leurs anciens correctifs 4K/HDR (2018-2022) « bit-rotted » ; Kwiboo réécrit l'ensemble (150+ correctifs, ~3/8 séries soumises) et les capacités « are expected to regress » en attendant [lu, extrait — fetch refusé] — [LibreELEC forum p.12](https://forum.libreelec.tv/thread/29953-le13-testing-for-rk3288-rk3328-rk3399-rk3566-rk3568-rk3576-rk3588/?pageNo=12).
- `{RK356x}` **BSP 6.1** : `dw_hdmi-rockchip.c` fait 2573 lignes. Il gère le YUV420 (repli quand le `max_tmds_clock` de l'EDID est inférieur au pixel clock), les propriétés `color_depth` et `hdr_panel_metadata`, et une entrée PHY à 594 MHz [lu, 6.1.172] — [BSP dw_hdmi-rockchip.c](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/drm/rockchip/dw_hdmi-rockchip.c).
- `{RK3566}` Audio HDMI mainline : les DTS mainline de la **ROCK 3C** et de la **Quartz64-A** déclarent un nœud `hdmi-sound` (I2S0 8ch `fe400000`) [lu, v7.2] — [rk3566-rock-3c.dts](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/rockchip/rk3566-rock-3c.dts) ; [rk3566-quartz64-a.dts](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/rockchip/rk3566-quartz64-a.dts). ⚠️ Un journal public montre `asoc-simple-card hdmi-sound: i2s-hifi <-> fe400000.i2s mapping ok`, mais sur un noyau **BSP 4.19.193** (compilé en octobre 2021), ROCK 3A **RK3568**, sorti en 1080p60. Ce n'est **pas** une preuve mainline, et l'audio n'y est pas vérifié [lu] — [gist avafinger « RK3568 HDMI »](https://gist.github.com/avafinger/d5038398d69d466ef31edf1b47f9b179).

**GPU (noyau)**
- `{RK356x}` Nœud GPU mainline : `compatible = "rockchip,rk3568-mali", "arm,mali-bifrost"`, désactivé par défaut et activé par les DTS de cartes [lu, v7.2] — [rk356x-base.dtsi](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/rockchip/rk356x-base.dtsi). OPP GPU **200/300/400/600/700/800 MHz**, dans `rk3566.dtsi` comme dans `rk3568.dtsi` [lu, v7.2] — [rk3566.dtsi](https://github.com/torvalds/linux/blob/v7.2/arch/arm64/boot/dts/rockchip/rk3566.dtsi).
- `{Bifrost v7}` Version de l'API noyau Panfrost (`panfrost_drv.c`) : **1.2** en v6.1 **et dans le BSP rk-6.1-rkr7.2**, 1.2 en v6.12, 1.3 en v6.13 (`JD_REQ_CYCLE_COUNT`, requêtes `SYSTEM_TIMESTAMP`), 1.4 en v6.17 et v6.18 (`SET_LABEL_BO`), **1.5 en v6.19** (`JM_CTX_{CREATE,DESTROY}`, contextes à priorité/affinité), **1.6 en v7.0** (`PANFROST_BO_MAP_WB`, `SYNC_BO`, `QUERY_BO_INFO`, `SELECTED_COHERENCY`) [lu, code aux tags] — [panfrost_drv.c v7.2](https://github.com/torvalds/linux/blob/v7.2/drivers/gpu/drm/panfrost/panfrost_drv.c) ; [v6.18](https://github.com/torvalds/linux/blob/v6.18/drivers/gpu/drm/panfrost/panfrost_drv.c) ; [BSP](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/drm/panfrost/panfrost_drv.c).
- `{Bifrost v7}` Commits Panfrost noyau récents : reprise sur panne et soumissions (« Handle job HW submit errors », 2025-10-20), mappings « Write-Back Cacheable » (2025-12-09), fuite de pages sous THP corrigée (2026-01-09) [lu] — [historique drm/panfrost](https://github.com/torvalds/linux/commits/master/drivers/gpu/drm/panfrost).
- `{RK356x}` Décodage vidéo mainline v7.2 : `rkvdec` couvre rk3288/3328/3399/**3588**/3576, **pas rk3568/rk3566**. Pour RK3568, Hantro ne connaît que `rk3568-vpu` (G1) et `rk3568-vepu` [lu] — [rkvdec.c v7.2](https://github.com/torvalds/linux/blob/v7.2/drivers/media/platform/rockchip/rkvdec/rkvdec.c) ; [hantro_drv.c v7.2](https://github.com/torvalds/linux/blob/v7.2/drivers/media/platform/verisilicon/hantro_drv.c).

**DDR devfreq (DMC)**
- `{RK356x}` Mainline v7.2 : `drivers/devfreq/` ne contient **que** `rk3399_dmc.o` ; aucun pilote DMC RK3568 [lu] — [devfreq Makefile](https://github.com/torvalds/linux/blob/master/drivers/devfreq/Makefile). Seul le **DFI** (compteurs, `rockchip,rk3568-dfi`) est en amont [lu] — [rockchip-dfi.c v7.2](https://github.com/torvalds/linux/blob/v7.2/drivers/devfreq/event/rockchip-dfi.c).
- `{RK3566}` ROCKNIX porte un DMC devfreq **hors arbre** sur **6.18.13** (« RK3568 DMC devfreq driver: BSP V2 SIP protocol, MCU-based HWFFC »). OPP 324/528/780/1056 MHz à 900 mV, TF-A **v1.45+** exigé (rkbin `ef49d0c2`, 2025-03-04). Effet sur la consommation **négligeable** : 0,08 W d'amplitude, η² = 0,015. Le bénéfice annoncé est « bandwidth matching for GPU-shared memory workloads », mais **aucune mesure GPU** n'est fournie. Gist du 2026-03-05 [mesuré par la source] — [gist aenertia](https://gist.github.com/aenertia/522cd8df6f0b68a0a2f59f73d5fe3af7).
- `{RK356x}` BSP 6.1 : `rockchip_dmc.c` gère `rockchip,rk3568-dmc`. Dans `rk356x.dtsi`, le nœud `dmc` (devfreq-events `dfi`, `vop-bw-dmc-freq`, `upthreshold = <40>`, `auto-freq-en = <1>`) est livré en **`status = "disabled"`** : c'est à la DTS de carte de l'activer [lu, 6.1.172] — [rockchip_dmc.c](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/devfreq/rockchip_dmc.c) ; [rk356x.dtsi BSP](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/arch/arm64/boot/dts/rockchip/rk356x.dtsi). La config ophub rk35xx 6.1 compile bien `CONFIG_ARM_ROCKCHIP_DMC_DEVFREQ=y` [lu] — [config-6.1](https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1).
- `{RK3566}` vs `{RK3568}` Blobs d'initialisation DDR par défaut de rkbin : **`rk3566_ddr_1056MHz_v1.26.bin`** contre **`rk3568_ddr_1560MHz_v1.26.bin`** [lu] — [RK3566MINIALL.ini](https://github.com/rockchip-linux/rkbin/blob/master/RKBOOT/RK3566MINIALL.ini) ; [RK3568MINIALL.ini](https://github.com/rockchip-linux/rkbin/blob/master/RKBOOT/RK3568MINIALL.ini).

**Configs noyau livrées (quel pilote GPU est seulement *possible*)**
- `{RK356x}` Armbian `linux-rk35xx-vendor.config` : `DRM_PANFROST=m`, `DRM_PANTHOR=m`, `MALI_MIDGARD=y`, `MALI_VALHALL=y`, mais **`MALI_BIFROST` absent**. Le kbase Bifrost (celui du Mali-G52) n'est donc pas construit ; `ARM_ROCKCHIP_DMC_DEVFREQ=y` et `ROCKCHIP_MPP_RKVDEC2=y` le sont [lu] — [linux-rk35xx-vendor.config](https://github.com/armbian/build/blob/main/config/kernel/linux-rk35xx-vendor.config). Même constat chez ophub : `# CONFIG_MALI_BIFROST is not set`, `DRM_PANFROST=m` [lu] — [ophub config-6.1](https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1).
- `{RK356x}` Le BSP rk-6.1-rkr7.2 embarque pourtant trois kbase : `bifrost/` (**g29p1-12eac0**, symbole `MALI_BIFROST`), `valhall/` (g29p1-11eac0, CSF) et `midgard/` (r18p0) [lu] — [drivers/gpu/arm/Kconfig](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/arm/Kconfig) ; [bifrost/Kbuild](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/arm/bifrost/Kbuild).

### Inferences
- **[déduit]** Rapprochement avec le labo (X88Pro20, ophub 6.1.141, 30/09) :
  - Panfrost chargé et **aucun `/dev/mali*`** : c'est exactement ce que produit une config ophub sans `MALI_BIFROST`. Le blob est impossible sans recompiler le noyau.
  - Pas de nœud DMC : le pilote est compilé, mais le nœud `dmc` du BSP est `disabled` par défaut et la DTS x88pro20 ne l'active visiblement pas. La DDR reste donc à la fréquence posée par le loader. Le blob rkbin RK3566 par défaut vise 1056 MHz ; celui du loader d'origine de la box n'est pas vérifié.
  - GPU à 200-800 MHz : conforme aux OPP BSP et mainline.
  - `/dev/mpp_service` sans `/dev/video*` : c'est le modèle MPP du BSP (pas de V4L2 M2M). Tout décodage matériel dans Chromium passe donc par un Chromium patché Rockchip + `libv4l-rkmpp`.
- **[déduit]** Avec ses **3 plans** VOP2 (Smart0 RGB linéaire, Esmart0 RGB/YUV linéaire, Cluster0 AFBC seul), un kiosque d'une seule page tient à l'aise sur RK3566. Le Chromium plein écran occupe le primaire ; il reste un plan YUV (Esmart0) pour une vidéo en overlay et un plan AFBC (Cluster0). Pas de marge au-delà.
- **[déduit, calculé]** Bande passante :
  - scanout 3840×2160 XRGB8888 à 60 Hz = 3840 × 2160 × 4 o × 60 ≈ **1,99 Go/s**, contre 0,50 Go/s en 1080p60 ;
  - en supposant un bus DDR 32 bits (**[supposé]**, non vérifié ici), LPDDR4 à 1056 MHz ≈ 2112 MT/s × 4 o ≈ **8,4 Go/s** théoriques (≈ 12,5 Go/s à 1560 MHz sur RK3568) ;
  - le seul scanout 4K60 prend donc ~¼ du pic théorique d'une RK3566, avant rendu GPU et texture.
  → Pour un kiosque sur G52 MP2, **sortir en 1080p60**, ou rendre en 1080p et laisser le VOP2 agrandir, est probablement le levier n°1, indépendant du choix de noyau. À mesurer.
- **[déduit]** Mainline 6.18 LTS / 7.x : intéressant pour le rendu seul (API Panfrost ≥ 1.4, contextes JM à priorité en 6.19+, mappings WB en 7.0+, HDMI 4K60 RGB). Rédhibitoire pour cette box si le kiosque doit **décoder** de la vidéo (pas de rkvdec2 RK356x en v7.2), et sans DTS mainline x88pro20 : ophub ne la construit qu'en BSP. **6.12 LTS est un mauvais choix** d'office pour du 4K60 (`max_tmds_clock = 340000` en v6.12), sauf correctif de distribution.
- **[déduit]** Pour la X88Pro20 : **BSP 6.1 (Armbian vendor rk-6.1-rkr7.2 ou ophub rk35xx 6.1.y) + Panfrost + Mesa récent**. Le mainline est à réserver aux cartes qui ont une DTS amont (ROCK 3C, Quartz64, Radxa Zero 3) et à un kiosque sans vidéo lourde.

### Gaps
- Pas de preuve **mesurée** du 4K60 HDMI mainline sur un **RK3566** (testé sur ROCK 3A = RK3568). À faire sur la box, si on bascule un jour.
- Contenu exact du fil LibreELEC (dates, auteur) non lisible (fetch refusé) ; seul l'extrait est connu.
- Largeur réelle du bus DDR et fréquence du loader **d'origine** de la X88Pro20 non vérifiées (le banner DDR du loader sur console série le dirait).
- Le détail des différences de sortie d'affichage RK3566 vs RK3568 (eDP/LVDS/DSI, PCIe 3.0…) n'a pas pu être vérifié, faute d'accès au datasheet (rock-chips.com bloqué).

---

## Q2 — Panfrost sur Mali-G52 (Bifrost v7) : API exposées par version de Mesa, conformité, progrès depuis 22.3, bugs Chromium, et AFBC en scanout

### Takeaway
Panfrost expose **OpenGL ES 3.1 et OpenGL 3.1** sur Bifrost v7, de Mesa 22.3 jusqu'à 26.3-devel. GLES 3.2 n'est **pas** exposé upstream : ni geometry, ni tessellation, ni cube-map arrays. Il est **conforme Khronos GLES 3.1 sur Mali-G52**. Entre 22.3.6 (Debian bookworm) et 25.0.7 (bookworm-backports), puis 26.2.3 (septembre 2026), les gains qui comptent pour un navigateur sont les suivants :
- la **transaction elimination (CRC)** est réactivée par défaut (25.0) après correctifs ; en 22.3 elle était active mais jugée « buggy » ;
- AFBC packing et AFBC split ;
- robustesse `GL_KHR_robustness` / accès mémoire robuste (25.3) ;
- timer queries (24.3, noyau ≥ 6.13).

Il n'y a **pas de reset-status/EGL robustness sur v7** (réservé v10+), et aucune entrée Panfrost dans les listes GPU de Chromium. L'AFBC en scanout existe sur RK356x, mais **seulement via l'overlay Cluster0** : le plan primaire est linéaire.

### Cited Findings
- `{Bifrost v7}` Doc Mesa `main` (26.3-devel) : « It is **conformant** on Mali-G52 (Khronos submission 949), Mali-G57 and Mali-G610, but non-conformant on other GPUs ». Tableau : « **G31, G51, G52, G76 | Bifrost (v7) | OpenGL ES 3.1 | OpenGL 3.1 | Vulkan 1.3** ». « Other graphics APIs (OpenCL) are not supported at this time. » [lu] — [panfrost.rst (miroir Mesa main)](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/drivers/panfrost.rst) (page officielle bloquée : [docs.mesa3d.org/drivers/panfrost.html](https://docs.mesa3d.org/drivers/panfrost.html)).
- `{Bifrost v7}` Historique : GLES 3.1 est arrivé sur Midgard (T760+) et Bifrost (G31/G52/G76) en juin 2021 [lu, extrait] — [CNX 2021-06-14](https://www.cnx-software.com/2021/06/14/panfrost-opengl-es-3-1-midgard-mali-t760-bifrost-mali-g31-g52-g76-gpu/). Annonce de la conformité GLES 3.1 sur Mali-G52 : « Conformance requires passing tens of thousands of … tests in a single run… over the summer, hundreds of patches were written » [lu, extrait — collabora.com bloqué] — [Collabora](https://www.collabora.com/news-and-blog/news-and-events/panfrost-achieves-opengl-es-3.1-conformance-on-mali-g52.html).
- `{Bifrost v7}` Code : `essl_feature_level = arch >= 6 ? 320 : 310` et GLSL 140 (330 avec `PAN_MESA_DEBUG=gl3`, « experimental GL 3.x implementation, up to 3.3 ») **à l'identique dans 22.3.6 et main** [lu] — [pan_screen.c 22.3.6](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/mesa-22.3.6/src/gallium/drivers/panfrost/pan_screen.c) ; [pan_screen.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_screen.c). Dans `features.txt`, `GL_OES_geometry_shader` et `GL_OES_texture_cube_map_array` ne citent pas panfrost, et `GL_OES_tessellation_shader` ne vaut que pour les pilotes qui ont `ARB_tessellation_shader`. Panfrost n'a donc pas GLES 3.2 [lu] — [features.txt main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/features.txt).
- `{Bifrost v7}` ⚠️ Un **portage non officiel**, `JimVulkan/mali-panfrost` (Mesa 26.3.0-devel), annonce « OpenGL 4.6 core … and OpenGL ES 3.2 » sur Bifrost. Il vise **Android sur kbase** (`/dev/mali0`), a été testé sur Exynos G76/G72, est « developed with heavy use of AI tools » et ne publie **aucune conformance ni benchmark**. Ce n'est **pas** Mesa amont [lu] — [JimVulkan/mali-panfrost](https://github.com/JimVulkan/mali-panfrost).
- `{Bifrost v7}` Chaînes vues par Chromium : `GL_VENDOR = "Mesa"`, `device vendor = "Arm"`, `GL_RENDERER = "%s MC%u (Panfrost)"` [lu] — [pan_screen.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_screen.c).
- `{Bifrost v7}` Robustesse : `robust_buffer_access_behavior = arch >= 6`, mais `device_reset_status_query = arch >= 10` [lu, main] — [pan_screen.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_screen.c). Les notes de 25.3.0 (2025-11-14) listent « GL_ARB_robust_buffer_access_behavior, GL_KHR_robust_buffer_access_behavior and GL_KHR_robustness support on Panfrost » et « EGL_EXT_create_context_robustness support on Panfrost **V10+** » [lu] — [25.3.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/25.3.0.rst).
- `{Bifrost v7}` Nouveautés GL Panfrost par version, tirées des sections « New features » des notes de version [lu] — [relnotes (miroir)](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/tree/main/docs/relnotes) :

  | Version (date) | Nouveauté Panfrost |
  |---|---|
  | 22.3.0 (2022-12-02) | « Shader disk cache on Panfrost » |
  | 23.0.0 (2023-02-22) | `GL_ARB_clip_control`, `GL_ARB_texture_filter_anisotropic` |
  | 24.3.0 (2024-11-21) | `GL_ARB_timer_query`, `GL_EXT_disjoint_timer_query` |
  | 25.2.0 (2025-08-06) | `GL_KHR_texture_compression_astc_hdr` |
  | 26.0.0 (2026-02-11) | `GL_EXT_shader_pixel_local_storage` on Panfrost v6+ |
  | 26.1.0 (2026-05-06) | `GL_EXT_shader_image_load_store` |
  | 26.2.0 (2026-08-05) | (G1 / v14) |

  26.2.3 est sortie le 2026-09-16 [lu] — [26.2.3.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/26.2.3.rst). Dates de 22.3.6 et 25.0.7 : 2023-02-22 et 2025-05-28 [lu] — [22.3.6.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/22.3.6.rst) ; [25.0.7.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/25.0.7.rst).
- `{Bifrost v7}` Timer queries : `query_time_elapsed` et `query_timestamp` dépendent de `props.gpu_can_query_timestamp` du noyau [lu] — [pan_screen.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_screen.c). Or l'API Panfrost n'expose `SYSTEM_TIMESTAMP` qu'à partir de la 1.3 (noyau 6.13) ; cf. Q1.
- `{Bifrost v7}` **CRC / transaction elimination** — défaut par version, vérifié dans le code :

  | Mesa | CRC par défaut |
  |---|---|
  | 22.3.6 | **activé** (option `nocrc`) |
  | 23.1.0 → 24.3.4 | **désactivé** (option `crc`) |
  | 25.0.0, 25.0.7, 26.2.0 | **activé** (option `nocrc`) |

  [lu] — [pan_screen.c 23.1.0](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/mesa-23.1.0/src/gallium/drivers/panfrost/pan_screen.c) ; [25.0.0](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/mesa-25.0.0/src/gallium/drivers/panfrost/pan_screen.c).
  - Raison de la désactivation (Alyssa Rosenzweig, 2023-02-10, `fc30fe5b`) : « Known unsound code… Even in synthetic glmark style benchmarks this seems to be a few % hit at most… **panfrost's implementation is buggy in several places**… Closes: #8113 » [lu] — [commit fc30fe5b](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/fc30fe5b).
  - Réactivation (Erik Faye-Lund, commité le 2025-01-03, `eac8f1d4`) : « There's been a bunch of CRC fixes applied recently. Let's see if this allows us to default to this as enabled » [lu] — [commit eac8f1d4](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/eac8f1d4).
  - Optimisation du hachage CRC des couleurs de clear en 2026 (`cef20f5a`, commité le 2026-06-26) [lu] — [commit cef20f5a](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/cef20f5a). Sa présence dans 26.2.0, d'après la date de branche, est **[déduite]**, pas vérifiée.
- `{Bifrost v7}` **AFBC** :
  - AFBC des cube maps (2022-12) ;
  - **AFBC packing**, qui compacte les superblocs pour économiser la mémoire (`bc55d150`, écrit en 2023-08, commité en 2023-10) : « the GPU will still be able to read from these packed textures, but won't be able to write directly to them » ; variable de ratio maximal, driconf `pan_force_afbc_packing` (2024-03) ;
  - **AFBC(split)** (commité le 2024-11-25) ;
  - « Increase AFBC body alignment requirement on v6+ » ;
  - « Use util_streaming_load_memcpy() to copy AFBC superblocks » (2025-05).

  [lu, titres de commits via l'API GitLab] — [commit bc55d150](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/bc55d150) ; [commit 4af57952](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/4af57952). Particularité v7 : « **v7 (only) restricts component orders with AFBC** », d'où un contournement par swizzle et une quirk de couleur de bord [lu] — [pan_screen.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_screen.c). Pas d'AFBC(Z32)+S8 sur v7- (« AFBC ZS target layout overlaps the S target layout ») [lu] — [pan_resource.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_resource.c).
- `{Bifrost v7}` **Tiler** : sélection du masque de hiérarchie reprise de PanVK (2025-01), niveaux désactivés selon la taille de tuile (2025-04), budget mémoire du tiler pris en compte (2025-04), driconfs de tas du tiler (2024-04) [lu, titres de commits] — [historique Mesa (API)](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commits/main/src/gallium/drivers/panfrost).
- `{Bifrost v7}` **Compilateur Bifrost** : « bi: Optimize scratch access » (2025-02), « pan/bi: Revamp bi_optimize_nir » (2025-08), « align spills to reduce TLS memory usage » (2025-09), lowering des textures en NIR sur Bifrost (2026-05). Un bug d'assertion de vectorisation a touché 26.0.0 (« Panfrost Bifrost compiler assertion failure… (Mesa 26.0.0) », corrigé en 26.1.0) [lu] — [historique compiler](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commits/main/src/panfrost/compiler) ; [26.1.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/26.1.0.rst).
- `{Bifrost v7}` **Contextes JM à priorité** : « panfrost: Support JM context creation and destruction… leveraging the new Panfrost **1.5** KM IOCTLs » (Boris Brezillon, 2025-08-29) [lu] — [commit e9aedfe5](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/e9aedfe5). Cela demande un noyau **≥ 6.19** (cf. Q1).
- `{Bifrost v7}` Bugs corrigés marquants dans les notes : « panfrost Mali-G31 glamor regression » (23.1.0), « gbm_bo_get_offset() wrongly returns 0 for second plane of NV12 buffers » (23.3.0/24.0.0), « assertion fail in pan_image_get_wsi_row_pitch » (25.3.0). **Aucun** titre de bug corrigé 23.0→26.2 ne cite Chromium, Skia, ANGLE ou Firefox, et aucun titre de commit Panfrost depuis 2022-11 (≈ 2 200 commits parcourus) ne cite Chromium, Skia ou ANGLE [lu] — [relnotes](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/tree/main/docs/relnotes).
- `{toutes puces}` Listes GPU de Chromium `main` (157.0.8080.0) :
  - **aucune entrée** « Panfrost » ou « Mesa sur Mali » dans `software_rendering_list.json` ; sous Linux, seuls les rendus logiciels et d'anciens pilotes Intel, AMD, NVIDIA, VMware ou VirtualBox sont bloqués ;
  - l'entrée **186**, « Disable webgpu on vk via gl interop », s'applique à tous sauf Intel/Mesa et NVIDIA ;
  - les contournements Mali de `gpu_driver_bug_list.json` ciblent `gl_vendor: "ARM.*"`, c'est-à-dire le **blob**, par exemple #478 Linux, « Program binaries don't contain transform feedback varyings on Mali GPUs ».

  [lu] — [software_rendering_list.json](https://github.com/chromium/chromium/blob/main/gpu/config/software_rendering_list.json) ; [gpu_driver_bug_list.json](https://github.com/chromium/chromium/blob/main/gpu/config/gpu_driver_bug_list.json) ; [chrome/VERSION](https://github.com/chromium/chromium/blob/main/chrome/VERSION).
- `{RK356x}` **AFBC en scanout** :
  - côté Mesa, un tampon `PIPE_BIND_SCANOUT` peut être AFBC via kmsro et un dumb buffer dimensionné pour l'AFBC. Le commentaire du code : « This is a bit of a lie… dumb buffers, which are extremely not meant for AFBC. And yet this has to work anyway » [lu] — [pan_resource.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/gallium/drivers/panfrost/pan_resource.c) ;
  - côté VOP2 mainline, l'AFBC n'existe que sur les fenêtres **Cluster** (overlay). Contraintes : rectangles source alignés sur 4 pixels, alignement de 64 pixels pour miroir/rotation, tampon de ligne 2048×16 (plein) ou 4096×8 (demi-mode pour une largeur de 2048 à 4096) [lu] — [rockchip_drm_vop2.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/rockchip/rockchip_drm_vop2.c) ;
  - l'AFBC sur Cluster avec Panfrost a été validé à l'origine avec `weston-simple-dmabuf-egl` sous Weston [lu, extrait, série VOP2 v3 de 2021-12] — [Patchwork VOP2 v3](https://patchwork.ozlabs.org/project/devicetree-bindings/cover/20211220110630.3521121-1-s.hauer@pengutronix.de/).

### Inferences
- **[déduit]** Pour Chromium, GLES 3.1 suffit : WebGL2 demande ES 3.0 et ANGLE-sur-GL tourne sur ES 3.x. GLES 3.2 n'apporterait rien au compositing d'une page. Le point faible de Panfrost v7 pour un kiosque est **l'absence de `device_reset_status` / `EGL_EXT_create_context_robustness`** : après un hang GPU, Chromium ne peut pas recevoir de notification de reset et dépend de son watchdog. Moins bien que sur v10+.
- **[déduit]** La **transaction elimination** compte particulièrement pour un kiosque : les pages sont en grande partie statiques, donc elle économise des écritures de tuiles et de la bande passante. **22.3.6** l'active, alors qu'upstream la jugeait bogguée en février 2023 : source possible de **tuiles figées ou fantômes**. **25.0.7** la réactive après une série de correctifs. Recommandation : **Mesa 25.0.7 (bookworm-backports) au minimum** au lieu de 22.3.6, et `PAN_MESA_DEBUG=nocrc` comme bascule de diagnostic si des artefacts apparaissent.
- **[déduit]** Sur le BSP 6.1 (API Panfrost 1.2), les apports de Mesa récent qui dépendent du noyau (timer queries, contextes JM à priorité, mappings WB) sont **inertes**. Mesa ≥ 25.3 apporte néanmoins la robustesse d'accès mémoire, et 26.x les correctifs de compilateur. Mesa gère ces absences par sondage de propriétés, donc aucune incompatibilité à attendre ; à vérifier au premier lancement.
- **[déduit]** L'AFBC **ne concerne pas** le plan primaire d'un Chromium plein écran sur RK356x : le primaire est Smart0 ou Esmart0, linéaire seulement. Le chemin d'affichage sera donc linéaire. Le gain AFBC (bande passante) resterait accessible si le compositeur (Weston, ou l'Ozone/DRM de Chromium) promeut la surface sur l'overlay **Cluster0**. Non trivial, à mesurer avant d'y investir. En interne, Panfrost profite quand même de l'AFBC pour ses textures et cibles de rendu hors écran.

### Gaps
- Plateforme exacte de la soumission Khronos 949 (quel SoC portait le Mali-G52 conforme) : khronos.org bloqué. **Ne pas supposer que c'était un RK3566.**
- Aucun bug Mesa ou Chromium **spécifique** « Chromium + Panfrost + Bifrost » trouvé : gitlab.freedesktop.org et issues.chromium.org sont bloqués, et le budget de recherche était épuisé. Les notes de version n'en citent pas.
- Pas de mesure de l'effet du CRC ni de l'AFBC sur Chromium ; le commentaire de 2023 parle de « a few % » sous glmark.

---

## Q3 — Blob libmali pour Mali-G52 : versions, variantes, sources, pilote kbase requis, bascule, et tenue face à Panfrost pour un navigateur

### Takeaway
Le blob courant pour G52 est **libmali `bifrost-g52` g24p0**, dernière mise à jour vue : **g24p0-10, 2025-06-25**. Il existe en `x11-gbm`, `wayland-gbm`, `x11-wayland-gbm`, `gbm`, `dummy*` et `nocl`, via `JeffyCN/mirrors@libmali` et le repaquetage `tsukumijima/libmali-rockchip`. Il exige le **kbase Bifrost du BSP** (g29p1 dans rk-6.1-rkr7.2), que **ni Armbian vendor ni ophub ne compilent**. C'est le chemin « référence Rockchip » : SDK, Chromium patché, `libv4l-rkmpp`. Aucune comparaison navigateur Panfrost vs libmali **mesurée** n'a été trouvée.

### Cited Findings
- `{RK356x}` Fichiers `bifrost-g52` du dépôt tsukumijima :
  - `libmali-bifrost-g52-g13p0-dummy-gbm.so` ;
  - `…-g24p0-dummy-gbm.so`, `…-g24p0-dummy-wayland-gbm.so`, `…-g24p0-dummy.so`, `…-g24p0-gbm.so`, `…-g24p0-nocl-dummy-gbm.so`, `…-g24p0-wayland-gbm.so`, `…-g24p0-x11-gbm.so`, `…-g24p0-x11-wayland-gbm.so`.

  Côté RK3588 : `valhall-g610-g24p0-*` ; et `valhall-g310-g29p1-*` [lu] — [libmali-rockchip lib/aarch64-linux-gnu](https://github.com/tsukumijima/libmali-rockchip/tree/master/lib/aarch64-linux-gnu). Selon un résumé tiers, « RK356X/RK3576 uses libmali-bifrost-g52-g13p0 » et « RK3588 uses libmali-valhall-g610-g24p0 » [lu, extrait ; à croiser avec la ligne ci-dessous] — [DeepWiki libmali-rockchip](https://deepwiki.com/tsukumijima/libmali-rockchip/4.1-mali-gpu-binary-drivers).
- `{RK356x}` Historique amont (JeffyCN, branche `libmali`) :
  - « libmali: update G31/G52 userspace driver to g24p0-4 » (2024-11-15), puis g24p0-6 (2024-12-17), g24p0-7 (2024-12-20), g24p0-9 (2025-06-03), **g24p0-10 (2025-06-25)** ;
  - « libmali: G52: Add libmali-bifrost-g52-g13p0-minicl.so » (2025-02-28) ;
  - « meson: Make wayland-egl wrapper optional » (2025-02-25).

  [lu] — [JeffyCN/mirrors commits libmali](https://github.com/JeffyCN/mirrors/commits/libmali).
- `{toutes puces}` Le `meson.build` de libmali embarque une **bibliothèque de hook** « for hacking GBM/EGL/X11 APIs » et annonce une API GBM **23.1.3** (« Provide newer GBM version with hook library »). Il fournit des wrappers pour `gbm`, `EGL`, `GLESv1_CM`, `GLESv2`, `wayland-egl`, `MaliOpenCL`/`OpenCL` et `MaliVulkan` [lu] — [meson.build libmali](https://github.com/JeffyCN/mirrors/blob/libmali/meson.build).
- `{RK356x}` Capacités du blob côté matériel, selon la spec fournisseur : « ARM Mali-G52 **2EE** GPU supporting OpenGL ES 1.1/2.0/3.2 and Vulkan 1.1 » (PineTab2) ; « OpenGL ES 1.1/2.0/3.2, OpenCL 2.0, and Vulkan 1.1 » (Quartz64 B) [lu, extraits] — [PineTab2 docs](https://pine64.org/documentation/PineTab2/_full/) ; [ameriDroid Quartz64 B](https://ameridroid.com/products/quartz64-model-b).
- `{RK356x}` Pilote noyau requis :
  - le BSP rk-6.1-rkr7.2 fournit `drivers/gpu/arm/bifrost` (**`MALI_RELEASE_NAME` g29p1-12eac0**, symbole `MALI_BIFROST`) ;
  - **Panfrost et kbase lient tous deux `arm,mali-bifrost`** (`panfrost_drv.c` et `kbase_dt_ids` dans `mali_kbase_core_linux.c`) ;
  - le nœud GPU du BSP est `compatible = "arm,mali-bifrost"`.

  [lu] — [bifrost/Kbuild](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/arm/bifrost/Kbuild) ; [panfrost_drv.c BSP](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/drm/panfrost/panfrost_drv.c) ; [mali_kbase_core_linux.c](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/drivers/gpu/arm/bifrost/mali_kbase_core_linux.c) ; [rk356x.dtsi BSP](https://github.com/armbian/linux-rockchip/blob/rk-6.1-rkr7.2/arch/arm64/boot/dts/rockchip/rk356x.dtsi).
- `{RK356x}` Configs livrées : Armbian vendor **sans** `MALI_BIFROST`, ophub rk35xx 6.1 `# CONFIG_MALI_BIFROST is not set` (cf. Q1) [lu] — [linux-rk35xx-vendor.config](https://github.com/armbian/build/blob/main/config/kernel/linux-rk35xx-vendor.config) ; [ophub config-6.1](https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1).
- `{RK3588S}` ⚠️ **Transposition** : la doc Radxa « Switch GPU driver » décrit la bascule sur **ROCK 5C (RK3588S)**. Selon l'extrait, Panfrost utilise le dépôt « stable » et le pilote Mali le dépôt « rk35*-bookworm » ; pour passer de libmali à Panfrost, on retire les paquets libmali et on installe Mesa [lu, extrait — docs.radxa.com bloqué] — [Radxa docs ROCK 5C](https://docs.radxa.com/en/rock5/rock5c/radxa-os/mali-gpu).
- `{RK356x}` SDK Rockchip RK356x **Linux 5.10** (v1.2.1, 2023-07-20) :
  - Debian 11.6, Yocto 4.0.9, Buildroot (base novembre 2021), **Weston 11.0.1**, GStreamer 1.22 ;
  - « Add **Chromium 111.0.5563.147**, support video H265 decoding » (Buildroot, v1.1.1) ;
  - côté Debian, « Filtering Mali DDK does not support GBM_FORMAT_R8 error issue ».

  [lu] — [RK3566_RK3568_Linux5.10_SDK_Note.md](https://github.com/TinkerBoard/rockchip-linux-bsp-internal_doc-en/blob/linux5.10-rk356x/RK3566_RK3568_Linux5.10_SDK_Note.md). Autre fournisseur : FriendlyELEC note « Chromium has been updated to the new stable version (130) for Debian 11 and Ubuntu 20 », avec libmali/`libv4l-rkmpp` mis à jour [lu, extrait] — [FriendlyELEC RK3568 UpdateLog](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3568-UpdateLog).
- `{RK3588}` `libv4l-rkmpp` : « A rockchip-mpp V4L2 wrapper plugin for chromium V4L2 VDA/VEA » ; il faut un Chromium patché, et il est « tested with custom chromium on **rk3588** EVB ». Dernière mise à jour 2025-04-30 [lu, extrait] — [JeffyCN/libv4l-rkmpp](https://github.com/JeffyCN/libv4l-rkmpp).
- `{toutes puces}` Chromium applique des contournements au **blob** Mali par `gl_vendor: "ARM.*"` : #478 (Linux), #484, #488, #498 (tous OS) [lu] — [gpu_driver_bug_list.json](https://github.com/chromium/chromium/blob/main/gpu/config/gpu_driver_bug_list.json).
- `{RK3566}` Bancs publics : un utilisateur rapporte « glmark2-es2 … a low **150** » sur le G52 d'un RK3566, contre plus de 200 pour un G31 sur une autre machine. Pilote et version non précisés dans l'extrait [mesuré par la source, extrait] — [Manjaro forum](https://forum.manjaro.org/t/can-someone-share-rk3566-gpu-benchmark/126583).

### Inferences
- **[déduit]** Pour passer au blob sur la X88Pro20, il faudrait :
  - recompiler le noyau BSP avec `CONFIG_MALI_BIFROST=m` (armbian-build `vendor`, ou config ophub modifiée) ;
  - empêcher Panfrost de lier le nœud (blacklist `panfrost`, puisque les deux lient `arm,mali-bifrost`) ;
  - installer `libmali-bifrost-g52-g24p0-<x11|wayland>-gbm` ;
  - utiliser un Chromium qui sait parler à libmali : celui du SDK Rockchip ou un paquet « +rkmpp ».

  kbase g29p1 et libmali g24p0 sont de générations différentes ; la compatibilité ascendante de l'interface kbase est **supposée**, pas vérifiée.
- **[déduit]** Le blob apporte GLES 3.2, OpenCL et un `device_reset_status` probable. Il coûte en contrepartie : noyau figé BSP, dépendance à un Chromium patché par Rockchip (en retard sur l'amont : 111 dans le SDK 5.10 de 2023, 130-132 chez des tiers en 2025), GBM « hooké » pour paraître Mesa 23.1, et une chaîne X11/Weston du SDK. Pour **un kiosque maintenable en 2026**, Panfrost + Mesa ≥ 25 + Chromium Debian amont semble le meilleur compromis, **faute de banc** montrant un écart navigateur net en faveur du blob.
- **[déduit]** Les contournements Chromium « ARM.* » montrent que le couple **Chromium + DDK Mali** est surtout exercé sur **ChromeOS** (Chromebooks Mali), pas sur Linux desktop avec libmali Rockchip.

### Gaps
- Pas de matrice officielle de compatibilité libmali ↔ kbase trouvée (le dépôt n'a pas de README) ; même chose pour la présence effective de Vulkan dans le blob `bifrost-g52` de Rockchip (aucun fichier « vulkan » listé pour g52).
- Versions exactes de Chromium, Weston et libmali du **SDK RK356x Linux 6.1** (Debian 12) non trouvées. Seule l'annonce Radxa « Debian 12 with Linux 6.1 for the RK3399 & RK356X Series » (2026-01-24) est connue, et par extrait seulement — [Radxa forum](https://forum.radxa.com/t/release-announcement-debian-12-with-linux-6-1-for-the-rk3399-rk356x-series/30172).
- Aucune comparaison **mesurée** Panfrost vs libmali en navigateur (WebGL, MotionMark, scroll) sur RK3566 ou RK3568 trouvée ; voir Q6.
- Un extrait de recherche **non attribuable** (sa page source n'a pas pu être identifiée) affirme : « as long as the kernel version is after 5.10 and GPU driver is Panfrost, performance will be very close regardless of OS distributions, with Mesa version being a key factor ». Écarté des faits cités pour cette raison.

---

## Q4 — PanVK sur Bifrost v7 (2025-2026) : conformité, stabilité, utilisable pour ANGLE-Vulkan / Chromium Vulkan / Skia Graphite ?

### Takeaway
**Non, pas en production.** Sur v6/v7, PanVK **refuse de se charger** sans `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` (« panvk is not well-tested on v7 »), dans Mesa 25.0.7 comme dans `main`. Il n'est conforme que sur Mali-G610 (v10). Les briques dont Chromium a besoin pour du Vulkan avec dmabuf (`VK_EXT_image_drm_format_modifier`, `sampler_ycbcr_conversion`) ne sont arrivées sur v7 qu'en **Mesa 26.0** (février 2026).

### Cited Findings
- `{Bifrost v7}` Code `main` : `case 6: case 7: case 11: case 14:` → sans `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`, erreur « WARNING: panvk is not well-tested on v%d, pass PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 if you know what you're doing. ». `if (arch != 10) vk_warn_non_conformant_implementation("panvk")` [lu] — [panvk_physical_device.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/panfrost/vulkan/panvk_physical_device.c). Même garde (v6/v7) dans **25.0.7** [lu] — [panvk_physical_device.c 25.0.7](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/mesa-25.0.7/src/panfrost/vulkan/panvk_physical_device.c).
- `{Bifrost v7}` Doc : « PanVK … is currently **conformant** on Mali-G610, but non-conformant on other GPUs. On GPUs where PanVK support is experimental, the driver refuses to load by default… may be broken, may require newer kernel driver versions, and may be removed. » Tableau : Vulkan « 1.3 » pour v6/v7 [lu] — [panfrost.rst main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/drivers/panfrost.rst).
- `{Bifrost v7}` Sur v7 (pré-CSF), PanVK n'a pas de timelines noyau : « We don't support timelines in the uAPI yet » → timelines émulées (`vk_sync_timeline`) ; une seule file (`queueCount = arch >= 10 ? 2 : 1`) [lu] — [panvk_physical_device.c main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/src/panfrost/vulkan/panvk_physical_device.c).
- `{Bifrost v7}` Ajouts propres à v7 dans les notes :
  - 26.0.0 (2026-02-11) : « VK_EXT_image_drm_format_modifier on panvk/v7 », « VK_KHR_sampler_ycbcr_conversion on panvk/v7 » ;
  - 26.1.0 : « fragmentStoresAndAtomics on panvk/v6-7 ».

  Beaucoup d'autres ajouts sont marqués « panvk/v10+ » (Vulkan 1.2 en 25.2, maintenance4/5/7/8, robustness2…) [lu] — [26.0.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/26.0.0.rst) ; [26.1.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/26.1.0.rst) ; [25.2.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/25.2.0.rst).
- `{Bifrost v7}` Signal historique : « Bifrost PanVK should not be in CI » (bug fermé en 23.3.0) [lu] — [23.3.0.rst](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/relnotes/23.3.0.rst). Travaux expérimentaux tiers : « experimental Mesa PanVK work for running Vulkan on a Mali-G52 MC2 (Bifrost / Job Manager) » [lu, extrait] — [LukeValen/panvk-mali-g52](https://github.com/LukeValen/panvk-mali-g52).
- `{toutes puces}` Chromium : l'entrée 186 désactive « webgpu on vk via gl interop » partout sauf Intel/Mesa et NVIDIA [lu] — [software_rendering_list.json](https://github.com/chromium/chromium/blob/main/gpu/config/software_rendering_list.json).
- `{RK3588}` ⚠️ Ne pas transposer : Vulkan 1.4 et la conformité PanVK concernent G610/v10 (Panthor) [lu] — [panfrost.rst main](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/blob/main/docs/drivers/panfrost.rst).

### Inferences
- **[déduit]** Pour le kiosque : **rester sur ANGLE-sur-GL / GLES** (Panfrost). Vulkan sur Bifrost v7 ne vaut que pour l'exploration, avec Mesa ≥ 26.0 au minimum (modificateurs DRM sur v7) et la variable d'environnement. Chromium ne l'utiliserait de toute façon pas par défaut pour WebGPU via interop GL (entrée 186). Skia Graphite sur PanVK v7 : **aucune** donnée ; à considérer comme non supporté.

### Gaps
- Aucune source sur des essais Chromium-Vulkan / Graphite / ANGLE-Vulkan sur PanVK v7 (blogs Collabora et Phoronix bloqués, budget de recherche épuisé). L'article « PanVK Extension Sprint: Mesa 26.1 » (2026-04-20) n'a pas pu être lu — [christian-gmeiner.info](https://christian-gmeiner.info/2026-04-20-panvk-extensions/).

---

## Q5 — Distributions réalistes pour un kiosque RK3566 en 2026, et pile navigateur de chacune

### Takeaway
- **Armbian**, officiel ou en image ophub : c'est la voie réaliste. Il offre `vendor` 6.1 BSP, `current` 6.18 LTS et `edge` 7.2 pour les RK3566 supportés ; ophub construit la X88Pro20 en BSP 6.1 uniquement.
- **Rockchip SDK** (Buildroot/Debian/Yocto + libmali + Chromium patché) : c'est la référence « tout accéléré » du fondeur, mais figée et en retard.
- **Ubuntu Rockchip (Joshua-Riek)** : archivé le 2026-04-29, jamais de RK3566.
- **postmarketOS PineTab2** : `testing`, noyau 6.10.2.
- **Buildroot amont** : aucun defconfig RK3566.
- **DietPi** : RK3566 sur noyaux mainline (6.12 pour la ZERO 3, d'après l'extrait).
- **Fedora** : non vérifié.

### Cited Findings
- `{RK3566}` **Armbian officiel** :
  - `rock-3c.csc` (communautaire) : `KERNEL_TARGET="current,edge"` ;
  - `radxa-zero3.conf` (standard, mainteneur igorpecovnik) : `"vendor,current,edge"` ;
  - `orangepi3b.csc` : `"vendor,current,edge"` ;
  - `quartz64a.csc` / `quartz64b.csc` (famille rockchip64) : `"current,edge"`.

  Branches : vendor 6.1 (rk-6.1-rkr7.2), current 6.18, edge 7.2 [lu] — [armbian/build boards](https://github.com/armbian/build/tree/main/config/boards) ; [rockchip64_common.inc](https://github.com/armbian/build/blob/main/config/sources/families/include/rockchip64_common.inc).
- `{RK3566}` **ophub** (images Armbian pour boîtiers TV) : la ligne `rk3566` liste Panther-X2, JP-TvBox, LCKFB-Taishan-Pi, WXY-OEC-turbo-4g, Station-M2, Orange-Pi-3B, **X88Pro20**, LubanCat-1, Rock-3C et Inspur-MD1000, avec noyaux `stable` et/ou `rk35xx` [lu] — [ophub README](https://github.com/ophub/amlogic-s9xxx-armbian). Pour la X88Pro20, la base de modèles dit : `rk35xx/6.1.y` seulement [lu] — [model_database.conf](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/armbian-files/common-files/etc/model_database.conf).
- `{RK3588}` **Ubuntu Rockchip (Joshua-Riek)** : « archived by the owner on Apr 29, 2026 » ; sujets rk3588/rk3588s/rk3576 ; « Ubuntu 22.04 LTS (with Rockchip Linux 5.10) and Ubuntu 24.04 LTS (with Rockchip Linux 6.1) », « 3D hardware acceleration support via panfork », « Chromium browser with smooth 4k youtube video playback » [lu] — [Joshua-Riek/ubuntu-rockchip](https://github.com/Joshua-Riek/ubuntu-rockchip). Sur RK3566, les notes de la v2.0.0 (avril 2024) disaient « Support for RK3566 will be addressed at a later date » [lu, extrait] — [newreleases v2.0.0](https://newreleases.io/project/github/Joshua-Riek/ubuntu-rockchip/release/v2.0.0). ⚠️ Un résumé de recherche a attribué à une « v2.3.0 du 2 août 2026 » des overlays génériques RK3566/RK3568. Cette date est **incompatible** avec l'archivage d'avril 2026 : fait **non retenu**.
- `{RK3588 surtout}` **PPA liujianfeng1994 « rockchip-multimedia »** (pour noyau BSP) :
  - `chromium 132.0.6834.159-1~deb12u1+rkmpp` (Noble, 2025-03-05) et `126.0.6478.182…+rkmpp~j` (Jammy, 2024-07-26) ;
  - `chromium-browser 2:114.0.5735.35…+rkmpp8` ;
  - `mpp 1.5.0+git20240612` ;
  - `libv4l-rkmpp 1.7.0+git240515` ;
  - `rockchip-multimedia-config 1.0.2`.

  Pas de paquet libmali/G52 visible [lu] — [Launchpad PPA packages](https://launchpad.net/~liujianfeng1994/+archive/ubuntu/rockchip-multimedia/+packages).
- `{toutes puces}` **Mesa récent sur Ubuntu** : PPA kisak-mesa **26.2.3** pour Resolute et Noble (publié le 2026-09-18), 26.1.4 pour Questing. Disponibilité **arm64 non vérifiée** [lu] — [kisak-mesa packages](https://launchpad.net/~kisak/+archive/ubuntu/kisak-mesa/+packages).
- `{RK356x}` **Radxa OS** : annonce « Debian 12 with Linux 6.1 for the RK3399 & RK356X Series », 2026-01-24 [lu, extrait] — [Radxa forum](https://forum.radxa.com/t/release-announcement-debian-12-with-linux-6-1-for-the-rk3399-rk356x-series/30172). Le dépôt `radxa-pkg/linux-rk356x` ne publie que du **5.10.160** (dernier : 5.10.160-39, 2024-12-31) [lu] — [releases](https://github.com/radxa-pkg/linux-rk356x/releases).
- `{RK3566}` **DietPi** : un extrait de recherche dit : « For Radxa ZERO 3, system images now come with the Linux 6.12 mainline long-term support kernel… migrates systems from legacy kernels ». ⚠️ La **page exacte n'est pas identifiée** : dietpi.com est bloqué, et ce ne peut pas être la note v9.4 (mai 2024), puisque le 6.12 date de novembre 2024. Candidats parmi les résultats : [DietPi 9.20 (déc. 2025), alternativeto](https://alternativeto.net/news/2025/12/dietpi-9-20-adds-rustdesk-server-hardware-updates-enhanced-software-and-bug-fixes) ; [DietPi Supported Hardware](https://dietpi.com/docs/hardware/) [lu, extrait, attribution incertaine]. L'Orange Pi 3B figure aussi parmi les cartes DietPi (correctif Bluetooth `sprdbt_tty` cité dans un extrait) [lu, extrait, attribution incertaine] — [DietPi docs](https://dietpi.com/docs/hardware/).
- `{RK3566}` **postmarketOS** : `device-pine64-pinetab2` est dans **`device/testing`** ; `linux-pine64-pinetab2` est en **`pkgver=6.10.2`** (fork `dreemurrs-embedded/linux-pinetab2`, tag `-danctnix`) [lu] — [deviceinfo](https://gitlab.com/postmarketOS/pmaports/-/blob/master/device/testing/device-pine64-pinetab2/deviceinfo) ; [APKBUILD noyau](https://gitlab.com/postmarketOS/pmaports/-/blob/master/device/testing/linux-pine64-pinetab2/APKBUILD).
- `{RK3568}` **Yocto** :
  - `meta-rockchip` (Yocto Project, correctifs cherry.de) : « mesa: build panfrost for RK3568 boards » (2024-05-31, rétroporté sur scarthgap le 2024-09-09), puis « mesa: enable PanVK » dans oe-core (2025-04-15) [lu, extraits] — [patchwork meta-rockchip](https://patchwork.yoctoproject.org/project/yocto/patch/20240531-mesa-panfrost-v1-2-84e23ae9a600@cherry.de/) ; [patchwork oe-core PanVK](https://patchwork.yoctoproject.org/project/oe-core/patch/20250415-mesa-panvk-v2-1-9cb969d64cd8@cherry.de/) ;
  - `meta-rockchip` **de Rockchip (JeffyCN)** : dépend de la branche « **wrynose** », testé « regularly » sur « rk3588 evb board », couche dynamique Chromium [lu] — [JeffyCN/meta-rockchip](https://github.com/JeffyCN/meta-rockchip).
- `{RK356x}` **Buildroot amont** (`BR2_VERSION 2026.11-git`) : dans `configs/`, entrées Rockchip `roc_pc_rk3399`, `rock4se`, `rock5b`, `rockpro64`… et **aucun** defconfig RK3566/RK3568 (pas de quartz64, rock3, radxa_zero3) [lu, listing via API GitLab, 205 premières entrées alphabétiques] — [buildroot configs](https://gitlab.com/buildroot.org/buildroot/-/tree/master/configs). Le SDK Rockchip RK356x, lui, repose sur un **Buildroot forké** (base novembre 2021, Weston 11.0.1, Chromium 111 en 2023) [lu] — [SDK note 5.10](https://github.com/TinkerBoard/rockchip-linux-bsp-internal_doc-en/blob/linux5.10-rk356x/RK3566_RK3568_Linux5.10_SDK_Note.md).
- `{RK3566}` Contexte : « Software development for the RK3566 platform has reached a high level of maturity with both mainline and BSP Linux supporting nearly all core functionality » (PineTab2, Pine64) [lu, extrait] — [PineTab2 docs](https://pine64.org/documentation/PineTab2/_full/).

### Inferences
- **[déduit]** Pile recommandée pour la X88Pro20, dans l'ordre de risque croissant :
  1. **Armbian/ophub bookworm, noyau BSP 6.1 + Panfrost + Mesa 25.0.7 (bookworm-backports) + Chromium Debian**. C'est ce que le labo a déjà, sauf Mesa. Sortie 1080p60 à évaluer contre 4K60.
  2. Même base, avec Mesa 26.2.x recompilé ou rétroporté, pour les correctifs Bifrost 2026 (compilateur, CRC). Gain surtout en maintenance, **pas** en API noyau, puisque l'API Panfrost reste en 1.2 sur BSP.
  3. Chemin vendeur libmali : noyau à recompiler avec `MALI_BIFROST` + Chromium patché. Seulement si un banc sur la box le justifie.
  4. Mainline (Armbian `current` 6.18 / `edge` 7.2) : seulement sur une carte à DTS amont (ROCK 3C : Armbian current/edge, ophub stable 6.18), et seulement si le kiosque n'a pas besoin de décodage HEVC/VP9/4K matériel.
- **[déduit]** Le labo en tient déjà compte : pour un **déploiement**, préférer une carte figée à DTS amont à la « loterie de révision » des boîtiers. Côté Armbian : ROCK 3C en `current,edge` seulement (communautaire), Orange Pi 3B en `vendor,current,edge` (communautaire), Radxa ZERO 3 en `vendor,current,edge` (support standard). L'Orange Pi 3B et la ZERO 3 gardent donc l'option BSP (MPP), la ROCK 3C non.

### Gaps
- **Fedora** : aucun fait vérifié sur le support RK3566/Quartz64 en 2026 (wiki et forums bloqués, budget épuisé).
- **Debian stock** (sans Armbian) : pas de source consultée sur l'image `netinst`/`DTB` RK3566 en trixie ; packages.debian.org bloqué, version de Mesa de trixie non vérifiée ici.
- **SDK Rockchip Linux 6.1** pour RK356x : versions de Chromium, Weston et libmali non trouvées.
- **DietPi** : release exacte du passage de la ZERO 3 en 6.12, et présence éventuelle d'un correctif 4K60 (un 6.12 **amont** plafonne à 340 MHz TMDS).

---

## Q6 — Comparaisons documentées Panfrost vs libmali, mainline vs BSP (navigateur, WebGL, glmark2) sur RK3566/RK3568

### Takeaway
**Rien de probant n'a été trouvé** : aucune comparaison tête-à-tête navigateur ou WebGL Panfrost vs libmali, ni mainline vs BSP, sur RK3566/RK3568. Seuls existent un glmark2-es2 isolé (~150, pilote non précisé) et un résultat OpenBenchmarking (Radxa Zero 3W) dont les chiffres n'ont pas pu être lus. **Le banc reste à faire sur la box.**

### Cited Findings
- `{RK3566}` « getting a low 150 mark » en glmark2-es2 sur le G52 d'un RK3566, contre « over 200 for a G31 » sur une autre machine [mesuré par la source, extrait ; pilote, noyau, Mesa et résolution inconnus] — [Manjaro forum](https://forum.manjaro.org/t/can-someone-share-rk3566-gpu-benchmark/126583).
- `{RK3566}` OpenBenchmarking « Arm Mali G52-2EE GPU Rockchip RK3566 Radxa Zero 3W Benchmarks », résultat `2512263-NE-ARMMALIG569` (identifiant daté du 26/12/2025) : **chiffres non consultés** [lu, existence seulement] — [openbenchmarking.org](https://openbenchmarking.org/result/2512263-NE-ARMMALIG569).
- `{Bifrost v7}` Seule donnée de perf Panfrost interne : le CRC coûte « a few % hit at most » en glmark synthétique selon l'auteure en 2023 ; ce n'est pas une comparaison avec le blob [lu] — [commit fc30fe5b](https://gitlab.com/freedesktop-sdk/mirrors/freedesktop/mesa/mesa/-/commit/fc30fe5b).
- `{RK3588}` ⚠️ Hors sujet (lignée G610) : les comparaisons Panfrost/panfork vs libmali existantes concernent le RK3588 (forum Radxa « GPU Performance with Debian ») et ne se transposent pas [lu, extrait] — [Radxa forum](https://forum.radxa.com/t/gpu-performance-with-debian/13576).

### Inferences
- **[déduit]** Protocole minimal pour trancher sur la box (référence intercalée, puisque le CPU et la DDR ne changent pas entre deux essais) :
  - `glmark2-es2-drm` et un WebGL fixe (Aquarium à N poissons, MotionMark, scroll d'une page du kiosque) ;
  - en **1080p60 puis 4K60** ;
  - avec Mesa 22.3.6 / 25.0.7 / 26.2.x, puis `PAN_MESA_DEBUG=nocrc` en contrôle ;
  - libmali g24p0 seulement si un noyau `MALI_BIFROST` est construit.

### Gaps
- Aucune source de bancs croisés trouvée, et la recherche a été interrompue : quota de 200 requêtes web de la session épuisé ; cnx-software, Armbian, Radxa, Phoronix et OpenBenchmarking bloqués en lecture directe. Pistes à rouvrir si l'accès le permet :
  - revues CNX de ROCK 3A/3C, Orange Pi 3B et Quartz64 (glmark2 sous chaque pilote) ;
  - fil Armbian « Orange Pi 3B graphic acceleration driver » : [forum.armbian.com/topic/32020](https://forum.armbian.com/topic/32020-orange-pi-3b-graphic-acceleration-driver/) ;
  - fil Radxa « Rock 3A/3B RK3568 GPU Drivers » : [forum.radxa.com/t/20646](https://forum.radxa.com/t/rock-3a-3b-rk3568-gpu-drivers/20646).
