// pxl-mode — pose un mode HDMI que Weston ne sait pas choisir lui-même (le 1080i50 : Weston prend toujours le 1080p50,
// même fréquence, et sa ligne de timings ignore l'entrelacé ; le paramètre video= du noyau aussi — mesuré le 02/10/2026).
//
//   pxl-mode 1920x1080i@50 [HDMI-A-1]
//   pxl-mode --liste [HDMI-A-1]        les modes que l'écran déclare, un par ligne (« 1280x720@50 », « 1920x1080i@50 »)
//   pxl-mode --couleur FORMAT PROF [HDMI-A-1]   format du LIEN HDMI : rgb | ycbcr444 | ycbcr422 | ycbcr420 | auto,
//                                      profondeur 8 | 10 | auto. Ne pose AUCUN mode : vaut pour le prochain modeset.
//
// ⚠ --couleur (04/10/2026) : propriétés Rockchip « color_format » / « color_depth » du connecteur. Weston ne les connaît
// pas et ne les touche pas ; le pilote les range dans SA structure (hdmi->hdmi_output / colordepth, lu dans
// dw_hdmi-rockchip.c, rockchip-linux develop-6.1) et les relit à CHAQUE modeset — d'où l'appel AVANT pxl-mode/Weston.
// Le pilote ne fait qu'ESSAYER : un format absent de l'EDID de l'écran retombe en RGB, un 10 bits sans « deep color »
// déclaré retombe en 8, sans erreur. La vérité est « bus_format » dans /sys/kernel/debug/dri/0/summary.
// « auto » = ycbcr_high_subsampling du pilote : 4:4:4 si l'écran le déclare, sinon 4:2:2, sinon RGB — il dépend donc de
// l'écran ET (en 10 bits) du format précédent du lien : non déterministe, à ne pas prendre pour une régie.
//
// ⚠ La liste sert à NE PAS demander un mode absent : Weston prend alors le mode PRÉFÉRÉ de l'écran sans rien dire —
// 3840x2160p60 sur la TV du labo (mesuré le 03/10/2026, en demandant un 720p25 qu'elle ne déclare pas).
//
// Lancé par preview.sh AVANT Weston, qui est alors réglé sur « mode=current » et reprend ce mode tel quel. Déroulé :
// maître DRM (premier à ouvrir la carte) → mode posé avec un tampon noir → on rend la main (drmDropMaster) MAIS on garde le
// tampon ouvert 30 s : fermer tout de suite retirerait le tampon, et le noyau éteindrait l'écran avant que Weston le lise.
// Code de sortie : 0 posé, 2 mode absent de l'écran, 1 autre échec — dans tous les cas preview.sh continue.
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static const char *nom_type(uint32_t t) {
	switch (t) { case DRM_MODE_CONNECTOR_HDMIA: return "HDMI-A"; case DRM_MODE_CONNECTOR_HDMIB: return "HDMI-B";
	default: return "?"; }
}

static int lister(const char *voulu) {
	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);   // lecture seule des modes : pas besoin d'être maître
	if (fd < 0) return 1;
	drmModeRes *res = drmModeGetResources(fd);
	if (!res) return 1;
	for (int k = 0; k < res->count_connectors; k++) {
		drmModeConnector *x = drmModeGetConnector(fd, res->connectors[k]);
		char n[32]; snprintf(n, sizeof n, "%s-%u", nom_type(x->connector_type), x->connector_type_id);
		if (x->connection == DRM_MODE_CONNECTED && !strcmp(n, voulu))
			for (int j = 0; j < x->count_modes; j++) {
				const drmModeModeInfo *m = &x->modes[j];
				printf("%dx%d%s@%u\n", m->hdisplay, m->vdisplay, (m->flags & DRM_MODE_FLAG_INTERLACE) ? "i" : "", m->vrefresh);
			}
		drmModeFreeConnector(x);
	}
	return 0;
}

