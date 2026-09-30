# Pile libmali + Xorg Rockchip + Chromium sur RK356x (Debian bookworm arm64)

> Recherche documentaire du **30/09/2026** (aucun SSH, aucun test sur la box).
> Contexte : box RK3566 (Mali-G52), Armbian bookworm, noyau ophub BSP 6.1.141, kbase **g29p1**
> construit hors arbre, userspace Radxa `libmali-bifrost-g52-g13p0-x11-gbm`. Xorg Debian 21.1.7
> segfault avec glamor+libmali ; sans glamor pas de DRI2 ⇒ EGL X11 de libmali KO. kbase : « no
> supported OPPs », GPU bloqué à 166 MHz.
>
> **Étiquettes** : **[mesuré par la source]** = la source rapporte une mesure · **[lu]** = lu dans
> une source (doc, code, changelog) · **[lu-deb]** = lu **par moi dans le paquet .deb téléchargé**
> (métadonnées `dpkg-deb -I`, `readelf`, `strings`) le 30/09/2026 — c'est du « lire du code », pas
> une exécution · **[déduit]** = inférence, à vérifier sur la box.
>
> **Hôtes refusés par le proxy (403 EGRESS_BLOCKED)**, donc lus seulement via extraits de recherche :
> `radxa-repo.github.io`, `docs.radxa.com`, `forum.radxa.com`, `forum.armbian.com`,
> `download.opensuse.org`, `api.launchpad.net`, API GitHub. Rien n'a été contourné.

---

## 0. La trouvaille qui change le plan : **les debs précompilés du SDK Rockchip existent toujours**

