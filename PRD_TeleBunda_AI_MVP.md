PRODUCT REQUIREMENTS DOCUMENT

TeleBunda AI

Aplikasi telehealth edukasi kehamilan dan konsultasi chat bidan | MVP Android

| Identitas dokumen | Keterangan                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------- |
| Versi             | 1.0 - baseline pengembangan                                                                       |
| Tanggal           | 2 November 2026                                                                                   |
| Status            | Disetujui sebagai baseline perencanaan dan implementasi MVP                                      |
| Platform          | Satu APK Flutter untuk pasien dan bidan                                                           |
| Stack             | Flutter (Dart) \| Laravel (PHP) \| Firebase Auth + Cloud Firestore \| Gemini API \| Mayar Sandbox |
| Tim               | Fida: PM, UI/UX, QA, dokumentasi; Rinanta: frontend Flutter; Iqbal: Laravel, Firebase, AI, Mayar  |

Keputusan inti: tidak ada video call. Chat AI gratis. Konsultasi bidan dilakukan melalui chat teks selama 30 menit dengan pembayaran melalui Mayar Sandbox. Hasil konsultasi disusun oleh bidan, bukan AI.

# 1. Ringkasan Produk

TeleBunda AI membantu pasien mendapatkan informasi awal seputar kehamilan melalui chatbot AI, memesan jadwal bidan, membayar konsultasi di lingkungan sandbox, melakukan konsultasi berbasis chat, dan melihat ringkasan hasil serta riwayat. Bidan menggunakan APK yang sama tetapi mendapatkan dashboard dan kewenangan berbeda.

# 2. Sasaran, Ruang Lingkup, dan Batasan

- Sasaran MVP: demo end-to-end untuk 1 pasien dan 1 bidan, dengan minimal 1 transaksi sandbox dan 1 sesi konsultasi selesai.
- Dalam lingkup: register/login, role, dashboard pasien/bidan, chatbot Gemini, profil & jadwal bidan, booking, Mayar Sandbox, chat teks, timer sesi 30 menit, catatan hasil, dan riwayat.
- Di luar lingkup MVP: video/audio call, pengiriman obat, e-resep formal, admin web, konsultasi 24 jam, sistem rekam medis rumah sakit, dan transaksi uang sungguhan.
- Keselamatan: AI hanya edukasi, bukan diagnosis atau pengganti pemeriksaan. Keluhan darurat harus diarahkan ke layanan medis segera; bidan menyarankan tindak lanjut sesuai kompetensi dan kewenangan.

# 3. Pengguna dan Role

| Role                    | Cara memperoleh akun                                                                             | Hak utama                                                                                     |
| ----------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Pasien                  | Daftar mandiri; memilih "Pasien" pada UI                                                         | Chat AI, cari bidan, booking, bayar sandbox, chat sesi sendiri, lihat hasil sendiri           |
| Bidan                   | Dapat memilih "Bidan" pada UI, tetapi akses hanya jika akun sudah diverifikasi/admin-provisioned | Lihat booking yang ditujukan kepadanya, konfirmasi, mulai sesi, chat, tulis hasil, selesaikan |
| Admin teknis (tanpa UI) | Proses admin terbatas melalui Firebase Console atau skrip/command Laravel yang hanya dijalankan server | Verifikasi akun bidan, seeding jadwal dan pemulihan data uji; tidak tersedia sebagai registrasi mandiri |

Catatan keamanan: pada registrasi, pilihan "Bidan" hanya membuat permohonan dengan status pending_verification; pilihan itu tidak memberikan kewenangan bidan. Role dan status verifikasi ditetapkan/diubah server, dan hanya bidan yang disetujui admin dapat memakai fitur bidan. Login memuat role tepercaya dari backend dan mengarahkan pengguna otomatis. Pilihan role saat login, jika tetap ditampilkan, hanya preferensi tampilan dan tidak digunakan untuk otorisasi.

# 4. Alur Bisnis End-to-End

