//+------------------------------------------------------------------+
//|                       NomShadoNgidi_EA.mq5                       |
//|            Expert Advisor — Nomshado Ngidi Trading Plan Q1 2025  |
//|                             Version 1.0                          |
//+------------------------------------------------------------------+
//
//  SETUP MODELS IMPLEMENTED:
//  BUY  → FVG Asian Buy | FVG Buy | Straight Buy
//  SELL → FVG Asian Sell | FVG Sell | Straight Sell
//
//  MANUAL TASKS (cannot be automated — trader must do these):
//  • Check DXY for directional confluence each session
//  • Identify key Daily/Weekly/Monthly levels before the week starts
//  • Mark equal highs/lows on the weekly chart
//  • Determine weekly phase: Trend / Reversal / Correction
//  • Review upcoming news (CPI, PPI, NFP) on an economic calendar
//  • Maintain daily bias; do not flip bias until price reaches key levels
//
//  HOW TO INSTALL:
//  1. Copy this file to: MT5 → File → Open Data Folder → MQL5 → Experts
//  2. Restart MetaTrader 5 (or press F5 in MetaEditor)
//  3. Drag the EA onto your H1 chart of the desired symbol
//  4. Ensure "Allow Algo Trading" is enabled in MT5
//  5. Configure input parameters to match your account/timezone
//
//+------------------------------------------------------------------+
#property copyright   "Nomshado Ngidi"
#property version     "1.00"
#property description "MT5 EA — Nomshado Ngidi Trading Plan Q1 2025"
#property description "Setups: FVG Buy/Sell, Asian FVG, Straight"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//============================================================
//  INPUT PARAMETERS
//============================================================

// All session hours are in NEW YORK TIME.
// Set InpNYtoServer = hours to add to NY time to reach your broker's server time.
// Examples: NYC broker (EST) = 0 | GMT broker = 5 | GMT+2 broker = 7 | GMT+3 broker = 8
input group "=== Session Times (New York Time) ==="
input int    InpNYtoServer     = 5;    // NY-to-Server offset (hours). EST=5, EDT=4, GMT+2=7
input int    InpAsianStartNY   = 19;   // Asian Session Start — NY time (plan: 19:00)
input int    InpAsianEndNY     = 0;    // Asian Session End   — NY time (plan: 00:00)
input int    InpLondonStartNY  = 2;    // London Kill Zone Start — NY time (plan: 02:00)
input int    InpNYKillZoneNY   = 5;    // NY Kill Zone Start — NY time (plan: 05:00–10:00)
input int    InpTradingEndNY   = 10;   // NY Kill Zone End / Trading Window End — NY time (plan: 10:00)

input group "=== Risk Management ==="
input double InpMinRRR         = 2.0;  // Minimum Risk:Reward Ratio (1:2 per plan)

input group "=== Stop Loss Settings ==="
input int    InpFVGBuffer      = 3;    // SL buffer beyond FVG/structure level (pips)

input group "=== Trade Settings ==="
input int    InpMaxDailyTrades = 2;    // Max trades per day (plan: max 2)
input bool   InpAllowMonday    = false;// Allow Monday trading (plan: NO)
input int    InpSTH_Lookback   = 20;   // Short-term High/Low lookback (H1 bars)
input int    InpMagicNumber    = 20250101; // EA Magic Number

input group "=== Alerts ==="
input bool   InpPopupAlerts    = true; // Enable popup alerts on new setup
input bool   InpPushAlerts     = false;// Enable push notifications

//============================================================
//  GLOBAL VARIABLES
//============================================================

CTrade       trade;
CPositionInfo pos;

// Daily trade counter
int      g_DailyCount   = 0;
datetime g_LastDay      = 0;

// Pip size (handles 3 & 5-digit brokers, and JPY pairs)
double g_PipSize        = 0;

// Asian session data (refreshed each new day)
double   g_AsianHigh        = 0;
double   g_AsianLow         = 0;
bool     g_AsianFVGBullish  = false;
bool     g_AsianFVGBearish  = false;
bool     g_AllAsianBullish  = false;
bool     g_AllAsianBearish  = false;
int      g_AsianLastBar     = -1;
datetime g_AsianDate        = 0;

// Per-day setup guards
bool     g_FVGSellDone        = false; // FVG Sell: do not reenter after first signal
bool     g_AsianSellSLHit     = false; // FVG Asian Sell closed at SL loss today
bool     g_AsianSellReentered = false; // Re-entry buy already placed after Asian Sell SL

//============================================================
//  INITIALISATION
//============================================================

