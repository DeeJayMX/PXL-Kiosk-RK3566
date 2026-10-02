// pxl-wb-enc — encodeur H.264 du flux writeback de Weston (patch PXL), SANS COPIE.
//
//   pxl-wb-enc [--socket /run/pxl-preview/pxl-wb.sock] [--fps 25] [--debit 6000] > flux.h264
//
// Weston (drm-backend patché, voir patches/weston-writeback-flux.patch) écrit l'image du HDMI dans un anneau de
// tampons NV12 et nous en passe les DMA-BUF une fois ; ensuite, à chaque image, un message « case n prête » et la
// barrière (out-fence) du writeback. On attend la barrière, MPP lit le tampon tel quel, on rend la case.
// Sortie : H.264 Annex-B sur stdout, SPS/PPS à chaque image clé (thq-publish.js en a besoin pour son avcC).
// Statistiques sur stderr toutes les 10 s.
// Leçons reprises de PXL-TurboHQ/TurboNode/noeud/turbohq-direct.cpp (import DRM, barrière, en-têtes).
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <rockchip/rk_mpi.h>

#define PXL_WB_N 4
#define PXL_WB_MAGIC 0x57584c50u
enum { PXL_WB_HELLO = 1, PXL_WB_RELEASE = 2, PXL_WB_RING = 10, PXL_WB_FRAME = 11 };
struct pxl_wb_msg {   // identique à drm.c (patch)
	uint32_t magic, type, slot, n, w, h, pitch, size, uvoff, fps;
	uint64_t t_ns, frames, skipped;
};

static int sfd = -1, ring_fd[PXL_WB_N], ring_n = 0, W = 0, H = 0, PAS = 0;
static MppCtx ctx; static MppApi *api; static MppBufferGroup grp; static MppBuffer mb[PXL_WB_N];
static int fps = 25, debit = 6000, enc_ok = 0;

static double ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

static void ecrire(const void *p, size_t n) {
	const uint8_t *c = p;
	while (n) { ssize_t r = write(1, c, n); if (r > 0) { c += r; n -= r; } else if (errno != EINTR) { perror("pxl-wb-enc : sortie"); exit(0); } }
}

static void enc_fermer(void) {
	for (int i = 0; i < ring_n; i++) { if (mb[i]) mpp_buffer_put(mb[i]); mb[i] = NULL; close(ring_fd[i]); }
	ring_n = 0;
	if (grp) { mpp_buffer_group_put(grp); grp = NULL; }
	if (ctx) { mpp_destroy(ctx); ctx = NULL; }
	enc_ok = 0;
}

static int enc_ouvrir(const struct pxl_wb_msg *m) {
	if (mpp_create(&ctx, &api) || mpp_init(ctx, MPP_CTX_ENC, MPP_VIDEO_CodingAVC)) { fprintf(stderr, "pxl-wb-enc : mpp_init\n"); return -1; }
	MppEncCfg cfg = NULL; mpp_enc_cfg_init(&cfg);
	mpp_enc_cfg_set_s32(cfg, "prep:width", m->w);
	mpp_enc_cfg_set_s32(cfg, "prep:height", m->h);
	mpp_enc_cfg_set_s32(cfg, "prep:hor_stride", m->pitch);
	mpp_enc_cfg_set_s32(cfg, "prep:ver_stride", m->uvoff / m->pitch);   // la chroma commence à uvoff
	mpp_enc_cfg_set_s32(cfg, "prep:format", MPP_FMT_YUV420SP);
	mpp_enc_cfg_set_s32(cfg, "rc:mode", MPP_ENC_RC_MODE_CBR);
	mpp_enc_cfg_set_s32(cfg, "rc:bps_target", debit * 1000);
	mpp_enc_cfg_set_s32(cfg, "rc:bps_max", debit * 1000 * 17 / 16);
	mpp_enc_cfg_set_s32(cfg, "rc:bps_min", debit * 1000 * 15 / 16);
	mpp_enc_cfg_set_s32(cfg, "rc:fps_in_num", fps);  mpp_enc_cfg_set_s32(cfg, "rc:fps_in_denorm", 1);
	mpp_enc_cfg_set_s32(cfg, "rc:fps_out_num", fps); mpp_enc_cfg_set_s32(cfg, "rc:fps_out_denorm", 1);
	mpp_enc_cfg_set_s32(cfg, "rc:gop", fps);   // une image clé par seconde : un spectateur qui arrive voit vite
	mpp_enc_cfg_set_s32(cfg, "codec:type", MPP_VIDEO_CodingAVC);
	mpp_enc_cfg_set_s32(cfg, "h264:profile", 100);
	mpp_enc_cfg_set_s32(cfg, "h264:level", 42);
	mpp_enc_cfg_set_s32(cfg, "h264:cabac_en", 1);
	int r = api->control(ctx, MPP_ENC_SET_CFG, cfg); mpp_enc_cfg_deinit(cfg);
	if (r) { fprintf(stderr, "pxl-wb-enc : MPP_ENC_SET_CFG %d\n", r); return -1; }
	MppEncHeaderMode hm = MPP_ENC_HEADER_MODE_EACH_IDR; api->control(ctx, MPP_ENC_SET_HEADER_MODE, &hm);
	if (mpp_buffer_group_get_external(&grp, MPP_BUFFER_TYPE_DRM)) { fprintf(stderr, "pxl-wb-enc : groupe externe\n"); return -1; }
	for (int i = 0; i < ring_n; i++) {
		MppBufferInfo info; memset(&info, 0, sizeof info);
		info.type = MPP_BUFFER_TYPE_DRM; info.fd = ring_fd[i]; info.size = m->size; info.index = i;
		if (mpp_buffer_import(&mb[i], &info)) { fprintf(stderr, "pxl-wb-enc : import %d\n", i); return -1; }
	}
	W = m->w; H = m->h; PAS = m->pitch; enc_ok = 1;
	fprintf(stderr, "pxl-wb-enc : %dx%d NV12 (pas %u) -> H.264 %d img/s %d kbit/s, %d tampons importés sans copie\n",
		W, H, m->pitch, fps, debit, ring_n);
	return 0;
}