## 4.1 Alur Pasien

1. Buka APK > halaman Selamat Datang > pilih Masuk atau Daftar.
2. Daftar: pilih role Pasien, isi identitas minimum; login: pengguna dapat memilih jenis akun sebagai preferensi UI, tetapi role sebenarnya diverifikasi dari akun.
3. Dashboard Pasien menampilkan tombol "Chat AI Gratis", "Cari Bidan", booking terdekat dan riwayat.
4. Chat AI (opsional): tanya jawab edukasi kehamilan; tersedia CTA "Konsultasi Bidan".
5. Pilih bidan, lihat profil dan slot tersedia, tentukan tanggal/jam, isi keluhan singkat, konfirmasi booking.
6. Backend menahan slot sementara dan membuat booking awaiting_payment; pasien mengisi nomor ponsel, lalu Laravel membuat invoice Mayar Sandbox dengan tarif dan waktu kedaluwarsa dari data server.
7. Pasien membayar melalui tautan checkout Mayar. Notifikasi `payment.received` hanya menjadi pemicu; Laravel mengambil status invoice langsung dari API Mayar dan mencocokkan invoice serta nominal sebelum mengubah booking menjadi paid_pending_midwife.
8. Bidan mengonfirmasi booking; status menjadi confirmed. Pasien melihat jadwal dan tombol chat terkunci hingga sesi dibuka.
9. Pada waktu sesi, bidan memulai sesi dan pasien masuk chat; timer konsultasi 30 menit dihitung oleh server berdasarkan started_at.
10. Bidan menulis ringkasan keluhan, saran, rekomendasi vitamin/suplemen jika sesuai kewenangan dan diperlukan, tindak lanjut/rujukan; bidan menekan Selesaikan.
11. Pasien melihat hasil dan riwayat; chat sesi selesai berubah menjadi hanya-baca.

## 4.2 Alur Bidan

12. Login sebagai akun bidan terverifikasi dan masuk Dashboard Bidan.
13. Lihat daftar booking berbayar dengan status menunggu konfirmasi, jadwal dan ringkasan keluhan.
14. Terima/tolak dengan alasan; booking yang ditolak masuk alur bantuan atau penjadwalan ulang/penanganan refund sandbox.
15. Menunggu jadwal; tombol Mulai Konsultasi muncul pada waktu yang diizinkan.
16. Bidan membuka chat, membalas pesan pasien selama sesi 30 menit.
17. Setelah sesi, isi form hasil konsultasi; simpan, konfirmasi dan tutup sesi.
18. Lihat konsultasi selesai dan catatan sebelumnya dalam riwayat.

# 5. Aturan Bisnis dan State Machine

