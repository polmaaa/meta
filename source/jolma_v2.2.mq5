//+------------------------------------------------------------------+
//|                                                 jolma_v2.2.mq5   |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://gemini.google|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://gemini.google"
#property version   "2.20"
#property description "Expert Advisor jolma_v2.2 - Exact Histori-Based Grid EA"

// Include MQL5 Standard Library for Trading
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Global Trade Objects
CTrade trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== General ==="
input ulong    InpMagicNumber            = 331405160;  // Magic Number
input bool     InpAllowBuy               = true;       // Allow Buy Entries
input bool     InpAllowSell              = true;       // Allow Sell Entries
input bool     InpStartWithDualHedge     = true;       // Start With Dual Hedge
input int      InpOperatingMode          = 1;          // Operating Mode (1 = Standard)
input int      InpSlippage               = 3;          // Slippage in points
input int      InpSpreadFilterMaxPoints  = 40;         // Max Spread in points
input int      InpMaxPositionsTotal      = 0;          // Max Positions Total (0 = No limit)
input int      InpMaxBuyPositions        = 0;          // Max Buy Positions (0 = No limit)
input int      InpMaxSellPositions       = 0;          // Max Sell Positions (0 = No limit)
input bool     InpEnableMaxFloatingLoss  = false;      // Enable Max Floating Loss
input double   InpMaxFloatingLossMoney   = 16000.0;    // Max Floating Loss Money (USC)
input bool     InpPauseEntryOnDrawdown   = false;      // Pause Entries on Drawdown
input double   InpDrawdownPausePercent   = 25.0;       // Pause Drawdown Percent (%)

input group "=== Dashboard Panel ==="
input bool     InpEnableDashboardPanel   = true;       // Enable Dashboard Panel

input group "=== Grid ==="
input int      InpGridStepPoints         = 200;        // Grid Step in points (200 points = 2.00 Gold)
input bool     InpFillMissedLevels       = true;       // Fill Missed Levels

input group "=== Entry Delay ==="
input bool     InpEnableEntryDelay       = false;      // Enable Entry Delay
input int      InpDelayMode              = 0;          // Delay Mode
input int      InpDelayMilliseconds      = 400;        // Delay in Milliseconds
input int      InpDelayCandleTimeframe   = 1;          // Delay Candle Timeframe

input group "=== Lot Sizing ==="
input double   InpInitialLot             = 0.01;       // Initial Lot Size
input int      InpLotMode                = 2;          // Lot Sizing Mode (1 = Exp, 2 = Linear Step, 3 = Linear Inc)
input double   InpLinearIncrement        = 0.01;       // Linear Increment (Mode 3)
input double   InpExponentialMultiplier  = 1.35;       // Exponential Multiplier (Mode 1)
input int      InpStepEveryXLayers       = 7;          // Step Every X Layers (Mode 2)
input double   InpStepLotIncrement       = 0.01;       // Step Lot Increment (Mode 2)
input double   InpMaxLotPerOrder         = 2.5;        // Max Lot Per Order

input group "=== Dynamic TP Per Side ==="
input double   InpBaseTPSideMoney        = 18.0;       // Base TP Side Money (USC)
input int      InpTPLevel1StartLayer     = 8;          // TP Level 1 Start Layer
input double   InpTPLevel1Money          = 25.0;       // TP Level 1 Money (USC)
input int      InpTPLevel2StartLayer     = 10;         // TP Level 2 Start Layer
input double   InpTPLevel2Money          = 70.0;       // TP Level 2 Money (USC)
input int      InpTPLevel3StartLayer     = 20;         // TP Level 3 Start Layer
input double   InpTPLevel3Money          = 200.0;      // TP Level 3 Money (USC)
input int      InpTPLevel4StartLayer     = 30;         // TP Level 4 Start Layer
input double   InpTPLevel4Money          = 400.0;      // TP Level 4 Money (USC)
input int      InpTPLevel5StartLayer     = 40;         // TP Level 5 Start Layer
input double   InpTPLevel5Money          = 800.0;      // TP Level 5 Money (USC)

input group "=== Trailing Per Side ==="
input int      InpTrailingMode           = 0;          // Trailing Mode (0 = Off, 1 = Money, 2 = Points)
input double   InpTrailingStartMoney     = 10.0;       // Trailing Start Money (USC)
input double   InpTrailingLockMoney       = 3.0;        // Trailing Lock Money (USC)
input double   InpTrailingStartPoints    = 400.0;      // Trailing Start Points
input double   InpTrailingLockPoints     = 150.0;      // Trailing Lock Points
input bool     InpEnableDynamicTrailing  = true;       // Enable Dynamic Trailing
input double   InpDynamicTrailingFactor  = 0.15;       // Dynamic Trailing Factor

