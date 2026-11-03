PRODUCT REQUIREMENTS DOCUMENT

TeleBunda AI

Aplikasi telehealth edukasi kehamilan dan konsultasi chat bidan | MVP Android

| Identitas dokumen | Keterangan                                                                                        |
| ----------------- | ------------------------------------------------------------------------------------------------- |
| Versi             | 1.0 - baseline pengembangan                                                                       |
| Tanggal           | 2 November 2026                                                                                   |
| Status            | Draft PRD untuk implementasi dan persetujuan tim                                                  |
| Platform          | Satu APK Flutter untuk pasien dan bidan                                                           |
| Stack             | Flutter (Dart) \| Laravel (PHP) \| Firebase Auth + Cloud Firestore \| Gemini API \| Mayar Sandbox |
| Tim               | Fida: PM, UI/UX, QA, dokumentasi; Rinanta: frontend Flutter; Iqbal: Laravel, Firebase, AI, Mayar  |

Keputusan inti: tidak ada video call. Chat AI gratis. Konsultasi bidan dilakukan melalui chat teks selama 30 menit dengan pembayaran simulasi Mayar Sandbox. Hasil konsultasi disusun oleh bidan, bukan AI.

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
| Admin teknis (tanpa UI) | Firebase Console / skrip Laravel admin untuk demo                                                | Verifikasi akun bidan, seeding jadwal dan pemulihan data uji                                  |

Catatan keamanan: layar pilihan role pada registrasi/login boleh tersedia sesuai permintaan UI, tetapi memilih "Bidan" tidak pernah otomatis menaikkan role. Pendaftaran bidan menghasilkan permohonan/akun pending_verification; hanya akun bidan yang diberi otorisasi admin dapat mengakses dashboard bidan. Pada login, backend memeriksa role tepercaya dan mengarahkan pengguna secara otomatis.

# 4. Alur Bisnis End-to-End

## 4.1 Alur Pasien

1. Buka APK > halaman Selamat Datang > pilih Masuk atau Daftar.
2. Daftar: pilih role Pasien, isi identitas minimum; login: pengguna dapat memilih jenis akun sebagai preferensi UI, tetapi role sebenarnya diverifikasi dari akun.
3. Dashboard Pasien menampilkan tombol "Chat AI Gratis", "Cari Bidan", booking terdekat dan riwayat.
4. Chat AI (opsional): tanya jawab edukasi kehamilan; tersedia CTA "Konsultasi Bidan".
5. Pilih bidan, lihat profil dan slot tersedia, tentukan tanggal/jam, isi keluhan singkat, konfirmasi booking.
6. Backend menahan slot sementara dan membuat booking awaiting_payment; pasien diarahkan ke halaman/link checkout Mayar Sandbox.
7. Mayar mengirim notifikasi pembayaran; Laravel memverifikasi keaslian dan status melalui API/aturan resmi penyedia, kemudian mengubah booking menjadi paid_pending_midwife.
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
| Booking                 | awaiting_payment -> paid_pending_midwife -> confirmed -> active -> completed; cabang: payment_failed, expired, rejected, cancelled, no_show |
| Pembayaran              | created / pending / paid / failed / expired / refunded_test (jika didukung skenario sandbox); paid hanya dari verifikasi server             |
| Slot                    | Tahan selama 15 menit (asumsi desain, configurable); dilepas saat pembayaran gagal/kedaluwarsa                                              |
| Konsultasi              | Sesi normal 30 menit; started_at dan ends_at dari backend; hanya 1 sesi aktif per booking                                                   |
| Keterlambatan           | Toleransi 10 menit (asumsi desain), dengan penjadwalan ulang/manual handling jika bidan tidak hadir                                         |
| Timer                   | Notifikasi 5 menit tersisa; ketika 30 menit tercapai input pesan ditutup untuk sesi normal, bidan tetap bisa menyimpan hasil                |
| Chat                    | Hanya peserta booking paid+confirmed+active yang boleh kirim; setelah completed hanya baca                                                  |
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
| FR-07 | Mayar Sandbox checkout dibuat oleh Laravel; hasil sukses UI tidak otomatis menandakan paid.     |
| FR-08 | Webhook/notifikasi tervalidasi dan idempoten mengubah status transaksi/booking sekali.          |
| FR-09 | Bidan hanya melihat dan menerima booking atas namanya yang sudah dibayar.                       |
| FR-10 | Chat pasien-bidan hanya bisa saat sesi aktif; kedua perangkat menerima pesan realtime.          |
| FR-11 | Timer 30 menit dan kunci pesan dikontrol server, tidak bergantung jam HP.                       |
| FR-12 | Bidan menyimpan ringkasan dan menyelesaikan konsultasi; pasien hanya membaca hasil miliknya.    |
| FR-13 | Riwayat menampilkan booking selesai beserta tanggal, bidan, dan hasil.                          |
| FR-14 | Loading, kosong, gagal jaringan, pembayaran pending/gagal dan tidak hadir punya state UI jelas. |

