//+------------------------------------------------------------------+
//|                                  SyncClosedPositionsToSheet.mq5 |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://mql5.com"
#property version   "1.00"
#property script_show_inputs

//--- Input Parameters
input group "=== PENGATURAN GOOGLE SPREADSHEET ==="
input string   InpGoogleWebAppUrl  = "https://script.google.com/macros/s/AKfycb.../exec"; // Masukkan URL Google Apps Script Web App Anda

input group "=== PENGATURAN ZONA WAKTU (WIB) ==="
input int      InpTargetGmtOffset  = 7;                // Target Zona Waktu (WIB = GMT+7)
input bool     InpAutoDetectBrokerGmt = true;          // Deteksi Otomatis Selisih Jam Broker
input int      InpManualBrokerGmt  = 3;                // Manual Broker GMT (jika AutoDetect = false)

input group "=== FILTER TRANSAKSI ==="
input int      InpDaysBack         = 30;               // Ambil Riwayat Berapa Hari Terakhir? (0 = Semua Riwayat Akun)
input string   InpFilterSymbol     = "";               // Filter Simbol (Kosongkan utk Semua Simbol)
input long     InpFilterMagic      = -1;               // Filter Magic Number (-1 = Semua Magic)

//--- Struktur Rekap Harian
struct SDailyProfit
{
   string   dateStr;       // YYYY-MM-DD
   datetime dayTimestamp;  // 00:00:00 timestamp
   double   totalProfit;   // Total Net Profit (USC / USD)
   int      tradesCount;   // Jumlah transaksi selesai
};

//+------------------------------------------------------------------+
//| Helper: Format datetime ke String "YYYY-MM-DD"                   |
//+------------------------------------------------------------------+
string TimeToDateString(datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   return StringFormat("%04d-%02d-%02d", mdt.year, mdt.mon, mdt.day);
}

//+------------------------------------------------------------------+
//| Hitung Offset GMT Broker                                         |
//+------------------------------------------------------------------+
int GetBrokerGmtOffset()
{
   if(!InpAutoDetectBrokerGmt) return InpManualBrokerGmt;
   
   datetime gmt = TimeGMT();
   datetime current = TimeCurrent();
   
   if(gmt <= 0 || current <= 0) return InpManualBrokerGmt;
   
   // Selisih dalam jam bulat
   int diffHours = (int)MathRound((double)(current - gmt) / 3600.0);
   return diffHours;
}

//+------------------------------------------------------------------+
//| Konversi Waktu Server MT5 ke Waktu WIB                           |
//+------------------------------------------------------------------+
datetime ConvertToWIB(datetime serverTime, int brokerGmt)
{
   int offsetDifference = InpTargetGmtOffset - brokerGmt;
   return serverTime + (offsetDifference * 3600);
}

//+------------------------------------------------------------------+
//| Kirim HTTP POST Request ke Google Apps Script                    |
//+------------------------------------------------------------------+
bool SendJsonToGoogle(const string url, const string jsonPayload, string &responseOut)
{
   if(StringLen(url) < 10 || StringFind(url, "https://") < 0)
   {
      Print("[-] URL Google Apps Script belum valid! Mohon masukkan URL Web App yang benar.");
      return false;
   }

   string headers = "Content-Type: application/json\r\n";
   char postData[];
   char result[];
   string resultHeaders;
   
   StringToCharArray(jsonPayload, postData, 0, WHOLE_ARRAY, CP_UTF8);
   // Hilangkan trailing null character dari StringToCharArray
   if(ArraySize(postData) > 0 && postData[ArraySize(postData)-1] == 0)
   {
      ArrayResize(postData, ArraySize(postData) - 1);
   }

   ResetLastError();
   Print("[*] Mengirim data ke Google Spreadsheet...");
   
   int res = WebRequest("POST", url, headers, 15000, postData, result, resultHeaders);
   
   if(res == -1)
   {
      int err = GetLastError();
      PrintFormat("[-] Gagal WebRequest. Error Code: %d", err);
      if(err == 4014)
      {
         Print("[-] PENTING: URL Google Apps Script belum diizinkan di MT5!");
         Print("[-] Silakan buka menu MT5: Tools -> Options -> Expert Advisors -> centang 'Allow WebRequest for listed URL' dan tambahkan URL:");
         Print("    https://script.google.com");
         Print("    https://script.googleusercontent.com");
      }
      return false;
   }
   
   responseOut = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   PrintFormat("[+] Respons Server HTTP Code: %d", res);
   PrintFormat("[+] Detail Respons: %s", responseOut);
   
   return (res >= 200 && res < 400);
}

