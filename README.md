# PXL-Kiosk-RK3566

**Une page web en plein écran sur la sortie HDMI d'une box RK3566, avec Chromium et le
décodage vidéo matériel.**

Box de référence : la **TurboNode** du labo PXL (HS86 Pro20 / X88 Pro 20 : RK3566, 4×A55,
Mali-G52, 4 Go), sous Armbian bookworm (image ophub, noyau Rockchip `6.1.141-rk35xx-ophub`).

> ✅ **30/09/2026 — le décodage matériel marche dans Chromium sur RK3566.** MPP décode en
> H.264 comme en HEVC, et le HEVC, **illisible** jusque-là, passe à 57 img/s en 1080p60.
> Le soir même, le GPU est **débloqué** (200 à 800 MHz sous kbase, correctif
> `patches/kbase-opp-ophub.patch`) : **58 img/s en H.264 1080p60** et **29,3 en HEVC 4K30**,
> GPU fixé à 800 MHz.

---

## 1. Pourquoi ce dépôt existe

La voie « normale » ne décode rien en matériel sur cette puce, et c'est **mesuré** :

| Pile | Rendu | Décodage vidéo | H.264 1080p30 | H.264 1080p60 | HEVC |
|---|---|---|---|---|---|
| Chromium **Debian** + Panfrost | Mali (Panfrost) | ❌ logiciel : pas de `/dev/video*` sur le noyau Rockchip, que MPP | — | — | ❌ |
| Chromium **Radxa 126** (patché Rockchip) + Panfrost, Mesa 22.3 **ou** 25.0 | Mali (Panfrost) | ❌ MPP décode, mais **Panfrost ne sait pas exporter du NV12 par GBM** : le processus GPU plante, puis repli logiciel | 30 img/s, **246 % CPU**, 82 °C | 39 img/s, CPU saturé | ❌ illisible |
| **Cette recette** : kbase + libmali + Xorg Rockchip + Chromium Radxa 126 (GPU bloqué à 166 MHz) | Mali (libmali, GLES 3.2) | ✅ **MPP, bout à bout** | **30 img/s, 133 % CPU**, 71 °C | 51 img/s (60 décodées) | ✅ **57 img/s** en 1080p60 |
| **… + correctif OPP + GPU à 800 MHz** (gouverneur `performance`) | idem | ✅ | 30 img/s | **58,1 img/s** | ✅ 55 img/s en 1080p60 · **29,3** en 4K30 |

Le détail de chaque essai, avec les journaux et les impasses, est dans
[`docs/recherche/test_chromium_radxa_126.md`](docs/recherche/test_chromium_radxa_126.md).

## 2. La pile, et pourquoi chaque pièce est là

```
 page web ─► Chromium 126 Radxa (patché Rockchip)
               │ vidéo : V4L2VideoDecoder ─► libv4l2 (Radxa, patch mmap) ─► libv4l-rkmpp ─► MPP ─► rkvdec
               │ rendu : ANGLE ─► libmali (EGL/GLES 3.2 + GBM qui sait le NV12)
               ▼
           Xorg PATCHÉ ROCKCHIP (glamor sur libmali + DRI2)
               ▼
           noyau Rockchip 6.1 : pilote Mali kbase (compilé hors arbre) + rockchip-drm (VOP2) ─► HDMI
```

