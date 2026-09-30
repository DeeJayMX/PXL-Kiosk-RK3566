# CLAUDE.md

## Nature de ce dépôt

La recette, les scripts et le dossier de mesures pour afficher **une page web en plein
écran, avec Chromium et le décodage vidéo matériel**, sur une box **RK3566** (Mali-G52,
VOP2, MPP). La box de référence est la **TurboNode** du labo (X88 Pro 20, Armbian
bookworm, image ophub, noyau Rockchip 6.1.141).

Voir `README.md` pour la recette et `docs/README.md` pour l'index du dossier.

## Règles de rédaction — celles des autres dépôts PXL

- **Chaque fait porte sa provenance** : **mesuré** (sur la box, avec sa date), **lu**
  (doc, code, fichier de config) ou **déduit**. Une source web lue seulement en extrait
  de moteur de recherche se marque « extrait ».
- **Une divergence constatée s'AJOUTE, datée, avec son mécanisme** ; on ne réécrit pas.
  Un chiffre corrigé en silence ne prouve plus rien. Les errata ne se nettoient pas.
- **Ne jamais citer un chiffre du dossier comme la vérité de la box aujourd'hui** :
  relancer le banc (`scripts/banc/mesurer-serie.sh`).
- **RK3566 ≠ RK3568 ≠ RK3588.** Un fait lu sur une autre puce se marque comme tel. Le
  RK3588 (Mali-G610, Panthor, VDPU381) ne se transpose pas au G52.

## Règles de code

- **Jamais de binaire versionné** : ni `.ko`, ni Xorg compilé, ni `.deb`, ni clip vidéo.
  Uniquement les scripts qui les produisent. Les sources tierces se clonent sous
  `/opt/pxl-kiosk/src`.
- **Tout ce qu'un script dépose hors de `/opt/pxl-kiosk` est noté au manifeste**
  (`$ETAT/manifeste`), et tout paquet apt figure dans `commun.sh`. `restaurer.sh` doit
  pouvoir tout défaire **et le vérifier** : versions, modules, services, `summary`,
  sysctl.
- Un seul endroit pour les versions et les URL : `scripts/commun.sh`.

## 🔴 Sur la box du labo

- **La TurboNode fait tourner d'autres essais**, dont l'affichage du PGM TurboHQ. Les
  scripts 30 et 40 **coupent l'affichage**. `00-etat-initial.sh` d'abord, puis
  `restaurer.sh` à la fin, **toujours**, et vérifier que tout y est « identique ».
- Changer de pilote GPU (`rmmod panfrost` / `insmod bifrost_kbase.ko`) demande
  l'**accord explicite** d'Eliott. Le filet `kernel.panic=10` / `panic_on_oops=1` est
  posé par le script 30 et retiré par `restaurer.sh`.
- Un redémarrage ramène Panfrost : le module n'est jamais installé dans
  `/lib/modules`.

## Les pièges déjà payés — ne pas les repayer

| Symptôme | Cause | Remède |
|---|---|---|
| `mmap() failed: No such device` dans le décodeur V4L2 | libv4l2 de Debian | libv4l2 **Radxa** 1.22.1-5 (patch mmap) |
| `gbm_wrapper: Failed to export buffer to dma_buf`, processus GPU qui plante, repli logiciel | GBM de **Panfrost** sans NV12 (Mesa 22.3 **et** 25.0) | libmali |
| Xorg segfault au démarrage de glamor | Xorg de Debian + libmali | Xorg **Rockchip** (`rockchip/debian/21.1.7`) |
| `Failed to get system egl display`, repli SwiftShader | écran sans DRI2 (glamor coupé) | glamor + `DRI "2"` sur le Xorg Rockchip |
| `Failed to activate virtual core keyboard` | Xorg compilé dans `/opt` qui cherche XKB chez lui | `-xkbdir /usr/share/X11/xkb` + lien `xkbcomp` |
| module kbase : `devfreq_table` inconnu, etc. | `EXTRA_CFLAGS` passé en ligne de commande écrase ceux du Makefile | passer par `KCFLAGS` |
| module kbase : `mali_read_poll_timeout_atomic` implicite | vieille `version_compat_defs.h` des en-têtes ophub | forcer celle des sources (`-include`) |
| Mesa 25 chargée seulement pour Chromium → llvmpipe | client Mesa 25 face à un Xorg lié à Mesa 22.3 (`DRI3: Could not get DRI3 device`) | tout le système sur la même Mesa, ou libmali |
| GPU à 166 MHz sous kbase | `no supported OPPs` (DT ophub, `opp-supported-hw`) | **ouvert** |
