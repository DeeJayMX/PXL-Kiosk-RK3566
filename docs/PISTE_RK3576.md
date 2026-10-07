# Piste v2 : RK3576 (ouverte le 07/10/2026, à instruire APRÈS l'Urban Trail)

Demande d'Eliott, 07/10 : *« RK3576 là c'est intéressant »*, puis *« on veut le décodage hardware dans Chrome, ça
viendra »*. Rien n'est acheté ni installé. **Rien de ce fichier n'est mesuré** : tout est **lu** (sources web lues en
**extrait** — proxy de la session — ou dépôt ophub lu directement) ou **déduit**, et marqué comme tel.

## Pourquoi cette puce

| | RK3566 (box actuelle, X88 Pro 20) | RK3576 | Provenance |
|---|---|---|---|
| CPU | 4 × A55 1,8 GHz | 4 × A72 2,2-2,3 GHz + 4 × A53 | lu (extrait : CNX, fiche brève V1.2) |
| GPU | Mali-G52 2EE | Mali-G52 **MC3**, GLES 3.2, Vulkan | lu (extrait) |
| Encodeur | 1080p (mesuré ici) | H.264 / H.265 **4K60** | lu (extrait) |
| Décodeur | 4K60 H.264/HEVC/VP9 | 4K120, AV1 compris | lu (extrait) |
| HDMI | 2.0 | **2.1** | lu (extrait) |
| RGA | RGA2 | **RGA2-Pro** (autre lignée : 1 cœur, 8192, 1/16~16) | lu — voir le bloc RK3576 de `PXL-Switcher/console/src/spec.mjs` |

🔴 **RK3576 ≠ RK3566 ≠ RK3588.** Même famille de GPU (G52) ne veut pas dire même pilote ni même `libmali` :
**à mesurer**, comme tout le reste.

## Où la trouver, et ce que vaut le support Linux

1. **Box TV H96 Max M9** (~75-85 $, prix 2024, lu en extrait) — support **communautaire d'une seule personne** sur le
   forum Armbian : images Armbian 24.8 / noyau vendeur 6.1.75 sur Google Drive (2024) ; Ethernet et Wi-Fi annoncés,
   Bluetooth par contournement, **pas de démarrage SD ni USB**, bouton reset mort après flashage, retour par pontage de
   contacts ; flashage `rkdeveloptool` + MiniLoaderAll RK3576 à l'offset 0 ; Wi-Fi / Ethernet **changent d'un lot à
   l'autre** (lu en extrait). ⇒ **pas une base de produit.**
2. **ophub** (le projet d'où vient l'image de notre box : entrée `r308 X88Pro20`, `rk35xx/6.1.y`) — **lu directement**
   dans `model_database.conf` le 07/10 : 4 **cartes** RK3576 (`r801` NanoPi-M5, `r802` LCKFB-Taishan-Pi-3M, `r803`
   reComputer-RK3576-DevKit, `r804` LubanCat-3), toutes en **`stable/6.18.y`** (noyau **mainline**), **aucune box TV**.
   ⇒ matériel stable, démarrage SD, même projet que la box actuelle.

## 🔴 Le point qui décide : le décodage matériel DANS Chromium

Sur la box actuelle, le décodage matériel de Chromium passe par la pile **VENDEUR** (mesuré, `README.md`) :
`V4L2VideoDecoder → libv4l2 (Radxa) → libv4l-rkmpp → MPP → rkvdec`, avec un Chromium **patché Rockchip** (Radxa 126,
ou PPA amazingfate 132). Cette pile suppose le **noyau vendeur 6.1** et MPP.

- **Noyau mainline (ophub 6.18)** : les décodeurs VDPU383 (RK3576) et VDPU381 (RK3588) ont été **fusionnés en amont**
  (Collabora, 25/02/2026 — lu en extrait), H.264 et HEVC, en **V4L2 *stateless*** avec deux contrôles HEVC nouveaux ;
  côté utilisateur : GStreamer 1.28, FFmpeg préliminaire. **Version exacte du noyau non confirmée.**
  🎯 *Déduit, à vérifier* : le Chromium de bureau Linux n'embarque pas son décodeur V4L2 *stateless* (code ChromeOS),
  et ne connaît sans doute pas encore ces contrôles HEVC ⇒ **pas de décodage matériel dans Chromium par cette voie à
  court terme**. Et Chromium n'a **aucun décodeur HEVC logiciel** : un canal HEVC y serait illisible.
- **Noyau vendeur 6.1 + MPP** : la voie de la box actuelle, transposable **si** la carte a une image à noyau vendeur et
  **si** le Chromium patché MPP connaît le RK3576 (à vérifier dans le PPA amazingfate).

⇒ **Pour le décodage matériel dans Chrome, le choix n'est pas ophub mainline par défaut** : il faut d'abord savoir quelle
carte RK3576 a une image à **noyau vendeur** fiable, puis le prouver sur banc.

## Ce qu'il faudra mesurer (dans cet ordre)

1. Démarrage, affichage, `libmali` ou Panfrost, GPU à pleine fréquence (le piège OPP du RK3566 : vérifier).
2. Chromium : page d'habillage Urban Trail (`test_habillage_urban_trail.md`), images/s et charge.
3. **Décodage matériel dans Chromium** : H.264 et HEVC 1080p60, 2160p30 (`<video>` **et** WebCodecs), comme le
   tableau du `README.md`.
4. Viewer TurboHQ web (`turbohq_viewer_ios.html` en HTTPS) : chemin basse latence, latence, images perdues.
5. Writeback + encodeur pour le flux TurboHQ (`FLUX_WRITEBACK.md`), 1080i50.