| Pièce | Source | Pourquoi elle ne se remplace pas |
|---|---|---|
| Pilote noyau **kbase** g29p1 | `unifreq/linux-6.1.y-rockchip`, compilé hors arbre | libmali ne parle qu'à kbase, et le noyau ophub n'a pas `CONFIG_MALI_BIFROST` |
| **libmali** `bifrost-g52-g13p0-x11-gbm` | dépôt Radxa | son GBM exporte le NV12, ce que Panfrost ne fait pas (crbug 372630272) |
| **Xorg Rockchip** 21.1.7 | `JeffyCN/xorg-xserver`, branche `rockchip/debian/21.1.7` | libmali X11 exige DRI2, donc glamor, et **glamor sur libmali segfaulte avec le Xorg de Debian** |
| **Chromium 126** Radxa | dépôt Radxa `rk3588-bookworm` | seul Chromium empaqueté avec les patchs V4L2/rkmpp ; celui de Debian ne cherche que `/dev/video*` |
| **libv4l-rkmpp** 1.7.0 | dépôt Radxa | présente MPP comme un décodeur V4L2 |
| **libv4l2** 1.22.1-5 **de Radxa** | dépôt Radxa | porte un patch `mmap` ; avec celle de Debian : `mmap() failed: No such device` |

## 3. La recette

> ⚠️ **Tout se lance en root sur la box.** Les scripts **coupent l'affichage** (ils
> arrêtent les services turbohq) et **changent de pilote GPU**. Chaque étape est
> réversible, et `restaurer.sh` vérifie le retour à l'état initial.
>
> ✅ **Rejoués tels quels sur la box le 30/09/2026** : 00 → 40, puis le banc. Durées :
> 10 → 5 min, 20 → 11 min 30, 25 → 53 s.
>
> 🔴 **Ne jamais décharger kbase à chaud** (`rmmod bifrost_kbase`) : c'est un Oops du
> noyau au modeset suivant (mesuré, détail dans `restaurer.sh`). Pour revenir à
> Panfrost, **redémarrer**. `restaurer.sh` le fait, puis se relance pour vérifier.

```bash
git clone https://github.com/DeeJayMX/PXL-Kiosk-RK3566 && cd PXL-Kiosk-RK3566
sudo scripts/00-etat-initial.sh        # photo de l'état : paquets, modules, services, affichage
sudo scripts/10-compiler-kbase.sh      # ≈ 4 min — pilote Mali kbase pour le noyau en cours
sudo scripts/20-compiler-xorg-rk.sh    # ≈ 10 min — Xorg Rockchip dans /opt/pxl-kiosk/xorg
sudo scripts/25-installer-pile.sh      # libmali, Chromium, libv4l-rkmpp, libv4l2 (décompressés)
sudo scripts/30-basculer-kbase.sh      # coupe l'affichage, Panfrost → kbase
sudo scripts/40-lancer-kiosque.sh https://ma.page/ 1920x1080
# … et pour revenir en arrière :
sudo scripts/restaurer.sh              # purge, puis REDÉMARRE si kbase est chargé
sudo scripts/restaurer.sh              # après le redémarrage : vérifie le retour à l'identique
```

**Vérifier que c'est bien accéléré**, et non un repli silencieux :

```bash
node scripts/banc/gl.mjs                        # attendu : ANGLE (ARM, Mali-G52, OpenGL ES 3.2)
grep -c rkvdec /proc/mpp_service/sessions-summary   # pendant une lecture : ≥ 1 (0 = décodage logiciel)
```

⚠️ `/dev/video-dec0` vit en tmpfs, et le module kbase n'est pas installé : **après un
redémarrage, relancer `25-installer-pile.sh` puis `30-basculer-kbase.sh`.** Un
redémarrage est donc aussi un retour garanti à Panfrost.

## 4. Le banc de mesure

`scripts/banc/`, sans aucune dépendance :

- `fabriquer-clips.sh` : sur un PC avec ffmpeg, fabrique 4 clips (H.264 1080p30 et
  1080p60, HEVC 1080p60 et 2160p30) avec compteur d'images incrusté ;
- `mesure.mjs` : pilote le Chromium du kiosque par DevTools et mesure images
  présentées, décodées, perdues et avance réelle ;
- `mesurer-serie.sh` : les 4 clips, plus CPU, température et **sessions MPP**.

Mesures du 30/09/2026 (sortie HDMI 1080p60). Premier passage, **GPU à 166 MHz** :

