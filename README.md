# yanrevenge

Repository ini berisi proyek **PHP2Shell**, toolkit riset keamanan untuk
mempelajari dan melakukan pengujian berizin terkait CVE-2026-109618 dan
CVE-2026-109619 pada konfigurasi PHP tertentu.

## Isi Repository

- [`php2shell/`](./php2shell/) — kode, profil build PHP, katalog riset, dan
  dokumentasi toolkit.
- [`php2shell/README.md`](./php2shell/README.md) — penjelasan lengkap mengenai
  isi proyek, batasan data, dan penggunaan yang bertanggung jawab.

## Peringatan Penggunaan

Toolkit ini bersifat **dual-use** dan beberapa pengujiannya dapat mengganggu
layanan, termasuk menyebabkan kehabisan memori atau menghentikan proses web
server. Gunakan hanya pada sistem milik sendiri atau sistem yang secara jelas
tercakup dalam izin tertulis. Jangan mengujinya pada situs, server, jaringan,
atau lingkungan produksi milik pihak lain.

Informasi kerentanan dan profil di repository ini merupakan materi riset,
bukan advisori resmi maupun bukti bahwa sistem tertentu rentan atau aman.
Periksa advisori PHP dan vendor distribusi untuk informasi keamanan terbaru.
