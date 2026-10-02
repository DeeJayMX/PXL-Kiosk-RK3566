// pxl-mode — pose un mode HDMI que Weston ne sait pas choisir lui-même (le 1080i50 : Weston prend toujours le 1080p50,
// même fréquence, et sa ligne de timings ignore l'entrelacé ; le paramètre video= du noyau aussi — mesuré le 02/10/2026).
//
//   pxl-mode 1920x1080i@50 [HDMI-A-1]
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

int main(int argc, char **argv) {
	if (argc < 2) { fprintf(stderr, "usage : pxl-mode LxH[i]@R [connecteur]\n"); return 1; }
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
