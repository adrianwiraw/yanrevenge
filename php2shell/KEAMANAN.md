# Kebijakan Keamanan (Security Policy)

## Cakupan (Scope)

PHP2Shell adalah *toolkit* penelitian yang ditujukan untuk pengujian berizin (*authorized*) terhadap CVE-2026-109618 / CVE-2026-109619. Perangkat lunak ini tidak menyediakan daftar target dan **dilarang keras** digunakan terhadap sistem pihak ketiga.

## Melaporkan Masalah pada Toolkit Ini

Jika Anda menemukan bug pada alat/skrip ini (dispatcher, mesin profile, konfigurasi laboratorium, atau dokumentasi), silakan buka *GitHub Issue* atau *Private Advisory*. Harap sertakan:

- Skrip dan versi yang terdampak;
- Perintah (*command*) dan konfigurasi spesifik yang digunakan;
- Perilaku yang terjadi vs perilaku yang diharapkan;
- Catatan log dengan menghapus/menyamarkan *hostname* target, alamat IP, *cookie*, dan data kredensial.

**Jangan menyertakan data dari sistem yang bukan milik Anda.**

## Melaporkan Kerentanan PHP

Repository ini bukan saluran resmi vendor. Jika Anda menemukan *build* baru yang terdampak atau isu kerentanan baru pada PHP, laporkan langsung ke tim keamanan PHP dan vendor distribusi terkait melalui proses pengungkapan terkoordinasi (*coordinated disclosure*).

## Penggunaan yang Diizinkan (Acceptable Use)

Pengujian hanya diizinkan pada sistem yang Anda miliki sendiri atau jika Anda memiliki izin tertulis secara eksplisit untuk mengujinya. Rangkaian eksploitasi ini bersifat mengganggu (*disruptive*): skrip ini mengirimkan *request body* berukuran besar, memicu kondisi kehabisan memori (*out-of-memory*), dan mematikan proses *child* Apache. Jangan gunakan mode *remote worker-saturation* terhadap infrastruktur pihak ketiga.