Sources (extraits) : [CNX — feuille de route RK3576](https://www.cnx-software.com/2023/11/02/rockchip-roadmap-reveals-rk3576-and-rk3506-iot-processors-linux-6-1-sdk/) ·
[fiche brève RK3576 V1.2](https://armdesigner.com/download/RK3576_Brief_Datasheet_V1.2-20240311.pdf) ·
[forum Armbian, H96 Max M9](https://forum.armbian.com/topic/40483-efforts-to-develop-firmware-for-h96-max-rk3576-tv-box-8g128g) ·
[Collabora — décodeurs RK3588/RK3576 en amont](https://collabora.com/news-and-blog/news-and-events/rk3588-and-rk3576-video-decoders-support-merged-in-the-upstream-linux-kernel.html) ·
[ophub, base des modèles](https://github.com/ophub/amlogic-s9xxx-armbian/blob/main/build-armbian/armbian-files/common-files/etc/model_database.conf) (lu directement).

## ⚠️ Ajout du 07/10 (même jour) — la déduction sur Chromium et le V4L2 sans état est REMISE EN QUESTION

Un rapport isolé (forum Armbian, lu en extrait) dit que **Chromium 150 de série décode en V4L2 sans état** sur RK3588
mainline (noyau 7.1). La phrase plus haut (*« pas de décodage matériel dans Chromium par cette voie à court terme »*) reste
écrite : c'est le raisonnement qui serait refait. Elle n'est plus qu'une **hypothèse à mesurer**. Détail et sources :
`COMPARATIF_PLATEFORMES.md`.

## ⭐ Ajout du 07/10 (nuit) — la carte : **Radxa ROCK 4D**, et ce que Radxa livre VRAIMENT pour le RK3576

Demande d'Eliott : *« plonge Rock 4D »*. Pages Radxa (docs, dl) **bloquées** par le proxy ; ce qui suit vient des dépôts
**GitHub de Radxa, lus directement** (clonés le 07/10), plus quelques extraits web marqués comme tels.

**La carte (extraits : CNX, fiche brève, LinuxLinks, AliExpress)** — RK3576 (4 × A72 2,2 GHz + 4 × A53 2,0 GHz), Mali-G52
MC3, NPU 6 TOPS ; LPDDR5 2 / 4 / 8 / 16 Go ; **1 × HDMI** (2.1 selon la fiche brève, 2.0 4Kp60 selon CNX — **à trancher**)
+ MIPI DSI ; **Ethernet Gigabit** (PoE en option) ; Wi-Fi 6 / BT 5.4 ; microSD + connecteur **eMMC** *ou* **UFS** (un seul
des deux) ; format Raspberry Pi. Décodeur H.265/VP9/AV1 8Kp30 ou 4Kp120, H.264 4Kp60 ; **encodeur H.264/H.265 4Kp60**.
Prix 2025 : 8 Go ≈ 58 $, 16 Go ≈ 100 $ (AliExpress, extrait). Support **mainline** depuis Linux 6.15 (extrait).

**L'image officielle (lu : `radxa-build/rock-4d`)** — Radxa ne fournit plus **que** l'image « Debian Desktop » ; versions
publiées `rsdk-r1` (stable), `rsdk-t1` / `t2` (tests). Base Debian **bookworm**.

**Le dépôt de paquets (lu : `radxa-repo/rk3576-bookworm`, dernier commit 19/06/2026)** :
- ✅ **Noyau VENDEUR** : `linux-rk2410` **6.1.84** (+ variante `-nocsf`) — la même famille de noyau que notre box.
- ✅ **Pile Rockchip** (MPP, RGA, libmali, GStreamer…) via `rockchip-prebuilt` `0.4.2-linux-6.1-stan-rkr4` — qui
  **reconditionne les paquets officiels du SDK Debian de Rockchip** (`gitlab.com/rk3588_linux/linux/debian`, sous-module
  `linux-6.1-stan-rkr4`), publiés pour `rk3576-bookworm` (lu : `pkg.conf.linux-6.1-stan-rkr4`).
- 🔴 **PAS de Chromium à décodage matériel** : le `chromium-x11_126.0.6478.126` du SDK Rockchip est **exclu de toutes
  les publications** (`"Releases": []`) dans les trois configurations (rkr4, rkr5.1, 6.12). Seul `rockchip-chromium-x11-utils`
  est publié. Le dépôt **RK3588** porte, lui, `chromium-x11 0.4.1-linux-6.1-stan-rkr1-5` — c'est celui qu'utilise notre
  box (`README.md`).
- ⭐ Une suite **trixie + noyau Rockchip 6.12** (`linux-6.12-stan-rkr1`) est préparée pour `rk3576-trixie`, `rk3566-trixie`
  et `rk3588-trixie` (lu dans `pkg.conf.linux-6.12-stan-rkr1`) — dépôt `rk3576-trixie` non lisible sans authentification.

**Ce que ça veut dire pour nous :**
- Le **socle est bon** : noyau vendeur 6.1 + MPP/RGA/libmali officiels, la même recette que la box.
- 🎯 **Le seul maillon manquant est Chromium.** *Déduit, à mesurer* : le Chromium Radxa du dépôt RK3588 (ou celui du PPA
  amazingfate) parle à MPP par `libv4l-rkmpp`, qui ne dépend pas de la puce ; avec la `librockchip_mpp` du SDK RK3576
  installée, il **devrait** décoder sur le RK3576. C'est la toute première chose à vérifier en recevant la carte.
- Choix d'achat : **8 Go + module eMMC** (l'UFS est plus rapide mais exclusif ; l'eMMC est ce qu'on maîtrise).
- À trancher en main : **HDMI 2.0 ou 2.1**, sortie **1080i50** via `pxl-mode`, dissipation (radiateur fourni ?), alimentation
  (USB-C PD).