# 7. Arsitektur Teknis

Flutter (Android) -> Laravel REST API (otorisasi, aturan bisnis, Gemini, Mayar) -> Firebase Admin SDK/Firestore. Firebase Authentication melakukan autentikasi pengguna; Flutter mengirim Firebase ID token melalui Authorization: Bearer ke Laravel. Laravel memverifikasi token dan role tepercaya. Firestore menjadi sumber data utama untuk user, booking, slot, chat, hasil konsultasi dan transaksi. Untuk chat real-time, Flutter dapat memakai Firestore listener langsung dengan Security Rules ketat; tulis pesan hanya untuk peserta sesi aktif sesuai status yang dikendalikan Laravel, atau gunakan API Laravel untuk penulisan jika aturan keamanan lebih mudah dikontrol demikian.

Laravel adalah backend pusat, bukan database SQL tambahan. Perlu PHP 8.x, Composer, Firebase Admin SDK untuk PHP yang kompatibel, kredensial service account server, dan endpoint HTTPS yang dapat diakses webhook Mayar. Jangan memasukkan service account, API key Gemini, ataupun Mayar secret ke APK atau Git.

# 8. Struktur Koleksi Firestore (usulan awal)

| Collection / subcollection              | Field utama                                                                                     |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| users/{uid}                             | uid, name, email, role, verified, created_at                                                    |
| midwives/{uid}                          | display_name, credential_label, bio, active, verification_status                                |
| slots/{slotId}                          | midwife_id, start_at, end_at, status, hold_booking_id, hold_expires_at                          |
| bookings/{bookingId}                    | patient_id, midwife_id, slot_id, complaint, amount, status, payment_id, created_at              |
| payments/{paymentId}                    | booking_id, provider=mayar, environment=sandbox, external_id, status, checkout_url, verified_at |
| consultations/{consultationId}          | booking_id, patient_id, midwife_id, started_at, ends_at, status, completed_at                   |
| consultations/{id}/messages/{messageId} | sender_id, text, sent_at, type=text                                                             |
| consultation_results/{id}               | consultation_id, summary, advice, supplement_note_optional, follow_up, saved_by, completed_at   |
| ai_chats/{uid}/messages/{messageId}     | role, content, created_at; optional, configurable retention                                     |

Indeks yang diperlukan: booking by patient/date; booking by midwife/status/date; slots by midwife/date/status; messages by sent_at. Gunakan timestamp UTC di database dan tampilkan WIB pada antarmuka.

# 9. Kontrak API Laravel (rancangan, bukan endpoint resmi Mayar/Gemini)

