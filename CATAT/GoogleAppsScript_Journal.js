/**
 * ==============================================================================
 * GOOGLE APPS SCRIPT: MT5 JOURNAL & CASHFLOW SYNC
 * ==============================================================================
 * Script ini menerima data hasil trading harian dari MetaTrader 5 (MQL5)
 * dan otomatis mencatat / memperbarui Kolom G (Tanggal) dan Kolom H (Profit/Loss USC)
 * pada sheet Jurnal Trading.
 *
 * Cara Setup:
 * 1. Buka Google Spreadsheet Anda.
 * 2. Klik menu 'Extensions' (Ekstensi) -> 'Apps Script'.
 * 3. Hapus kode bawaan, lalu paste seluruh isi file ini.
 * 4. Klik tombol 'Deploy' (Terapkan) -> 'New deployment' (Penerapan baru).
 * 5. Pilih type: 'Web app' (Aplikasi web).
 * 6. Set Description: "MT5 Journal Receiver".
 * 7. Set 'Execute as': "Me" (Email Google Anda).
 * 8. Set 'Who has access': "Anyone" (Siapa saja - agar MT5 bisa mengirim data).
 * 9. Klik 'Deploy' dan salin URL Web App yang dihasilkan.
 * 10. Masukkan URL tersebut ke parameter MQ5 dan Allow WebRequest di MT5.
 * ==============================================================================
 */

// Konfigurasi Nama Sheet & Baris Awal
const SHEET_NAME = "METATRADER JOURNAL AND CASHFLOW DASHBOARD"; // Ganti jika nama tab sheet berbeda
const START_ROW = 27; // Baris awal data jurnal
const COL_DATE = 7;   // Kolom G (Tanggal)
const COL_PROFIT = 8; // Kolom H (Profit/Loss USC)
const COL_EST_IDR = 9;// Kolom I (Est. Profit IDR)
const COL_STATUS = 10;// Kolom J (Status WIN/LOSS)
const COL_AKUM = 11;  // Kolom K (Akumulasi IDR)

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.tryLock(30000); // Kunci agar tidak terjadi race condition jika ada request bersamaan

  try {
    if (!e || !e.postData || !e.postData.contents) {
      return createJsonResponse({ status: "error", message: "No payload received" }, 400);
    }

    const payload = JSON.parse(e.postData.contents);
    const ss = SpreadsheetApp.getActiveSpreadsheet();
    let sheet = ss.getSheetByName(SHEET_NAME);
    
    // Jika tidak ditemukan sheet dengan nama tersebut, gunakan sheet aktif pertama
    if (!sheet) {
      sheet = ss.getSheets()[0];
    }

    let records = [];
    if (payload.data && Array.isArray(payload.data)) {
      records = payload.data;
    } else if (payload.date && payload.profit_usc !== undefined) {
      records = [payload];
    } else {
      return createJsonResponse({ status: "error", message: "Invalid payload format" }, 400);
    }

    // Urutkan records berdasarkan tanggal jika ada multiple
    records.sort((a, b) => (a.date > b.date ? 1 : -1));

    const lastRow = Math.max(sheet.getLastRow(), START_ROW);
    
    // Ambil seluruh data tanggal yang sudah ada di Kolom G
    let dateRangeValues = [];
    if (lastRow >= START_ROW) {
      dateRangeValues = sheet.getRange(START_ROW, COL_DATE, lastRow - START_ROW + 1, 1).getValues();
    }

    // Buat map tanggal -> nomor baris
    const dateToRowMap = {};
    for (let i = 0; i < dateRangeValues.length; i++) {
      const val = dateRangeValues[i][0];
      if (val) {
        let dateStr = "";
        if (val instanceof Date) {
          dateStr = Utilities.formatDate(val, "Asia/Jakarta", "yyyy-MM-dd");
        } else {
          dateStr = String(val).trim();
        }
        if (dateStr) {
          dateToRowMap[dateStr] = START_ROW + i;
        }
      }
    }

    let updatedCount = 0;
    let insertedCount = 0;
    let details = [];

    // Cari baris terakhir yang benar-benar ada data tanggal
    let currentLastDataRow = START_ROW - 1;
    for (let i = dateRangeValues.length - 1; i >= 0; i--) {
      if (dateRangeValues[i][0] && String(dateRangeValues[i][0]).trim() !== "") {
        currentLastDataRow = START_ROW + i;
        break;
      }
    }

    for (let r = 0; r < records.length; r++) {
      const item = records[r];
      const targetDate = String(item.date).trim();
      const profitUsc = Number(item.profit_usc);

      if (!targetDate) continue;

      if (dateToRowMap[targetDate]) {
        // --- 1. TANGGAL SUDAH ADA: UPDATE NILAI KOLOM H ---
        const targetRow = dateToRowMap[targetDate];
        sheet.getRange(targetRow, COL_PROFIT).setValue(profitUsc);
        
        // Pastikan formula kolom I, J, K tetap sinkron jika kosong
        ensureRowFormulas(sheet, targetRow);

        updatedCount++;
        details.push({ date: targetDate, action: "updated", row: targetRow, profit: profitUsc });
      } else {
        // --- 2. TANGGAL BARU: TAMBAH BARIS BARU ---
        const newRow = currentLastDataRow + 1;
        
        // Set Tanggal (Kolom G) dan Profit USC (Kolom H)
        sheet.getRange(newRow, COL_DATE).setValue(targetDate);
        sheet.getRange(newRow, COL_PROFIT).setValue(profitUsc);

        // Pasang Formula Otomatis Kolom I, J, K
        ensureRowFormulas(sheet, newRow);

        // Format angka kolom H
        sheet.getRange(newRow, COL_PROFIT).setNumberFormat('+#,##0.00;-#,##0.00;"0.00"');

        dateToRowMap[targetDate] = newRow;
        currentLastDataRow = newRow;
        insertedCount++;
        details.push({ date: targetDate, action: "inserted", row: newRow, profit: profitUsc });
      }
    }

    SpreadsheetApp.flush();

    return createJsonResponse({
      status: "success",
      message: `Berhasil sinkronisasi: ${updatedCount} diupdate, ${insertedCount} baris baru ditambahkan.`,
      updated: updatedCount,
      inserted: insertedCount,
      details: details
    }, 200);

  } catch (err) {
    return createJsonResponse({
      status: "error",
      message: err.toString()
    }, 500);
  } finally {
    lock.releaseLock();
  }
}