int OnInit()
{
   // Determine pip size for this symbol
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_PipSize = (digits == 3 || digits == 5) ? _Point * 10.0 : _Point;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   PrintFormat("=== Nomshado Ngidi EA v1.0 Initialised ===");
   PrintFormat("Symbol: %s | Pip Size: %.5f", _Symbol, g_PipSize);
   PrintFormat("Risk per trade: Account Balance / 6 | Min RRR 1:%.1f", InpMinRRR);
   PrintFormat("Asian NY: %02d:00-%02d:00 | London KZ NY: %02d:00-%02d:00 | NY KZ NY: %02d:00-%02d:00",
               InpAsianStartNY, InpAsianEndNY, InpLondonStartNY, InpNYKillZoneNY,
               InpNYKillZoneNY, InpTradingEndNY);
   PrintFormat("NY-to-Server offset: +%d hrs | Max daily trades: %d",
               InpNYtoServer, InpMaxDailyTrades);

   if(!InpAllowMonday)
      Print("Monday filter: ACTIVE (no trades on Mondays)");

   Print("REMINDER: Check DXY, key Daily/Weekly levels, and news before each session.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("EA removed. Reason code: %d", reason);
}

//============================================================
//  MAIN TICK — only acts on newly closed H1 bar
//============================================================

void OnTick()
{
   static datetime s_LastBar = 0;
   datetime curBar = iTime(_Symbol, PERIOD_H1, 0);
   if(curBar == s_LastBar) return;
   s_LastBar = curBar;

   // --- Pre-trade guards ---
   ResetDailyCount();

   // Monitor FVG Asian Sell position for SL hit (runs every bar, outside trading window)
   CheckAsianSellSLReentry();

   if(!InpAllowMonday && IsMonday())        return;
   if(g_DailyCount >= InpMaxDailyTrades)    return;
   if(!IsInTradingWindow())                 return;
   // No HasOpenPosition() block — a carry-over trade from a previous day
   // does not prevent opening up to InpMaxDailyTrades new trades today.

   // Build Asian session context for today
   AnalyseAsianSession();

   // Re-entry buy triggered by FVG Asian Sell SL hit — takes priority this bar
   if(g_AsianSellSLHit && !g_AsianSellReentered)
   {
      TryAsianSellReentryBuy();
      return;
   }

   // Scan buy setups first; if nothing triggers, scan sells
   if(!ScanBuySetups())
      ScanSellSetups();
}

//============================================================
//  TIME HELPERS
//============================================================

bool IsMonday()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.day_of_week == 1;
}

bool IsInTradingWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int serverHour  = dt.hour;
   int serverStart = NYtoServer(InpLondonStartNY);  // London KZ open = trading starts
   int serverEnd   = NYtoServer(InpTradingEndNY);
   return (serverHour >= serverStart && serverHour < serverEnd);
}

int CurrentHour()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.hour;
}

// Returns the server hour that corresponds to the NY Kill Zone open
int ServerNYKillZone() { return NYtoServer(InpNYKillZoneNY); }

datetime TodayMidnight()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

//============================================================
//  TIME CONVERSION
//  All session times are configured as New York time.
//  NYtoServer() converts them to broker server time.
//============================================================

int NYtoServer(int nyHour) { return (nyHour + InpNYtoServer) % 24; }

void ResetDailyCount()
{
   datetime today = TodayMidnight();
   if(today != g_LastDay)
   {
      g_DailyCount          = 0;
      g_LastDay             = today;
      g_FVGSellDone         = false;
      g_AsianSellSLHit      = false;
      g_AsianSellReentered  = false;
   }
}

double PipsToPrice(double pips) { return pips * g_PipSize; }
double PriceToPips(double dist)  { return (g_PipSize > 0) ? dist / g_PipSize : 0; }

double CalcLotSize(double slPips)
{
   if(slPips <= 0) return 0;

   // Plan formula: lots = (balance / 6) / slPips / 10
   // Example: balance=$600 → risk=$100 | SL=50 pips → $100/50=2 → 2/10=0.2 lots
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lots    = (balance / 6.0) / slPips / 10.0;

   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   // Round down to nearest broker step, then clamp to broker min/max.
   // If rounding produces 0 we still use minLot so the trade is never
   // blocked purely because of leverage / lot-size constraints.
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   PrintFormat("CalcLotSize: balance=%.2f risk=%.2f SL=%.1f pips → lots=%.2f (min=%.2f max=%.2f)",
               balance, balance / 6.0, slPips, lots, minLot, maxLot);
   return lots;
}

