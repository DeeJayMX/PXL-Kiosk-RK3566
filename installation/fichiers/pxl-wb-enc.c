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
//
// ENTRELACÉ (1080i) — mesuré le 03/10/2026, voir docs/FLUX_WRITEBACK.md :
//  - le writeback du RK3566 n'écrit qu'UNE trame par capture (540 lignes) ; ses registres n'ont ni pas de ligne,
//    ni hauteur, ni parité. Weston capture donc des PAIRES de trames consécutives (rang 1 puis 2 dans FRAME).
//  - on les TISSE à la RGA, sans que le processeur touche un pixel : un NV12 1920×1080 a exactement la disposition
//    d'un NV12 3840×540 dont la moitié gauche porte les lignes paires et la droite les impaires. Tisser = deux
//    copies RGA ordinaires (trame du haut à gauche, du bas à droite), Y et UV compris.
//  - QUELLE trame va en haut : la parité du numéro de vblank (envoyé par Weston), à un décalage près que l'IMAGE
//    fixe — l'ordre juste est le plus lisse entre lignes voisines (mesuré : 1,69 contre 2,81, le mauvais ordre
//    peigne le texte). Le décalage est appris, puis re-vérifié chaque seconde ; trois désaccords francs le basculent.
//    ⚠ Une paire ne commence pas toujours sur la même trame (une recomposition ratée la décale) : on ne fige donc
//    JAMAIS « la première de la paire va en haut ».
//  - en PsF (réglage « 25p propre »), les deux trames d'une paire sont la MÊME image : la parité apprise est
//    renvoyée à Weston (message PARITE), qui cale alors chaque image sur la trame du haut.
#include <errno.h>
#include <linux/dma-buf.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <rockchip/rk_mpi.h>
#include <rga/im2d.h>
#include <rga/rga.h>

#define PXL_WB_N 6
#define PXL_WB_MAGIC 0x57584c50u
enum { PXL_WB_HELLO = 1, PXL_WB_RELEASE = 2, PXL_WB_PARITE = 3, PXL_WB_RING = 10, PXL_WB_FRAME = 11 };
struct pxl_wb_msg {   // identique à drm.c (patch)
	uint32_t magic, type, slot, n, w, h, pitch, size, uvoff, fps;
	uint64_t t_ns, frames, skipped;
	uint64_t seq;
};
#define TISSE_N 2

static int sfd = -1, ring_fd[PXL_WB_N], ring_n = 0, W = 0, H = 0, PAS = 0;
static uint32_t TAILLE = 0, UVOFF = 0;
static MppCtx ctx; static MppApi *api; static MppBufferGroup grp, grp_t; static MppBuffer mb[PXL_WB_N], tb[TISSE_N];
static rga_buffer_handle_t rh[PXL_WB_N], rt[TISSE_N];
static uint8_t *vue[PXL_WB_N];
static int fps = 25, debit = 6000, enc_ok = 0, tisse_ok = 0, tisse_i = 0;

static double ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

static void ecrire(const void *p, size_t n) {
	const uint8_t *c = p;
	while (n) { ssize_t r = write(1, c, n); if (r > 0) { c += r; n -= r; } else if (errno != EINTR) { perror("pxl-wb-enc : sortie"); exit(0); } }
}

static void enc_fermer(void) {
	for (int i = 0; i < TISSE_N; i++) {
		if (rt[i]) releasebuffer_handle(rt[i]);
		rt[i] = 0;
		if (tb[i]) mpp_buffer_put(tb[i]);
		tb[i] = NULL;
	}
	for (int i = 0; i < ring_n; i++) {
		if (rh[i]) releasebuffer_handle(rh[i]);
		rh[i] = 0;
		if (vue[i]) munmap(vue[i], TAILLE);
		vue[i] = NULL;
		if (mb[i]) mpp_buffer_put(mb[i]);
		mb[i] = NULL;
		close(ring_fd[i]);
	}
	ring_n = 0;
	if (grp_t) { mpp_buffer_group_put(grp_t); grp_t = NULL; }
	if (grp) { mpp_buffer_group_put(grp); grp = NULL; }
	if (ctx) { mpp_destroy(ctx); ctx = NULL; }
	enc_ok = tisse_ok = 0;
}