| Objek                   | Status / aturan                                                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Booking                 | Alur normal: awaiting_payment -> paid_pending_midwife -> confirmed -> active -> completed. Alur akhir/pengecualian: awaiting_payment -> payment_failed / expired / cancelled; paid_pending_midwife -> rejected; confirmed -> no_show. Setiap transisi divalidasi backend. |
| Pembayaran              | created / pending / paid / failed / expired / paid_requires_reconciliation / refunded_test (jika didukung skenario sandbox); paid hanya dari verifikasi server |
| Slot | Alur status `available -> held -> booked`; ditahan secara atomik 15 menit sejak booking dibuat, satu slot hanya boleh memiliki satu booking aktif. Status `held` memakai `hold_booking_id` dan `hold_expires_at`. Hold dilepas ke `available` saat pembayaran belum terverifikasi ketika kedaluwarsa. Setelah pembayaran terverifikasi saat hold masih dimiliki booking, slot menjadi `booked`. Scheduler backend memeriksa hold kedaluwarsa sekurangnya setiap menit dan hanya melepas slot bila booking masih `awaiting_payment` serta slot masih menunjuk booking tersebut. Durasi dapat dikonfigurasi server (`BOOKING_HOLD_MINUTES`, default 15). Pembayaran valid yang datang setelah hold dilepas direkonsiliasi dan tidak otomatis mengambil slot kembali. |
| Tarif konsultasi        | `midwives/{uid}.consultation_fee` adalah integer Rupiah positif yang hanya ditetapkan proses admin tepercaya. Saat booking, backend membaca tarif ini dan menyalinnya ke `bookings.amount`; klien tidak boleh mengirim atau menentukan tarif. Bidan tanpa tarif valid belum dapat dipesan. |
| Konsultasi              | Sesi normal 30 menit; started_at dan ends_at ditetapkan backend; hanya 1 sesi aktif per booking. |
| Keterlambatan           | Toleransi 10 menit adalah jendela bidan untuk memulai sesi dari waktu jadwal; setelah itu tandai no_show dan lakukan penanganan/penjadwalan ulang manual. Toleransi tidak memperpanjang durasi sesi. |
| Timer                   | Notifikasi pada 5 menit tersisa. Saat ends_at tercapai, backend menolak pesan baru; sesi tetap perlu difinalisasi bidan dengan hasil konsultasi. |
| Chat                    | Hanya peserta booking paid+confirmed+active yang boleh mengirim pesan sebelum ends_at; setelah completed hanya baca. Pada akhir timer, pengiriman pesan dikunci meskipun bidan belum menyimpan hasil. |
| Hasil                   | Bidan wajib mengisi ringkasan dan tindak lanjut sebelum finalisasi; anjuran suplemen opsional                                               |
| Penolakan setelah bayar | Tidak boleh menghilangkan transaksi; lakukan pengaturan jadwal ulang/refund sesuai dukungan Mayar dan kebijakan yang ditentukan             |

# 6. Kebutuhan Fungsional (Acceptance Criteria)

| ID    | Kebutuhan dan kriteria diterima                                                                 |
| ----- | ----------------------------------------------------------------------------------------------- |
| FR-01 | Registrasi pasien dengan email/password berhasil; role tidak bisa diedit sendiri.               |
| FR-02 | Akun bidan yang belum diverifikasi ditolak untuk fitur bidan.                                   |
| FR-03 | Setelah login, dashboard sesuai role tepercaya; akses silang menghasilkan 403.                  |
| FR-04 | Chat AI menerima pesan dan respons edukasi, menampilkan disclaimer dan penanganan error.        |
| FR-05 | Daftar bidan dan jadwal hanya menampilkan slot valid yang tersedia.                             |
| FR-06 | Booking membuat hold atomik; satu slot tidak bisa terjual ke dua pasien.                        |
| FR-07 | Mayar Sandbox invoice dibuat oleh Laravel dengan tarif booking dari server; Flutter hanya membuka tautan checkout dan tidak dapat menandai pembayaran lunas. |
| FR-08 | Notifikasi `payment.received` diterima di endpoint webhook beralamat rahasia; Laravel memverifikasi invoice dan nominal langsung ke Mayar. Pemrosesan idempoten; pembayaran setelah hold dilepas memerlukan rekonsiliasi manual. |
| FR-09 | Bidan hanya melihat dan menerima booking atas namanya yang sudah dibayar.                       |
| FR-10 | Chat pasien-bidan hanya bisa saat sesi aktif; kedua perangkat menerima pesan realtime.          |
| FR-11 | Timer 30 menit dan kunci pesan dikontrol server, tidak bergantung jam HP.                       |
| FR-12 | Bidan menyimpan ringkasan dan menyelesaikan konsultasi; pasien hanya membaca hasil miliknya.    |
| FR-13 | Riwayat menampilkan booking selesai beserta tanggal, bidan, dan hasil.                          |
| FR-14 | Loading, kosong, gagal jaringan, pembayaran pending/gagal dan tidak hadir punya state UI jelas. |

# 7. Arsitektur Teknis

**Keputusan teknis implementasi MVP (disepakati tim):**