static ssize_t recevoir(struct pxl_wb_msg *m, int *fds, int *nfds) {
	char ctl[CMSG_SPACE(sizeof(int) * PXL_WB_N)];
	struct iovec iov = { m, sizeof *m };
	struct msghdr mh = { .msg_iov = &iov, .msg_iovlen = 1, .msg_control = ctl, .msg_controllen = sizeof ctl };
	ssize_t r = recvmsg(sfd, &mh, MSG_CMSG_CLOEXEC);
	*nfds = 0;
	for (struct cmsghdr *c = CMSG_FIRSTHDR(&mh); c; c = CMSG_NXTHDR(&mh, c))
		if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
			*nfds = (c->cmsg_len - CMSG_LEN(0)) / sizeof(int);
			memcpy(fds, CMSG_DATA(c), sizeof(int) * *nfds);
		}
	return r;
}

int main(int argc, char **argv) {
	const char *chemin = "/run/pxl-preview/pxl-wb.sock";
	for (int i = 1; i + 1 < argc; i += 2) {
		if (!strcmp(argv[i], "--socket")) chemin = argv[i + 1];
		else if (!strcmp(argv[i], "--fps")) fps = atoi(argv[i + 1]);
		else if (!strcmp(argv[i], "--debit")) debit = atoi(argv[i + 1]);
	}
	if (fps < 1 || fps > 60) fps = 25;
	signal(SIGPIPE, SIG_IGN);
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	strncpy(a.sun_path, chemin, sizeof a.sun_path - 1);
	// Weston peut ne pas être encore là (démarrage, relance de l'écran) : on réessaie
	for (int essai = 0; ; essai++) {
		sfd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
		if (!connect(sfd, (struct sockaddr *)&a, sizeof a)) break;
		close(sfd);
		if (essai == 0) fprintf(stderr, "pxl-wb-enc : %s pas encore là (%s), on attend\n", chemin, strerror(errno));
		sleep(1);
	}
	struct pxl_wb_msg m = { .magic = PXL_WB_MAGIC, .type = PXL_WB_HELLO, .fps = fps };
	if (send(sfd, &m, sizeof m, 0) != sizeof m) { perror("pxl-wb-enc : hello"); return 1; }

	long images = 0, octets = 0, ratees = 0; double t_enc = 0, t0 = ms(), attente = 0; uint64_t sautees = 0;
	for (;;) {
		int fds[PXL_WB_N], nfds;
		ssize_t r = recevoir(&m, fds, &nfds);
		if (r <= 0) { fprintf(stderr, "pxl-wb-enc : Weston a fermé le flux\n"); return 2; }   // relancé par systemd
		if (r != sizeof m || m.magic != PXL_WB_MAGIC) { for (int i = 0; i < nfds; i++) close(fds[i]); continue; }
		if (m.type == PXL_WB_RING) {
			enc_fermer();
			ring_n = nfds < (int)m.n ? nfds : (int)m.n;
			for (int i = 0; i < ring_n; i++) ring_fd[i] = fds[i];
			if (enc_ouvrir(&m)) return 1;
			continue;
		}
		if (m.type != PXL_WB_FRAME) { for (int i = 0; i < nfds; i++) close(fds[i]); continue; }
		const double e0 = ms();
		// ⚠ LA BARRIÈRE : sans l'attendre on encode un tampon que le VOP2 remplit encore (image déchirée)
		if (nfds > 0) { struct pollfd pf = { fds[0], POLLIN, 0 }; if (poll(&pf, 1, 100) <= 0) ratees++; close(fds[0]); }
		attente += ms() - e0;
		if (enc_ok && m.slot < (uint32_t)ring_n) {
			MppFrame frm = NULL; mpp_frame_init(&frm);
			mpp_frame_set_width(frm, W); mpp_frame_set_height(frm, H);
			mpp_frame_set_hor_stride(frm, PAS); mpp_frame_set_ver_stride(frm, H);
			mpp_frame_set_fmt(frm, MPP_FMT_YUV420SP);
			mpp_frame_set_buffer(frm, mb[m.slot]);
			if (api->encode_put_frame(ctx, frm) == MPP_OK) {
				MppPacket pkt = NULL;
				if (api->encode_get_packet(ctx, &pkt) == MPP_OK && pkt) {
					size_t n = mpp_packet_get_length(pkt);
					ecrire(mpp_packet_get_pos(pkt), n); octets += n; images++;
					mpp_packet_deinit(&pkt);
				}
			}
			mpp_frame_deinit(&frm);
		}
		t_enc += ms() - e0;
		struct pxl_wb_msg rel = { .magic = PXL_WB_MAGIC, .type = PXL_WB_RELEASE, .slot = m.slot };
		send(sfd, &rel, sizeof rel, MSG_NOSIGNAL);
		sautees = m.skipped;
		const double t = ms();
		if (t - t0 >= 10000) {
			fprintf(stderr, "pxl-wb-enc : %.1f img/s · %.0f kbit/s · encodage %.1f ms/img (barrière %.1f) · %ld barrières en retard · %llu images non capturées (anneau plein)\n",
				images * 1000.0 / (t - t0), octets * 8.0 / (t - t0), images ? t_enc / images : 0, images ? attente / images : 0,
				ratees, (unsigned long long)sautees);
			images = 0; octets = 0; t_enc = 0; attente = 0; t0 = t;
		}
	}
}