//============================================================
//  ASIAN SESSION ANALYSIS
//  Runs once per calendar day to build context:
//  • Asian High/Low range
//  • Whether last Asian candle had a bullish or bearish FVG
//  • Whether all Asian candles were bullish/bearish (reversal warning)
//============================================================

void AnalyseAsianSession()
{
   datetime today = TodayMidnight();
   if(today == g_AsianDate) return; // Already done for today

   // Reset
   g_AsianHigh       = 0;
   g_AsianLow        = DBL_MAX;
   g_AsianFVGBullish = false;
   g_AsianFVGBearish = false;
   g_AllAsianBullish = true;
   g_AllAsianBearish = true;
   g_AsianLastBar    = -1;

   int totalBars = iBars(_Symbol, PERIOD_H1);
   bool foundAny = false;

   for(int i = 1; i < totalBars; i++)
   {
      datetime bTime = iTime(_Symbol, PERIOD_H1, i);
      MqlDateTime bDt;
      TimeToStruct(bTime, bDt);

      // Reconstruct this bar's midnight
      MqlDateTime bMidDt = bDt;
      bMidDt.hour = 0; bMidDt.min = 0; bMidDt.sec = 0;
      datetime bDay = StructToTime(bMidDt);

      if(bDay < today) break;    // Reached yesterday — stop
      if(bDay > today) continue; // Future bar — skip

      // Asian session: 19:00–00:00 NY, converted to server time
      int sAsianStart = NYtoServer(InpAsianStartNY); // e.g. NY 19 + offset
      int sAsianEnd   = NYtoServer(InpAsianEndNY);   // e.g. NY 00 + offset
      bool inAsian    = (sAsianStart < sAsianEnd)
                        ? (bDt.hour >= sAsianStart && bDt.hour < sAsianEnd)
                        : (bDt.hour >= sAsianStart || bDt.hour < sAsianEnd); // handles wrap

      if(inAsian)
      {
         foundAny = true;
         double bH = iHigh (_Symbol, PERIOD_H1, i);
         double bL = iLow  (_Symbol, PERIOD_H1, i);
         double bO = iOpen (_Symbol, PERIOD_H1, i);
         double bC = iClose(_Symbol, PERIOD_H1, i);

         if(bH > g_AsianHigh) g_AsianHigh = bH;
         if(bL < g_AsianLow)  g_AsianLow  = bL;

         if(bC <= bO) g_AllAsianBullish = false;
         if(bC >= bO) g_AllAsianBearish = false;

         // Track the LAST (most recent) Asian session bar = the bar just before session ends
         int sAsianLast = (sAsianEnd - 1 + 24) % 24;
         if(bDt.hour == sAsianLast)
            g_AsianLastBar = i;
      }
   }

   if(!foundAny)
   {
      g_AsianLow        = 0;
      g_AllAsianBullish = false;
      g_AllAsianBearish = false;
   }
   else if(g_AsianLow == DBL_MAX)
   {
      g_AsianLow = 0;
   }

   // Detect FVG on the last Asian candle
   if(g_AsianLastBar > 0)
   {
      int fvgType = DetectFVG(g_AsianLastBar);
      g_AsianFVGBullish = (fvgType ==  1);
      g_AsianFVGBearish = (fvgType == -1);
   }

   g_AsianDate = today;

   // === PLAN WARNING: all bullish Asian candles → watch for sell reversal ===
   if(g_AllAsianBullish)
   {
      string msg = "⚠ CAUTION: All Asian candles BULLISH — potential SELL reversal forming on " + _Symbol;
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }

   PrintFormat("Asian session analysed | High: %.5f | Low: %.5f | FVG: %s | AllBull: %s | AllBear: %s",
               g_AsianHigh, g_AsianLow,
               g_AsianFVGBullish ? "BULLISH" : g_AsianFVGBearish ? "BEARISH" : "NONE",
               g_AllAsianBullish ? "YES" : "NO",
               g_AllAsianBearish ? "YES" : "NO");
}

//============================================================
//  FVG (FAIR VALUE GAP) DETECTION
//
//  A 3-candle pattern:
//    LEFT  = bar[startBar + 2]  (oldest)
//    MIDDLE= bar[startBar + 1]  (impulse)
//    RIGHT = bar[startBar]      (newest / confirmation)
//
//  Bullish FVG : LEFT.high < RIGHT.low  → upward gap, price moved up fast
//  Bearish FVG : LEFT.low  > RIGHT.high → downward gap, price moved down fast
//
//  Returns: 1 = bullish, -1 = bearish, 0 = no FVG
//============================================================