- **Autentikasi dan role:** Flutter membuat akun/melakukan login melalui Firebase Authentication. Setiap permintaan API mengirim `Authorization: Bearer <Firebase ID token>`; Laravel memverifikasi token dan membaca profil serta role tepercaya dari Firestore. Endpoint registrasi menerima pasien atau permohonan bidan; backend menetapkan role/status yang diizinkan dan tidak menerima `verified` atau role istimewa dari klien. Hanya proses admin tepercaya yang dapat memverifikasi bidan.
- **Hold dan pembayaran terlambat:** `POST /api/bookings` menjalankan pembacaan slot, pemeriksaan bidan aktif/terverifikasi dan tarif, pembuatan booking `awaiting_payment`, serta perubahan slot menjadi `held` dalam satu transaksi Firestore. Jika belum ada pembayaran terverifikasi saat hold habis, scheduler backend (wajib dijalankan melalui `php artisan schedule:run` setiap menit atau proses `php artisan schedule:work`) menandai booking `expired` dan melepas slot dalam transaksi yang memeriksa kembali kepemilikan hold. Jika notifikasi pembayaran valid tiba setelah slot dilepas/booking expired, jangan mengambil slot yang mungkin sudah dipesan orang lain; tandai untuk rekonsiliasi dan penanganan manual/refund sandbox sesuai dukungan Mayar. Webhook diproses idempoten.
- **Tarif booking:** proses admin tepercaya mengisi `midwives/{uid}.consultation_fee` sebagai integer Rupiah positif. Field ini boleh ditampilkan di katalog; backend selalu membaca ulang nilainya di dalam transaksi booking dan menyalinnya ke `bookings.amount`. Tarif dari request klien diabaikan. Bidan tanpa tarif valid tidak dapat dipesan sampai tarif diatur.
- **Penolakan dan no-show setelah pembayaran:** utamakan penjadwalan ulang yang disetujui pasien. Jika tidak dapat dijadwalkan ulang, catat kasus untuk bantuan/refund sandbox secara manual, bergantung pada kemampuan provider; MVP tidak menjanjikan refund otomatis sebelum kemampuan Mayar dikonfirmasi. Tidak ada pembayaran uang sungguhan pada MVP.
- **Waktu sesi:** bidan hanya dapat memulai pada/setelah waktu slot dan paling lambat 10 menit sesudahnya. Backend menetapkan `started_at` dan `ends_at = started_at + 30 menit`; waktu perangkat hanya untuk tampilan countdown. Setelah `ends_at`, backend menolak pesan baru, tetapi bidan tetap dapat menyimpan hasil untuk menutup sesi.
- **Chat realtime dan otorisasi:** rekomendasi MVP adalah Laravel memvalidasi setiap pesan (identitas peserta, booking berstatus active, dan waktu sebelum `ends_at`) lalu menulis ke Firestore melalui Admin SDK; Flutter menerima pesan realtime dengan listener Firestore. Security Rules mengizinkan pembacaan hanya untuk pasien/bidan yang tercatat sebagai peserta sesi dan menolak penulisan langsung dari klien. Riwayat pesan tetap dapat dibaca peserta setelah sesi selesai.
- **Privasi chat AI:** jangan menyimpan isi percakapan AI ke Firestore atau log server pada MVP; tampilkan percakapan hanya selama sesi aplikasi berjalan. Jangan mencatat teks keluhan/chat dalam log operasional. Retensi riwayat konsultasi bidan mengikuti kebutuhan hasil konsultasi dan akses terbatas sesuai role.
- **Sumber kebenaran status:** UI tidak boleh mengubah status pembayaran, booking, verifikasi, timer, ataupun kelayakan chat. Perubahan tersebut hanya berasal dari endpoint/backend atau webhook terverifikasi.

Keputusan pada bagian ini menjadi baseline implementasi MVP. Untuk chat realtime, pesan ditulis melalui Laravel dan dibaca realtime dari Firestore; penulisan langsung dari klien bukan jalur implementasi MVP.