static uint32_t prop(int fd, uint32_t obj, const char *nom, const char *enumere, uint64_t *val) {
	drmModeObjectProperties *p = drmModeObjectGetProperties(fd, obj, DRM_MODE_OBJECT_CONNECTOR);
	uint32_t id = 0;
	for (unsigned i = 0; p && i < p->count_props && !id; i++) {
		drmModePropertyRes *q = drmModeGetProperty(fd, p->props[i]);
		if (q && !strcmp(q->name, nom)) {
			if (!enumere) id = q->prop_id;
			else for (int e = 0; e < q->count_enums; e++) if (!strcmp(q->enums[e].name, enumere)) { id = q->prop_id; *val = q->enums[e].value; }
		}
		drmModeFreeProperty(q);
	}
	drmModeFreeObjectProperties(p);
	return id;
}

static int couleur(const char *format, const char *prof, const char *voulu) {
	const char *f = !strcmp(format, "auto") ? "ycbcr_high_subsampling" : format;
	const char *d = !strcmp(prof, "10") ? "30bit" : !strcmp(prof, "8") ? "24bit" : !strcmp(prof, "auto") ? "Automatic" : NULL;
	if (!d || (strcmp(f, "rgb") && strcmp(f, "ycbcr444") && strcmp(f, "ycbcr422") && strcmp(f, "ycbcr420") && strcmp(f, "ycbcr_high_subsampling"))) {
		fprintf(stderr, "pxl-mode : couleur inconnue (%s %s)\n", format, prof); return 1; }
	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror("pxl-mode : /dev/dri/card0"); return 1; }
	if (drmSetMaster(fd)) fprintf(stderr, "pxl-mode : pas maître DRM (%s) — on essaie quand même\n", strerror(errno));
	drmModeRes *res = drmModeGetResources(fd);
	if (!res) return 1;
	int rc = 1;
	for (int k = 0; k < res->count_connectors; k++) {
		drmModeConnector *x = drmModeGetConnector(fd, res->connectors[k]);
		char n[32]; snprintf(n, sizeof n, "%s-%u", nom_type(x->connector_type), x->connector_type_id);
		if (!strcmp(n, voulu)) {
			uint64_t vf = 0, vd = 0;
			uint32_t pf = prop(fd, x->connector_id, "color_format", f, &vf), pd = prop(fd, x->connector_id, "color_depth", d, &vd);
			uint32_t pb = prop(fd, x->connector_id, "max bpc", NULL, NULL);
			if (!pf || !pd) fprintf(stderr, "pxl-mode : %s sans color_format/color_depth (pilote non Rockchip ?)\n", voulu);
			else {
				rc = 0;
				// « max bpc » (8..16) : Weston le recopie, et 0 fait refuser son premier commit (cause de l'écran noir, 04/10)
				if (pb && drmModeConnectorSetProperty(fd, x->connector_id, pb, !strcmp(prof, "8") ? 8 : 10)) rc = 1;
				if (drmModeConnectorSetProperty(fd, x->connector_id, pf, vf)) { perror("pxl-mode : color_format"); rc = 1; }
				if (drmModeConnectorSetProperty(fd, x->connector_id, pd, vd)) { perror("pxl-mode : color_depth"); rc = 1; }
				if (!rc) printf("pxl-mode : lien %s demandé en %s / %s (vérité : bus_format du summary)\n", voulu, f, d);
			}
		}
		drmModeFreeConnector(x);
	}
	drmDropMaster(fd);
	return rc;
}

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage : pxl-mode LxH[i]@R [connecteur] | --liste [connecteur]\n"); return 1; }
	if (!strcmp(argv[1], "--liste")) return lister(argc > 2 ? argv[2] : "HDMI-A-1");
	if (!strcmp(argv[1], "--couleur")) {
		if (argc < 4) { fprintf(stderr, "usage : pxl-mode --couleur FORMAT PROF [connecteur]\n"); return 1; }
		return couleur(argv[2], argv[3], argc > 4 ? argv[4] : "HDMI-A-1");
	}
	int l, h, r; char i = 0;
	if (sscanf(argv[1], "%dx%d%c@%d", &l, &h, &i, &r) != 4) { i = 0; if (sscanf(argv[1], "%dx%d@%d", &l, &h, &r) != 3) return 1; }
	int entrelace = (i == 'i');
	const char *voulu = argc > 2 ? argv[2] : "HDMI-A-1";

	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror("pxl-mode : /dev/dri/card0"); return 1; }
	if (drmSetMaster(fd)) fprintf(stderr, "pxl-mode : pas maître DRM (%s) — on essaie quand même\n", strerror(errno));
	drmModeRes *res = drmModeGetResources(fd);
	if (!res) { perror("pxl-mode : ressources"); return 1; }

	drmModeConnector *c = NULL;
	for (int k = 0; k < res->count_connectors && !c; k++) {
		drmModeConnector *x = drmModeGetConnector(fd, res->connectors[k]);
		char n[32]; snprintf(n, sizeof n, "%s-%u", nom_type(x->connector_type), x->connector_type_id);
		if (x->connection == DRM_MODE_CONNECTED && !strcmp(n, voulu)) c = x; else drmModeFreeConnector(x);
	}
	if (!c) { fprintf(stderr, "pxl-mode : %s absent ou débranché\n", voulu); return 1; }

	drmModeModeInfo *m = NULL;
	for (int k = 0; k < c->count_modes && !m; k++) {
		drmModeModeInfo *x = &c->modes[k];
		if (x->hdisplay == l && x->vdisplay == h && (int)x->vrefresh == r && !!(x->flags & DRM_MODE_FLAG_INTERLACE) == entrelace) m = x;
	}
	if (!m) { fprintf(stderr, "pxl-mode : %s absent de la liste de l'écran\n", argv[1]); return 2; }

	uint32_t crtc = 0;
	drmModeEncoder *e = c->encoder_id ? drmModeGetEncoder(fd, c->encoder_id) : NULL;
	if (e && e->crtc_id) crtc = e->crtc_id;
	for (int k = 0; !crtc && k < c->count_encoders; k++) {
		drmModeEncoder *x = drmModeGetEncoder(fd, c->encoders[k]);
		for (int j = 0; j < res->count_crtcs && !crtc; j++) if (x->possible_crtcs & (1u << j)) crtc = res->crtcs[j];
		drmModeFreeEncoder(x);
	}
	if (!crtc) { fprintf(stderr, "pxl-mode : aucun CRTC\n"); return 1; }

	struct drm_mode_create_dumb cd = { .width = l, .height = h, .bpp = 32 };
	if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) { perror("pxl-mode : tampon"); return 1; }
	uint32_t fb;
	if (drmModeAddFB(fd, l, h, 24, 32, cd.pitch, cd.handle, &fb)) { perror("pxl-mode : AddFB"); return 1; }
	struct drm_mode_map_dumb md = { .handle = cd.handle };
	if (!drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) {
		void *p = mmap(0, cd.size, PROT_WRITE, MAP_SHARED, fd, md.offset);
		if (p != MAP_FAILED) { memset(p, 0, cd.size); munmap(p, cd.size); }
	}
	if (drmModeSetCrtc(fd, crtc, fb, 0, 0, &c->connector_id, 1, m)) { perror("pxl-mode : SetCrtc"); return 1; }
	printf("pxl-mode : %s posé sur %s (crtc %u, %u kHz)\n", m->name, voulu, crtc, m->clock);
	fflush(stdout);
	drmDropMaster(fd);
	// garder le tampon le temps que Weston prenne la main (il lit le mode courant à son démarrage)
	if (fork() == 0) { sleep(30); _exit(0); }
	return 0;
}
