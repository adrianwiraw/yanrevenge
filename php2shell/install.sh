#!/usr/bin/env bash

# Pastikan dijalankan dengan bash
if [ -z "$BASH_VERSION" ]; then
    echo "[-] Harap jalankan script ini menggunakan bash: bash install.sh"
    exit 1
fi

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="$INSTALL_DIR/tools/php2shell_auto.py"

# Cek apakah file python utamanya ada
if [ ! -f "$TARGET_FILE" ]; then
    echo "[-] Error: File php2shell_auto.py tidak ditemukan di direktori tools/"
    exit 1
fi

# Tentukan file konfigurasi shell user (.bashrc atau .zshrc)
SHELL_RC="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
fi

# Blok fungsi yan yang akan disuntikkan ke bashrc/zshrc
INSTALL_DIR_Q="$(printf '%q' "$INSTALL_DIR")"
read -r -d '' YAN_FUNCTION << EOF

# --- YANREVENGE TOOLKIT START ---
YANREVENGE_INSTALL_DIR=$INSTALL_DIR_Q
yan() {
    case "\$1" in
        ""|help|-h|--help)
            cat <<'YAN_HELP'
Penggunaan: yan <perintah>

Perintah:
  help, -h, --help   Tampilkan bantuan ini.
  bootstrap          Jalankan bootstrap_upstream.py.
  exploit            Jalankan php2shell_auto.py dengan argumen yang diberikan.
  lab                Kelola lab PHP lokal (up, status, down, test).

Gunakan operasi pengujian hanya di lab terisolasi yang Anda miliki atau
yang secara eksplisit tercakup dalam izin tertulis.
YAN_HELP
            ;;
        exploit)
            shift
            python3 "\$YANREVENGE_INSTALL_DIR/tools/php2shell_auto.py" "\$@"
            ;;
        bootstrap)
            python3 "\$YANREVENGE_INSTALL_DIR/tools/bootstrap_upstream.py"
            ;;
        lab)
            shift
            if [ "\$#" -eq 0 ]; then
                echo "Penggunaan: yan lab <up|status|down|test> [opsi]" >&2
                return 2
            fi
            python3 "\$YANREVENGE_INSTALL_DIR/tools/php2shell_labs.py" "\$@"
            ;;
        *)
            echo "Perintah tidak dikenal: \$1" >&2
            echo "Jalankan 'yan help' untuk melihat daftar perintah." >&2
            return 2
            ;;
    esac
}
# --- YANREVENGE TOOLKIT END ---
EOF

# Cek apakah fungsi yan sudah ada di file RC
if grep -q "YANREVENGE TOOLKIT START" "$SHELL_RC"; then
    echo "[*] Fungsi yan sudah terdaftar di $SHELL_RC. Memperbarui..."
    # Hapus konfigurasi lama
    sed -i '/# --- YANREVENGE TOOLKIT START ---/,/# --- YANREVENGE TOOLKIT END ---/d' "$SHELL_RC"
fi

# Tambahkan fungsi baru ke akhir file RC
echo "$YAN_FUNCTION" >> "$SHELL_RC"

echo "[+] Berhasil! Perintah 'yan' telah ditambahkan secara otomatis ke $SHELL_RC"
echo "[*] Silakan jalankan perintah berikut untuk mengaktifkannya sekarang:"
echo "    source $SHELL_RC"