Flutter (Android) -> Laravel REST API (otorisasi, aturan bisnis, Gemini, Mayar) -> Firebase Admin SDK/Firestore. Firebase Authentication melakukan autentikasi pengguna; Flutter mengirim Firebase ID token melalui Authorization: Bearer ke Laravel. Laravel memverifikasi token dan role tepercaya. Firestore menjadi sumber data utama untuk user, booking, slot, chat, hasil konsultasi dan transaksi. Untuk chat real-time, Flutter dapat memakai Firestore listener langsung dengan Security Rules ketat; tulis pesan hanya untuk peserta sesi aktif sesuai status yang dikendalikan Laravel, atau gunakan API Laravel untuk penulisan jika aturan keamanan lebih mudah dikontrol demikian.

Laravel adalah backend pusat, bukan database SQL tambahan. Perlu PHP 8.x, Composer, Firebase Admin SDK untuk PHP yang kompatibel, kredensial service account server, dan endpoint HTTPS yang dapat diakses webhook Mayar. Jangan memasukkan service account, API key Gemini, ataupun Mayar secret ke APK atau Git.

# 8. Struktur Koleksi Firestore (usulan awal)

| Collection / subcollection              | Field utama                                                                                     |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| users/{uid}                             | uid, name, email, role, verified, created_at                                                    |
| midwives/{uid}                          | display_name, credential_label, bio, active, verification_status, consultation_fee (Rupiah integer) |
| slots/{slotId}                          | midwife_id, start_at, end_at, status, hold_booking_id, hold_expires_at                          |
| bookings/{bookingId}                    | patient_id, midwife_id, slot_id, slot_start_at, complaint, amount, status, payment_id, created_at, hold_expires_at |
| payments/{invoiceId}                    | provider, environment, invoice_id, transaction_id, booking_id, patient_id, amount, checkout_url, status, created_at, hold_expires_at, verified_at, reconciliation_reason_optional |
| consultations/{consultationId}          | booking_id, patient_id, midwife_id, started_at, ends_at, status, completed_at                   |
| consultations/{id}/messages/{messageId} | sender_id, text, sent_at, type=text                                                             |
| consultation_results/{id}               | consultation_id, summary, advice, supplement_note_optional, follow_up, saved_by, completed_at   |
| ai_chats/{uid}/messages/{messageId}     | Tidak dibuat/disimpan pada MVP; percakapan AI hanya sementara di aplikasi                       |

Indeks yang diperlukan: booking by patient/date; booking by midwife/status/date; booking by status/hold_expires_at untuk pemrosesan hold kedaluwarsa; slots by midwife/date/status; messages by sent_at. Gunakan timestamp UTC di database dan tampilkan WIB pada antarmuka.

# 9. Kontrak API Laravel (rancangan, bukan endpoint resmi Mayar/Gemini)