`rockchip-linux/debian` a disparu de GitHub, mais son contenu est **miroité sur GitLab** et Radxa
s'en sert comme sous-module : `https://gitlab.com/rk3588_linux/linux/debian.git`
([.gitmodules de radxa-pkg/rockchip-prebuilt](https://github.com/radxa-pkg/rockchip-prebuilt)) [lu].

Tags disponibles (API GitLab, 30/09/2026) [lu] : `linux-6.12-stan-rkr1` (2026-06-30) ·
`linux-6.1-stan-rkr5.1` (2025-02-12) · `linux-6.1-stan-rkr5` (2024-12-25) · `linux-6.1-stan-rkr4`
(2024-10-16) · `linux-6.1-stan-rkr1` (2023-12-28) · … (anciens 5.10/4.19).

Les binaires sont dans `packages/arm64/<famille>/` et se téléchargent directement (pas de LFS) :
`https://gitlab.com/rk3588_linux/linux/debian/-/raw/<TAG>/packages/arm64/<famille>/<fichier>.deb`
— vérifié : `xserver-xorg-core` rkr4 = 1 253 564 o, HTTP 200, deb valide [lu-deb].

⇒ **Il n'est probablement pas nécessaire de compiler JeffyCN/xorg-xserver** : le SDK en livre le
binaire bookworm arm64 prêt à l'emploi (voir § 1.1). [déduit]

---

## 1. Paquets prêts à l'emploi — URLs, noms, versions

### 1.1 SDK Rockchip (miroir GitLab) — paquets pertinents [lu, listing API GitLab 30/09/2026]

| Famille | `linux-6.1-stan-rkr4` (oct. 2024) | `linux-6.1-stan-rkr5.1` (fév. 2025) | `linux-6.12-stan-rkr1` (juin 2026) |
|---|---|---|---|
| xserver | `xserver-xorg-core_21.1.7-3_arm64.deb`, `xserver-common_21.1.7-3_all`, `xserver-xorg-legacy_21.1.7-3` | idem 21.1.7-3 | **`xserver-xorg-core_21.1.7-3+deb12u2_arm64.deb`** (+common, +legacy) |
| libmali G52 | `libmali-bifrost-g52-g13p0-{x11-gbm, x11-wayland-gbm, wayland-gbm, gbm, dummy…}_1.9-1` **et** `…-g2p0-…_1.9-1` | **`libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1`** (seul) | **`libmali-bifrost-g52-g29p1_1.10-1`** (paquet unique, sans suffixe de plateforme) |
| chromium | `chromium/chromium-x11_126.0.6478.126_arm64.deb` | idem 126 | `chromium-ozone-wayland_132.0.6834.83_arm64.deb` (**Wayland**, plus de x11) |
| libv4l-rkmpp | `libv4l/libv4l-rkmpp_1.7.0-1` + `libv4l-0_1.22.1-5` (patché) + `v4l-utils_1.22.1-5` | idem | `libv4l-rkmpp_1.8.0-1` + `libv4l-0t64_1.30.1-1` (**t64 = trixie**, pas pour bookworm) |
| mpp | `librockchip-mpp1_1.5.0-1`, `librockchip-vpu0_1.5.0-1`, `rockchip-mpp-demos` | idem | idem 1.5.0-1 |
| gstreamer | `gst-rkmpp/gstreamer1.0-rockchip1_1.14-4` (+ gst-plugins-{base,good,bad} 1.22.9 recompilés) | idem | idem 1.14-4 |
| rga | `rga/librga2_2.1.0-1` **et** `rga2/librga2_2.2.0-1` (même nom de paquet, deux versions) | idem | idem |
| divers | `libdrm2_2.4.114-1`, `libdrm-cursor_1.4.1-1`, `weston_10.0.1-1+deb12u1` | idem | `libdrm2_2.4.124-2`, `weston_14.0.2-5` |

Dépendances relevées dans les .deb [lu-deb] :
- `xserver-xorg-core 2:21.1.7-3` (rkr4) et `2:21.1.7-3+deb12u2` (6.12-rkr1) : `Depends … libegl1,
  libgbm1 (>= 17.3.0~rc1), libgl1, librga2, libc6 (>= 2.35)` · **`Provides: xserver-xorg-video-modesetting`**
  · `Conflicts/Replaces: xserver-xorg-video-modesetting`. Contient `modesetting_drv.so` et
  `libglamoregl.so`. Le `modesetting_drv.so` porte les chaînes `FlipFB`, `MaxFlipRate`,
  `AsyncFlipSecondaries`, `Atomic`, `HotplugReset`, `NoEDID`, `Padding`, `c_RkRgaBlit`, `librga.so.2`,
  `Using RGA EXA`, `DRI2-flip` — c'est bien le fork JeffyCN (options Rockchip + EXA sur RGA).
  Le changelog Debian embarqué s'arrête à `2:21.1.7-3` (03/05/2023) : les patches Rockchip ne sont
  **pas** tracés dans le changelog.
- `libv4l-rkmpp 1.7.0-1` : `libc6 (>= 2.34), librockchip-mpp1` · fichier unique
  `/usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-rkmpp.so`.
- `gstreamer1.0-rockchip1 1.14-4` : `libgstreamer1.0-0 (>= 1.14), librga2, librockchip-mpp1, libx11-6, libdrm2`.
- `librockchip-mpp1 1.5.0-1` : `libc6 (>= 2.34), libstdc++6 (>= 5)`.
- `libmali-bifrost-g52-g29p1 1.10-1` : `libc6 (>= 2.28), libdrm2, libstdc++6` — **aucune dépendance X11
  déclarée** (voir § 4).

⚠️ **Piège de version (apt)** [déduit] : le SDK numérote `2:21.1.7-3` / `+deb12u2`, alors que Debian
bookworm a publié depuis des mises à jour de sécurité `2:21.1.7-3+deb12uN` avec N > 2. Un
`apt upgrade` **remplacera** le Xorg Rockchip par celui de Debian (et le segfault reviendra).
Idem `libv4l-0 1.22.1-5` : **même numéro** que Debian bookworm, mais le SDK porte le patch mmap exigé
par libv4l-rkmpp (§ 3.4) — apt peut considérer les deux interchangeables. ⇒ `apt-mark hold`
(ou pin 1001) sur `xserver-xorg-core xserver-common xserver-xorg-legacy libv4l-0 libv4lconvert0
libmali-*`. Vérifier avec `apt-cache policy` sur la box.

### 1.2 Radxa — dépôts apt par SoC

- Dépôt : `deb [signed-by=/usr/share/keyrings/radxa-archive-keyring.gpg] https://radxa-repo.github.io/rk3566-bookworm/ rk3566-bookworm main`
  (idem `rk3568-bookworm`, `rk3566t-bookworm`) — script
  [`install.sh` de radxa-repo/rk3566-bookworm](https://github.com/radxa-repo/rk3566-bookworm) [lu, 30/09/2026].
  Keyring : `https://github.com/radxa-pkg/radxa-archive-keyring/releases/latest/download/radxa-archive-keyring_${version}_all.deb`.
- **Le dépôt Radxa n'est qu'un ré-emballage du SDK** : `pkgs.json` de rk3566-bookworm liste
  `rockchip-prebuilt 0.4.2-linux-6.1-stan-rkr4-5`, et `pkg.conf.linux-6.1-stan-rkr4` publie **tous**
  les debs du tag rkr4 (clé `"*"`) vers `rk3566-bookworm`, `rk3568-bookworm`, `rk3566t-bookworm`…
  sauf `chromium-x11_126.0.6478.126_arm64.deb` dont la liste de releases est **vide**
  ([pkg.conf](https://github.com/radxa-pkg/rockchip-prebuilt), changelog) [lu].
  ⇒ Le `xserver-xorg-core` servi par Radxa rk3566-bookworm = **`2:21.1.7-3` du SDK rkr4** ; la libmali
  = `libmali-bifrost-g52-g13p0-*_1.9-1`. [déduit du mécanisme, `radxa-repo.github.io` non lisible]
- Chronologie chromium côté Radxa (changelog `rockchip-prebuilt`) [lu] :
  - 12/12/2024 `0.4.2-…-rkr4-3` : « chromium: replace libmali-hook.so.1 to libgbm.so.1 » ;
  - 07/08/2025 (PR #10) puis **03/04/2026** `0.4.2-…-rkr4-5` : « remove the prebuilt chromium package »
    pour rkr5.1 puis rkr4.
  - À la place, `pkgs.json` (rk3566/rk3568/bookworm) pointe `chromium-x11 0.4.1-linux-6.1-stan-rkr1-5`,
    release du 07/08 dont le seul asset est **`chromium-x11_111.0.5563.147_arm64.deb`** (78,3 Mo) avec
    la note : « **This old Chromium version is picked specifically for better VPU support.** »
    ([release](https://github.com/radxa-pkg/chromium-x11/releases/tag/0.4.1-linux-6.1-stan-rkr1-5)) [lu].
    Le script `fixup` du dépôt fait `patchelf --replace-needed libmali.so.1 libgbm.so.1` sur
    `chromium-bin` et ajoute `libc++1` aux Depends ([fixup](https://github.com/radxa-pkg/chromium-x11/blob/main/fixup)) [lu].
  - ⇒ **Radxa a retiré Chromium 126 et sert aujourd'hui Chromium 111 aux RK356x, « pour un meilleur
    support VPU ».** La raison exacte (régression VPU de la 126 ?) n'est pas écrite publiquement. [lu + déduit]
- Autres paquets Radxa utiles (`pkgs.json` rk3566-bookworm, 30/09/2026) [lu] :
  `rockchip-chromium-x11-utils 0.2.3` (service qui crée `/dev/video-dec0` — § 3.4),
  `radxa-xorg-wrapper 0.2.0`, `gstreamer-rockchip 1.14-5`, `libdrm 2.4.122+git…oibaf`,
  `mesa git2407100600…oibaf` (Panfrost), `linux-rk2312 6.1.43-26`, `linux-rk2410 6.1.84-8`.
- Doc Radxa « Switch GPU driver » (extraits de recherche, page non lisible) [lu] : sous bookworm les
  RK356X sont en **Panfrost par défaut** ; pour passer sur Mali, fichier `apt preferences` avec
  `Pin: release a=rk3566-bookworm` / `Pin-Priority: 1001` pour les paquets xserver, puis
  `apt-get install libmali-bifrost-g52-g13p0-x11-wayland-gbm`.
  <https://docs.radxa.com/en/som/cm/cm5/radxa-os/mali-gpu>

### 1.3 Armbian / amazingfate (liujianfeng1994)

- Armbian a basculé sur la pile **libre** (Panfrost/Panthor + Mesa backportée), pas libmali [lu] :
  PR [#6994](https://github.com/armbian/build/pull/6994) (26/07/2024) ajoute pour bookworm
  `deb http://download.opensuse.org/repositories/home:/amazingfate:/mesa-bookworm-backport/Debian_12/ /`.
  PR [#7515](https://github.com/armbian/build/pull/7515) (02/12/2024) retire `ppa:liujianfeng1994/chromium`
  (chromium importé dans le dépôt Armbian ; jammy/noble).
- OBS amazingfate : projet `home:amazingfate:libmali-rockchip` avec cibles **Debian_12** et
  Debian_Testing (extrait de recherche) —
  <https://download.opensuse.org/download/repositories/home:/amazingfate:/libmali-rockchip/> [lu, non ouvert : 403].
- PPA `ppa:liujianfeng1994/rockchip-multimedia` (rockchip-multimedia-config, libv4l-rkmpp,
  gstreamer1.0-rockchip, chromium patché) : **Ubuntu jammy/noble seulement** ; « Launchpad PPAs don't
  support Debian » (extraits) [lu]. Pour bookworm, préférer le SDK (§ 1.1).
- Firefly / Orange Pi / Khadas : rien de plus récent ni de plus précis trouvé que le SDK ; leurs images
  Debian embarquent les mêmes paquets SDK [déduit, non vérifié].

---

## 2. Recettes complètes connues et Chromium livré

### 2.1 Recette de référence = SDK Rockchip Debian 12 (overlay du miroir, tag rkr4) [lu]

`overlay/etc/init.d/rockchip.sh`, au premier boot, pour `rk3566|rk3568` :
```
MALI=bifrost-g52-g13p0
apt install -fy --allow-downgrades /libmali-*$MALI*-x11-wayland-gbm*.deb
```
puis, à chaque boot :
```
echo dec > /dev/video-dec0 ; echo enc > /dev/video-enc0
chmod 660 /dev/video-* ; chown root:video /dev/video-*
ln -rsf /usr/lib/*/libv4l2.so /usr/lib/
ln -Tsf lib /usr/lib64
```
Plus `S10atomic_commit.sh` : `modetest -M rockchip -aw <plan>:ASYNC_COMMIT:1` sur tous les plans.
Plus une règle udev : `KERNEL=="mali*", MODE="0660", GROUP="video"`, idem `rga`, `mpp_service`,
`rkvdec`… (`99-rockchip-permissions.rules`).
Source : <https://gitlab.com/rk3588_linux/linux/debian/-/tree/linux-6.1-stan-rkr4/overlay>

⚠️ **Le SDK choisit `x11-wayland-gbm`, pas `x11-gbm`** pour RK3566/3568 [lu]. Notre box a `x11-gbm`.

### 2.2 `20-modesetting.conf` du SDK (rkr4) — texte intégral utile [lu]
```
Section "OutputClass"
    Identifier  "RockchipDRM"
    MatchDriver "rockchip"
    Option      "PrimaryGPU"     "yes"
EndSection
Section "Device"
    Identifier  "Rockchip Graphics"
    Driver      "modesetting"
#   Option      "AccelMethod"    "exa"      ### RGA 2D
    Option      "AccelMethod"    "glamor"   ### GPU
    Option      "DRI"            "2"
### "always" évite le tearing, jusqu'à 50 % de perte de perf
    Option      "FlipFB"         "always"
#   Option      "MaxFlipRate"    "60"
    Option      "NoEDID"         "true"
    Option      "UseGammaLUT"    "true"
EndSection
```
(`rockchip.sh` remplace `always` par `none` pour les puces Midgard/Utgard/G31, **pas** pour G52.)
Autres variables : `/etc/profile.d/x11.sh` → `DISPLAY=:0`, `XSERVER_FREEZE_DISPLAY=/tmp/.freeze_xserver`.

### 2.3 Chromium livré, et comment il est câblé [lu-deb, chromium-x11 126.0.6478.126 du SDK rkr4]

- Taille 92,7 Mo ; `/usr/bin/chromium → /usr/lib/chromium/chromium-wrapper` ; embarque ses propres
  `libEGL.so`/`libGLESv2.so` (ANGLE), `libc++.so.1`, swiftshader.
- `chromium-bin` **NEEDED : `libmali-hook.so.1` et `libmali.so.1`** (lien direct à libmali !). Il
  référence en dur `/usr/lib64/libv4l2.so`, `/usr/lib/libmali.so`, `/dev/video-dec0`, `/dev/video-enc0`.
  ⇒ Sans `/usr/lib64 → lib` et le lien `libv4l2.so`, pas de décodage matériel. [lu-deb + déduit]
- Arguments forcés par le wrapper :
  `--use-gl=angle --use-angle=gles-egl --use-cmd-decoder=passthrough --no-sandbox --gpu-sandbox-start-early --ignore-gpu-blocklist --enable-gpu-rasterization --enable-accelerated-video-decode --enable-features=VaapiVideoDecoder,VaapiVideoEncoder`
  (plus webgpu/unsafe-webgpu, remote-extensions…).
- La libmali `g13p0` du SDK fournit bien `libmali-hook.so.1` ; Radxa l'a patché vers `libgbm.so.1`
  (12/12/2024) [lu] — probablement parce que certaines libmali/Panfrost n'ont pas de hook [déduit].

### 2.4 Images Radxa ROCK 3C / ZERO 3W
- Annonce « Debian 12 with Linux 6.1 for the RK3399 & RK356X Series » (forum Radxa, non lisible) ;
  par défaut **Panfrost**, Mali en option (§ 1.2) [lu, extraits].
- Chromium côté dépôt aujourd'hui : **111.0.5563.147** (§ 1.2).
- Ubuntu-Rockchip (Joshua-Riek) sur ZERO 3W : issue [#692](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/692)
  (05/04/2024) — pas d'accélération vidéo Chromium (`Failed to export buffer to dma_buf`,
  `Failed to query video capabilities: Inappropriate ioctl for device`), **fermée « not planned »**,
  dépôt archivé 29/04/2026 [lu].

### 2.5 Performances réelles rapportées
- **Aucun chiffre public trouvé** de lecture Chromium + libv4l-rkmpp sur RK3566 (fps, images perdues).
- libv4l-rkmpp : « performance similaire aux autres décodeurs MPP, dépend surtout de la résolution/débit
  et des horloges VPU » (README/issues) [lu]. Testé par l'auteur sur **RK3588 EVB** seulement [lu].
- V4L2VideoDecoder générique sur Rockchip (Hantro, rk3399/rk3568, noyau mainline) : image instable,
  « perceived fps around 15 » malgré des timestamps corrects
  ([chromium-dev](https://groups.google.com/a/chromium.org/g/chromium-dev/c/AOPuSQVz9Gs)) [mesuré par la source] —
  chemin **différent** du nôtre (stateless mainline, pas libv4l-rkmpp).
- Plafond logiciel pour comparaison, NanoPi R3S (RK3566), décodage **CPU** 1080p30 bruité :
  H.264 **2,56× temps réel**, HEVC **1,15×**, 4K sous le temps réel
  ([Anthias PR #3332](https://github.com/Screenly/Anthias/pull/3332)) [mesuré par la source].
- Matériel RK3566 annoncé : H.265/VP9 4K60, H.264 4K30/1080p60… (fiches) [lu].
  ⇒ **Notre banc sera la première mesure** ; mettre `log-fps=1` dans `/dev/video-dec0` (§ 3.4).

---

## 3. Pièges connus

### 3.1 libmali + glamor (Xorg)
- **Xorg Debian + libmali = segfault / pas de DRI2** : attendu. Le glamor amont suppose Mesa (GL
  desktop / extensions). Le fork JeffyCN porte des correctifs précisément là [lu, liste des commits
  de `JeffyCN/xorg-xserver` branche `rockchip/debian/21.1.7`] :
  « glamor: Make GL_{ARB,OES}_texture_border_clamp optional » (05/03/2024),
  « HACK: glamor: Special hacks for Mali Utgard DDK », « HACK: glamor: Early out for making
  GBM_FORMAT_R8 pixmap », « HACK: glamor: Clear the created empty FBO » (05/06/2024),
  « glamor: Always unmap bo when finishing access » (04/12/2024),
  « modesetting: dri2: Disable pageflipping when transformed »,
  « modesetting: Fix flicker when setting mode in flip fb mode » (23/01/2025),
  « modesetting: Fix output padding error » (20/02/2025),
  « modesetting: Recreate flip fb buffers when CRTC mode changed » (06/11/2025),
  « modesetting: Fixup output's enc_clone_mask » (11/11/2025).
  <https://github.com/JeffyCN/xorg-xserver/commits/rockchip/debian/21.1.7>
  ⚠️ Le deb **rkr4 (oct. 2024)** précède les correctifs de 2025 ; le deb **6.12-stan-rkr1
  (`+deb12u2`, juin 2026)** les contient probablement [déduit des dates]. **Préférer celui-là** si l'on
  prend un binaire ; sinon compiler la tête de branche (ce qui est le plan actuel).
- `Option "DRI" "2"` est **explicite** dans la conf SDK : la libmali g13p0 X11 ne parle que **DRI2**
  (NEEDED `libxcb-dri2.so.0`, pas de dri3/present) [lu-deb]. La g24p0 ajoute dri3/present/xfixes [lu-deb].
- `FlipFB "always"` : anti-tearing au prix de « jusqu'à 50 % » de perf ; `MaxFlipRate "60"` pour
  limiter. En kiosque plein écran vidéo : tester `always` vs `none` [lu + déduit].
- `AccelMethod "exa"` = 2D sur RGA (repli si glamor pose problème) ; mais alors pas de DRI2 via glamor
  → EGL X11 libmali probablement KO comme aujourd'hui [déduit : le message
  `DRI2: glamor lacks support for pixmap import/export` est dans le binaire].
- Le deb Rockchip **Provides/Replaces `xserver-xorg-video-modesetting`** : ne pas réinstaller de
  pilote modesetting séparé [lu-deb].
- `ASYNC_COMMIT=1` sur les plans (script S10) : comportement des anciens BSP 4.4 ; à reproduire si le
  flip bloque [lu].
- meta-rockchip (Yocto de JeffyCN) utilise le même `20-modesetting.conf` — non relu ici (hors délai).

### 3.2 Chromium Rockchip
- La 126 du SDK est **liée à `libmali.so.1` + `libmali-hook.so.1`** : elle ne démarre pas sans
  libmali installée ; changer de libmali (g13p0 → g24p0/g29p1) garde les SONAME, a priori compatible
  [lu-deb + déduit].
- Radxa a jugé la **111** meilleure pour le VPU et a retiré la 126 (§ 1.2) : si la 126 ne décode pas
  en matériel sur notre box, la 111 est la référence Radxa à essayer [lu + déduit].
- `--use-gl=angle --use-angle=gles-egl` : ANGLE sur EGL/GLES de libmali ⇒ c'est le chemin EGL X11
  (DRI2) qui doit marcher d'abord (`es2_info`/`glmark2-es2` côté X). [déduit]

### 3.3 kbase : « no supported OPPs » et GPU bloqué

**Mécanisme** [lu dans le code] :
- Le message vient du **cœur OPP du noyau**, `drivers/opp/of.c` (v6.1.141) :
  `_opp_is_supported()` — si la plateforme **n'a pas fixé `supported_hw`** et qu'un nœud OPP porte
  `opp-supported-hw`, l'OPP est **rejetée** (« no way to see if the hardware supports it ») ; si aucune
  ne reste : `dev_err(dev, "%s: no supported OPPs")` → `-ENOENT`.
  <https://github.com/gregkh/linux/blob/v6.1.141/drivers/opp/of.c>
- La table GPU du DT vendeur (`rk356x.dtsi`, Rockchip develop-6.1 **et** `unifreq/linux-6.1.y-rockchip`,
  la base d'ophub) porte `rockchip,supported-hw;` et **chaque OPP a `opp-supported-hw`**
  (`<0xfb 0xffff>` pour 200–700 MHz, `<0xf9 0xffff>` pour 800 MHz), plus des cellules nvmem
  `leakage`, `pvtm`, `mbist-vmin`, `opp-info`, `specification_serial_number`,
  `remark_spec_serial_number` et `rockchip,pvtm-voltage-sel` [lu].
- C'est `rockchip_opp_select.c` qui calcule `supported_hw` : `[0] = BIT(bin)` (bin = 0 normal,
  1 = « M », 2 = « J », 3 = « S », lus dans l'OTP), `[1] = BIT(volt_sel)` (leakage/pvtm), puis
  `dev_pm_opp_set_config()` [lu]. Pour un RK3566 standard (bin 0) → 0x01 ∈ 0xfb : les 200–800 MHz
  sont éligibles [déduit].
- Le kbase **Rockchip** appelle ce chemin : `mali_kbase_core_linux.c` →
  `#ifdef CONFIG_ARCH_ROCKCHIP kbase_platform_rk_init_opp_table()` →
  `rockchip_init_opp_table(dev, &opp_info, "clk_mali", "mali")` (fichier
  `platform/rk/mali_kbase_config_rk.c`) ; **sinon** `dev_pm_opp_of_add_table()` nu [lu].
  <https://github.com/rockchip-linux/kernel/tree/develop-6.1/drivers/gpu/arm/bifrost>

**Causes probables sur notre box** [déduit] :
1. kbase construit **sans la plateforme `rk`** (`MALI_PLATFORM_NAME=devicetree`, défaut du Kconfig)
   ou d'une source ARM non-Rockchip ⇒ `dev_pm_opp_of_add_table()` sans `supported_hw` ⇒ toutes les
   OPP rejetées. **C'est le candidat n° 1** : le Kconfig ophub a `# CONFIG_MALI_BIFROST is not set`
   et `CONFIG_DRM_PANFROST=m` (kbase jamais construit par ophub), mais `CONFIG_ROCKCHIP_OPP=y`,
   `ROCKCHIP_PVTM=y`, `ROCKCHIP_SYSTEM_MONITOR=y`, `ROCKCHIP_IPA=y`, `NVMEM_ROCKCHIP_OTP=y` — les
   briques sont là, il faut que le module les appelle.
   <https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1> [lu]
2. DT de la box (dtb TV-box ophub) : nœud GPU **mainline** (`clock-names "gpu","bus"`, pas
   `clk_mali`) ou sans `mali-supply` ⇒ `rockchip_init_opp_table(…,"clk_mali","mali")` échoue avant
   de poser `supported_hw`. Vérifier `dtc -I fs /proc/device-tree` → nœud `gpu@fde60000`.
3. Cellules nvmem (OTP) absentes/illisibles ⇒ erreur `Failed to get specification_serial_number`.
- Les 166 MHz : fréquence laissée par le firmware/SCMI (`clk_mali` = `scmi_clk 1`) faute de devfreq
  [déduit, non vérifié].

**Remèdes, du plus propre au plus brutal** [déduit] :
- (a) Reconstruire kbase depuis `drivers/gpu/arm/bifrost` de **`unifreq/linux-6.1.y-rockchip`**
  (même arbre qu'ophub, `MALI_RELEASE_NAME "g29p1-12eac0"`) avec `CONFIG_MALI_BIFROST=m`,
  `CONFIG_MALI_PLATFORM_NAME="rk"`, `CONFIG_MALI_BIFROST_DEVFREQ=y` ; dmesg doit alors afficher
  `bin=…`, `soc version=…, speed=…`.
- (b) Overlay DT qui **supprime `opp-supported-hw`** de chaque nœud de `gpu_opp_table` (et
  `rockchip,supported-hw`) : le cœur OPP accepte alors toutes les OPP ; on perd la sélection de
  tension par leakage/pvtm (tension L0 nominale — plus chaude, pas dangereuse dans la plage 850–1000 mV
  du DT). Garder max 600 ou 800 MHz selon refroidissement de la box.
- (c) Table OPP mainline (`opp-200000000 … opp-800000000` sans `opp-supported-hw`) si le nœud GPU est
  mainline.

### 3.4 libv4l-rkmpp (décodage Chromium)
- Exige **v4l-utils/libv4l2 avec le patch « Support mmap to libv4l plugin »** (README) ; le SDK le livre
  dans `libv4l-0_1.22.1-5` — même numéro que Debian (§ 1.1) [lu].
  <https://github.com/JeffyCN/libv4l-rkmpp>
- Faux nœuds `/dev/video-dec0` / `/dev/video-enc0` = **fichiers texte** de capacités. Le service Radxa
  `rockchip-chromium-prep` écrit pour `*rk3568*` :
  `type=dec / codecs=VP8:VP9:H.264:H.265 / max-width=3840 / max-height=2160` ; **pour tout autre
  compatible (donc `rockchip,rk3566`) seulement `dec`** [lu].
  <https://github.com/radxa-pkg/rockchip-chromium-x11-utils>
  Le plugin met `max_width/max_height` **à 0** s'ils ne sont pas donnés (`calloc`, pas de valeur par
  défaut dans `libv4l-rkmpp.c`) [lu] ⇒ sur RK3566, **écrire le fichier complet à la main** (copier la
  ligne rk3568, ajouter `log-fps=1` pour mesurer) [déduit].
- Le plugin ignore les vrais périphériques caractère (`S_ISCHR` → refus) : c'est voulu, le nœud doit
  être un fichier ordinaire [lu].
- Chromium cherche `/usr/lib64/libv4l2.so` : `ln -rsf /usr/lib/*/libv4l2.so.0 /usr/lib/libv4l2.so` et
  `ln -Tsf lib /usr/lib64` [lu].

---

## 4. libmali g13p0 (userspace) contre kbase g29p1 (noyau) — compatibilité UK

**Ce que dit le code du noyau** [lu] — `kbase_api_handshake()` (Rockchip develop-6.1, g29p1) :
```
case BASE_UK_VERSION_MAJOR:
    /* set minor to be the lowest common */
    version->minor = min_t(int, BASE_UK_VERSION_MINOR, (int)version->minor);
default: /* on renvoie notre version, l'userspace décide */
```
- kbase g29p1 (JM, Bifrost G52) : `BASE_UK_VERSION_MAJOR 11`, `MINOR 46` (develop-6.1) ; le g25p0 de
  develop-5.10 annonce 11.47 [lu]. Tout userspace JM en **11.x** passe donc la poignée de main, le
  noyau s'alignant sur la mineure la plus basse ; l'historique 11.13→11.46 est documenté dans
  `mali_kbase_jm_ioctl.h` [lu].
- **Donc g13p0 (UK 11.x plus ancienne) sur kbase g29p1 : compatible au niveau protocole, par
  conception** [déduit du code]. Le sens dangereux est l'inverse (userspace plus récent que le noyau).
- **Mais** les retours terrain disent « DDK firmware et libmali doivent être la même version », avec le
  symptôme `Failed creating base context during opening of kernel driver`
  ([rockchip-linux/libmali#53](https://github.com/rockchip-linux/libmali/issues/53),
  [ubuntu-rockchip#1200](https://github.com/Joshua-Riek/ubuntu-rockchip/issues/1200), forum Radxa
  « Mali GPU DDK rkr… ») [lu] — cas surtout **Valhall/CSF (RK3588)** où il y a un firmware GPU ;
  Bifrost G52 n'a pas de firmware CSF [déduit].
- **Chaînes relevées dans les binaires** [lu-deb] : g13p0 = `Bifrost-"g13p0-01eac0"`, g24p0 =
  `"g24p0-00eac0"`, g29p1 = `"g29p1-12eac0"` — **identique au `MALI_RELEASE_NAME` du kbase
  develop-6.1/unifreq**.
- ⇒ **Recommandation** [déduit] : apparier exactement, avec
  `libmali-bifrost-g52-g29p1_1.10-1_arm64.deb` du tag `linux-6.12-stan-rkr1`
  (<https://gitlab.com/rk3588_linux/linux/debian/-/raw/linux-6.12-stan-rkr1/packages/arm64/libmali/libmali-bifrost-g52-g29p1_1.10-1_arm64.deb>).
  Il dépend de `libc6 (>= 2.28)` — installable sur bookworm. Points à vérifier :
  - il ne déclare **aucune** dépendance X11/Wayland et n'a **pas** de `NEEDED` libX11/libxcb : il les
    **charge dynamiquement** ; les chaînes montrent `libX11.so`, `libX11-xcb.so`, `libxcb.so` **sans
    numéro** (au moins dans la couche Vulkan WSI) ⇒ il faudra peut-être `libx11-dev`/`libxcb1-dev`
    (liens `.so`) ou des liens manuels ; vérifier avec `LD_DEBUG=libs` ou `strace -e openat`.
  - il ajoute `/etc/profile.d/mali-priority.sh` (`MALI_SCHED_RT_THREAD_PRIORITY=95`) et un ICD Vulkan.
  - il fournit toujours `libmali.so.1` + `libmali-hook.so.1` ⇒ le Chromium 126 du SDK doit se lier.
  - Même nom de fichier `libmali.so.1` dans tous les paquets (`Conflicts/Provides: libmali`) ⇒ une seule
    libmali à la fois ; `/etc/ld.so.conf.d/00-aarch64-mali.conf` place `mali/` devant Mesa.
- Alternative intermédiaire : `libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1` (rkr5.1), qui gère
  DRI2 **et** DRI3/present [lu-deb].

---

## 5. Ordre de marche proposé (à valider sur la box) [déduit]

1. kbase : reconstruire avec plateforme `rk` (§ 3.3 a) **ou** overlay sans `opp-supported-hw` ;
   critère : `cat /sys/class/devfreq/fde60000.gpu/available_frequencies` non vide, plus de 166 MHz figé.
2. libmali : `libmali-bifrost-g52-g29p1_1.10-1` (appariée au kbase) ; contrôle hors X :
   un client GBM/EGL (le paquet `glmark2-es2-drm` du SDK existe dans rkr4).
3. Xorg : **prendre le deb SDK `xserver-xorg-core_21.1.7-3+deb12u2`** (tag 6.12-rkr1, post-correctifs
   2025) + `xserver-common` + `xserver-xorg-legacy` du même tag, `apt-mark hold`, conf § 2.2.
   Compiler JeffyCN seulement si ce deb pose problème. Critère : `Xorg.0.log` montre glamor initialisé
   et `DRI2` actif.
4. Décodage : `librockchip-mpp1 1.5.0-1`, `libv4l-0`/`libv4lconvert0 1.22.1-5` **du SDK** (hold),
   `libv4l-rkmpp 1.7.0-1`, `/dev/video-dec0` complet (§ 3.4), liens `/usr/lib64`.
5. Chromium : la 126 du SDK (wrapper tel quel) ; si pas de décodage matériel, essayer la **111** de
   Radxa (`chromium-x11_111.0.5563.147_arm64.deb`, release `0.4.1-linux-6.1-stan-rkr1-5`).
6. Mesurer (`log-fps=1`, `chrome://media-internals` → `kVideoDecoderName` = `V4L2VideoDecoder`/VDA).

---

## Sources (consultées le 30/09/2026)

- Miroir SDK Debian Rockchip : <https://gitlab.com/rk3588_linux/linux/debian> (API tags/tree, overlay, debs)
- <https://github.com/radxa-pkg/rockchip-prebuilt> (README, changelog, `pkg.conf.*`, `.gitmodules`)
- <https://github.com/radxa-repo/rk3566-bookworm> (`install.sh`, `pkgs.json`) ; idem rk3568-bookworm
- <https://github.com/radxa-pkg/chromium-x11> (releases, `fixup`)
- <https://github.com/radxa-pkg/rockchip-chromium-x11-utils> (`usr/bin/rockchip-chromium-prep`)
- <https://github.com/JeffyCN/xorg-xserver/commits/rockchip/debian/21.1.7>
- <https://github.com/JeffyCN/libv4l-rkmpp> (README, `src/libv4l-rkmpp.c`)
- <https://github.com/JeffyCN/mirrors/tree/libmali> (`gpu-chips.txt`, `meson_options.txt`)
- <https://github.com/rockchip-linux/kernel/tree/develop-6.1> (`rk356x.dtsi`, `rk3568.dtsi`,
  `drivers/gpu/arm/bifrost/…`, `drivers/soc/rockchip/rockchip_opp_select.c`, `mali_kbase_jm_ioctl.h`)
- <https://github.com/unifreq/linux-6.1.y-rockchip> (`rk356x.dtsi`, `bifrost/Kbuild`)
- <https://github.com/ophub/kernel/blob/main/kernel-config/release/rk35xx/config-6.1>
- <https://github.com/gregkh/linux/blob/v6.1.141/drivers/opp/of.c>
- <https://github.com/armbian/build/pull/6994>, <https://github.com/armbian/build/pull/7515>
- <https://github.com/Joshua-Riek/ubuntu-rockchip/issues/692>, <https://github.com/Joshua-Riek/ubuntu-rockchip/issues/1200>
- <https://github.com/rockchip-linux/libmali/issues/53>
- <https://github.com/Screenly/Anthias/pull/3332>
- <https://groups.google.com/a/chromium.org/g/chromium-dev/c/AOPuSQVz9Gs>
- Extraits de recherche seulement (hôtes bloqués) : docs.radxa.com « Switch GPU driver »,
  forum.radxa.com (annonce Debian 12 RK356X ; « Mali GPU DDK »), forum.armbian.com,
  download.opensuse.org `home:amazingfate:*`.
