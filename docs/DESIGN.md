# Desain Installer Xray All-in-One (`bin/install`)

Dokumen ini menjelaskan desain dan keputusan arsitektur installer (implementasi modular di `bin/` + `lib/`). Target pembaca: siapapun yang ingin memahami *mengapa* script berperilaku seperti ini sebelum menyentuh kodenya.

---

## 1. Tujuan

Satu perintah menjadikan server Ubuntu/Debian menjadi *proxy gateway* Xray-core yang langsung dipakai, dengan **hanya satu input**: `DOMAIN` (untuk sertifikat Let's Encrypt). Setelah domain dimasukkan, seluruh instalasi berjalan otomatis hingga mencetak link share siap-import.

Hasil akhir menyediakan **24 kombinasi** protokol × transport:

| | TCP | WebSocket | HTTPUpgrade | XHTTP | gRPC |
|---|---|---|---|---|---|
| **VLESS** | ✔ | ✔ | ✔ | ✔ | ✔ |
| **VMess** | ✔ | ✔ | ✔ | ✔ | ✔ |
| **Trojan** | ✔ | ✔ | ✔ | ✔ | ✔ |

- **Port 443 (TLS)**: semua 15 kombinasi.
- **Port 80 (HTTP, tanpa TLS)**: 9 kombinasi (ws, httpupgrade, xhttp untuk tiap protokol).

---

## 2. Prinsip desain (keputusan yang ditegaskan)

Keputusan berikut adalah *requirement eksplisit* dan disengaja:

1. **Paksa timpa; tanpa backup / tanpa rollback.**
   - Saat installer dijalankan ulang, `users.json` dan `config.json` **langsung ditimpa** dengan kredensial baru.
   - Tidak ada salinan cadangan, tidak ada prompt konfirmasi, tidak ada pemulihan otomatis saat gagal.
   - Konsekuensi yang disadari: UUID/password/path lama *mati* seketika; semua user non-admin hilang. Hanya peringatan teks yang dicetak.
   - Pengecualian yang eksplisit: `menu_update_users` (menu) memakai temp-copy **transien** selama operasi untuk rollback bila `xray-config build` gagal — ini mekanisme atomicity tulis-config, bukan backup; file-nya tidak pernah menetap di disk.
2. **Tanpa verifikasi checksum.**
   - Unduhan (instalasi-cert ikut *installer resmi XTLS* dan *paket nginx.org*) dipercaya berdasarkan HTTPS/TLS; tidak ada cek sha256/pin versi.
3. **Semua acak.** UUID, password trojan, path, nama service gRPC, dan **port internal** dibangkitkan acak tiap run.
4. **IPv4 only.** IPv6 dinonaktifkan lewat `sysctl`; Xray bind `0.0.0.0`.
5. **Interaktif minimal** — satu-satunya input adalah domain; sisanya otomatis.

---

## 3. Arsitektur jaringan

```
Internet
 ├─ :443 ── Xray (VLESS-TCP-TLS entrypoint + fallbacks) ── TLS termination
 │           ├─ VLESS utuh            -> ditangani langsung oleh entry (tanpa fallback)
 │           ├─ ALPN kustom "vmess"   -> inbound internal vmess-tcp   (127.0.0.1:IP)
 │           ├─ ALPN h2               -> inbound internal trojan-tcp  (127.0.0.1:IP)
 │           │                          └─ {gRPC, XHTTP, bukan-trojan} -> nginx h2c.sock
 │           ├─ path ws  (http/1.1)   -> inbound internal ws
 │           ├─ path httpupgrade      -> inbound internal httpupgrade
 │           └─ sisanya (probe)       -> nginx h1.sock  (decoy)
 │
 ├─ :80 ── Xray (VLESS plain-HTTP entrypoint + fallbacks)
 │           ├─ path ws/httpupgrade   -> inbound internal ws/httpupgrade
 │           └─ sisanya (xhttp/ACME/decoy) -> nginx h1.sock
 │
 └─ Nginx ── hanya listen di unix socket:
              /dev/shm/h1.sock  (http/1.1) -> decoy, webroot ACME, proxy xhttp
              /dev/shm/h2c.sock (http/2)   -> grpc_pass, proxy xhttp dari :443
   (Nginx TIDAK listen di port 80/443 — keduanya dipegang Xray.)
```

### Mengapa Nginx?

Xray hanya bisa menyortir koneksi lewat `fallback` berbasis **path (http/1.1)** atau **ALPN**. gRPC dan XHTTP memakai HTTP/2, yang tidak bisa dicocokkan dengan path fallback. Solusinya: seluruh traffic `h2` diarahkan ke `alpn:h2 → trojan-tcp → nginx`, lalu nginx yang tahu `grpc_pass` / `proxy_pass` meneruskan ke inbound internal yang tepat. Nginx sekaligus menjadi **decoy** (situs palsu) dan pelayan challenge ACME via `h1.sock`.

### Bagaimana membedakan VMess-TCP tanpa header HTTP

Entry 443 adalah inbound **VLESS**, jadi VMess/Trojan harus dipilah lewat *fallback*. Trojan-TCP disortir lewat `alpn=h2`. VMess-TCP menggunakan **ALPN kustom `"vmess"`** (bukan header HTTP path). Syarat di sisi klien: `alpn=vmess` **dan `fingerprint=unsafe`** — karena uTLS Chrome bawaan memaksa ALPN `h2,http/1.1`, sehingga satu-satunya cara mengirim ALPN kustom adalah dengan memakai Go TLS standar (`unsafe`).

### Port internal (127.0.0.1)

14 inbound internal acak-unik di **40000–60000**, hanya bind localhost, dan wajib `acceptProxyProtocol` (PROXY protocol) — jadi tidak bisa diakses langsung dari internet. Urutan: `tcp → ws → httpupgrade → xhttp → grpc`.

- `acceptProxyProtocol` memakai kebijakan **REQUIRE** di Xray; koneksi tanpa header PROXY protocol langsung ditolak → ini sengaja membatasi akses hanya lewat entry Xray.

---

## 4. Sumber paket

| Komponen | Sumber | Catatan |
|---|---|---|
| Xray-core | rilis resmi upstream (XTLS/Xray-install) | tanpa pin versi / checksum |
| Nginx | **repo resmi nginx.org** (bukan paket apt distro) | signing key + `deb [signed-by=...]`, `Pin-Priority` 1000 agar mengalahkan paket distro; dukungan arch: amd64/arm64/i386/ppc64el/s390x |
| curl, openssl, ca-certificates, jq, gpg, certbot, iproute2, lsb-release | apt distro | `iproute2` wajib utk `ss`; `lsb-release` fallback deteksi codename |

Nginx dari nginx.org otomatis dijalankan apt dan memuat `conf.d/default.conf` (listen 80) yang **harus dihapus** — default site ini akan merebut port 80 dari Xray. Nginx di-*stop* sementara sampai config `xray.conf` ditulis, lalu di-start ulang.

---

## 5. Alur instalasi

1. **Pra-cek**: root, systemd, distro (Ubuntu/Debian), lalu log ditulis ke `/var/log/xray-installer.log`.
2. **Input domain** (satu-satunya prompt) + validasi format.
3. **Instalasi dependensi** (`apt-get update` + paket inti + `iproute2`/`lsb-release`).
4. **Validasi (pra-cek)**: koneksi internet, DNS domain terselesaikan & searah IP publik server, port 80/443 bebas (selain yang dipegang Xray).
5. **Timezone Asia/Jakarta**: timezone sistem diatur ke `Asia/Jakarta`, lalu mode **IPv4 only** diterapkan melalui `/etc/sysctl.d/99-disable-ipv6.conf` + `sysctl`.
6. **Pasang nginx** dari repo nginx.org, lalu **pasang Xray-core** dari upstream + override unit systemd (user `xray`, akses sertifikat via grup — lihat §6).
7. **Nginx**: tulis `xray.conf` (socket h1/h2c), `nginx -t`, start.
8. **Sertifikat Let's Encrypt** (penerbitan awal standalone — nginx belum berjalan; renewal kemudian lewat webroot) bila belum ada; jika sudah ada, dipakai apa adanya.
9. **Bangun `config.json`** dengan `jq` (entry 443, entry 80, inbound internal, fallbacks, port/path acak).
10. **Validasi config** `xray run -test`, pasang hook renewal (webroot — tanpa stop/start service), `systemctl enable --now xray`.
11. **Cleanup harian**: `xray-cleanup.timer` menjalankan `xray-cleanup` (dari `bin/xray-cleanup`) setiap pukul 00:00 waktu `Asia/Jakarta`.
12. **Pasang CLI**: `xray-config` (dari `bin/xray-config`) menjadi `/usr/local/bin/xray-config`, `menu` (dari `bin/menu`) menjadi `/usr/local/bin/menu`, beserta `lib/` ke `/usr/local/lib/xray-installer`.
13. **Output**: cetak link share (`vless://`, `vmess://`, `trojan://`) ke terminal **dan** ke file log; setelah setup selesai menu dapat dibuka dengan mengetik `menu`.

### Rerun

Jalankan ulang → peringatan "kredensial baru, link lama mati" → `users.json` **ditimpa paksa** dengan set acak baru (hanya user `admin`) → `config.json` dibangun ulang. Tanpa backup, tanpa konfirmasi, tanpa rollback otomatis; tetap tanpa checksum unduhan.

---

## 6. Keamanan & izin file

- `config.json` → `0640 xray:xray` (berisi UUID/password; tidak readable umum).
- `/etc/nginx/conf.d/xray.conf` → `0640 root:www-data`.
- `users.json` → `0600` root; direktori `/etc/xray-users` → `0700`.
- Tidak menulis file konfigurasi klien ke disk — hanya link di terminal + log.
- Direktori `/var/log/xray`, socket nginx di `/dev/shm`.
- Inbound internal hanya di `127.0.0.1` + `acceptProxyProtocol` (REQUIRE) → tidak terbuka ke internet.
- Service systemd Xray berjalan sebagai user `xray` (bukan `nobody`) dengan `CAP_NET_BIND_SERVICE` (tanpa `CAP_DAC_READ_SEARCH`). Akses baca sertifikat LE diberikan via grup: `chgrp xray` + `chmod 0640` pada `fullchain.pem`/`privkey.pem` (dan `0750` pada direktori `live/`/`archive/`), diterapkan ulang oleh deploy hook renewal.
- Renewal LE via **webroot** (`/var/www/certbot`, dilayani nginx h1.sock lewat fallback Xray): Xray tetap memegang port 80, tidak ada `pre_hook`/`post_hook` stop/start; deploy hook reload xray + terapkan ulang izin sertifikat. Penerbitan awal tetap standalone (nginx belum berjalan saat itu).

---

## 7. Nilai default yang disengaja

| Hal | Nilai |
|---|---|
| Domain | satu-satunya input; validasi format (huruf/angka/titik/tanda hubung) |
| Kredensial | acak tiap run (`/proc/sys/kernel/random/uuid`, `openssl rand`; password trojan 8 byte / 64-bit hex — 16 karakter) |
| Path / nama gRPC | acak penuh, **tanpa prefix** `/vl-` `/vm-` `/tr-` (agar tidak membocorkan protokol) |
| Port internal | acak unik 40000–60000 |
| Port publik | 443 (TLS) & 80 (HTTP) |
| Mode jaringan | IPv4 only |
| Nginx | repo resmi nginx.org, listen hanya di unix socket |
| Log | `/var/log/xray-installer.log` (ditimpa tiap run — keputusan desain: log run sebelumnya hilang; konteks diagnosa run lama tidak dipertahankan) |

---

## 8. Multi-user & menu (`bin/menu`)

Sejak versi multi-user, `config.json` **tidak lagi dibangun inline di installer**, melainkan oleh builder bersama **`xray-config`** (dari `bin/xray-config`) dari sumber kebenaran tunggal **`/etc/xray-users/users.json`**:

```json
{
  "site": { "domain", "cert_file", "key_file", "h1_sock", "h2c_sock",
             "ports": {tc_vm,tc_tr,ws_*,hu_*,xh_*,gr_*},
             "paths": {vl_ws,vm_ws,tr_ws,vl_hu,vm_hu,tr_hu,vl_xh,vm_xh,tr_xh},
             "grpc":  {vl,vm,tr} },
  "users": [ { "name", "uuid", "trojan", "protocols": ["vless","vmess","trojan"] } ]
}
```

- `bin/install` **menulis** `users.json` (site params + user awal `admin`), lalu memanggil `xray-config build` dan `xray-config links admin`.
- `bin/menu` membaca/mengedit `users.json` (tambah/hapus user, pilih protokol), memanggil `xray-config build`, lalu `systemctl reload xray`.
- Setiap user hanya masuk ke inbound protokol yang aktif di `protocols` (subset vless/vmess/trojan); kredensial dibangkitkan acak saat tambah user.
- User `admin` adalah akun awal installer: tetap disimpan di `users.json` dan tetap aktif di Xray, tetapi sengaja disembunyikan dari daftar, cetak link, dan operasi hapus di menu untuk mencegah penghapusan tidak sengaja.
- Link share dicetak oleh `xray-config links <nama>` — satu sumber format, dipakai installer untuk admin dan menu untuk user non-admin.
- `xray-config` dipasang ke `/usr/local/bin/xray-config` oleh installer.
- `menu` dipasang sebagai `/usr/local/bin/menu`, sehingga setelah instalasi cukup ketik `menu` dari shell (karena `/usr/local/bin` berada di PATH standar).

### Masa aktif / kuota

Masa aktif **sudah diimplementasikan** (lihat `expires` di atas): ditetapkan per-user dalam hari saat tambah. Enforcement **hanya via timer harian** — build (dari menu/installer) TIDAK memfilter atau me-prune user expired. Akun dibersihkan dari config dan `users.json` setiap pukul 00:00 waktu `Asia/Jakarta` lewat **timer `xray-cleanup`**:

Konsekuensi sengaja: user yang melewati batas tetap aktif sampai timer 00:00 menembak (±24 jam window). Ini satu-satunya titik enforcement.

```text
xray-cleanup.timer (setiap pukul 00:00 Asia/Jakarta)
        └── xray-cleanup.service
                └── /usr/local/bin/xray-cleanup
                        ├── prune expired dari users.json (flock)
                        └── xray-config build -> reload xray
```

Logika masa aktif (prune expired) sengaja **dipisah** ke script tersendiri `xray-cleanup`, sehingga `xray-config` hanya membangun config & mencetak link. Penulisan `users.json` oleh menu, installer, dan cleanup diproteksi satu **lock bersama** `/etc/xray-users/.lock` (`flock`): menu & installer blocking, cleanup non-blocking (skip jika sedang dipakai). Timer ini dipasang installer dan dihapus uninstaller. Jadwalnya setiap pukul 00:00 waktu `Asia/Jakarta`.

Menu **Perpanjang** menambah hari pada masa aktif user (dihitung dari tanggal akhir saat ini; user tanpa batas mulai dihitung dari hari ini), lalu rebuild config + reload. Kuota trafik belum ada; untuk itu struktur tetap siap menerima field tambahan.

---

## 9. Batasan & catatan

- **Port 80 = HTTP polos**: trafik proxy terlihat sebagai HTTP biasa → rentan DPI/blocking ISP. Kombinasi 443 tetap yang paling aman.
- **Rerun mematikan link lama** — paksa timpa, tanpa backup, tanpa rollback (keputusan desain).
- **Tanpa checksum** unduhan (keputusan desain; mengandalkan HTTPS).
- **Perilaku decoy fallback (disengaja)**: koneksi yang tidak cocok dengan path/ALPN mana pun jatuh ke nginx `h1.sock` (situs palsu) tanpa logging khusus. Konsekuensi: klien dengan konfigurasi salah (mis. ALPN tidak sesuai) hanya melihat "server web biasa" — stealth bagus, tapi troubleshooting sisi klien sulit. Saat user melapor gagal-koneksi padahal service aktif, cek dulu kecocokan ALPN/path di link share vs config.
- xhttp hanya melalui HTTP/2 (h3/QUIC tidak diaktifkan).
- WebSocket, VMess, Trojan, dan gRPC ditandai *deprecated* oleh Xray (arah masa depan: VLESS + xhttp); semuanya tetap berfungsi.
- Firewall provider wajib membuka **TCP 80** dan **TCP 443**.
- Panduan tidak mengubah aturan ufw/iptables apa pun.