//+------------------------------------------------------------------+
//| Script Program Main Function                                     |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("======================================================");
   Print("          SINKRONISASI JURNAL TRADING KE GOOGLE SHEET ");
   Print("======================================================");

   int brokerGmt = GetBrokerGmtOffset();
   PrintFormat("[*] Broker GMT Terdeteksi: GMT%+d | Target WIB: GMT%+d", brokerGmt, InpTargetGmtOffset);

   // Tentukan rentang waktu riwayat
   datetime startTime = 0;
   if(InpDaysBack > 0)
   {
      startTime = TimeCurrent() - (InpDaysBack * 86400);
   }
   datetime endTime = TimeCurrent();

   // Pilih riwayat deals
   if(!HistorySelect(startTime, endTime))
   {
      Print("[-] Gagal memuat History Deals dari terminal MT5!");
      return;
   }

   int totalDeals = HistoryDealsTotal();
   PrintFormat("[*] Total riwayat deals ditemukan: %d", totalDeals);

   if(totalDeals == 0)
   {
      Print("[!] Tidak ada transaksi tertutup pada rentang waktu yang dipilih.");
      return;
   }

   // Tampung ke array SDailyProfit
   SDailyProfit dailyList[];
   int dailyCount = 0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      // Hanya ambil transaksi penutupan posisi (ENTRY_OUT / ENTRY_INOUT / ENTRY_OUT_BY)
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT && dealEntry != DEAL_ENTRY_OUT_BY)
      {
         continue;
      }

      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      // Abaikan transaksi deposit / withdraw / penyesuaian saldo
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      {
         continue;
      }

      // Filter Simbol jika diisi
      string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      if(InpFilterSymbol != "" && dealSymbol != InpFilterSymbol)
      {
         continue;
      }

      // Filter Magic jika diisi
      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(InpFilterMagic >= 0 && dealMagic != InpFilterMagic)
      {
         continue;
      }

      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      datetime wibTime  = ConvertToWIB(dealTime, brokerGmt);
      string   dateStr  = TimeToDateString(wibTime);

      double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double fee        = HistoryDealGetDouble(dealTicket, DEAL_FEE);
      double netProfit  = profit + swap + commission + fee;

      // Cari apakah tanggal sudah ada di array
      int foundIndex = -1;
      for(int d = 0; d < dailyCount; d++)
      {
         if(dailyList[d].dateStr == dateStr)
         {
            foundIndex = d;
            break;
         }
      }

      if(foundIndex >= 0)
      {
         dailyList[foundIndex].totalProfit += netProfit;
         dailyList[foundIndex].tradesCount++;
      }
      else
      {
         ArrayResize(dailyList, dailyCount + 1);
         dailyList[dailyCount].dateStr = dateStr;
         dailyList[dailyCount].dayTimestamp = wibTime;
         dailyList[dailyCount].totalProfit = netProfit;
         dailyList[dailyCount].tradesCount = 1;
         dailyCount++;
      }
   }

   if(dailyCount == 0)
   {
      Print("[!] Tidak ada transaksi posisi tertutup yang memenuhi kriteria filter.");
      return;
   }

   // Urutkan tanggal secara Ascending
   for(int i = 0; i < dailyCount - 1; i++)
   {
      for(int j = 0; j < dailyCount - i - 1; j++)
      {
         if(dailyList[j].dateStr > dailyList[j+1].dateStr)
         {
            SDailyProfit tmp = dailyList[j];
            dailyList[j] = dailyList[j+1];
            dailyList[j+1] = tmp;
         }
      }
   }

   PrintFormat("[+] Berhasil merekap %d hari transaksi:", dailyCount);
   for(int i = 0; i < dailyCount; i++)
   {
      PrintFormat("    - [%s]: Net Profit = %+.2f | Total Posisi = %d", 
                  dailyList[i].dateStr, dailyList[i].totalProfit, dailyList[i].tradesCount);
   }

   // Bangun format JSON Payload
   string json = "{\"action\":\"sync_daily_profit\",\"data\":[";
   for(int i = 0; i < dailyCount; i++)
   {
      json += StringFormat("{\"date\":\"%s\",\"profit_usc\":%.2f,\"trades_count\":%d}",
                           dailyList[i].dateStr, dailyList[i].totalProfit, dailyList[i].tradesCount);
      if(i < dailyCount - 1) json += ",";
   }
   json += "]}";

   // Kirim ke Google Apps Script
   string serverResponse = "";
   bool ok = SendJsonToGoogle(InpGoogleWebAppUrl, json, serverResponse);

   if(ok)
   {
      Print("[SUCCESS] Data riwayat transaksi berhasil disinkronkan ke Google Spreadsheet!");
      MessageBox(StringFormat("Berhasil sinkronisasi %d tanggal ke Google Spreadsheet!\n\nRespons: %s", dailyCount, serverResponse),
                 "Sukses Sinkronisasi", MB_OK | MB_ICONINFORMATION);
   }
   else
   {
      Print("[-] Sinkronisasi gagal atau URL belum dikonfigurasi dengan benar.");
      MessageBox("Gagal mengirim data ke Google Spreadsheet.\nPeriksa Tab 'Experts' di MT5 untuk melihat detail pesan kesalahan.",
                 "Gagal Sinkronisasi", MB_OK | MB_ICONWARNING);
   }
}
//+------------------------------------------------------------------+
