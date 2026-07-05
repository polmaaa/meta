//+------------------------------------------------------------------+
//|                                                 jolma_v2.1.mq5   |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://gemini.google|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://gemini.google"
#property version   "2.40"
#property description "Active Bollinger Bands Reversion EA with Auto-History Validation"

// Include MQL5 Standard Library
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Global Objects
CTrade trade;
CPositionInfo posInfo;

// Indicator Handles
int handle_bb;
int handle_ema_slow;
int handle_atr;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double   InpRiskPercent            = 1.5;        // Risk Percent per Trade (1.5 = 1.5% of Equity)
input double   InpMinLot                 = 0.01;       // Minimum Lot Size
input double   InpMaxLot                 = 5.0;        // Maximum Lot Size
input ulong    InpMagicNumber            = 331405160;  // Magic Number

input group "=== Bollinger Bands ==="
input int      InpBBPeriod               = 20;         // BB Period (Default: 20)
input double   InpBBDeviation            = 2.0;        // BB Deviation (Default: 2.0)

input group "=== Trend Filter ==="
input bool     InpUseTrendFilter         = false;      // Enable EMA Trend Filter (Matikan jika data histori terbatas)
input int      InpEMASlowPeriod          = 50;         // EMA Trend Filter Period

input group "=== Volatility (ATR) ==="
input int      InpATRPeriod              = 14;         // ATR Period
input double   InpStopLossMultiplier     = 1.5;        // Stop Loss ATR Multiplier (SL = 1.5 * ATR)
input double   InpTakeProfitMultiplier   = 3.0;        // Take Profit ATR Multiplier (TP = 3.0 * ATR)

input group "=== Trailing Stop ==="
input bool     InpEnableTrailing         = true;       // Enable Trailing Stop
input double   InpTrailingStartATR       = 1.2;        // Trailing Start ATR Multiplier
input double   InpTrailingStepATR        = 0.4;        // Trailing Stop Distance ATR Multiplier
//+------------------------------------------------------------------+