// Le tissage : des tampons 1920×1080 où la RGA pose les deux trames ; MPP les encode ensuite comme n'importe quelle
// image. Préparé à l'ouverture de l'anneau, mais seulement utilisé si des paires arrivent.
static void tisse_ouvrir(void) {
	if (W * 2 > 4096 || (H / 2) & 1) {   // la RGA2 du RK3566 sort au plus 4096 de large
		fprintf(stderr, "pxl-wb-enc : tissage impossible en %dx%d (la RGA sort au plus 4096 de large)\n", W, H);
		return;
	}
	if (mpp_buffer_group_get_internal(&grp_t, MPP_BUFFER_TYPE_DRM)) return;
	for (int i = 0; i < TISSE_N; i++) {
		if (mpp_buffer_get(grp_t, &tb[i], TAILLE)) return;
		im_handle_param_t p = { (uint32_t)W * 2, (uint32_t)H / 2, RK_FORMAT_YCbCr_420_SP };
		rt[i] = importbuffer_fd(mpp_buffer_get_fd(tb[i]), &p);
		if (!rt[i]) { fprintf(stderr, "pxl-wb-enc : RGA, import du tampon tissé %d\n", i); return; }
	}
	for (int i = 0; i < ring_n; i++) {
		im_handle_param_t p = { (uint32_t)PAS, (uint32_t)(UVOFF / PAS), RK_FORMAT_YCbCr_420_SP };
		rh[i] = importbuffer_fd(ring_fd[i], &p);
		if (!rh[i]) { fprintf(stderr, "pxl-wb-enc : RGA, import de la case %d\n", i); return; }
		// lecture seule, pour juger l'ordre des trames (quelques milliers d'octets par seconde)
		vue[i] = mmap(NULL, TAILLE, PROT_READ, MAP_SHARED, ring_fd[i], 0);
		if (vue[i] == MAP_FAILED) vue[i] = NULL;
	}
	tisse_ok = 1;
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
	W = m->w; H = m->h; PAS = m->pitch; TAILLE = m->size; UVOFF = m->uvoff; enc_ok = 1;
	fprintf(stderr, "pxl-wb-enc : %dx%d NV12 (pas %u) -> H.264 %d img/s %d kbit/s, %d tampons importés sans copie\n",
		W, H, m->pitch, fps, debit, ring_n);
	tisse_ouvrir();
	return 0;
}