input group "=== Session Filter ==="
input bool     InpUseSessionFilter       = false;      // Use Session Filter
input int      InpOutsideSessionAction   = 1;          // Outside Session Action (1 = Pause entries)
input bool     Session1Enable            = true;       // Session 1 Enable
input string   Session1Start             = "00:00";    // Session 1 Start
input string   Session1End               = "12:00";    // Session 1 End
input bool     Session2Enable            = true;       // Session 2 Enable
input string   Session2Start             = "12:00";    // Session 2 Start
input string   Session2End               = "00:00";    // Session 2 End
input int      OffsetMinutesFromServer   = 420;        // Server Offset Minutes (e.g. 420 mins = UTC+7)

input group "=== Daily Profit Control ==="
input bool     InpDailyProfitEnable      = false;      // Daily Profit Control Enable
input double   InpDailyProfitTargetUSD   = 2000.0;     // Daily Profit Target (USD)
input int      InpDailyProfitAction      = 1;          // Daily Profit Action (1 = Pause entries)

input group "=== Daily Loss Control ==="
input bool     InpDailyLossEnable        = false;      // Daily Loss Control Enable
input double   InpDailyLossLimitUSD      = 10000.0;    // Daily Loss Limit (USD)
input int      InpDailyLossAction        = 1;          // Daily Loss Action (1 = Close all & Pause)
//+------------------------------------------------------------------+

// Global State Trackers
double g0_buy_price = 0.0;
double g0_sell_price = 0.0;
double buy_trail_peak_profit = 0.0;
double sell_trail_peak_profit = 0.0;
bool buy_trailing_active = false;
bool sell_trailing_active = false;

// Latency & Duplicate Level Protection Global Trackers
int last_sent_buy_level = 9999;
int last_sent_sell_level = 9999;
datetime last_buy_send_time = 0;
datetime last_sell_send_time = 0;

