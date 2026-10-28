# PHP2Shell — Toolkit Riset Keamanan

PHP2Shell adalah toolkit riset keamanan yang berisi skrip pendukung, katalog,
dan profil build untuk mempelajari konfigurasi PHP tertentu. Gunakan informasi
dan pengujian hanya pada sistem milik sendiri atau yang tercakup dalam izin
tertulis.

Toolkit ini bersifat **dual-use** dan beberapa pengujiannya dapat mengganggu
layanan. Gunakan hanya pada sistem milik sendiri atau sistem yang secara jelas
tercakup dalam izin tertulis. Jangan mengujinya pada situs, server, atau jaringan
pihak lain maupun pada lingkungan produksi.

## Isi Repository

| Lokasi | Isi |
| --- | --- |
| `tools/` | Skrip Python untuk inventarisasi, penilaian awal, pengelolaan lab, kalibrasi, dan pengolahan profil. |
| `katalog/kerentanan.json` | Catatan versi dan status kerentanan yang dikumpulkan untuk kebutuhan riset. Verifikasi selalu dengan advisori resmi PHP dan vendor distribusi. |
| `profiles/` | Data per build PHP, distribusi, dan arsitektur. Profil menyimpan informasi konfigurasi serta status verifikasi; profil yang tersedia tidak mewakili semua instalasi PHP. |
| `profiles/offsets/` | Data offset untuk build tertentu yang digunakan dalam konteks riset profil. |
| `profiles/schema.json` | Skema untuk struktur data profil JSON. |
| `payload/payload.txt` | Berkas data payload yang menjadi bagian dari materi toolkit. |
| `vendor/php2shell-upstream/` | Materi upstream yang dirujuk, termasuk kode, dokumentasi riset, konfigurasi Docker, dan catatan lab. |
| `install.sh` | Menambahkan fungsi shell `yan` ke konfigurasi Bash atau Zsh pengguna. |
| `LICENSE` | Ketentuan lisensi repository. |
| `KEAMANAN.md` | Kebijakan pelaporan masalah pada toolkit dan panduan penggunaan yang diizinkan. |
| `PERINGATAN.md` | Peringatan singkat sebelum menggunakan materi proyek. |

## `install.sh` — Instalasi Perintah `yan`

Skrip instalasi mendaftarkan fungsi `yan` di `~/.bashrc` atau `~/.zshrc`.
Skrip tidak menyalin berkas proyek atau memasang dependensi. Fungsi tersebut
menyediakan perintah bantuan dan shortcut:

- `yan help` menampilkan bantuan singkat; `yan -h` dan `yan --help` adalah aliasnya.
- `yan bootstrap` menjalankan `tools/bootstrap_upstream.py`.
- `yan lab up` menyalakan lab PHP lokal; `yan lab status` memeriksa status,
  `yan lab down` menghentikannya, dan `yan lab test` menjalankan pengujian
  terhadap lab lokal yang aktif. Tambahkan `--only <versi[,versi...]>` setelah
  `up` untuk memilih build tertentu.

Lab PHP hanya dipublikasikan pada alamat loopback (`127.0.0.1`). Docker harus
terpasang dan berjalan untuk perintah lab. Perintah `test` melakukan pengujian
aktif dan hanya boleh digunakan terhadap lab terisolasi milik Anda.

### Setup lokal

Jalankan perintah berikut dari direktori proyek PHP2Shell:

```bash
bash install.sh
```

Perintah `yan` menggunakan lokasi proyek PHP2Shell tempat `install.sh` dijalankan.
Setelah instalasi, muat konfigurasi sesuai shell yang digunakan. Untuk Bash:

```bash
source ~/.bashrc
```

Untuk Zsh:

```zsh
source ~/.zshrc
```

Verifikasi bahwa antarmuka tersedia dengan `yan help`. Sebelum melakukan
pengujian keamanan apa pun, pastikan target adalah lab yang terisolasi dan
izin, ruang lingkup, pemantauan, serta prosedur pemulihannya sudah jelas.
README ini tidak menyediakan langkah untuk mengeksploitasi target. Baca bagian
[Penggunaan yang Bertanggung Jawab](#penggunaan-yang-bertanggung-jawab) dan
[`PERINGATAN.md`](./PERINGATAN.md) terlebih dahulu.

### Gambaran skrip di `tools/`

- `php2shell_assess.py` — mengumpulkan indikator dan melakukan penilaian awal
  terhadap konfigurasi yang diuji.
- `php2shell_auto.py` dan `php2shell_rce.py` — komponen orkestrasi pengujian
  yang terkait dengan rantai riset; penggunaannya berisiko mengganggu layanan.
- `php2shell_calibrate.py`, `php2shell_matrix.py`, dan `php2shell_offsets.py`
  — membantu riset kalibrasi dan penyusunan data untuk build tertentu.
- `php2shell_inventory.py` — merangkum data profil yang tersedia.
- `php2shell_labs.py` — mengelola operasi lingkungan lab lokal.
- `php2shell_upstream.py`, `bootstrap_upstream.py`, `php2shell_paths.py`, dan
  `php2shell_ui.py` — komponen pendukung integrasi upstream, lokasi berkas, dan
  tampilan terminal.

Nama dan fungsi skrip dapat berubah. Periksa dokumentasi serta kode sumber yang
sesuai sebelum melakukan perubahan atau pengujian. README ini menjelaskan
struktur repository, bukan panduan operasional untuk mengeksploitasi sistem.

## Batasan dan Interpretasi Data

- Profil berlaku untuk build dan kondisi yang dicatat di dalamnya; jangan
  menganggapnya cocok untuk versi, distribusi, arsitektur, atau konfigurasi lain.
- Status profil adalah catatan hasil riset, bukan advisori vendor ataupun bukti
  bahwa sistem lain rentan atau aman.
- Versi PHP saja tidak cukup untuk menyimpulkan dampak. Periksa status
  dukungan, pembaruan keamanan, dan kemungkinan backport dari vendor distribusi.
- Informasi dalam katalog dan profil dapat berubah atau belum lengkap. Cocokkan
  dengan sumber resmi sebelum mengambil keputusan keamanan.

## Penggunaan yang Bertanggung Jawab

Pengujian aktif hanya boleh dilakukan di lingkungan laboratorium terisolasi
yang Anda miliki atau yang secara eksplisit tercakup dalam izin tertulis.
Sebelum pengujian, sepakati ruang lingkup, jadwal, pemantauan, dan prosedur
pemulihan. Siapkan snapshot atau backup serta pembatasan jaringan yang sesuai.

Pengujian dapat mengirim request berukuran besar, menyebabkan kehabisan memori
(*out-of-memory*), dan menghentikan proses child Apache. Mode saturasi worker
jarak jauh tidak boleh digunakan pada infrastruktur pihak ketiga. Hentikan
pengujian jika layanan menjadi tidak stabil dan ikuti prosedur pemulihan lab.

Untuk memastikan layanan terlindungi, utamakan inventarisasi versi dari sistem
yang Anda kelola, advisori resmi, dan pembaruan yang direkomendasikan vendor.
Pantau log aplikasi dan web server untuk gangguan atau konsumsi resource yang
tidak normal.

## Pelaporan

Untuk melaporkan masalah pada skrip, profil, atau dokumentasi, ikuti petunjuk di
[`KEAMANAN.md`](./KEAMANAN.md). Jangan sertakan hostname, alamat IP, cookie,
kredensial, atau data yang diperoleh dari sistem yang bukan milik Anda.