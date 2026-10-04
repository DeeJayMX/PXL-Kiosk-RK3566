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
| Traces du noyau (pilote Wi-Fi `SKW…`) visibles sur l'écran HDMI entre les étapes et à la fermeture du splash, malgré `loglevel=1` | `console=both` dans `armbianEnv.txt` met `console=tty0` sur la ligne de démarrage : le noyau écrit sur tty1, et tty1 revient à l'écran dès que Plymouth le lâche (mesuré 02/10 en lisant `/dev/vcs1`) | `console=serial` **et** supprimer la ligne `consoleargs=` d'armbianEnv.txt (boot.scr l'importe telle quelle : elle remettait `console=tty0`), puis vider tty1 juste avant `plymouth quit` (`fin-ecran-demarrage.sh`) |
| Reconstruire l'initramfs (`update-initramfs`/`mkinitramfs`) pour y ajouter quelque chose | l'initramfs d'ophub a été fabriqué sur LEUR machine : reconstruit sur la box, il en donne un autre (mesuré 02/10 : 1422 → 1219 fichiers, `simple-framebuffer`/`cryptroot` disparus, autres `modprobe.d`) — et `/boot` est en **ext4**, une carte qui ne démarre plus ne se répare pas depuis Windows | **coller** une seconde archive xz à l'original intact (`fichiers/initramfs/facade-initramfs.sh`) ; `lsinitramfs` ne lit que la 1ʳᵉ archive, le contrôle relit l'ajout à part. Retour : `facade-initramfs.sh --retirer` (ou `ln -sfn uInitrd-<noyau> /boot/uInitrd` depuis un Linux). Témoin : `/run/pxl-facade-initramfs` (`rc=0 uptime=9.51`) |
| Mise à jour appliquée, alimentation coupée : la box revient à la version d'AVANT | la racine est montée en **`commit=600`** (fstab Armbian, pour ménager la carte) : jusqu'à 10 min d'écritures restent en mémoire et une coupure les efface (vu le 02/10 : v1.2.6 → v1.2.5) | `sync` à la fin de toute mise à jour (`maj.mjs`) et de tout réglage de `/admin` ; le serveur d'habillage écrit son état avec `fsync` (fichier + dossier). `commit=600` est gardé : ce qui compte est gravé tout de suite |
| Sortie en **1080i50** impossible : Weston prend le 1080p50 (même fréquence), sa ligne de timings ignore l'entrelacé, et `video=HDMI-A-1:1920x1080@50i` du noyau rend aussi du p50 (mesuré 02/10, `drm.debug=0x4` : « cmdline mode … interlaced » lu, puis « 1920x1080 » posé) | Weston ne choisit pas un mode entrelacé ; le noyau 6.1 de la box non plus | `fichiers/pxl-mode.c` (compilé à l'installation) pose `1920x1080i` avant Weston, réglé en `mode=current` ; mesuré : `Display mode: 1920x1080i50`, gardé par Weston. `SORTIE_MODE=1920x1080i@50` |
| Capture writeback de Weston (`weston_capture_v1`) : « matérielle », mais coûteuse | Weston 13 alloue un tampon par image, **recopie au processeur** dans la mémoire du client, au format de la sortie (XRGB8888, que le writeback du RK3566 ne sait pas écrire), et **bloque sa boucle d'affichage** jusqu'à la fin du writeback (lu dans `drm.c`, 02/10) ; `drm_output_find_compatible_writeback()` refuse même le connecteur, faute de XRGB8888 | `patches/weston-writeback-flux.patch` + `weston-pxl.sh` : anneau NV12, connecteur attaché une fois, barrière laissée à l'encodeur. Mesuré : 24,8 img/s, 0 modeset, écran à 49 img/s avec ou sans flux — `docs/FLUX_WRITEBACK.md` |
| Flux writeback en **1080i** : image écrasée dans les 540 premières lignes, le reste vert | le writeback du RK3566 n'écrit qu'UNE trame par capture ; ses 11 registres n'ont ni pas de ligne, ni hauteur, ni parité (lu dans le pilote 6.1, 03/10) ; `dsp_field_pol` est la polarité HDMI, pas celle du writeback | v1.8.0 : Weston capture des **paires** de trames consécutives + leur n° de vblank, l'encodeur les **tisse à la RGA** (NV12 1920×1080 = NV12 3840×540 gauche/droite), ordre appris sur l'image. Mesuré : 1920×1080 net, 23,5-24 img/s — `docs/FLUX_WRITEBACK.md` |
| Flux 1080i en **PsF** à 21-23 img/s au lieu de 25, image recalée sans arrêt | trois causes empilées : recalage qui datait l'image plus TÔT (13 ms pour composer), attente de la FIN du writeback au lieu de l'application du commit, et fenêtre de composition de Weston (7 ms) trop courte pour un 1080 sur le Mali (mesuré par les écarts de trames, 03/10) | v1.9.0 : dater plus TARD, attendre le compteur de vblank, `repaint-window=15` en PsF seulement (`preview.sh`) → 24,7-25 img/s, 0 paire cassée, Chromium à 25,0 |
| 🔴 /admin entièrement inerte depuis la v1.7.0 (02/10) : onglets sans effet, rien ne se charge | `const w = E.wb` ajouté dans `rendre()`, où `w` était déjà le Wi-Fi (`wifi: w`) : **erreur de syntaxe**, donc AUCUN script de la page ne s'exécute. Aucun test ne chargeait la page (trouvé le 03/10 en rendant la page dans Chromium avec l'état réel) | v1.10.0 : renommé ; **rendre la page dans Chromium** (Playwright, `/api/etat` réel) avant de livrer une modification de `admin.html` — `node --check` sur son script ne coûte rien |
| Mode HDMI demandé absent de l'écran : Weston part en **4K60** | Weston prend le mode préféré de l'écran sans rien dire (mesuré 03/10 : 720p25 demandé, 3840x2160p60 posé) | `pxl-mode --liste` ; `preview.sh` se replie explicitement (720p50…) ; /admin signale le mode absent |
| Écran **débranché / rebranché** : plus aucun signal jusqu'à une relance à la main | le premier commit de Weston après le rebranchement est refusé (« atomic: couldn't commit new state: Invalid argument », « repaint-flush failed ») et Weston ne réessaie jamais : Video Port0 reste éteint (mesuré 04/10, TV Samsung) | v1.14.0 : `pxl-hdmi-garde.service` — écran `connected` + preview active + aucun « Video Port: ACTIVE » dans `summary` pendant 3 lectures (6 s) ⇒ relance de pxl-preview (et pxl-wb), au plus une fois / 30 s. ⚠ Le rebranchement ne se simule PAS en logiciel (`force` du debugfs et `status` du sysfs refusés ou sans effet, 04/10) : logique testée sur fichiers factices (`PXL_GARDE_STATUT/RESUME/PAS`). 04/10 12:22 : rebranchement réel (4 s débranché) → image revenue SANS que la garde ait eu à agir (Weston a réussi seul) : la garde n'a pas encore été vue en action . v1.14.1 (décision d'Eliott, option A) : la garde relance AUSSI à CHAQUE rebranchement (transition débranché → branché lue sur `status`, réveil par `udevadm monitor` drm, 3 s de stabilité) — ~10 s de noir assumés, signal toujours reposé à neuf ; couvre le « signal noir » du 1080i50 rebranché, Video Port actif, que le filet ne voit pas . v1.15.0 (Eliott : « un peu long ») : remplacé — mode FORCÉ ⇒ AUCUNE relance au rebranchement (la box n'a pas cessé d'émettre) ; nouveau mode **AUTO** dans /admin (`SORTIE_MODE=auto`, résolu par preview.sh : 1080i50 › 1080p50 › 720p50 › 1080i60 › 1080p60 › 720p60) ⇒ relance seulement si l'EDID change (autre écran). Le « signal noir » du 1080i50 ne venait PAS de la résolution (Eliott, 04/10) ; le filet Video Port reste |
| **1080i50 noir** sur la TV Samsung de la régie, 1080i60 et 720p50 OK | non trouvé : le signal émis est conforme (timings CEA 2640/1125, VIC 20 dans l'AVI, mesurés au registre dw-hdmi le 04/10) et le writeback montre la bonne image — c'est la TV qui ne l'affiche pas | la TV du labo affichait le 1080i50 (03/10). /admin propose désormais 720p 25-60, 1080p 24-60, 1080i 50/60 (v1.14.0) ; pas de 4K ni de SD (flux writeback tissé en 1920×1080) |
| Companion Satellite : « `getDevices error: /sys/bus/usb/devices/ not found` » et arrêt au démarrage | machine sans bus USB (VM, conteneur) : le module de surface énumère l'USB et l'erreur n'est pas rattrapée (mesuré 04/10, Satellite 3.4.1 x64) | sans objet sur la box ; pour un essai : `unshare -m` + tmpfs sur `/sys/bus` avec un `usb/devices` vide |
| Règles udev de Satellite introuvables (`satellite/assets/linux/50-satellite.rules`) | ce chemin n'existe que dans les SOURCES ; le paquet officiel les met à SA RACINE, hors de `app.asar` (vu 04/10) | `satellite-installer.sh` les copie vers `/opt/companion-satellite/50-satellite.rules` ; /admin y lit les fabricants reconnus |
| Logo d'allumage de la box (avant Linux) | il vient du U-Boot **Android en eMMC** (partitions `uboot`/`boot`), pas de `/boot/boot.bmp` : `bootlogo=true` d'Armbian n'ajoute qu'un paramètre `bootsplash` inopérant sur ce noyau (vu 02/10) | ne pas y toucher sans décision explicite : réécrire l'eMMC peut rendre la box indémarrable (récupération en maskrom) |

## Numéro de version

`installation/VERSION` porte la version (MAJEUR.MINEUR.CORRECTIF), affichée sur la box (/admin, écran de démarrage, console). **À relever dans le commit qui livre un changement** : correctif → +0.0.1, fonction nouvelle → +0.1.0. Un numéro qui ne bouge pas ne dit plus ce qui tourne.

## Passage sur l'eMMC interne (préparé le 04/10/2026)

- **Sauvegarde de l'Android d'origine FAITE et VÉRIFIÉE** : `/root/sauvegarde-emmc/` sur la SD de la box — image complète de
  `mmcblk2` en gzip (31 Go → 2,18 Go, relue et comparée par empreinte), `mmcblk2boot0/1`, table `sfdisk`. À copier aussi
  hors de la box : `scp -r root@<box>:/root/sauvegarde-emmc .`
- 🔴 **Ordre de démarrage relevé (lecture seule)** : le chargeur U-Boot 2017.09-armbian (SD) teste la **SD avant l'eMMC**
  (`boot_targets=nvme mmc1 mmc0`, `rkimg_bootdev` : « Boot from SDcard »). SD insérée = la SD démarre, sans rien dire.
  ⇒ pas de « double boot » automatique : la SD de secours se garde **hors de la box** ; l'insérer = démarrer dessus.
- `installation/fichiers/emmc-installer.sh` : `--verifier` (rien écrit) / `--appliquer` (efface l'eMMC). Garde-fous :
  système sur la SD, sauvegarde vérifiée (`SHA256SUMS`), chargeur à écrire identique À L'OCTET à celui de la SD, rien à
  l'antenne. Même disposition que la SD, UUID neufs, copie rsync en deux passes (la seconde serveur arrêté), pas de
  redémarrage. Ensuite : éteindre, RETIRER la SD, rallumer.
- ⚠️ **Non prouvé** : que ce chargeur armbian démarre la box EN PREMIER ÉTAGE depuis l'eMMC (aujourd'hui l'eMMC porte le
  chargeur Android, et on ne sait pas lequel des deux a tourné — pas de console série). S'il échoue, la box n'amorce plus
  rien seule : retour par le mode **maskrom** (câble USB A-A, bouton reset) et RKDevTool / `rkdeveloptool`, image de la
  sauvegarde. Vérifier le câble AVANT `--appliquer`.
- ⭐ **Chaîne de démarrage LUE dans les binaires (04/10, même soir)** — elle corrige le point « non prouvé » ci-dessus :
  le premier étage de l'eMMC (idbloader Android : SPL `2017.09-g606f72bd97a`, 30/05/2024) a
  `u-boot,spl-boot-order = dwmmc@fe2b0000 (SD), sdhci@fe310000 (eMMC), …` : la BootROM le charge depuis l'eMMC et il va
  chercher le second étage **sur la SD d'abord** (FIT au secteur 16384, sans partition « uboot » — la SD n'en a pas, donc
  le repli brut est déjà prouvé). Le premier étage armbian de la SD est celui d'une **Radxa ROCK3 C** (DDR V1.10) et n'a
  probablement jamais démarré cette box. ⇒ `emmc-installer.sh` **garde le premier étage de l'eMMC** (secteurs 64-16383,
  empreinte contrôlée avant / après) et n'écrit que `u-boot.itb` au secteur 16384. Chaîne après installation, SD retirée :
  même premier étage → même U-Boot (lu sur l'eMMC) → `boot.scr` de l'eMMC. **Filet** : SD insérée, ce premier étage charge
  la SD — la carte de secours démarre sans câble ni maskrom. Piège évité dans le script : `strings | grep -q` sous
  `pipefail` rend un faux échec (SIGPIPE) — `grep -c >/dev/null`.
- ✅✅ **FAIT le 04/10 à 20 h 47 — la box tourne sur l'eMMC.** `emmc-installer.sh --appliquer` : 7 min (copie à chaud 5 min,
  passe finale serveur arrêté 17 s), premier étage relu identique à l'Android d'origine. Éteinte, SD retirée, rallumée :
  `/` = `mmcblk2p2` (UUID 510da7c7…), `/boot` = `mmcblk2p1`, tous les services actifs, sortie 1080i50, palmarès et
  préparations retrouvés, polices chargées ; 22 Go libres. Retour sur le réseau ~1 min 30 après l'allumage.
  La SD (inchangée) est la carte de SECOURS : insérée, elle démarre en priorité. Sauvegarde de l'Android : sur la SD
  (`/root/sauvegarde-emmc`) et sur le SSD Samsung T7 « ATEM Rec » d'Eliott (`PXLnode-sauvegarde-eMMC-Android-2026-10-04`).
  ⚠️ La SD de secours se périme : avant la course, la remettre à niveau (l'insérer, démarrer dessus, `maj.mjs appliquer`).
- 🔴 **Écran NOIR en 1080i50 au démarrage (04/10 au soir, sur l'eMMC)** : signal présent, mais le premier commit atomique
  de Weston est refusé (`couldn't commit new state: Invalid argument`, `repaint-flush failed` ; drm.debug=0x1e : le noyau
  abandonne pendant le réglage des propriétés du CONNECTEUR) et Weston ne réessaie jamais. **Course, pas mode refusé** :
  même séquence (fbdev 4K30 → pxl-mode 1080i50 → Weston) tantôt OK tantôt KO. ⚠️ Piège de diagnostic : pendant 30 s, le
  tampon noir de pxl-mode occupe un plan (`Smart0-win0: ACTIVE`) — un plan actif ne prouve pas l'image de Weston.
  Correctifs (v1.16.2) : `preview.sh` attend 1 s après pxl-mode, puis lit le journal de Weston 3 s après son démarrage ;
  refus ⇒ sortie, systemd relance (≈ 10 s). Mesuré : 6 relances, 6 images, dont 1 rattrapée seule. Et la garde HDMI
  (v1.16.1) relance aussi quand le Video Port est actif sans AUCUN plan actif.