| Method / Endpoint                     | Akses / Tindakan                                                        |
| ------------------------------------- | ----------------------------------------------------------------------- |
| POST /api/auth/register               | Pasien; membuat profil akun setelah Firebase Auth                       |
| GET /api/me                           | Semua; role dan profil                                                  |
| GET /api/midwives                     | Pasien; daftar bidan aktif                                              |
| GET /api/midwives/{id}/slots          | Pasien; slot tersedia                                                   |
| POST /api/bookings                    | Pasien; buat booking + hold slot                                        |
| GET /api/bookings                     | Pasien/bidan; data berdasarkan role                                     |
| POST /api/bookings/{id}/checkout      | Pasien; buat checkout Mayar Sandbox                                     |
| POST /api/webhooks/mayar              | Mayar; callback server, verifikasi signature/payload sesuai dokumentasi |
| POST /api/bookings/{id}/accept        | Bidan pemilik booking                                                   |
| POST /api/bookings/{id}/reject        | Bidan; alasan dan penanganan lanjutan                                   |
| POST /api/consultations/{id}/start    | Bidan; mulai sesi sesuai jadwal                                         |
| GET /api/consultations/{id}           | Peserta; status dan timer                                               |
| POST /api/consultations/{id}/complete | Bidan; simpan hasil + complete                                          |
| POST /api/ai/chat                     | Pasien; Laravel meneruskan permintaan ke Gemini                         |
| GET /api/history                      | Pasien/bidan; hasil dan riwayat yang diizinkan                          |

Endpoint Mayar sebenarnya, skema webhook, signature, jenis pembayaran, response dan status harus disalin dari dokumentasi Mayar sesuai versi API yang dipilih sebelum coding; tabel ini hanya kontrak API internal Laravel.

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
| 0\. Finalisasi               | Setujui flow, role, 30 menit, status pembayaran dan batas fitur; buat repo & issue board             | PRD disetujui, backlog dibagi                           |
| 1\. Desain                   | Fida: wireframe dan Figma/Stitch 15 layar, design system, state gagal/loading                        | Navigasi bisa diuji sebagai prototype                   |
| 2\. Infrastruktur            | Rinanta: Flutter project; Iqbal: Laravel project, Firebase project/Auth/Firestore; setup environment | Flutter bisa mengakses /api/health di Laravel           |
| 3\. Auth & role              | Register pasien, login, token Firebase, middleware Laravel, seed bidan verified                      | Dua akun masuk dashboard berbeda; penolakan role ilegal |
| 4\. Data bidan & slot        | Profil bidan, slot dan kalender; frontend list/detail/booking form                                   | Pasien melihat slot valid dari backend                  |
| 5\. Booking tanpa bayar      | Hold slot, catat keluhan, status pending, cegah double-book                                          | Booking berhasil dan tidak duplikat                     |
| 6\. Chat AI                  | Endpoint Gemini Laravel, prompt aman, limit input/rate, UI chat                                      | AI menjawab dan fallback saat error                     |
| 7\. Konsultasi tanpa payment | Konfirmasi booking dummy paid dalam lingkungan DEV saja; start sesi, chat realtime, timer, hasil     | Demo pasien-bidan end-to-end dengan status dev          |
| 8\. Mayar Sandbox            | Checkout API, deep link/webview/browser, callback HTTPS, validasi webhook, status paid               | Transaksi sandbox tervalidasi memicu booking paid       |
| 9\. Integrasi final          | Hapus bypass paid DEV, hubungkan pembayaran ke booking dan konsultasi                                | Konsultasi hanya aktif setelah paid+confirmed           |
| 10\. QA & demo               | Uji dua perangkat, jaringan buruk, timer, role, duplikat, payment failure, laporan                   | APK release demo, skenario rekaman dan bukti test       |

# 12. Pembagian Tanggung Jawab dan Handoff

| Personel | Tugas & handoff                                                                                                                                                                 |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fida     | PRD, desain UI dan prototype, sistem status/state, acceptance checklist, uji integrasi, laporan/PPT/video; serahkan file Figma dan flow ke Rinanta/Iqbal                        |
| Rinanta  | Flutter page routes, Firebase Auth SDK, API client Bearer token, form, UI chat, listener, payment redirect, error handling, build APK                                           |
| Iqbal    | Laravel APIs/middleware, Firestore collections & rules, seed bidan, booking atomik, Gemini server-side, Mayar sandbox checkout/webhook, timer server-side dan pengujian backend |