/**
 * Memastikan baris memiliki formula standar untuk Est. Profit (IDR), Status, dan Akumulasi
 */
function ensureRowFormulas(sheet, rowNum) {
  const cellEstIdr = sheet.getRange(rowNum, COL_EST_IDR);
  const cellStatus = sheet.getRange(rowNum, COL_STATUS);
  const cellAkum = sheet.getRange(rowNum, COL_AKUM);

  // Kolom I (Est. Profit IDR): =H[row]*($K$12/100) atau disesuaikan dengan sel Kurs
  if (!cellEstIdr.getFormula()) {
    cellEstIdr.setFormula(`=H${rowNum}*($K$12/100)`);
    cellEstIdr.setNumberFormat('"+ Rp "#,##0;"- Rp "#,##0;"Rp -"');
  }

  // Kolom J (Status): =IF(H[row]>0,"WIN",IF(H[row]<0,"LOSS","BREAK EVEN"))
  if (!cellStatus.getFormula()) {
    cellStatus.setFormula(`=IF(H${rowNum}>0,"WIN",IF(H${rowNum}<0,"LOSS","BREAK EVEN"))`);
  }

  // Kolom K (Akumulasi IDR): baris pertama = I27, baris selanjutnya = K[row-1] + I[row]
  if (!cellAkum.getFormula()) {
    if (rowNum === START_ROW) {
      cellAkum.setFormula(`=I${rowNum}`);
    } else {
      cellAkum.setFormula(`=K${rowNum - 1}+I${rowNum}`);
    }
    cellAkum.setNumberFormat('"+ Rp "#,##0;"- Rp "#,##0;"Rp -"');
  }
}

function doGet(e) {
  return createJsonResponse({
    status: "ok",
    message: "Google Apps Script MT5 Journal Receiver is active and ready."
  }, 200);
}

function createJsonResponse(data, statusCode) {
  return ContentService.createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