int DetectFVG(int startBar)
{
   if(startBar < 1 || startBar + 2 >= iBars(_Symbol, PERIOD_H1)) return 0;

   double leftHigh  = iHigh(_Symbol, PERIOD_H1, startBar + 2);
   double leftLow   = iLow (_Symbol, PERIOD_H1, startBar + 2);
   double rightLow  = iLow (_Symbol, PERIOD_H1, startBar);
   double rightHigh = iHigh(_Symbol, PERIOD_H1, startBar);

   if(leftHigh < rightLow)  return  1;  // Bullish FVG
   if(leftLow  > rightHigh) return -1;  // Bearish FVG
   return 0;
}

// Returns the price range (zone) of a detected FVG
// For bullish FVG: zoneLow = left.high, zoneHigh = right.low  (the gap going up)
// For bearish FVG: zoneHigh= left.low,  zoneLow  = right.high (the gap going down)
bool GetFVGZone(int startBar, double &zoneHigh, double &zoneLow)
{
   int type = DetectFVG(startBar);
   if(type == 0) return false;

   if(type == 1) // Bullish: gap from left.high up to right.low
   {
      zoneLow  = iHigh(_Symbol, PERIOD_H1, startBar + 2); // bottom of gap
      zoneHigh = iLow (_Symbol, PERIOD_H1, startBar);     // top of gap
   }
   else // Bearish: gap from right.high up to left.low
   {
      zoneHigh = iLow (_Symbol, PERIOD_H1, startBar + 2); // top of gap (left.low)
      zoneLow  = iHigh(_Symbol, PERIOD_H1, startBar);     // bottom of gap (right.high)
   }

   return (zoneHigh > zoneLow);
}

//============================================================
//  MARKET STRUCTURE UTILITIES
//============================================================

// Short-term high: the most recent level where a bullish body is immediately followed
// by a bearish body — where bulls met bears. TP level = open of that bearish candle.
// Must be ABOVE the Asian session high. Falls back to highest high if no pattern found.
double GetSTHigh(int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      // bar[i+1] bullish → bar[i] bearish: bodies meeting at a high
      if(IsBearishCandle(i) && IsBullishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i); // Open of bearish candle = meeting point
         if(level > g_AsianHigh) return level;
      }
   }

   // Fallback: highest high in lookback
   double h = 0;
   for(int i = 1; i <= lim; i++)
      h = MathMax(h, iHigh(_Symbol, PERIOD_H1, i));
   return h;
}

// Short-term low: the most recent level where a bearish body is immediately followed
// by a bullish body — where bears met bulls. TP level = open of that bullish candle.
// Must be BELOW the Asian session low. Falls back to lowest low if no pattern found.
double GetSTLow(int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      // bar[i+1] bearish → bar[i] bullish: bodies meeting at a low
      if(IsBullishCandle(i) && IsBearishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i); // Open of bullish candle = meeting point
         if(level < g_AsianLow) return level;
      }
   }

   // Fallback: lowest low in lookback
   double l = DBL_MAX;
   for(int i = 1; i <= lim; i++)
      l = MathMin(l, iLow(_Symbol, PERIOD_H1, i));
   return (l == DBL_MAX) ? 0 : l;
}

bool IsBullishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) > iOpen(_Symbol, PERIOD_H1, bar); }
bool IsBearishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) < iOpen(_Symbol, PERIOD_H1, bar); }

bool HasDownsideViolation()
{
   // Last closed candle wicked or broke below the previous candle's low
   return iLow(_Symbol, PERIOD_H1, 1) < iLow(_Symbol, PERIOD_H1, 2);
}

bool HasUpsideViolation()
{
   return iHigh(_Symbol, PERIOD_H1, 1) > iHigh(_Symbol, PERIOD_H1, 2);
}

double AvgBodySize(int fromBar = 2, int count = 20)
{
   double total = 0;
   for(int i = fromBar; i < fromBar + count; i++)
      total += MathAbs(iClose(_Symbol, PERIOD_H1, i) - iOpen(_Symbol, PERIOD_H1, i));
   return total / count;
}

bool IsVeryLongBearishCandle(int bar)
{
   double body = iOpen(_Symbol, PERIOD_H1, bar) - iClose(_Symbol, PERIOD_H1, bar);
   return IsBearishCandle(bar) && body > AvgBodySize() * 2.0;
}

bool IsVeryLongBullishCandle(int bar)
{
   double body = iClose(_Symbol, PERIOD_H1, bar) - iOpen(_Symbol, PERIOD_H1, bar);
   return IsBullishCandle(bar) && body > AvgBodySize() * 2.0;
}

