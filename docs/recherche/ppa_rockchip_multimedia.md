# PPA `liujianfeng1994/rockchip-multimedia` — vérifié le 01/10/2026

Point de départ : la branche `rockchip-rkmpp-130` de `github.com/amazingfate/chromium-debian-build` (Jianfeng
Liu, développeur Armbian/Rockchip). C'est la recette Debian de Chromium avec 20 patchs Rockchip
(`debian/patches/rkmpp/`).

## Ce que contient la recette — lu

- décodeur V4L2 + plugins libv4l : `use_v4l2_codec=true use_v4lplugin=true` en arm64 ;
- correctifs Wayland : `0011`, `0018`, `upstream/wayland-gbm-pixmap.patch` ;
- `0019` « NV12 direct rendering » : retire dans `ui/gfx/linux/gbm_wrapper.cc` le refus « gbm format not
  supported », hors minigbm.
  ⚠️ C'est le fichier de notre échec avec Panfrost (`test_chromium_radxa_126.md`), mais notre message était un
  échec d'**export**, pas ce refus-là. Effet sur Panfrost : **non mesuré**.

## Ce que publie le PPA — interrogé par l'API Launchpad (mesuré)

`ppa:liujianfeng1994/rockchip-multimedia`, série **noble** (Ubuntu 24.04), arm64 :

| Paquet | Version | Publié |
|---|---|---|
| **chromium** | `132.0.6834.159-1~deb12u1+rkmpp` | 06/03/2025 |
| libv4l-rkmpp | 1.7.0 git240515 | 15/05/2024 |
| v4l-utils | 1.26.1 `+rkmpp1` (libv4l patchée) | 15/05/2024 |
| mpp | 1.5.0 git20240612 | 13/06/2024 |
| librga, gstreamer1.0-rockchip, ffmpeg (rkmpp), rockchip-multimedia-config | — | 2024 |

Le PPA voisin `liujianfeng1994/chromium` (« Chromium from debian ») porte un Chromium **135** sans suffixe
`rkmpp`, pour noble, en avril 2025.

## Le binaire Chromium 132 — mesuré

Paquet téléchargé et ouvert dans `/tmp` sur la box, sans l'installer, puis effacé :
- 85,7 Mo ;
- `readelf -d` : `libX11`, `libgbm` ;
- `strings` : `zwp_linux_dmabuf_v1` / `xdg_wm_base` présents, **4 occurrences**. Le Chromium Radxa 126 en a
  **0**. Le libwayland est donc embarqué, et la **plateforme Wayland est compilée**.
- `Depends: libc6 (>= 2.38)` ⇒ **Ubuntu noble obligatoire** ; bookworm a la 2.36.

## Ce que ça change

Tout ce qu'on assemble à la main sur Armbian bookworm existe empaqueté pour **noble** : MPP, libv4l-rkmpp,
libv4l patchée, et un Chromium MPP **avec Wayland**.

Essai à faire, sans réinstaller la box : un environnement noble en chroot sur la TurboNode, avec Mesa/Panfrost
de noble, un compositeur (cage) et ce Chromium, puis le même banc. Aucun changement de pilote noyau.
