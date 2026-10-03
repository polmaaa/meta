//+------------------------------------------------------------------+
//|                                        AutoJournalTrackerEA.mq5 |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://mql5.com     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property link      "https://mql5.com"
#property version   "1.00"

//--- Input Parameters
input group "=== PENGATURAN GOOGLE SPREADSHEET ==="
input string   InpGoogleWebAppUrl    = "https://script.google.com/macros/s/AKfycb.../exec"; // URL Web App Google Apps Script
input int      InpSyncIntervalMins   = 15;                 // Sinkronisasi Rutin Tiap Berapa Menit (Timer)
input bool     InpSyncOnTradeClosed  = true;               // Otomatis Sync Langsung Saat Ada Posisi Tertutup

input group "=== PENGATURAN ZONA WAKTU (WIB) ==="
input int      InpTargetGmtOffset    = 7;                  // Target Zona Waktu (WIB = GMT+7)
input bool     InpAutoDetectBrokerGmt= true;               // Deteksi Otomatis Selisih Jam Broker
input int      InpManualBrokerGmt    = 3;                  // Manual Broker GMT (jika AutoDetect = false)

input group "=== FILTER TRANSAKSI ==="
input int      InpLookbackDays       = 7;                  // Cek Riwayat Berapa Hari Terakhir (Default: 7 hari)
input string   InpFilterSymbol       = "";                 // Filter Simbol (Kosongkan utk Semua Simbol)
input long     InpFilterMagic        = -1;                 // Filter Magic Number (-1 = Semua Magic)

//--- Variabel Global
datetime g_lastSyncTime = 0;
datetime g_lastDealTime = 0;

//--- Struktur Rekap Harian
struct SDailyProfit
{
   string   dateStr;       // YYYY-MM-DD
   datetime dayTimestamp;  // 00:00:00 timestamp
   double   totalProfit;   // Total Net Profit (USC / USD)
   int      tradesCount;   // Jumlah transaksi selesai
};

//+------------------------------------------------------------------+
//| Format datetime ke String "YYYY-MM-DD"                           |
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
   return (int)MathRound((double)(current - gmt) / 3600.0);
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
      Print("[EA] [PERINGATAN] URL Google Apps Script belum diisi / tidak valid!");
      return false;
   }

   string headers = "Content-Type: application/json\r\n";
   char postData[];
   char result[];
   string resultHeaders;
   
   StringToCharArray(jsonPayload, postData, 0, WHOLE_ARRAY, CP_UTF8);
   if(ArraySize(postData) > 0 && postData[ArraySize(postData)-1] == 0)
   {
      ArrayResize(postData, ArraySize(postData) - 1);
   }

   uint startTicks = GetTickCount();
   ResetLastError();
   int res = WebRequest("POST", url, headers, 10000, postData, result, resultHeaders);
   uint elapsedMs = GetTickCount() - startTicks;
   
   if(res == -1)
   {
      int err = GetLastError();
      PrintFormat("[EA] [GAGAL] WebRequest Error Code: %d (Durasi: %d ms).", err, elapsedMs);
      if(err == 4014)
      {
         Print("[EA] [PENTING] Masukkan https://script.google.com dan https://script.googleusercontent.com ke menu Tools -> Options -> Expert Advisors -> Allow WebRequest!");
      }
      return false;
   }
   
   responseOut = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   PrintFormat("[EA] [SUKSES] HTTP Code: %d | Waktu proses: %.2f detik | Respons: %s", res, elapsedMs / 1000.0, responseOut);
   return (res >= 200 && res < 400);
}

//+------------------------------------------------------------------+
//| Lakukan Proses Rekap dan Kirim ke Google Sheet                   |
//+------------------------------------------------------------------+
void PerformSync()
{
   int brokerGmt = GetBrokerGmtOffset();
   datetime startTime = (InpLookbackDays > 0) ? (TimeCurrent() - (InpLookbackDays * 86400)) : 0;
   datetime endTime = TimeCurrent();

   if(!HistorySelect(startTime, endTime)) return;

   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;

   SDailyProfit dailyList[];
   int dailyCount = 0;

   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket <= 0) continue;

      long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT && dealEntry != DEAL_ENTRY_OUT_BY) continue;

      long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

      string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      if(InpFilterSymbol != "" && dealSymbol != InpFilterSymbol) continue;

      long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
      if(InpFilterMagic >= 0 && dealMagic != InpFilterMagic) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      datetime wibTime  = ConvertToWIB(dealTime, brokerGmt);
      string   dateStr  = TimeToDateString(wibTime);

      double profit     = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double fee        = HistoryDealGetDouble(dealTicket, DEAL_FEE);
      double netProfit  = profit + swap + commission + fee;

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

   if(dailyCount == 0) return;

   // Urutkan Ascending
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

   string json = "{\"action\":\"sync_daily_profit\",\"data\":[";
   for(int i = 0; i < dailyCount; i++)
   {
      json += StringFormat("{\"date\":\"%s\",\"profit_usc\":%.2f,\"trades_count\":%d}",
                           dailyList[i].dateStr, dailyList[i].totalProfit, dailyList[i].tradesCount);
      if(i < dailyCount - 1) json += ",";
   }
   json += "]}";

   string resp = "";
   if(SendJsonToGoogle(InpGoogleWebAppUrl, json, resp))
   {
      g_lastSyncTime = TimeCurrent();
      PrintFormat("[EA] Sukses sinkronisasi jurnal ke Google Sheets (%d hari terkirim).", dailyCount);
   }
}

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("[EA] AutoJournalTrackerEA dimulai.");
   EventSetTimer(60); // Timer cek tiap 60 detik
   PerformSync();     // Lakukan sync pertama saat EA dipasang
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("[EA] AutoJournalTrackerEA dimatikan.");
}

//+------------------------------------------------------------------+
//| Expert Timer Function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpSyncIntervalMins > 0)
   {
      if(TimeCurrent() - g_lastSyncTime >= (InpSyncIntervalMins * 60))
      {
         PerformSync();
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Function (Deteksi Posisi Tertutup)       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!InpSyncOnTradeClosed) return;

   // Cek jika ada Deal baru yang ditambahkan
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         // Jika transaksi adalah penutupan posisi (ENTRY_OUT)
         if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT || dealEntry == DEAL_ENTRY_OUT_BY)
         {
            PrintFormat("[EA] Terdeteksi penutupan deal #%I64u. Memulai auto sync ke Google Sheet...", dealTicket);
            PerformSync();
         }
      }
   }
}
//+------------------------------------------------------------------+