// Daily buy reversal pattern: last completed Daily candle is a very long bearish candle (≥ 2× avg D1 body).
// This signals a potential bullish reversal on the higher timeframe.
bool IsDailyBuyReversalPattern()
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 22) return false; // need enough history

   double avgBody = 0;
   for(int i = 2; i < 22; i++)
      avgBody += MathAbs(iClose(_Symbol, PERIOD_D1, i) - iOpen(_Symbol, PERIOD_D1, i));
   avgBody /= 20.0;

   double d1Body = iOpen(_Symbol, PERIOD_D1, 1) - iClose(_Symbol, PERIOD_D1, 1);
   bool d1Bearish = iClose(_Symbol, PERIOD_D1, 1) < iOpen(_Symbol, PERIOD_D1, 1);

   return d1Bearish && d1Body > avgBody * 2.0;
}

// Checks that ALL H1 candles between TradingStart and the given endHour are bearish
bool BearishCandlesTillHour(int endHour)
{
   int bars = iBars(_Symbol, PERIOD_H1);
   bool checked = false;
   for(int i = 1; i < bars; i++)
   {
      MqlDateTime dt;
      TimeToStruct(iTime(_Symbol, PERIOD_H1, i), dt);
      if(dt.hour < InpTradingStart) break;
      if(dt.hour >= InpTradingStart && dt.hour <= endHour)
      {
         checked = true;
         if(IsBullishCandle(i)) return false;
      }
   }
   return checked;
}

//============================================================
//  POSITION / ORDER HELPERS
//============================================================

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i))
         if(pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol)
            return true;
   }
   return false;
}

bool PlaceBuy(double entry, double sl, double tp, string label)
{
   double slPips = PriceToPips(entry - sl);
   double tpPips = PriceToPips(tp - entry);

   if(slPips <= 0 || tpPips <= 0)
   { PrintFormat("[%s] Invalid SL/TP (slPips=%.1f tpPips=%.1f)", label, slPips, tpPips); return false; }

   if(tpPips / slPips < InpMinRRR)
   { PrintFormat("[%s] RRR %.2f below minimum %.1f — skipped", label, tpPips/slPips, InpMinRRR); return false; }

   double lots = CalcLotSize(slPips);
   if(lots <= 0) { PrintFormat("[%s] Lot calc returned 0", label); return false; }

   bool ok = false;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(entry <= ask + PipsToPrice(2.0))
      ok = trade.Buy(lots, _Symbol, 0, sl, tp, label);
   else
      ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);

   if(ok)
   {
      g_DailyCount++;
      string msg = StringFormat("✓ BUY [%s] Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f Risk:Balance/6",
                                label, entry, sl, tp, lots);
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }
   else
      PrintFormat("✗ BUY FAILED [%s] Code:%d %s", label, trade.ResultRetcode(), trade.ResultComment());

   return ok;
}

bool PlaceSell(double entry, double sl, double tp, string label)
{
   double slPips = PriceToPips(sl - entry);
   double tpPips = PriceToPips(entry - tp);

   if(slPips <= 0 || tpPips <= 0)
   { PrintFormat("[%s] Invalid SL/TP (slPips=%.1f tpPips=%.1f)", label, slPips, tpPips); return false; }

   if(tpPips / slPips < InpMinRRR)
   { PrintFormat("[%s] RRR %.2f below minimum %.1f — skipped", label, tpPips/slPips, InpMinRRR); return false; }

   double lots = CalcLotSize(slPips);
   if(lots <= 0) { PrintFormat("[%s] Lot calc returned 0", label); return false; }

   bool ok = false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(MathAbs(entry - bid) <= PipsToPrice(2.0))
      ok = trade.Sell(lots, _Symbol, 0, sl, tp, label);          // Near current price: market sell
   else if(entry > bid + PipsToPrice(2.0))
      ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label); // Above bid: sell limit (wait for retrace up)
   else
   { PrintFormat("[%s] Entry %.5f is below bid %.5f — SellStop not supported", label, entry, bid); return false; }

   if(ok)
   {
      g_DailyCount++;
      string msg = StringFormat("✓ SELL [%s] Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f Risk:Balance/6",
                                label, entry, sl, tp, lots);
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }
   else
      PrintFormat("✗ SELL FAILED [%s] Code:%d %s", label, trade.ResultRetcode(), trade.ResultComment());

   return ok;
}

//============================================================
//  BUY SETUPS — called in priority order
//============================================================