static long octets = 0, images = 0;
static void encoder(MppBuffer b) {
	MppFrame frm = NULL; mpp_frame_init(&frm);
	mpp_frame_set_width(frm, W); mpp_frame_set_height(frm, H);
	mpp_frame_set_hor_stride(frm, PAS); mpp_frame_set_ver_stride(frm, UVOFF / PAS);
	mpp_frame_set_fmt(frm, MPP_FMT_YUV420SP);
	mpp_frame_set_buffer(frm, b);
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

// Laquelle des deux trames va en haut, d'après l'IMAGE : l'ordre juste est le plus lisse entre lignes voisines.
// Rend 0 (a en haut), 1 (b en haut), -1 (indécidable : image trop uniforme, ou trames trop différentes).
static void sync_dmabuf(int fd, uint64_t f) { struct dma_buf_sync s = { f }; ioctl(fd, DMA_BUF_IOCTL_SYNC, &s); }
static int juger(int a, int b) {
	if (!vue[a] || !vue[b]) return -1;
	sync_dmabuf(ring_fd[a], DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ);
	sync_dmabuf(ring_fd[b], DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ);
	const uint8_t *A = vue[a], *B = vue[b];
	long s_ab = 0, s_ba = 0, n = 0;
	for (int y = 0; y + 1 < H / 2; y++)
		for (int x = 32; x < W - 32; x += 32) {
			s_ab += abs(B[y * PAS + x] - A[(y + 1) * PAS + x]);   // a en haut : … a(y) b(y) a(y+1) …
			s_ba += abs(A[y * PAS + x] - B[(y + 1) * PAS + x]);   // b en haut : … b(y) a(y) b(y+1) …
			n++;
		}
	sync_dmabuf(ring_fd[a], DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
	sync_dmabuf(ring_fd[b], DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ);
	const long d = labs(s_ab - s_ba), hi = s_ab > s_ba ? s_ab : s_ba;
	if (d * 100 < hi * 15 || d < n / 4) return -1;   // < 15 % d'écart, ou < 0,25 de niveau en moyenne : on ne tranche pas
	return s_ab < s_ba ? 0 : 1;
}

// Pose la trame `haut` à gauche, `bas` à droite d'un NV12 3840×540 — c'est-à-dire tisse un 1920×1080.
static int tisser(int haut, int bas, MppBuffer *sortie) {
	const int t = tisse_i; tisse_i = (tisse_i + 1) % TISSE_N;
	rga_buffer_t dst = wrapbuffer_handle_t(rt[t], W * 2, H / 2, W * 2, H / 2, RK_FORMAT_YCbCr_420_SP);
	rga_buffer_t pat; memset(&pat, 0, sizeof pat);
	im_rect vide = { 0, 0, 0, 0 };
	const int src[2] = { haut, bas };
	for (int k = 0; k < 2; k++) {
		rga_buffer_t s = wrapbuffer_handle_t(rh[src[k]], W, H / 2, PAS, UVOFF / PAS, RK_FORMAT_YCbCr_420_SP);
		im_rect sr = { 0, 0, W, H / 2 }, dr = { k * W, 0, W, H / 2 };
		IM_STATUS r = improcess(s, dst, pat, sr, dr, vide, IM_SYNC);
		if (r != IM_STATUS_SUCCESS) { fprintf(stderr, "pxl-wb-enc : RGA, tissage : %s\n", imStrError(r)); return -1; }
	}
	*sortie = tb[t];
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

// La parité apprise repart vers Weston : en PsF il cale les images sur la trame du haut (pxl_psf_flip).
static void annoncer_parite(int decalage) {
	struct pxl_wb_msg p = { .magic = PXL_WB_MAGIC, .type = PXL_WB_PARITE, .n = (uint32_t)decalage };
	send(sfd, &p, sizeof p, MSG_NOSIGNAL);
}

static void rendre(uint32_t slot) {
	struct pxl_wb_msg rel = { .magic = PXL_WB_MAGIC, .type = PXL_WB_RELEASE, .slot = slot };
	send(sfd, &rel, sizeof rel, MSG_NOSIGNAL);
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

	long ratees = 0, paires = 0, cassees = 0, indecis = 0, bascules = 0; double t_enc = 0, t0 = ms(), attente = 0; uint64_t sautees = 0;
	int tenue = -1; uint64_t tenue_seq = 0;      // trame 1 d'une paire, en attente de la 2
	int decalage = -1, desaccords = 0, accords = 0; long n_paire = 0;   // trame du haut = (seq + decalage) pair
	int dit_taille = 0;
	for (;;) {
		int fds[PXL_WB_N], nfds;
		ssize_t r = recevoir(&m, fds, &nfds);
		if (r <= 0) { fprintf(stderr, "pxl-wb-enc : Weston a fermé le flux\n"); return 2; }   // relancé par systemd
		if (r != sizeof m || m.magic != PXL_WB_MAGIC) {
			if (!dit_taille++) fprintf(stderr, "pxl-wb-enc : message de %zd octets au lieu de %zu — Weston et l'encodeur ne sont pas du même patch\n", r, sizeof m);
			for (int i = 0; i < nfds; i++) close(fds[i]);
			continue;
		}
		if (m.type == PXL_WB_RING) {
			enc_fermer(); tenue = -1;
			if (decalage >= 0) annoncer_parite(decalage);   // un Weston relancé l'a oubliée
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
		sautees = m.skipped;
		if (!enc_ok || m.slot >= (uint32_t)ring_n) { rendre(m.slot); continue; }

		if (m.n == 0) {                 // progressif : une capture = une image
			if (tenue >= 0) { rendre(tenue); tenue = -1; }
			encoder(mb[m.slot]);
			rendre(m.slot);
		} else if (m.n == 1) {          // entrelacé, première trame : on la garde
			if (tenue >= 0) { rendre(tenue); cassees++; }
			tenue = m.slot; tenue_seq = m.seq;
		} else {                        // entrelacé, seconde trame
			if (tenue < 0 || m.seq != tenue_seq + 1 || !tisse_ok) {
				if (tenue >= 0) rendre(tenue);
				rendre(m.slot); tenue = -1; cassees++;
				continue;
			}
			const int a = tenue, b = m.slot;      // a = trame n° tenue_seq, b = la suivante
			// l'image juge une paire sur 25 (une par seconde), et chacune tant que l'ordre n'est pas appris
			if (decalage < 0 || (n_paire++ % 25) == 0) {
				const int j = juger(a, b);      // 0 : a en haut
				if (j < 0) indecis++;
				else {
					const int dec = (int)((tenue_seq + (j == 0 ? 0 : 1)) & 1);   // tel que (seq_haut + dec) soit pair
					if (decalage < 0) { decalage = dec; annoncer_parite(dec); fprintf(stderr, "pxl-wb-enc : ordre des trames appris sur l'image (décalage %d)\n", dec); }
					else if (dec != decalage) {
						if (++desaccords >= 3) { decalage = dec; desaccords = 0; bascules++; annoncer_parite(dec); fprintf(stderr, "pxl-wb-enc : ordre des trames rebasculé par l'image\n"); }
					} else { desaccords = 0; accords++; }
				}
			}
			const int a_haut = decalage < 0 ? 1 : (((tenue_seq + decalage) & 1) == 0);
			MppBuffer tisse = NULL;
			const int ok = !tisser(a_haut ? a : b, a_haut ? b : a, &tisse);
			rendre(a); rendre(b); tenue = -1;
			if (ok) { encoder(tisse); paires++; }
		}
		t_enc += ms() - e0;
		const double t = ms();
		if (t - t0 >= 10000) {
			fprintf(stderr, "pxl-wb-enc : %.1f img/s · %.0f kbit/s · %.1f ms/img (barrière %.1f) · %ld barrières en retard · %llu non capturées (anneau plein)",
				images * 1000.0 / (t - t0), octets * 8.0 / (t - t0), images ? t_enc / images : 0, images ? attente / images : 0,
				ratees, (unsigned long long)sautees);
			if (paires || cassees)
				fprintf(stderr, " · entrelacé : %ld paires tissées, %ld cassées, ordre %s (%d accords, %ld indécis, %ld bascules)",
					paires, cassees, decalage < 0 ? "PAS ENCORE APPRIS" : "appris", accords, indecis, bascules);
			fputc('\n', stderr);
			images = 0; octets = 0; t_enc = 0; attente = 0; t0 = t; paires = 0; cassees = 0;
		}
	}
}
