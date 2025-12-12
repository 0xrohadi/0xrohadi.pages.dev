+++
date = '2025-12-12T02:35:00Z'
draft = false
title = 'One UUID Change - Full Payout Account Takeover'
+++
Halo semuanya! Dalam pengujian keamanan yang saya lakukan pada private bug bounty program ini, perhatian saya langsung tertuju pada fitur **Payments** (Pembayaran). Fitur yang menangani transaksi finansial adalah target bernilai tinggi karena potensi dampak yang dapat ditimbulkan terhadap integritas keuangan pengguna.

![setting payments](/images/setting-payments.png)

Saya memfokuskan pengujian pada bagaimana sistem menangani pengaturan metode pembayaran (payout methods), khususnya integrasi dengan penyedia layanan pembayaran pihak ketiga, **Tipalti.**

## Discovery - The Red Flag

Endpoint yang bertanggung jawab untuk mengambil URL dashboard Tipalti adalah:

```
GET /api/v1.3/payments/users/{user_id}/payout-methods/tipalti/url?...
Host: www.private.com
Authorization: Bearer eyJhbG... (token milik attacker)
Content-Type: application/json
...
```
Struktur endpoint ini, yang secara eksplisit memasukkan {user_id} sebagai parameter path, adalah indikator potensial untuk kerentanan **IDOR** (Insecure Direct Object Reference).

### The Security Question

Pertanyaan kritis yang muncul:

*Apakah server memverifikasi bahwa ID pengguna yang membuat request memiliki otorisasi untuk mengakses {user_id} yang diminta dalam path?*

Ini adalah inti dari pengujian **Broken Access Control**, memastikan bahwa kontrol akses diterapkan dengan benar pada level aplikasi.

## Methodology - Testing for Authorization Bypass

Sesuai dengan etika pengujian yang bertanggung jawab, saya menggunakan dua akun uji yang saya kontrol penuh:

### Setup Pengujian:

1. **Akun Penyerang** (Attacker Account)
* User ID: 66bc3872-a65d-4c4e-bb05-8ba3878e78ea
* Token: Bearer eyJhbG... (valid authentication token)

2. **Akun Korban** (Victim Account)
* User ID: 02400792-9156-47ea-bee7-15376143df16
* Tidak memiliki akses ke token ini dari akun penyerang

### Step 1: Baseline Request

Langkah pertama adalah menangkap request normal ketika Akun Penyerang mengakses dashboard Tipalti miliknya sendiri:

```
GET /api/v1.3/payments/users/66bc3872-a65d-4c4e-bb05-8ba3878e78ea/payout-methods/tipalti/url?... HTTP/1.1
Host: www.private.com
Authorization: Bearer eyJhbG...
Content-Type: application/json
...
```
**Response:**
```
{
  "url": "https://***.redacted.com/payeedashboard/home?ts=1761732202&idap=[ATTACKER_UUID]&payer=[REDACTED]&hashkey=[HASH_REDACTED]"
}
```
Response ini valid dan sesuai harapan - pengguna dapat mengakses dashboard pembayaran miliknya sendiri.

### Step 2: The IDOR Test

Saya kemudian memodifikasi request di Burp Suite Repeater, mengganti {user_id} penyerang dengan {user_id} milik korban:

![GET request to payments](/images/GET-payments.png)

```
GET /api/v1.3/payments/users/02400792-9156-47ea-bee7-15376143df16/payout-methods/tipalti/url?... HTTP/1.1
Host: www.private.com
Authorization: Bearer eyJhbG... (token milik attacker)
Content-Type: application/json
...
```

## The Vulnerability - Authorization Bypass Confirmed

Alih-alih menerima response 403 Forbidden atau 401 Unauthorized yang seharusnya muncul ketika mencoba mengakses resource milik pengguna lain, server justru mengembalikan response 200 OK dengan payload yang berisi URL dashboard Tipalti yang **valid untuk Akun Korban:**

![Dashboard edit payments](/images/dashboard-payments.png)

```
{
  "url": "https://***.redacted.com/payeedashboard/home?ts=1761732202&idap=[VICTIM_UUID]&payer=[REDACTED]&hashkey=[VICTIM_HASH_REDACTED]"
}
```
### What This Means?

Dengan URL ini, penyerang dapat:
1. Mengakses dashboard pembayaran korban di Tipalti
2. Melihat informasi metode pembayaran yang sudah terdaftar
3. Menambahkan rekening bank baru jika korban belum mengatur metode pembayaran
4. Memodifikasi rekening bank yang ada menjadi rekening yang dikontrol penyerang

**Hasil akhir:** Semua pendapatan dan pembayaran masa depan dari akun korban akan dialihkan langsung ke rekening bank yang dikendalikan penyerang.

## Proof of Concept Video

[Saya telah membuat video PoC yang mendemonstrasikan eksploitasi penuh, dari pengambilan URL hingga modifikasi metode pembayaran. Video ini telah dikirimkan secara private kepada tim keamanan program.]