# 13. Checklist Uji Penerimaan (UAT)

- Pasien bisa daftar/login; bidan hanya berhasil jika verified; akun pasien tidak bisa mengakses endpoint bidan.
- Pemilihan slot yang sama oleh dua pasien hanya menghasilkan satu booking yang valid.
- Booking unpaid tidak muncul sebagai sesi yang dapat dimulai; pembayaran pending/gagal tidak membuka chat.
- Mayar sandbox sukses setelah webhook valid mengubah status sekali, bahkan jika webhook berulang.
- Bidan mengonfirmasi booking; pasien memperoleh status confirmed dan jadwal.
- Dua perangkat saling menerima pesan; pengguna ketiga tidak dapat membaca pesan orang lain.
- Timer 30 menit konsisten setelah HP dimatikan/di-refresh; setelah selesai pesan terkunci.
- Hasil konsultasi tidak dapat diisi AI atau pasien, hanya bidan terkait.
- Gemini tidak boleh menampilkan diagnosis pasti; untuk tanda bahaya tampilkan arahan pertolongan segera.
- Aplikasi tetap memberi pesan kesalahan yang jelas saat koneksi/API provider gagal.

# 14. Risiko, Asumsi, dan Ketergantungan

| Risiko                                             | Mitigasi                                                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Mayar endpoint/status berbeda antardokumen         | Tetapkan versi API Mayar dan uji endpoint sandbox dari dokumentasi resmi terlebih dahulu        |
| Laravel di localhost tidak menerima webhook publik | Gunakan endpoint staging HTTPS/tunnel aman untuk pengujian webhook                              |
| Firebase Security Rules lemah                      | Gunakan pembatasan role/peserta dan uji akses silang dengan emulator; jangan mengandalkan UI    |
| Duplikasi slot & webhook                           | Gunakan transaksi/lock Firestore dan idempotency key                                            |
| AI memberi informasi kesehatan keliru              | Prompt keselamatan, disclaimer, pembatasan, uji red flag dan eskalasi ke tenaga kesehatan       |
| Konsultasi melewati 30 menit / tidak hadir         | State akhir jelas, kebijakan kompensasi dan petunjuk hubungi bantuan                            |
| Data medis sensitif                                | Minimalisasi data, hak akses ketat, hindari logging keluhan mentah dan simpan kebijakan retensi |

# 15. Definition of Done dan Target Demo

MVP dinyatakan selesai jika dua akun berbeda berhasil menjalankan alur pasien booking -> pembayaran Mayar Sandbox terverifikasi -> bidan menerima -> chat real-time 30 menit -> bidan menyelesaikan catatan -> pasien melihat hasil/riwayat. Semua status ditampilkan jelas; pengujian keamanan role, status payment, dan timer lulus. APK dapat dipasang pada Android dan Laravel dapat diakses oleh perangkat demo.

# 16. Referensi Teknis dan Catatan Verifikasi

- Mayar Developer/API: <https://mayar.id/agents> ; dokumentasi API: <https://docs.mayar.id/> (periksa versi, status, dan webhook aktual).
- Mayar sandbox evidence: <https://mcp.mayar.id/> menyebut Environment=sandbox; untuk REST tetap cocokkan base URL dan autentikasi dokumentasi resminya.
- Google Gemini API key: <https://ai.google.dev/gemini-api/docs/api-key> ; simpan credential di Laravel, bukan APK.
- Firebase: <https://firebase.google.com/docs/auth> dan <https://firebase.google.com/docs/firestore> ; implementasikan Rules dan indeks berdasarkan skema.
- Laravel: <https://laravel.com/docs> ; gunakan framework versi stabil yang kompatibel dengan PHP server tim.

Dokumen ini merupakan spesifikasi implementasi MVP, bukan persetujuan operasional layanan kesehatan yang sesungguhnya. Sebelum dipakai publik, diperlukan validasi klinis, proses verifikasi tenaga kesehatan, privasi data, dan kepatuhan regulasi yang relevan.