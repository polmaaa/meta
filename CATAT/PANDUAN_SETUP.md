# Panduan Lengkap Sinkronisasi Jurnal MT5 ke Google Spreadsheet

Sistem ini berfungsi untuk membaca transaksi posisi yang sudah ditutup (**History Deals**) di MetaTrader 5, mengelompokkannya per tanggal berdasarkan **Waktu Indonesia Barat (WIB / UTC+7)**, lalu otomatis mengirimkan total profit/loss ke **Kolom G (Tanggal)** dan **Kolom H (Profit/Loss USC)** di Google Spreadsheet Anda.

---

## 📁 File yang Tersedia di Folder `CATAT/`

1. **`GoogleAppsScript_Journal.js`**  
   Kode Google Apps Script yang dipasang di Google Spreadsheet sebagai penerima data (Web App API).
2. **`SyncClosedPositionsToSheet.mq5`** (Script MT5)  
   Script untuk sinkronisasi manual/sekali jalan (misal: rekap 30 hari terakhir atau seluruh akun).
3. **`AutoJournalTrackerEA.mq5`** (Expert Advisor MT5)  
   EA yang berjalan di background dan otomatis mengirim data begitu ada posisi tertutup atau secara berkala (misal tiap 15 menit).

---

## 🚀 Langkah 1: Pasang Google Apps Script di Spreadsheet

1. Buka file Google Spreadsheet Anda: [METATRADER JOURNAL AND CASHFLOW DASHBOARD](https://docs.google.com/spreadsheets/d/147EHrm_ghelsvi8mxY9IpCX_7t2KE4D2iy4ZmmHbmpM/edit?gid=1272196974#gid=1272196974).
2. Di menu atas, klik **Extensions** (Ekstensi) $\rightarrow$ **Apps Script**.
3. Hapus kode default yang ada di editor Apps Script, lalu salin dan tempel (*copy-paste*) seluruh isi dari file [`GoogleAppsScript_Journal.js`](file:///c:/xampp/htdocs/meta/CATAT/GoogleAppsScript_Journal.js).
4. Klik tombol **Save** (ikon disket).
5. Klik tombol biru **Deploy** (Terapkan) di pojok kanan atas $\rightarrow$ pilih **New deployment** (Penerapan baru).
6. Di jendela popup:
   * **Select type (ikon gerigi)**: Pilih **Web app** (Aplikasi web).
   * **Description**: Ketik `MT5 Journal Sync`.
   * **Execute as**: Pilih **Me (email Anda)**.
   * **Who has access**: Pilih **Anyone** (Siapa saja). *(Penting agar MT5 dapat mengirim data tanpa perlu login browser)*.
7. Klik **Deploy** $\rightarrow$ Jika muncul permintaan izin (*Authorization*), klik **Review permissions** $\rightarrow$ Pilih akun Google Anda $\rightarrow$ Klik **Advanced** $\rightarrow$ Klik **Go to Untitled project (unsafe)** $\rightarrow$ Klik **Allow**.
8. Salin **Web App URL** yang diberikan (formatnya biasanya: `https://script.google.com/macros/s/AKfycb.../exec`).

---

## ⚙️ Langkah 2: Izinkan WebRequest di MetaTrader 5

Agar MT5 diizinkan mengirimkan data keluar ke internet via HTTP POST:

1. Buka aplikasi **MetaTrader 5**.
2. Klik menu **Tools** $\rightarrow$ **Options** (atau tekan `Ctrl + O`).
3. Buka tab **Expert Advisors**.
4. Centang opsi **"Allow WebRequest for listed URL"**.
5. Klik dua kali tanda tambah `+` di bawahnya dan tambahkan dua URL berikut:
   * `https://script.google.com`
   * `https://script.googleusercontent.com`
6. Klik **OK**.

---

## 💻 Langkah 3: Menggunakan Script / EA di MT5

### Opsi A: Menggunakan Script Manual (`SyncClosedPositionsToSheet.mq5`)
1. Salin file [`SyncClosedPositionsToSheet.mq5`](file:///c:/xampp/htdocs/meta/CATAT/SyncClosedPositionsToSheet.mq5) ke folder `MQL5/Scripts` pada MT5 Anda (atau buka di MetaEditor lalu klik **Compile**).
2. Di MT5, seret script tersebut ke chart apa saja.
3. Pada tab **Inputs**:
   * Masukkan URL Web App Google Anda ke kolom `InpGoogleWebAppUrl`.
   * Atur `InpDaysBack` (misal `30` untuk 30 hari terakhir, atau `0` untuk semua riwayat).
   * Pastikan `InpTargetGmtOffset` bernilai `7` (WIB).
4. Klik **OK**. Script akan memproses seluruh riwayat transaksi dan langsung mengisi Google Spreadsheet Anda.

---

### Opsi B: Menggunakan Auto Tracker EA (`AutoJournalTrackerEA.mq5`)
1. Salin file [`AutoJournalTrackerEA.mq5`](file:///c:/xampp/htdocs/meta/CATAT/AutoJournalTrackerEA.mq5) ke folder `MQL5/Experts` pada MT5 Anda (atau buka di MetaEditor lalu klik **Compile**).
2. Pasang EA ke salah satu chart.
3. Masukkan `InpGoogleWebAppUrl` dan aktifkan **Algo Trading** di toolbar MT5.
4. EA akan terus aktif memonitor trading Anda:
   * Setiap kali ada transaksi yang baru ditutup, EA langsung meng-update total profit hari itu di Google Sheet.
   * EA juga melakukan sinkronisasi berkala setiap interval waktu (default 15 menit).

---

## 📊 Apa yang Terjadi di Google Spreadsheet?

* Jika tanggal transaksi **sudah ada** di Kolom G (misal `2026-10-03`), script akan **memperbarui angka di Kolom H** dengan akumulasi laba/rugi terbaru hari itu.
* Jika tanggal transaksi **baru** (misal hari berikutnya `2026-10-04`), script akan **menambahkan baris baru** di bawah baris terakhir secara urut, memasukkan Tanggal (Kolom G), Profit USC (Kolom H), dan otomatis memasang rumus formula untuk:
  * **Kolom I**: `=H[baris]*($K$12/100)` (Estimasi IDR)
  * **Kolom J**: `=IF(H[baris]>0,"WIN",IF(H[baris]<0,"LOSS","BREAK EVEN"))` (Status)
  * **Kolom K**: `=K[baris_sebelumnya]+I[baris]` (Akumulasi IDR)
