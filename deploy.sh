#!/usr/bin/env bash
# deploy.sh - satu perintah untuk update situs Hugo + theme (submodule fork)
# Alur: build check -> commit/push theme -> commit/push repo utama -> Cloudflare auto-deploy
#
# Pakai:
#   ./deploy.sh                   # pesan commit otomatis (tanggal & jam)
#   ./deploy.sh -m "add new post" # pesan commit sendiri
#   ./deploy.sh -y                # tanpa konfirmasi
#   ./deploy.sh -u                # merge dulu dari upstream theme (remote "upstream")
#   ./deploy.sh -s                # lewati build check
set -euo pipefail

SITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$SITE_DIR/themes/nostyleplease"
BRANCH="main"
MSG=""
ASSUME_YES=0
UPDATE_UPSTREAM=0
SKIP_BUILD=0

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while getopts "m:yush" opt; do
  case "$opt" in
    m) MSG="$OPTARG" ;;
    y) ASSUME_YES=1 ;;
    u) UPDATE_UPSTREAM=1 ;;
    s) SKIP_BUILD=1 ;;
    h|*) usage ;;
  esac
done

[[ -n "$MSG" ]] || MSG="update $(date '+%Y-%m-%d %H:%M')"

site() { git -C "$SITE_DIR" "$@"; }
theme() { git -C "$THEME_DIR" "$@"; }

[[ -e "$SITE_DIR/.git" ]] || die "$SITE_DIR bukan repo git."
[[ -e "$THEME_DIR/.git" ]] || die "Theme $THEME_DIR bukan submodule/repo git."

# ---------- 1. Build check ----------
if [[ $SKIP_BUILD -eq 0 ]]; then
  if command -v hugo >/dev/null 2>&1; then
    info "Build check (hugo)..."
    TMP_OUT="$(mktemp -d)"
    trap 'rm -rf "$TMP_OUT"' EXIT
    hugo --source "$SITE_DIR" --destination "$TMP_OUT" --gc --minify --quiet \
      || die "Build gagal. Perbaiki dulu sebelum push."
  else
    warn "hugo tidak ditemukan, build check dilewati."
  fi
fi

# ---------- 2. Ringkasan perubahan + konfirmasi ----------
THEME_CHANGES="$(theme status --porcelain)"
SITE_CHANGES="$(site status --porcelain | grep -v ' themes/nostyleplease$' || true)"

if [[ -n "$THEME_CHANGES" ]]; then
  info "Perubahan di theme:"; echo "$THEME_CHANGES"
fi
if [[ -n "$SITE_CHANGES" ]]; then
  info "Perubahan di repo utama:"; echo "$SITE_CHANGES"
fi
if [[ -z "$THEME_CHANGES" && -z "$SITE_CHANGES" && $UPDATE_UPSTREAM -eq 0 ]]; then
  info "Tidak ada perubahan lokal. Mengecek apakah ada commit yang belum di-push..."
fi

if [[ $ASSUME_YES -eq 0 && ( -n "$THEME_CHANGES" || -n "$SITE_CHANGES" ) ]]; then
  read -r -p "Lanjut commit & push dengan pesan \"$MSG\"? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Dibatalkan."
fi

# ---------- 3. Theme (fork submodule) ----------
info "Theme: commit perubahan (jika ada)..."
if [[ -n "$THEME_CHANGES" ]]; then
  theme add -A
  theme commit -m "$MSG"
fi

theme fetch origin --quiet

# Keluar dari detached HEAD (kondisi default submodule)
if ! theme symbolic-ref -q HEAD >/dev/null; then
  if theme merge-base --is-ancestor "origin/$BRANCH" HEAD; then
    info "Theme: detached HEAD -> pindah ke branch $BRANCH"
    theme checkout -B "$BRANCH" --quiet
    theme branch --set-upstream-to="origin/$BRANCH" "$BRANCH" >/dev/null
  else
    die "Theme detached dan origin/$BRANCH punya commit yang tidak ada di lokal. Selesaikan manual (cd $THEME_DIR)."
  fi
fi

if [[ $UPDATE_UPSTREAM -eq 1 ]]; then
  if theme remote get-url upstream >/dev/null 2>&1; then
    info "Theme: merge dari upstream/$BRANCH..."
    theme fetch upstream --quiet
    theme merge "upstream/$BRANCH" -m "merge upstream theme" \
      || die "Konflik merge di theme. Selesaikan manual, lalu jalankan ulang."
  else
    die "Remote 'upstream' belum ada. Tambahkan: git -C $THEME_DIR remote add upstream <URL_REPO_ASLI>"
  fi
fi

THEME_AHEAD="$(theme rev-list --count "origin/$BRANCH..HEAD")"
if [[ "$THEME_AHEAD" -gt 0 ]]; then
  info "Theme: push $THEME_AHEAD commit ke fork..."
  theme push origin "HEAD:$BRANCH"
else
  info "Theme: sudah sinkron dengan fork."
fi

# ---------- 4. Repo utama ----------
info "Repo utama: stage perubahan (termasuk pointer theme)..."
site add -A
if ! site diff --cached --quiet; then
  site commit -m "$MSG"
fi

site fetch origin --quiet
if ! site merge-base --is-ancestor "origin/$BRANCH" HEAD; then
  info "Repo utama: rebase ke origin/$BRANCH..."
  site pull --rebase --autostash origin "$BRANCH"
fi

SITE_AHEAD="$(site rev-list --count "origin/$BRANCH..HEAD")"
if [[ "$SITE_AHEAD" -gt 0 ]]; then
  info "Repo utama: push $SITE_AHEAD commit..."
  site push origin "$BRANCH"
  info "Selesai. Cloudflare Pages akan build otomatis (cek tab Deployments)."
else
  info "Repo utama: tidak ada yang perlu di-push."
fi