## Impact Analysis

Kerentanan IDOR pada endpoint pembayaran ini memiliki dampak Critical terhadap integritas finansial platform dan penggunanya:

### 1. Durect Financial Lost
* Penyerang dapat mengalihkan semua pembayaran masa depan korban
* Tidak ada batasan jumlah korban yang dapat ditarget
* Potensi kerugian finansial berskala besar untuk platform dan pengguna

### 2. Compliance & Regulatory Risk
* Pelanggaran regulasi KYC (Know Your Customer)
* Pelanggaran AML (Anti-Money Laundering) regulations
* Potensi denda dari regulator financial
* Exposure data sensitif pembayaran melanggar PCI DSS compliance

### 3. Reputational Damage
* Kehilangan kepercayaan pengguna secara masif
* Dampak negatif pada brand reputation yang sulit dipulihkan
* Potensi class-action lawsuit dari pengguna yang terdampak

### 4. Account Takeover Chain
* Akses ke dashboard pembayaran dapat mengekspos informasi PII (Personally Identifiable Information)
* Dapat digunakan sebagai pivot point untuk serangan lebih lanjut

### 5. Mass Exploitation Potential
* Kerentanan dapat diautomasi dengan script sederhana
* Tidak ada rate limiting yang mencegah enumerasi user IDs
* Tidak ada alert/notification ke korban ketika metode pembayaran dimodifikasi

## Root Cause Analysis

Kerentanan ini terjadi karena:
1. Missing Server-Side Authorization Check
Server tidak memvalidasi apakah user yang terotentikasi memiliki hak akses terhadap {user_id} yang diminta
2. Trust in Client-Provided Input
Aplikasi mempercayai parameter {user_id} dari request tanpa verifikasi ownership
3. Lack of Access Control Layer
Tidak ada middleware atau access control layer yang memeriksa relationship antara authenticated user dan requested resource

## Mitigation (The Fix)

Perbaikan untuk masalah ini harus dilakukan di server-side dengan implementasi proper authorization checks.

### Server-Side Authorization Cheks:
```python
# Example
# Psudocode
def get_tipalti_url(request, user_id):
    authenticated_user_id = get_user_from_token(request.headers['Authorization'])
    
    # Critical: Verify ownership
    if authenticated_user_id != user_id:
        return Response(status=403, body={"error": "Forbidden: Access denied"})
    
    # Proceed only if authorization passes
    tipalti_url = generate_tipalti_url(user_id)
    return Response(status=200, body={"url": tipalti_url})
```

### Additional Security Layers
1. **Implement Indirect Object References**
* Gunakan session-based references daripada direct user IDs
* Contoh: /api/v1.3/payments/me/payout-methods/tipalti/url

2. **Enhanced Logging & Monitoring**
* Log semua akses ke endpoint finansial sensitif
* Alert ketika terdeteksi cross-user access attempts
* Implement anomaly detection untuk pola akses mencurigakan

3. **Rate Limiting**
* Batasi jumlah request ke endpoint pembayaran per user per timeframe
* Prevent automated enumeration attacks

4. **Multi-Factor Authentication**
* Require MFA untuk modifikasi metode pembayaran
* Add confirmation via email/SMS ketika payment method berubah

5. **Input Validation**
* Validate UUID format untuk {user_id} parameter
* Reject malformed or suspicious inputs

## Conclusion

Kerentanan IDOR pada endpoint finansial dapat memiliki dampak yang sangat serius. Kasus ini menegaskan kembali pentingnya:

* Implementasi **Broken Access Control** testing yang menyeluruh
* **Server-side authorization checks** yang ketat pada setiap endpoint
* **Defense in depth** approach untuk melindungi data dan transaksi finansial

Sebagai bug bounty hunter, tanggung jawab kita bukan hanya menemukan kerentanan, tetapi juga membantu organisasi memahami risiko dan memperbaiki sistem mereka dengan cara yang bertanggung jawab.

### Final Thoughts

Bug ini mengajarkan beberapa hal penting:
* **Trust is expensive**: Parameter `{user_id}` yang terlihat innocent ternyata menjadi pintu masuk ke rekening bank pengguna lain
* **Financial APIs need extra scrutiny**: Satu endpoint yang exposed dapat membahayakan ribuan pengguna dan reputasi platform
* **Fast response matters**: Dari report hingga fix dalam 3 hari menyelamatkan platform dari potensi kerugian yang jauh lebih besar

**Keep hacking ethically, stay curious, and always protect user data!**

---

**Disclosure:** Write-up ini dipublikasikan setelah mendapat izin dari program dan setelah vulnerability telah sepenuhnya diperbaiki. Beberapa detail teknis dan identifiable information telah di-redact untuk melindungi privasi program.

Terima kasih telah meluangkan waktu untuk membaca artikel ini. Jika ada pertanyaan atau diskusi lebih lanjut mengenai metodologi testing, silakan hubungi saya melalui [X].

Have a good day!