bool ScanBuySetups()
{
   int hr          = CurrentHour();
   int sLondon     = NYtoServer(InpLondonStartNY);
   int sNYKZ       = NYtoServer(InpNYKillZoneNY);
   int sEnd        = NYtoServer(InpTradingEndNY);
   bool triggered  = false;

   // --- Priority 1: FVG Asian Buy (bullish FVG in last Asian candle) | London + NY KZ ---
   if(!triggered && g_AsianFVGBullish && hr >= sLondon && hr < sEnd)
      triggered = TryFVGAsianBuy();

   // --- Priority 2: FVG Buy (no Asian FVG → wait for violation + FVG) | London + NY KZ ---
   if(!triggered && !g_AsianFVGBullish && hr >= sLondon && hr < sEnd)
      triggered = TryFVGBuy();

   // --- Priority 3: Straight Buy | NY Kill Zone only (after 05:00 NY) ---
   if(!triggered && hr >= sNYKZ && hr < sEnd)
      triggered = TryStraightBuy();

   return triggered;
}

// FVG Asian Buy
// Trigger: bullish FVG in last Asian candle | 2–10AM | Daily buy reversal confirmed
// Entry  : market buy instantly on H1 candle close that forms the FVG
// SL     : below the lowest point of the Asian session range
// TP     : 1hr short-term high
bool TryFVGAsianBuy()
{
   if(g_AsianLastBar < 0) return false;
   if(!IsDailyBuyReversalPattern()) return false; // Daily must show a buy reversal candle

   double zHigh, zLow;
   if(!GetFVGZone(g_AsianLastBar, zHigh, zLow)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Market buy on FVG close

   // SL = lowest point of the Asian session range minus buffer
   double sl = g_AsianLow - PipsToPrice(InpFVGBuffer);

   double tp = GetSTHigh(InpSTH_Lookback);
   if(tp <= entry) return false;

   return PlaceBuy(entry, sl, tp, "FVG_Asian_Buy");
}

// FVG Buy (no Asian FVG)
// Trigger: downside violation occurred, then bullish FVG forms | 2–10AM
// Entry  : market buy instantly on H1 candle close that forms the FVG
// SL     : below left candle of FVG (candle before the gap)
// TP     : 1hr short-term high
bool TryFVGBuy()
{
   if(!HasDownsideViolation()) return false;
   if(DetectFVG(1) != 1)       return false;

   double zHigh, zLow;
   if(!GetFVGZone(1, zHigh, zLow)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK); // Market buy on FVG close
   // Left candle of FVG at bar[1] is bar[3]
   double sl = iLow(_Symbol, PERIOD_H1, 3) - PipsToPrice(InpFVGBuffer);
   double tp = GetSTHigh(InpSTH_Lookback);
   if(tp <= entry) return false;

   return PlaceBuy(entry, sl, tp, "FVG_Buy");
}

// Straight Buy
// Trigger: after 5AM | bearish candles until London | bullish close
// Note   : Asian FVG may or may not be present — allowed as long as daily is NOT a reversal
// Entry  : market buy on bullish H1 close
// SL     : below current bullish candle or previous candle (whichever is lower)
// TP     : 1hr short-term high
bool TryStraightBuy()
{
   if(!BearishCandlesTillHour(InpLondonOpen)) return false;
   if(!IsBullishCandle(1))                    return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = MathMin(iLow(_Symbol, PERIOD_H1, 1),
                           iLow(_Symbol, PERIOD_H1, 2)) - PipsToPrice(InpFVGBuffer);
   double tp    = GetSTHigh(InpSTH_Lookback);
   if(tp <= entry) return false;

   return PlaceBuy(entry, sl, tp, "Straight_Buy");
}

//============================================================
//  FVG ASIAN SELL — SL REENTRY LOGIC
//  If FVG_Asian_Sell closes at a loss today (SL hit), place a buy on the next
//  H1 bar with TP at the 1hr short-term high (proxy for daily equal highs).
//  ⚠ MANUAL: verify TP at equal highs on the daily chart before leaving the trade.
//============================================================

// Polls today's closed deal history for a FVG_Asian_Sell that exited at a loss.
// Sets g_AsianSellSLHit = true on detection. Safe to call every bar.
void CheckAsianSellSLReentry()
{
   if(g_AsianSellSLHit || g_AsianSellReentered) return;

   datetime dayStart = TodayMidnight();
   if(!HistorySelect(dayStart, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket,  DEAL_COMMENT)  != "FVG_Asian_Sell") continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)    != InpMagicNumber)   continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL)   != _Symbol)          continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)    != DEAL_ENTRY_OUT)   continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0)
      {
         g_AsianSellSLHit = true;
         string msg = "⚠ FVG_Asian_Sell SL hit — re-entry BUY will fire on next bar. "
                      "Verify TP at daily equal highs.";
         Print(msg);
         if(InpPopupAlerts) Alert(msg);
         if(InpPushAlerts)  SendNotification(msg);
      }
      break; // Only need the first (most recent) exit deal for this label
   }
}