| Method / Endpoint                     | Akses / Tindakan                                                        |
| ------------------------------------- | ----------------------------------------------------------------------- |
| POST /api/auth/register               | Pengguna terautentikasi Firebase; membuat profil pasien atau permohonan bidan pending. Backend memvalidasi jenis pendaftaran dan menetapkan role/status yang diizinkan. |
| GET /api/me                           | Semua; role dan profil                                                  |
| GET /api/midwives                     | Pasien; daftar bidan aktif                                              |
| GET /api/midwives/{id}/slots          | Pasien; slot tersedia                                                   |
| GET /api/midwife/bookings             | Bidan terverifikasi; daftar booking milik sendiri                      |
| POST /api/bookings                    | Pasien; body `slot_id` dan `complaint`; buat booking `awaiting_payment` + hold atomik 15 menit. `amount` diambil backend dari tarif bidan, tidak diterima dari klien. |
| GET /api/bookings/{id}                | Pasien pemilik booking; status dan data booking terbaru dari backend    |
| POST /api/bookings/{id}/checkout      | Pasien; body nomor ponsel; buat invoice Mayar dari nominal booking di server |
| POST /api/webhooks/mayar/{secret}     | Mayar; callback HTTPS dengan URL rahasia; invoice dan nominal selalu diverifikasi ulang melalui API Mayar |
| POST /api/bookings/{id}/accept        | Bidan terverifikasi pemilik booking; konfirmasi transaksi atomik        |
| POST /api/bookings/{id}/reject        | Bidan pemilik booking; alasan wajib; refund Mayar ditangani manual      |
| POST /api/consultations/{id}/start    | Bidan; mulai sesi sesuai jadwal                                         |
| GET /api/consultations/{id}           | Peserta; status dan timer                                               |
| POST /api/consultations/{id}/messages | Peserta; backend memvalidasi sesi aktif dan waktu, lalu menulis pesan    |
| POST /api/consultations/{id}/complete | Bidan; simpan hasil + complete                                          |
| POST /api/ai/chat                     | Pasien; Laravel meneruskan permintaan ke Gemini                         |
| GET /api/history                      | Pasien/bidan; hasil dan riwayat yang diizinkan                          |

Endpoint Mayar sebenarnya, jenis pembayaran, response dan status harus mengikuti dokumentasi Mayar v2; tabel ini hanya kontrak API internal Laravel. Dokumentasi webhook Mayar yang digunakan tidak mendeskripsikan signature untuk diverifikasi, sehingga endpoint memakai URL rahasia yang disimpan di `MAYAR_WEBHOOK_SECRET` dan tidak mempercayai isi callback sebagai bukti pembayaran. Callback `payment.received` hanya memicu Laravel untuk mengambil detail invoice secara server-to-server. Endpoint checkout dan seluruh endpoint bisnis memerlukan autentikasi Firebase; endpoint webhook memerlukan URL rahasia dan verifikasi status langsung ke Mayar. Setiap endpoint memeriksa kepemilikan/role di backend, bukan hanya di UI.

Untuk konfigurasi lokal, isi `MAYAR_ENVIRONMENT=sandbox`, `MAYAR_API_KEY`, dan `MAYAR_WEBHOOK_SECRET` di `backend/.env`; jangan menaruh API key di Flutter, Git, atau chat. Webhook Mayar harus menunjuk ke URL HTTPS publik yang berakhir dengan `/api/webhooks/mayar/{nilai-MAYAR_WEBHOOK_SECRET}`.

# 10. Daftar Layar dan Navigasi

| Kode layar | Halaman                                                          | Role         |
| ---------- | ---------------------------------------------------------------- | ------------ |
| UI-01      | Splash / pilihan Masuk atau Daftar                               | Publik       |
| UI-02      | Login, pilih tampilan role (opsional), autentikasi role otomatis | Publik       |
| UI-03      | Registrasi pasien / permohonan bidan                             | Publik       |
| UI-04      | Dashboard Pasien                                                 | Pasien       |
| UI-05      | Chat AI Kehamilan                                                | Pasien       |
| UI-06      | Daftar & detail bidan                                            | Pasien       |
| UI-07      | Pilih jadwal, isi keluhan, konfirmasi                            | Pasien       |
| UI-08      | Checkout Mayar & status pembayaran                               | Pasien       |
| UI-09      | Status booking & jadwal                                          | Pasien       |
| UI-10      | Chat konsultasi (30 menit)                                       | Pasien/Bidan |
| UI-11      | Hasil & riwayat konsultasi                                       | Pasien       |
| UI-12      | Dashboard Bidan                                                  | Bidan        |
| UI-13      | Daftar & detail booking                                          | Bidan        |
| UI-14      | Form hasil konsultasi                                            | Bidan        |
| UI-15      | Riwayat konsultasi bidan                                         | Bidan        |

# 11. Urutan Pengerjaan Aplikasi (wajib berurutan per dependensi)

