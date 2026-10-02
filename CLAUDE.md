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
  `/lib/modules`. 🔴 **C'est même le SEUL retour sûr** : un `rmmod bifrost_kbase` fait un
  Oops du noyau au modeset suivant (mesuré le 30/09/2026).

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
| GPU à 166 MHz sous kbase, `no supported OPPs` | DT ophub : `rockchip,supported-hw` sans `opp-supported-hw` sur les entrées ; horloge nommée `gpu` et non `clk_mali` | `patches/kbase-opp-ophub.patch` (appliqué par le script 10) |
| 🔴 Oops `rockchip_system_status_notifier`, présentateur bloqué en D dans `drm_fb_release` | `rmmod bifrost_kbase` avec OPP actives : pointeur laissé dans le moniteur système Rockchip | **ne jamais `rmmod` kbase** : redémarrer (`restaurer.sh` le fait) |
| 60p à 49-53 img/s alors que le décodeur tient 60 | `simple_ondemand` : GPU entre 300 et 400 MHz | gouverneur `performance` : 58 img/s |
| Toute animation à 30 img/s (même un carré CSS), GPU presque à vide | `FlipFB "always"` dans `conf/xorg-rk.conf` : une image sur deux perdue (mesuré 01/10) | `FlipFB "none"` → 60 img/s, mais Xorg recopie au lieu de basculer : **déchirure à vérifier à l'œil** (`mire-dechirure.mjs`) |
| Fenêtre Chromium en 945×1060 +10+10 malgré `--kiosk` | pas de gestionnaire de fenêtres : `--kiosk` / `--start-fullscreen` ne sont que des souhaits (mesuré 01/10) | `--window-position=0,0 --window-size=…` ; ⚠️ `1920,1080` donne 1919×1079 ; taille **exacte** ⇒ bascule DRI2 ⇒ 30 img/s |
| Bascule DRI2 obtenue, mais 30 img/s | libmali DRI2 à deux tampons : un retour d'écran de plus par échange (dri2.c l. 961) | sous X11 : 60 par recopie (déchirure à juger) **ou** 30 par bascule ; les deux = Wayland/KMS |
| Après le redémarrage de `restaurer.sh` : flux PGM reçu à 60 img/s mais « jetée(s) … sans tampon », Esmart0 éteint | présentateur turbohq qui démarre avant que l'affichage soit prêt (vu le 30/09 et le 01/10) | `systemctl restart turbohq.service`, puis relancer `restaurer.sh`. ⚠️ `inet_diag`/`tcp_diag` absents du diff des modules : chargés à la demande, sans conséquence |
| 🔴 Après démontage d'un chroot : `/sys/fs/cgroup`, `/dev/pts`, `/dev/shm`, debugfs **disparus de l'hôte**, systemd en `219/CGROUP` | `mount --rbind` de `/sys` et `/dev` + `umount -l` : les montages sont *partagés*, le démontage se **propage à l'hôte** (vécu le 01/10) | monter en `--rbind` **puis** `mount --make-rslave` sur chaque point, avant tout démontage ; une fois le mal fait, seul un redémarrage répare |
| 🔴 La session ssh meurt au milieu d'une commande de nettoyage | `pkill -f <motif>` tue aussi le shell dont la ligne de commande contient le motif (vécu le 01/10) | `systemctl stop <unité>` ; jamais `pkill -f` |
| `parted resizepart` : « Unable to satisfy all constraints » sur une image agrandie | GPT : l'en-tête de secours est resté à l'ancienne fin du fichier (vu le 01/10) | `sfdisk --relocate gpt-bak-std` puis `echo ", +" \| sfdisk -N 2` (dans `fabriquer-image.sh`) |
| Image fabriquée : « recovery required », `loop0` impossible à détacher | le montage de l'image s'était **propagé** dans les espaces de montage privés des services de l'hôte (udevd, resolved, logind, NetworkManager, chrony, turbohq-dns), qui le gardaient ouvert en écriture (vu le 01/10) | fabriquer dans un espace privé : `unshare --mount --propagation private` (fait par `fabriquer-image.sh`). Les copies déjà prises se libèrent au redémarrage de l'hôte |
| Image ophub en `Asia/Shanghai` | fuseau par défaut d'ophub | `FUSEAU=Europe/Paris` (`installer.sh`) : le serveur d'habillage affiche l'heure locale |
| Box neuve figée sur « watchdog.service » à l'écran, preview relancée en boucle | `seatd` lancé par `/usr/bin/seatd` : sur noble il est en `/usr/sbin` ⇒ `203/EXEC` en boucle, Weston sans siège (vu au 1er démarrage de la box, 02/10/2026). L'écran ne montre que le dernier message de démarrage | chemin lu par `command -v seatd` (`installer.sh`) |
| Weston : `failed to create input devices` puis `fatal: failed to create compositor backend` | aucune entrée : les télécommandes IR/CEC sont retirées à Weston (`LIBINPUT_IGNORE_DEVICE`) et aucun clavier n'est branché (02/10) | `require-input=false` dans `[core]` de `weston.ini` |
| Système « degraded » : `wd_keepalive.service` en échec | deux maîtres du chien de garde : systemd (`RuntimeWatchdogSec`) et le démon `watchdog` de l'image Armbian ; l'arrêt du second lance `wd_keepalive`, qui trouve le périphérique tenu (02/10) | `systemctl mask watchdog wd_keepalive` : systemd seul |
| `journalctl` : « No journal files were found » au premier démarrage | `armbian-fix` (ophub) régénère le machine-id APRÈS le départ de journald, qui écrit sous l'ancien (02/10) ; lisible par `journalctl -D /var/log/journal/<ancien id>` | journald relancé par un `ExecStartPost` posé sur `armbian-firstrun` ; un redémarrage suffit aussi |
| Carte SD écrite en continu : 856 Kio / 120 s (≈ 600 Mo/jour) | journal **persistant** (réglé par nous) écrit sur la carte — `armbian-ramlog` ne remonte `/var/log` en RAM qu'au 1er démarrage —, sa copie par rsyslog, le tampon de journaux de `tailscaled` (`/var/lib/tailscale/tailscaled.log*.txt`) et vnstat (mesuré 02/10) | `Storage=volatile`, rsyslog et vnstat coupés, `TS_LOGS_DIR=/run/tailscale` → **0 Kio en 150 s**. Le journal ne survit plus à un redémarrage : c'est voulu (décision d'Eliott) |
| Page d'admin : le profil Ethernet « trouvé » était `eth0` ou « Wired connection 1 », et le modifier ne survivait pas | ces deux profils sont **temporaires** (`/run/…`) : le DHCP automatique d'Ubuntu, et le profil né quand la veille de secours pose son adresse hors de NetworkManager. Et un profil créé par `nmcli` sur Ubuntu est rangé **via netplan** (`/etc/netplan/90-NM-<uuid>.yaml`), NM n'en montrant que la copie `/run/…/netplan-NM-…` (mesuré 02/10) | `admin.mjs` crée son profil `pxl-ethernet` (priorité 100) au premier réglage, le reconnaît par `/etc/` **ou** `netplan-`, et le **supprime** si on annule ce premier réglage |
| Écran de démarrage Plymouth en mode TEXTE (« details forced » / « renderers are being explicitly skipped ») | la console série `ttyS2` de la ligne de démarrage force le thème texte ; et sans `splash`/`plymouth.graphical` sur la ligne de démarrage, plymouthd n'ouvre aucun rendu graphique (mesuré 02/10) | `--ignore-serial-consoles` sur plymouthd **et** `plymouth.graphical` dans `extraargs` — surtout **pas** `splash`, qui réveille aussi le Plymouth de l'initramfs (module texte seul, l'initramfs n'est pas reconstruit exprès) |
| Logo d'allumage de la box (avant Linux) | il vient du U-Boot **Android en eMMC** (partitions `uboot`/`boot`), pas de `/boot/boot.bmp` : `bootlogo=true` d'Armbian n'ajoute qu'un paramètre `bootsplash` inopérant sur ce noyau (vu 02/10) | ne pas y toucher sans décision explicite : réécrire l'eMMC peut rendre la box indémarrable (récupération en maskrom) |