// Re-entry buy placed on the bar AFTER FVG_Asian_Sell SL is hit.
// Entry  : market buy at open of new bar
// SL     : below the low of the previous H1 candle
// TP     : 1hr short-term high (automated proxy for daily equal highs)
// ⚠ MANUAL: adjust TP to actual equal highs on the daily chart.
bool TryAsianSellReentryBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = iLow(_Symbol, PERIOD_H1, 1) - PipsToPrice(InpFVGBuffer);
   double tp    = GetSTHigh(InpSTH_Lookback);

   if(tp <= entry) return false;

   bool ok = PlaceBuy(entry, sl, tp, "Asian_Sell_Reentry_Buy");
   if(ok)
   {
      g_AsianSellReentered = true;
      string msg = "✓ Re-entry BUY placed after FVG_Asian_Sell SL hit. "
                   "⚠ MANUAL: move TP to equal highs on D1 chart.";
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }
   return ok;
}

//============================================================
//  SELL SETUPS — called in priority order
//============================================================

bool ScanSellSetups()
{
   int hr          = CurrentHour();
   int sAsianEnd   = NYtoServer(InpAsianEndNY);   // 00:00 NY — Asian session closes
   int sLondon     = NYtoServer(InpLondonStartNY); // 02:00 NY
   int sNYKZ       = NYtoServer(InpNYKillZoneNY);  // 05:00 NY
   int sEnd        = NYtoServer(InpTradingEndNY);   // 10:00 NY
   bool triggered  = false;

   // --- Priority 1: FVG Asian Sell | 00:00–10:00 AM NY (inclusive) ---
   // Bearish FVG formed in last Asian candle; enter as soon as Asian session closes
   if(!triggered && g_AsianFVGBearish && hr >= sAsianEnd && hr <= sEnd)
      triggered = TryFVGAsianSell();

   // --- Priority 2: FVG Sell (no Asian FVG) | 02:00–10:00 AM NY (inclusive) ---
   if(!triggered && !g_AsianFVGBearish && hr >= sLondon && hr <= sEnd)
      triggered = TryFVGSell();

   // --- Priority 3: Straight Sell (Bearish Wick) | NY session start onwards (05:00–10:00 NY incl.) ---
   // Allow re-entry: no single-fire guard — setup can retrigger on a new valid bar
   if(!triggered && hr >= sNYKZ && hr <= sEnd)
      triggered = TryStraightSell();

   return triggered;
}

// FVG Asian Sell
// Context: bearish FVG in last candle of Asian session | requires daily confirmation
//          (strong continuation or strong reversal on D1 — verify manually).
//          May 2024 is a reference month: look for equal lows on daily as key TP target.
// Window : 00:00–10:00 AM NY (inclusive) — enters as soon as Asian session closes
// Entry  : SELL LIMIT at midpoint of the bearish FVG zone ((zHigh + zLow) / 2).
//          Price fills back up into the gap; we sell at the 50% level of the gap.
// SL     : above the high of the candle before the FVG (left candle of 3-bar pattern)
// TP     : 1hr short-term low.
//          ⚠ MANUAL: also look for key daily equal lows as the primary TP target.
// Reentry: if SL is hit, a buy re-entry fires on the next H1 bar (see TryAsianSellReentryBuy).
bool TryFVGAsianSell()
{
   if(g_AsianLastBar < 0) return false;

   double zHigh, zLow;
   if(!GetFVGZone(g_AsianLastBar, zHigh, zLow)) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Entry is the MIDPOINT of the bearish FVG zone — sell limit placed at 50% of the gap.
   // Guard: if price is already at or above our entry, the gap has already been filled — skip.
   double entry = (zHigh + zLow) / 2.0;
   if(entry <= bid) return false;

   // SL = above the left candle of the FVG (bar that is 2 back from the right candle)
   double sl = iHigh(_Symbol, PERIOD_H1, g_AsianLastBar + 2) + PipsToPrice(InpFVGBuffer);

   // TP = 1hr short-term low (automated).
   // Alert reminds trader to also check daily equal lows for the primary TP level.
   double tp = GetSTLow(InpSTH_Lookback);
   if(tp <= 0 || tp >= entry) return false;

   string dailyMsg = "⚠ FVG_Asian_Sell placed — verify DAILY chart: strong continuation or reversal? "
                     "Check equal lows on D1 for key TP. May 2024 is a reference example.";
   Print(dailyMsg);
   if(InpPopupAlerts) Alert(dailyMsg);

   return PlaceSell(entry, sl, tp, "FVG_Asian_Sell");
}