| Tahap                        | Pekerjaan inti                                                                                       | Output / syarat lanjut                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| 0\. Persiapan kerja          | Buat backlog/issue dari PRD yang disetujui, tetapkan pemilik dan urutan dependensi                 | Tugas awal jelas dan dapat dikerjakan paralel tanpa mengubah kontrak yang disepakati |
| 1\. Desain                   | Fida: wireframe dan Figma/Stitch 15 layar, design system, state gagal/loading                        | Navigasi dan state UI dapat diuji sebagai prototype    |
| 2\. Infrastruktur            | Rinanta: Flutter; Iqbal: Laravel, Firebase Auth/Firestore; siapkan environment                        | Flutter dapat memanggil `/api/health` Laravel dari perangkat demo |
| 3\. Auth & role              | Register/login Firebase, verifikasi token Laravel, profil/role, status bidan, seed akun demo         | Pasien dan bidan terverifikasi masuk sesuai role; akses ilegal ditolak API |
| 4\. Data bidan & slot        | Profil bidan, slot dan kalender dari Firestore/backend; sambungkan UI                                 | Slot yang tampil berasal dari backend dan sudah difilter valid/tersedia |
| 5\. Booking tanpa bayar      | Hold slot atomik, expiry, transisi booking dan proteksi double-book                                   | Dua permintaan bersamaan pada slot sama hanya menghasilkan satu hold |
| 6\. Chat AI                  | Endpoint Gemini Laravel, prompt keselamatan, validasi/rate limit, tanpa penyimpanan chat MVP         | Jawaban edukasi, eskalasi red flag, dan state error provider teruji |
| 7\. Konsultasi DEV           | Bypass paid hanya di environment DEV; start sesi, chat realtime, batas waktu server, hasil           | Demo pasien-bidan end-to-end; bypass tidak tersedia di staging/production |
| 8\. Mayar Sandbox            | Checkout API, redirect, callback HTTPS, validasi webhook dan idempotensi                             | Pembayaran sandbox valid mengubah status sekali; callback ulang/terlambat ditangani |
| 9\. Integrasi final          | Hapus bypass paid DEV dan verifikasi akses per status/role                                            | Sesi hanya dimulai dari booking paid+confirmed          |
| 10\. QA & demo               | Uji dua perangkat, jaringan buruk, timer, role, slot ganda, status pembayaran/no-show                | UAT Bagian 13 lulus; APK demo dan bukti pengujian tersedia |

# 12. Pembagian Tanggung Jawab dan Handoff

| Personel | Tugas & handoff                                                                                                                                                                 |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fida     | PRD, desain UI dan prototype, sistem status/state, acceptance checklist, uji integrasi, laporan/PPT/video; serahkan file Figma dan flow ke Rinanta/Iqbal                        |
| Rinanta  | Flutter page routes, Firebase Auth SDK, API client Bearer token, form, UI chat, listener, payment redirect, error handling, build APK                                           |
| Iqbal    | Laravel APIs/middleware, Firestore collections & rules, seed bidan, booking atomik, Gemini server-side, Mayar sandbox checkout/webhook, timer server-side dan pengujian backend |

# 13. Checklist Uji Penerimaan (UAT)

- Pasien bisa daftar/login; bidan hanya berhasil jika verified; akun pasien tidak bisa mengakses endpoint bidan.
- Pemilihan slot yang sama oleh dua pasien hanya menghasilkan satu booking yang valid.
- Hold yang kedaluwarsa melepaskan slot; pembayaran valid yang datang terlambat tidak merebut kembali slot dan masuk rekonsiliasi.
- Booking unpaid tidak muncul sebagai sesi yang dapat dimulai; pembayaran pending/gagal tidak membuka chat.
- Mayar sandbox sukses setelah webhook valid mengubah status sekali, bahkan jika webhook berulang.
- Bidan mengonfirmasi booking; pasien memperoleh status confirmed dan jadwal.
- Dua perangkat saling menerima pesan; pengguna ketiga tidak dapat membaca pesan orang lain.
- Penulisan langsung ke Firestore oleh klien ditolak; API menolak pesan dari non-peserta atau setelah ends_at.
- Timer 30 menit konsisten setelah HP dimatikan/di-refresh; pesan terkunci setelah ends_at sementara bidan tetap dapat menyimpan hasil.
- Hasil konsultasi tidak dapat diisi AI atau pasien, hanya bidan terkait.
- Gemini tidak boleh menampilkan diagnosis pasti; untuk tanda bahaya tampilkan arahan pertolongan segera.
- Isi chat AI tidak tersimpan di Firestore maupun log server.
- Aplikasi tetap memberi pesan kesalahan yang jelas saat koneksi/API provider gagal.