// Multiplier untuk menyelaraskan akun USD ke USC (Cent)
double money_multiplier = 1.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) == 0.0)
   {
      Print("Error: Gagal mendapatkan harga simbol!");
      return(INIT_FAILED);
   }
   
   // Deteksi mata uang akun untuk auto-scale target TP/Loss dari Cent ke USD
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   if(currency == "USD" || currency == "EUR" || currency == "GBP" || currency == "JPY")
   {
      money_multiplier = 0.01;
      Print("Mata uang akun terdeteksi: ", currency, ". Mengaktifkan Auto-Scale Uang (Multiplier = 0.01) untuk menyelaraskan parameter Cent ke USD.");
   }
   else
   {
      money_multiplier = 1.0;
      Print("Mata uang akun terdeteksi: ", currency, ". Menggunakan Multiplier = 1.0.");
   }
   
   Print("EA jolma_v2.2 custom grid-hedge berhasil diinisialisasi.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA jolma_v2.2 dinonaktifkan.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(ask == 0.0 || bid == 0.0) return;
   
   // 1. Spread Filter
   if(spread > InpSpreadFilterMaxPoints) return;
   
   // 2. Session Time Filter
   bool is_inside_session = true;
   if(InpUseSessionFilter)
   {
      is_inside_session = CheckSessionTime();
      if(!is_inside_session && InpOutsideSessionAction == 2)
      {
         CloseAllPositions();
         return;
      }
   }
   
   // 3. Daily Profit & Loss Controls
   if(InpDailyProfitEnable || InpDailyLossEnable)
   {
      double daily_profit = GetDailyProfitLoss();
      if(InpDailyProfitEnable && daily_profit >= InpDailyProfitTargetUSD) return; // Pause entries
      if(InpDailyLossEnable && daily_profit <= -InpDailyLossLimitUSD)
      {
         if(InpDailyLossAction == 2 || InpDailyLossAction == 1) { CloseAllPositions(); return; }
         return; // Pause entries
      }
   }
   
   // 4. Hitung Statistik Transaksi Aktif
   int total_buy = 0;
   int total_sell = 0;
   double buy_profit = 0.0;
   double sell_profit = 0.0;
   
   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double floating_dd_percent = (account_balance > 0) ? ((account_balance - account_equity) / account_balance) * 100.0 : 0.0;
   
   // Cari harga G0 dari posisi aktif di market
   g0_buy_price = 0.0;
   g0_sell_price = 0.0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               total_buy++;
               buy_profit += posInfo.Profit();
               
               if(posInfo.Comment() == "B|G0|L1|TPAnchor|HedgePro" || 
                  posInfo.Comment() == "B|G0|L1|Dual|HedgePro" ||
                  posInfo.Comment() == "B|G0|L1|Idle|HedgePro")
               {
                  g0_buy_price = posInfo.PriceOpen();
               }
            }
            else if(posInfo.PositionType() == POSITION_TYPE_SELL)
            {
               total_sell++;
               sell_profit += posInfo.Profit();
               
               if(posInfo.Comment() == "S|G0|L1|TPAnchor|HedgePro" || 
                  posInfo.Comment() == "S|G0|L1|Dual|HedgePro" ||
                  posInfo.Comment() == "S|G0|L1|Idle|HedgePro")
               {
                  g0_sell_price = posInfo.PriceOpen();
               }
            }
         }
      }
   }
   
   double net_profit = buy_profit + sell_profit;
   
   // 5. Max Floating Loss Control
   if(InpEnableMaxFloatingLoss && net_profit <= -InpMaxFloatingLossMoney * money_multiplier)
   {
      Print("Max Floating Loss terlampaui. Menutup semua posisi.");
      CloseAllPositions();
      return;
   }
   
   // 6. Portfolio Hedge Recovery (Co-Recovery)
   // Tutup gabungan jika ada buy & sell dan total net profit mencapai TP dinamis
   double target_profit = GetTargetProfitForSide(MathMax(total_buy, total_sell));
   if((total_buy > 0 && total_sell > 0) && net_profit >= target_profit)
   {
      Print("Hedge Recovery Tercapai! Net Profit: ", net_profit, " USD/USC. Menutup portfolio.");
      CloseAllPositions();
      return;
   }
   
   // 7. Cek Take Profit & Trailing Arah BUY
   if(total_buy > 0)
   {
      double buy_target = GetTargetProfitForSide(total_buy);
      
      if(InpTrailingMode == 1 && buy_profit >= InpTrailingStartMoney * money_multiplier)
      {
         if(!buy_trailing_active)
         {
            buy_trailing_active = true;
            buy_trail_peak_profit = buy_profit;
         }
         else if(buy_profit > buy_trail_peak_profit)
         {
            buy_trail_peak_profit = buy_profit;
         }
         
         double trail_sl = buy_trail_peak_profit - (InpTrailingStartMoney - InpTrailingLockMoney) * money_multiplier;
         if(buy_profit <= trail_sl)
         {
            Print("Buy Trailing Stop Terpicu! Profit: ", buy_profit);
            ClosePositionsByType(POSITION_TYPE_BUY);
            total_buy = 0;
            buy_trailing_active = false;
         }
      }
      
      if(total_buy > 0 && !buy_trailing_active && buy_profit >= buy_target)
      {
         Print("Buy Basket TP Terpenuhi! Profit: ", buy_profit);
         ClosePositionsByType(POSITION_TYPE_BUY);
         total_buy = 0;
      }
   }
   
   // 8. Cek Take Profit & Trailing Arah SELL
   if(total_sell > 0)
   {
      double sell_target = GetTargetProfitForSide(total_sell);
      
      if(InpTrailingMode == 1 && sell_profit >= InpTrailingStartMoney * money_multiplier)
      {
         if(!sell_trailing_active)
         {
            sell_trailing_active = true;
            sell_trail_peak_profit = sell_profit;
         }
         else if(sell_profit > sell_trail_peak_profit)
         {
            sell_trail_peak_profit = sell_profit;
         }
         
         double trail_sl = sell_trail_peak_profit - (InpTrailingStartMoney - InpTrailingLockMoney) * money_multiplier;
         if(sell_profit <= trail_sl)
         {
            Print("Sell Trailing Stop Terpicu! Profit: ", sell_profit);
            ClosePositionsByType(POSITION_TYPE_SELL);
            total_sell = 0;
            sell_trailing_active = false;
         }
      }
      
      if(total_sell > 0 && !sell_trailing_active && sell_profit >= sell_target)
      {
         Print("Sell Basket TP Terpenuhi! Profit: ", sell_profit);
         ClosePositionsByType(POSITION_TYPE_SELL);
         total_sell = 0;
      }
   }
   
   // 9. Aturan Batas Transaksi Baru
   bool can_buy = (InpMaxPositionsTotal == 0 || (total_buy + total_sell) < InpMaxPositionsTotal) && (InpMaxBuyPositions == 0 || total_buy < InpMaxBuyPositions);
   bool can_sell = (InpMaxPositionsTotal == 0 || (total_buy + total_sell) < InpMaxPositionsTotal) && (InpMaxSellPositions == 0 || total_sell < InpMaxSellPositions);
   
   if(InpPauseEntryOnDrawdown && floating_dd_percent >= InpDrawdownPausePercent)
   {
      can_buy = false;
      can_sell = false;
   }
   
   if(!is_inside_session)
   {
      can_buy = false;
      can_sell = false;
   }
   
   // 10. Logika Pembukaan Awal G0 (Perpetual Grid)
   if(InpStartWithDualHedge)
   {
      if(InpAllowBuy && total_buy == 0 && can_buy)
      {
         double lot = CalculateLotSize(0);
         string comment = (total_sell > 0) ? "B|G0|L1|Dual|HedgePro" : "B|G0|L1|Idle|HedgePro";
         if(trade.Buy(lot, _Symbol, ask, 0.0, 0.0, comment))
         {
            g0_buy_price = ask;
            Print("Membuka BUY G0 (Dual) pada: ", ask);
         }
      }
      
      if(InpAllowSell && total_sell == 0 && can_sell)
      {
         double lot = CalculateLotSize(0);
         string comment = (total_buy > 0) ? "S|G0|L1|Dual|HedgePro" : "S|G0|L1|Idle|HedgePro";
         if(trade.Sell(lot, _Symbol, bid, 0.0, 0.0, comment))
         {
            g0_sell_price = bid;
            Print("Membuka SELL G0 (Dual) pada: ", bid);
         }
      }
   }
   else // InpStartWithDualHedge = false (Mulai searah)
   {
      if(InpAllowBuy && total_buy == 0 && total_sell == 0 && can_buy)
      {
         double lot = CalculateLotSize(0);
         if(trade.Buy(lot, _Symbol, ask, 0.0, 0.0, "B|G0|L1|Idle|HedgePro"))
         {
            g0_buy_price = ask;
         }
      }
      else if(InpAllowSell && total_sell == 0 && total_buy == 0 && can_sell)
      {
         double lot = CalculateLotSize(0);
         if(trade.Sell(lot, _Symbol, bid, 0.0, 0.0, "S|G0|L1|Idle|HedgePro"))
         {
            g0_sell_price = bid;
         }
      }
   }
   
   // 11. Pemicu Grid Seberang Otomatis (Opposite Hedge Trigger)
   if(InpAllowBuy && total_buy == 0 && total_sell >= InpStepEveryXLayers && can_buy)
   {
      double lot = CalculateLotSize(0);
      string comment = "B|G0|L1|Dual|HedgePro";
      if(trade.Buy(lot, _Symbol, ask, 0.0, 0.0, comment))
      {
         g0_buy_price = ask;
         Print("Pemicu Hedge Seberang! Membuka BUY G0 sebagai pelindung SELL L", total_sell);
      }
   }
   
   if(InpAllowSell && total_sell == 0 && total_buy >= InpStepEveryXLayers && can_sell)
   {
      double lot = CalculateLotSize(0);
      string comment = "S|G0|L1|Dual|HedgePro";
      if(trade.Sell(lot, _Symbol, bid, 0.0, 0.0, comment))
      {
         g0_sell_price = bid;
         Print("Pemicu Hedge Seberang! Membuka SELL G0 sebagai pelindung BUY L", total_buy);
      }
   }
   
   // 12. Pemicu Reopen Basket yang Selesai Secara Mandiri
   if(InpAllowBuy && total_buy == 0 && total_sell > 0 && can_buy)
   {
      double lot = CalculateLotSize(0);
      string comment = "B|G0|L1|TPAnchor|HedgePro";
      if(trade.Buy(lot, _Symbol, ask, 0.0, 0.0, comment))
      {
         g0_buy_price = ask;
         Print("Basket BUY selesai. Membuka kembali BUY G0 pada: ", ask);
      }
   }
   
   if(InpAllowSell && total_sell == 0 && total_buy > 0 && can_sell)
   {
      double lot = CalculateLotSize(0);
      string comment = "S|G0|L1|TPAnchor|HedgePro";
      if(trade.Sell(lot, _Symbol, bid, 0.0, 0.0, comment))
      {
         g0_sell_price = bid;
         Print("Basket SELL selesai. Membuka kembali SELL G0 pada: ", bid);
      }
   }
   
   // Konversi jarak grid ke satuan harga
   double grid_step = InpGridStepPoints * point;
   
   // 13. Kelola Penambahan Grid BUY (Averaging Down & Up berdasarkan target level terhitung)
   if(InpAllowBuy && total_buy > 0 && can_buy && g0_buy_price > 0)
   {
      // Cari target level berikutnya yang terdekat dari harga saat ini
      int current_level = (int)MathRound((ask - g0_buy_price) / grid_step);
      
      if(current_level != 0)
      {
         // Pemicu Averaging Down
         if(current_level < 0 && ask <= g0_buy_price + current_level * grid_step)
         {
            if(!LevelExists(POSITION_TYPE_BUY, current_level) && !(current_level == last_sent_buy_level && TimeCurrent() - last_buy_send_time < 5))
            {
               OpenNextGridTrade(POSITION_TYPE_BUY, ask, total_buy, current_level);
            }
         }
         // Pemicu Averaging Up
         else if(current_level > 0 && ask >= g0_buy_price + current_level * grid_step)
         {
            if(!LevelExists(POSITION_TYPE_BUY, current_level) && !(current_level == last_sent_buy_level && TimeCurrent() - last_buy_send_time < 5))
            {
               OpenNextGridTrade(POSITION_TYPE_BUY, ask, total_buy, current_level);
            }
         }
      }
   }
   
   // 14. Kelola Penambahan Grid SELL (Averaging Up & Down berdasarkan target level terhitung)
   if(InpAllowSell && total_sell > 0 && can_sell && g0_sell_price > 0)
   {
      int current_level = (int)MathRound((bid - g0_sell_price) / grid_step);
      
      if(current_level != 0)
      {
         // Pemicu Averaging Up
         if(current_level > 0 && bid >= g0_sell_price + current_level * grid_step)
         {
            if(!LevelExists(POSITION_TYPE_SELL, current_level) && !(current_level == last_sent_sell_level && TimeCurrent() - last_sell_send_time < 5))
            {
               OpenNextGridTrade(POSITION_TYPE_SELL, bid, total_sell, current_level);
            }
         }
         // Pemicu Averaging Down
         else if(current_level < 0 && bid <= g0_sell_price + current_level * grid_step)
         {
            if(!LevelExists(POSITION_TYPE_SELL, current_level) && !(current_level == last_sent_sell_level && TimeCurrent() - last_sell_send_time < 5))
            {
               OpenNextGridTrade(POSITION_TYPE_SELL, bid, total_sell, current_level);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Lot Mode & Layers                    |
//+------------------------------------------------------------------+
double CalculateLotSize(int active_count)
{
   double lot = InpInitialLot;
   
   // Mode 1: Exponential
   if(InpLotMode == 1)
   {
      lot = InpInitialLot * MathPow(InpExponentialMultiplier, active_count);
   }
   // Mode 2: Linear Step (Arithmetic progression dari data histori)
   else if(InpLotMode == 2)
   {
      lot = InpInitialLot + MathFloor(active_count / InpStepEveryXLayers) * InpStepLotIncrement;
   }
   // Mode 3: Linear Increment (Bertambah setiap layer)
   else if(InpLotMode == 3)
   {
      lot = InpInitialLot + active_count * InpLinearIncrement;
   }
   
   if(lot > InpMaxLotPerOrder) lot = InpMaxLotPerOrder;
   
   // Validasi dengan minimum/maksimum broker
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lot < min_volume) lot = min_volume;
   if(lot > max_volume) lot = max_volume;
   
   lot = MathRound(lot / step_volume) * step_volume;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Open Next Grid Trade with dynamic level tracking                 |
//+------------------------------------------------------------------+
void OpenNextGridTrade(ENUM_POSITION_TYPE pos_type, double execution_price, int active_count, int level)
{
   double lot = CalculateLotSize(active_count);
   int layer = active_count + 1;
   
   if(pos_type == POSITION_TYPE_BUY)
   {
      string comment = StringFormat("B|G%d|L%d|Grid|HedgePro", level, layer);
      
      last_sent_buy_level = level;
      last_buy_send_time = TimeCurrent();
      
      if(trade.Buy(lot, _Symbol, execution_price, 0.0, 0.0, comment))
      {
         Print("Membuka Grid BUY L", layer, " (G", level, ") pada harga: ", execution_price, " Lot: ", lot);
      }
   }
   else if(pos_type == POSITION_TYPE_SELL)
   {
      string comment = StringFormat("S|G%d|L%d|Grid|HedgePro", level, layer);
      
      last_sent_sell_level = level;
      last_sell_send_time = TimeCurrent();
      
      if(trade.Sell(lot, _Symbol, execution_price, 0.0, 0.0, comment))
      {
         Print("Membuka Grid SELL L", layer, " (G", level, ") pada harga: ", execution_price, " Lot: ", lot);
      }
   }
}

//+------------------------------------------------------------------+
//| Get dynamic target profit money based on current active layers   |
//+------------------------------------------------------------------+
double GetTargetProfitForSide(int active_count)
{
   double tp = InpBaseTPSideMoney;
   
   if(active_count >= InpTPLevel5StartLayer) tp = InpTPLevel5Money;
   else if(active_count >= InpTPLevel4StartLayer) tp = InpTPLevel4Money;
   else if(active_count >= InpTPLevel3StartLayer) tp = InpTPLevel3Money;
   else if(active_count >= InpTPLevel2StartLayer) tp = InpTPLevel2Money;
   else if(active_count >= InpTPLevel1StartLayer) tp = InpTPLevel1Money;
   
   return tp * money_multiplier;
}

//+------------------------------------------------------------------+
//| Check if current time is inside active trading sessions          |
//+------------------------------------------------------------------+
bool CheckSessionTime()
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   int current_minutes = dt.hour * 60 + dt.min;
   
   // Cek Sesi 1
   if(Session1Enable)
   {
      int start_mins = ParseTimeString(Session1Start);
      int end_mins = ParseTimeString(Session1End);
      if(start_mins <= end_mins)
      {
         if(current_minutes >= start_mins && current_minutes <= end_mins) return true;
      }
      else
      {
         if(current_minutes >= start_mins || current_minutes <= end_mins) return true;
      }
   }
   
   // Cek Sesi 2
   if(Session2Enable)
   {
      int start_mins = ParseTimeString(Session2Start);
      int end_mins = ParseTimeString(Session2End);
      if(start_mins <= end_mins)
      {
         if(current_minutes >= start_mins && current_minutes <= end_mins) return true;
      }
      else
      {
         if(current_minutes >= start_mins || current_minutes <= end_mins) return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Helper to parse "HH:MM" string to minutes of day                 |
//+------------------------------------------------------------------+
int ParseTimeString(string time_str)
{
   string parts[];
   StringSplit(time_str, ':', parts);
   if(ArraySize(parts) < 2) return 0;
   
   int hour = (int)StringToInteger(parts[0]);
   int min = (int)StringToInteger(parts[1]);
   
   return hour * 60 + min;
}

//+------------------------------------------------------------------+
//| Get daily profit/loss in account currency                        |
//+------------------------------------------------------------------+
double GetDailyProfitLoss()
{
   datetime now = TimeCurrent();
   datetime start_of_day = now - (now % 86400); // 00:00 server time
   
   HistorySelect(start_of_day, now);
   int total_deals = HistoryDealsTotal();
   double daily_profit = 0.0;
   
   for(int i = 0; i < total_deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0)
      {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagicNumber)
         {
            daily_profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         }
      }
   }
   
   return daily_profit;
}

//+------------------------------------------------------------------+
//| Close all positions of a specific type (Buy or Sell)             |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE pos_type)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber && posInfo.PositionType() == pos_type)
         {
            trade.PositionClose(posInfo.Ticket(), InpSlippage);
         }
      }
   }
   
   if(pos_type == POSITION_TYPE_BUY) g0_buy_price = 0.0;
   if(pos_type == POSITION_TYPE_SELL) g0_sell_price = 0.0;
}

//+------------------------------------------------------------------+
//| Close all positions (Buys & Sells) under magic number            |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            trade.PositionClose(posInfo.Ticket(), InpSlippage);
         }
      }
   }
   
   g0_buy_price = 0.0;
   g0_sell_price = 0.0;
}

//+------------------------------------------------------------------+
//| Check if an active position already exists at the given level    |
//+------------------------------------------------------------------+
bool LevelExists(ENUM_POSITION_TYPE pos_type, int level)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double grid_step = InpGridStepPoints * point;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber && posInfo.PositionType() == pos_type)
         {
            double g0_price = (pos_type == POSITION_TYPE_BUY) ? g0_buy_price : g0_sell_price;
            if(g0_price == 0.0) continue;
            
            int pos_level = (int)MathRound((posInfo.PriceOpen() - g0_price) / grid_step);
            if(pos_level == level) return true;
         }
      }
   }
   return false;
}