| Clip | Présentées/s | Décodées/s | CPU (sur 400 %) | Temp. |
|---|---|---|---|---|
| H.264 1080p30 | **30,1** (0 perdue) | 30,0 | 133 % | 71 °C |
| H.264 1080p60 | 50,7 | **60,0** | 167 % | 74 °C |
| HEVC 1080p60 | 57,0 | **59,9** | 174 % | 72 °C |
| HEVC 2160p30 | 23,0 | **30,0** | 137 % | 72 °C |

Rejeu du dépôt, **correctif OPP actif** :

| Clip | `simple_ondemand` (200-800 MHz) | `performance` (800 MHz fixe) |
|---|---|---|
| H.264 1080p30 | 29,9 img/s, 148 % CPU, 78 °C | — |
| H.264 1080p60 | 49,3 | **58,1** |
| HEVC 1080p60 | 53,3 | **55,3** |
| HEVC 2160p30 | **29,3** (au lieu de 23,0) | — |

⇒ Le gouverneur par défaut monte trop tard (sondage toutes les 50 ms) : pendant les
60p, le GPU passe l'essentiel du temps entre 300 et 400 MHz. **Pour un kiosque vidéo :
gouverneur `performance`** (ou `min_freq` relevé) sur `/sys/class/devfreq/fde60000.gpu`.
La température monte à 78-81 °C, près du bridage à 85 °C : à surveiller dans le boîtier.

## 5. Ce qui reste

1. ✅ **GPU débloqué** (30/09) par `patches/kbase-opp-ophub.patch`. Il y avait deux
   causes :
   - la table du DT ophub déclare `rockchip,supported-hw` sans qu'aucune entrée ne
     porte `opp-supported-hw` : le noyau 6.1 les rejette alors toutes ;
   - l'horloge s'y nomme `gpu`, là où le pilote demande `clk_mali` (nom du DT
     Android/Rockchip).

   Le correctif retire la propriété de la **copie en mémoire** du DT et prend
   l'horloge `gpu`. Le `.dtb` sur disque n'est pas touché. Référence Android (même
   box) : table 200-700 MHz, chaque entrée portant `opp-supported-hw = <0xfb 0xffff>`.
   Reste à faire : **garder le 60p à 60** (gouverneur, et le dernier écart côté X11).
2. **libmali g29p1**, exactement appariée au kbase : elle existe dans les paquets du
   SDK Rockchip (miroir GitLab `rk3588_linux`). À essayer à la place de la g13p0.
3. **X11 n'offre aucun overlay vidéo** : la vidéo reste composée par le GPU. Pour une
   vidéo 60p sans perte, l'architecture déjà mesurée à 60/60 par le labo met la vidéo
   sur son propre plan (Esmart0) avec la page par-dessus. Voir
   [`docs/RAPPORT_RECHERCHE.md`](docs/RAPPORT_RECHERCHE.md).
4. **Chromium récent** (148 à 152) : les patchs Rockchip existent dans `meta-rockchip`,
   mais il faut les compiler. Remis à plus tard.
5. **Sortie 4K** : rendre en 1080p et laisser la TV (ou le VOP2) agrandir. Même choix
   que le constructeur sous Android (`persist.vendor.framebuffer.main=1920x1080@60`).

## 6. Documents

| | |
|---|---|
| [`docs/RAPPORT_RECHERCHE.md`](docs/RAPPORT_RECHERCHE.md) | la synthèse : chemin recommandé, 16 contradictions ouvertes, 17 mesures à faire |
| [`docs/recherche/`](docs/recherche/) | les notes de recherche (web + labo), chaque fait tagué mesuré / lu / déduit |
| [`docs/README.md`](docs/README.md) | l'index des notes, et d'où elles viennent |

Origine : ce travail a commencé dans `DeeJayMX/PXL-TurboHQ` (`TurboNode/`), où les notes
d'origine restent en place.