# 14. Risiko, Asumsi, dan Ketergantungan

| Risiko                                             | Mitigasi                                                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Mayar webhook tidak menyebut signature pada dokumentasi yang digunakan | Rahasiakan URL webhook dan verifikasi invoice langsung via API Mayar; jangan mempercayai callback sebagai bukti bayar |
| Laravel di localhost tidak menerima webhook publik | Gunakan endpoint staging HTTPS/tunnel aman untuk pengujian webhook                              |
| Firebase Security Rules lemah                      | Gunakan pembatasan role/peserta dan uji akses silang dengan emulator; jangan mengandalkan UI    |
| Duplikasi slot & webhook                           | Gunakan transaksi/lock Firestore dan idempotency key                                            |
| AI memberi informasi kesehatan keliru              | Prompt keselamatan, disclaimer, pembatasan, uji red flag dan eskalasi ke tenaga kesehatan       |
| Konsultasi melewati 30 menit / tidak hadir         | State akhir jelas, kebijakan kompensasi dan petunjuk hubungi bantuan                            |
| Data medis sensitif                                | Minimalisasi data, hak akses ketat, hindari logging keluhan mentah dan simpan kebijakan retensi |

# 15. Definition of Done dan Target Demo

MVP dinyatakan selesai jika dua akun berbeda berhasil menjalankan alur pasien booking -> pembayaran Mayar Sandbox terverifikasi -> bidan menerima -> chat real-time 30 menit -> bidan menyelesaikan catatan -> pasien melihat hasil/riwayat. Semua status ditampilkan jelas; pengujian keamanan role, status payment, dan timer lulus. APK dapat dipasang pada Android dan Laravel dapat diakses oleh perangkat demo.

# 16. Referensi Teknis dan Catatan Verifikasi

- Mayar API v2: <https://docs.mayar.id/api-reference-v2/introduction.md>, <https://docs.mayar.id/api-reference-v2/invoice/create.md>, <https://docs.mayar.id/api-reference-v2/invoice/detail.md>; gunakan host Sandbox `https://api.mayar.club/hl/v2` dan Production `https://api.mayar.id/hl/v2`, dengan API key pada header `Authorization: Bearer <API_KEY>` sesuai integrasi resmi Mayar saat ini (<https://github.com/mayarid/mayar-cli>).
- Mayar webhook: <https://docs.mayar.id/integration/webhook.md>; dokumentasi yang digunakan tidak mendeskripsikan signature callback.
- Google Gemini API key: <https://ai.google.dev/gemini-api/docs/api-key> ; simpan credential di Laravel, bukan APK.
- Firebase: <https://firebase.google.com/docs/auth> dan <https://firebase.google.com/docs/firestore> ; implementasikan Rules dan indeks berdasarkan skema.
- Laravel: <https://laravel.com/docs> ; gunakan framework versi stabil yang kompatibel dengan PHP server tim.

Dokumen ini merupakan spesifikasi implementasi MVP, bukan persetujuan operasional layanan kesehatan yang sesungguhnya. Sebelum dipakai publik, diperlukan validasi klinis, proses verifikasi tenaga kesehatan, privasi data, dan kepatuhan regulasi yang relevan.