// FVG Sell (no Asian FVG) — DO NOT REENTER
// Pre-checks : 02:00–10:00 AM NY (inclusive) | upside violation of Asian range | bearish FVG formed
// Entry      : market sell on close of the FVG candle (bar[1])
// SL         : above the high of the candle before the FVG (bar[3]) + buffer
// TP         : 1hr short-term low.
//              Exception — if ALL Asian candles were bullish, TP = lowest point of Asian range.
bool TryFVGSell()
{
   if(g_FVGSellDone)           return false; // No reenter after first signal today
   if(!HasUpsideViolation())   return false;
   if(DetectFVG(1) != -1)      return false;

   double zHigh, zLow;
   if(!GetFVGZone(1, zHigh, zLow)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // SL above the left candle of the FVG (bar[3] in the 3-bar pattern starting at bar[1])
   double sl = iHigh(_Symbol, PERIOD_H1, 3) + PipsToPrice(InpFVGBuffer);

   // TP: if all Asian candles were bullish, use the Asian range low; else use ST low
   double tp;
   if(g_AllAsianBullish && g_AsianLow > 0 && g_AsianLow < entry)
      tp = g_AsianLow;
   else
      tp = GetSTLow(InpSTH_Lookback);

   if(tp <= 0 || tp >= entry) return false;

   bool ok = PlaceSell(entry, sl, tp, "FVG_Sell");
   if(ok) g_FVGSellDone = true;
   return ok;
}

// Straight Sell (Bearish Wick) — ALLOW RE-ENTRY
// Window : 05:00–10:00 AM NY (start of NY session)
// Trigger: Prior bullish candle formations, then bar[1] closes bearish with a wick
//          above bar[2]'s high (market execution on close).
//          Strong confirmation: bar[2] is a very long bullish candle (e.g. news spike),
//          but a standard bearish wick above the previous high is also valid.
// SL     : above MathMax(bar[1].high, bar[2].high) + buffer
//          — covers both the wick tip (simple case) and the prior spike high (news case)
// TP     : 1hr short-term low.
//          If all Asian candles were strong bearish, use Asian session low as TP.
bool TryStraightSell()
{
   // Core condition: bar[1] closes bearish with a wick above bar[2]'s high
   if(!IsBearishCandle(1)) return false;
   if(iHigh(_Symbol, PERIOD_H1, 1) <= iHigh(_Symbol, PERIOD_H1, 2)) return false;

   // Bullish formations must precede the reversal: bar[2] or bar[3] should be bullish
   bool hasBullishFormation = IsBullishCandle(2) || IsBullishCandle(3);
   if(!hasBullishFormation) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // SL above the highest point between the entry candle's wick and the prior candle
   double sl = MathMax(iHigh(_Symbol, PERIOD_H1, 1),
                       iHigh(_Symbol, PERIOD_H1, 2)) + PipsToPrice(InpFVGBuffer);

   // TP: Asian low if all Asian candles were bearish; otherwise 1hr short-term low
   double tp;
   if(g_AllAsianBearish && g_AsianLow > 0 && g_AsianLow < entry)
      tp = g_AsianLow;
   else
      tp = GetSTLow(InpSTH_Lookback);

   if(tp <= 0 || tp >= entry) return false;

   return PlaceSell(entry, sl, tp, "Straight_Sell");
}

//+------------------------------------------------------------------+
//  END OF EA
//+------------------------------------------------------------------+
//
//  NOTES ON RE-ENTRIES (plan section — handled manually):
//
//  The plan allows specific re-entry scenarios:
//  1. FVG Asia Sell did not work → re-enter if 1AM candle takes you out → switch to buys
//  2. Straight buys/sells with weak candles → switch direction
//  These require real-time judgment about session context and candle
//  strength that are best managed manually by the trader.
//
//  DXY CONFLUENCE (manual):
//  Before each session, check DXY direction. If DXY is bullish, favour
//  USD-strength setups. If bearish, favour USD-weakness setups. This
//  filters out counter-trend entries this EA might otherwise trigger.
//
//  KEY LEVELS (manual):
//  Mark Daily, 4H, Weekly, Monthly key levels on your chart. After the
//  market hits a key level and corrects, wait before re-entering. The EA
//  uses short-term highs/lows for TP, but your marked levels take priority.
//
//+------------------------------------------------------------------+