// Global Variables
datetime last_bar_time = 0;
bool warning_printed_bb = false;
bool warning_printed_ema = false;
bool warning_printed_atr = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   // Inisialisasi indicator handles
   handle_bb = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, _Period, InpATRPeriod);
   
   if(InpUseTrendFilter)
   {
      handle_ema_slow = iMA(_Symbol, _Period, InpEMASlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   }
   else
   {
      handle_ema_slow = INVALID_HANDLE;
   }
   
   if(handle_bb == INVALID_HANDLE || handle_atr == INVALID_HANDLE || (InpUseTrendFilter && handle_ema_slow == INVALID_HANDLE))
   {
      Print("Error: Gagal menginisialisasi indikator Bollinger Bands/ATR/EMA!");
      return(INIT_FAILED);
   }
   
   Print("EA jolma_v2.4 Active BB Reversion berhasil diaktifkan.");
   Print("Trend Filter: ", InpUseTrendFilter ? "Aktif" : "Non-aktif");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handle_bb);
   IndicatorRelease(handle_atr);
   if(handle_ema_slow != INVALID_HANDLE)
   {
      IndicatorRelease(handle_ema_slow);
   }
   
   Print("EA jolma_v2.4 dinonaktifkan.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Dapatkan waktu bar saat ini untuk filter bar baru
   datetime current_bar_time = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);
   bool is_new_bar = (current_bar_time != last_bar_time);
   
   // 2. Trailing Stop dijalankan setiap tick untuk presisi
   if(InpEnableTrailing)
   {
      ManageTrailingStop();
   }
   
   // Hanya lakukan evaluasi entry posisi pada penutupan bar
   if(!is_new_bar) return;
   
   // 3. Salin data indikator terbaru dengan pengecekan error & log
   double main_bb[2], upper_bb[2], lower_bb[2];
   double ema_slow[2];
   double atr[2];
   
   if(CopyBuffer(handle_bb, 0, 1, 2, main_bb) < 2 || 
      CopyBuffer(handle_bb, 1, 1, 2, upper_bb) < 2 || 
      CopyBuffer(handle_bb, 2, 1, 2, lower_bb) < 2)
   {
      if(!warning_printed_bb)
      {
         Print("Warning: Menunggu data Bollinger Bands siap (membutuhkan minimal ", InpBBPeriod, " bar histori)...");
         warning_printed_bb = true;
      }
      return;
   }
   warning_printed_bb = false; // Reset warning jika sudah siap
   
   if(CopyBuffer(handle_atr, 0, 1, 2, atr) < 2)
   {
      if(!warning_printed_atr)
      {
         Print("Warning: Menunggu data ATR siap (membutuhkan minimal ", InpATRPeriod, " bar histori)...");
         warning_printed_atr = true;
      }
      return;
   }
   warning_printed_atr = false;
   
   if(InpUseTrendFilter && handle_ema_slow != INVALID_HANDLE)
   {
      if(CopyBuffer(handle_ema_slow, 0, 1, 2, ema_slow) < 2)
      {
         if(!warning_printed_ema)
         {
            Print("Warning: Menunggu data EMA Trend siap (membutuhkan minimal ", InpEMASlowPeriod, " bar histori)...");
            warning_printed_ema = true;
         }
         return;
      }
   }
   warning_printed_ema = false;
   
   // Dapatkan harga pasar
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close_prev = iClose(_Symbol, _Period, 1);
   double low_prev = iLow(_Symbol, _Period, 1);
   double high_prev = iHigh(_Symbol, _Period, 1);
   
   // Hitung jumlah posisi aktif kita
   int total_buy = 0;
   int total_sell = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY) total_buy++;
            if(posInfo.PositionType() == POSITION_TYPE_SELL) total_sell++;
         }
      }
   }
   
   // 4. Logika Sinyal Entry Aktif (Bollinger Bands Mean Reversion)
   if(total_buy == 0 && total_sell == 0)
   {
      // --- SIGNAL BUY ---
      // Tren Global: Bullish (Jika filter tren aktif, harga penutupan harus di atas EMA Slow)
      // Reversi: Low bar sebelumnya menembus atau menyentuh Lower Bollinger Band
      bool is_bullish_trend = !InpUseTrendFilter || (close_prev > ema_slow[0]);
      bool is_bb_oversold = (low_prev <= lower_bb[0]);
      
      if(is_bullish_trend && is_bb_oversold)
      {
         double sl_price = ask - (atr[0] * InpStopLossMultiplier);
         double tp_price = ask + (atr[0] * InpTakeProfitMultiplier);
         double lot = CalculateRiskLot(sl_price, ask);
         
         if(trade.Buy(lot, _Symbol, ask, sl_price, tp_price, "B|BB_Reversion|HedgePro"))
         {
            Print("Membuka BUY. Price: ", ask, " SL: ", sl_price, " TP: ", tp_price);
            last_bar_time = current_bar_time;
         }
      }
      
      // --- SIGNAL SELL ---
      // Tren Global: Bearish (Jika filter tren aktif, harga penutupan harus di bawah EMA Slow)
      // Reversi: High bar sebelumnya menembus atau menyentuh Upper Bollinger Band
      bool is_bearish_trend = !InpUseTrendFilter || (close_prev < ema_slow[0]);
      bool is_bb_overbought = (high_prev >= upper_bb[0]);
      
      if(is_bearish_trend && is_bb_overbought)
      {
         double sl_price = bid + (atr[0] * InpStopLossMultiplier);
         double tp_price = bid - (atr[0] * InpTakeProfitMultiplier);
         double lot = CalculateRiskLot(bid, sl_price);
         
         if(trade.Sell(lot, _Symbol, bid, sl_price, tp_price, "S|BB_Reversion|HedgePro"))
         {
            Print("Membuka SELL. Price: ", bid, " SL: ", sl_price, " TP: ", tp_price);
            last_bar_time = current_bar_time;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Dynamic Risk Percent                 |
//+------------------------------------------------------------------+
double CalculateRiskLot(double sl_price, double entry_price)
{
   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_money = account_equity * (InpRiskPercent / 100.0);
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tick_size == 0 || tick_value == 0) return InpMinLot;
   
   double sl_distance_points = MathAbs(entry_price - sl_price) / point;
   if(sl_distance_points <= 0) return InpMinLot;
   
   double lot = risk_money / ((sl_distance_points * point / tick_size) * tick_value);
   
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(lot < min_volume) lot = min_volume;
   if(lot > max_volume) lot = max_volume;
   if(lot < InpMinLot) lot = InpMinLot;
   if(lot > InpMaxLot) lot = InpMaxLot;
   
   lot = MathRound(lot / step_volume) * step_volume;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop for active positions                        |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double atr[1];
   if(CopyBuffer(handle_atr, 0, 0, 1, atr) < 1) return;
   
   double trail_start_dist = atr[0] * InpTrailingStartATR;
   double trail_stop_dist = atr[0] * InpTrailingStepATR;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagicNumber)
         {
            if(posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(bid - posInfo.PriceOpen() >= trail_start_dist)
               {
                  double new_sl = bid - trail_stop_dist;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                  
                  if(new_sl > posInfo.StopLoss() || posInfo.StopLoss() == 0)
                  {
                     trade.PositionModify(posInfo.Ticket(), new_sl, posInfo.TakeProfit());
                  }
               }
            }
            else if(posInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(posInfo.PriceOpen() - ask >= trail_start_dist)
               {
                  double new_sl = ask + trail_stop_dist;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                  
                  if(new_sl < posInfo.StopLoss() || posInfo.StopLoss() == 0)
                  {
                     trade.PositionModify(posInfo.Ticket(), new_sl, posInfo.TakeProfit());
                  }
               }
            }
         }
      }
   }
}
