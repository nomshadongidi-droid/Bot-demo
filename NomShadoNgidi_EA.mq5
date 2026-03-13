//+------------------------------------------------------------------+
//|                       NomShadoNgidi_EA.mq5                       |
//|            Expert Advisor — Nomshado Ngidi Trading Plan Q1 2025  |
//|           Instrument: US_30 (US.30) ONLY  |  Version 1.02        |
//+------------------------------------------------------------------+
//
//  ⚠ THIS EA WILL ONLY RUN ON US_30 (also accepted: US.30, US30)
//  It will REFUSE to load on any other instrument.
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
//  3. Drag the EA onto your US_30 H1 chart (ONLY instrument supported)
//  4. Ensure "Allow Algo Trading" is enabled in MT5
//  5. Configure input parameters to match your account/timezone
//
//+------------------------------------------------------------------+
#property copyright   "Nomshado Ngidi"
#property version     "1.02"
#property description "MT5 EA — Nomshado Ngidi Trading Plan Q1 2025"
#property description "⚠ Instrument: US_30 (US.30) ONLY — will refuse all other symbols"
#property description "Setups: FVG Buy/Sell, Asian FVG, Straight"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//============================================================
//  INPUT PARAMETERS
//============================================================

// All session hours are in Eastern Time (ET) — DST is handled automatically.
//   • EST (UTC-5): first Sunday of November → second Sunday of March
//   • EDT (UTC-4): second Sunday of March   → first Sunday of November
// Uses TimeGMT() so broker server timezone is completely irrelevant.
input group "=== Session Times (Eastern Time — auto DST) ==="
input int    InpAsianStartNY          = 19;  // Asian Session Start — NY time (plan: 19:00)
input int    InpAsianEndNY            = 0;   // Asian Session End   — NY time (plan: 00:00)
input int    InpFVGAsianWindowStartNY = 1;   // FVG Asian setups window start — NY time (plan: 01:00)
input int    InpLondonStartNY         = 2;   // London Kill Zone Start — NY time (plan: 02:00)
input int    InpNYKillZoneNY          = 5;   // NY Kill Zone Start — NY time (plan: 05:00)
input int    InpTradingEndNY          = 10;  // Trading Window End — NY time (plan: 10:00)

input group "=== Risk Management ==="
input double InpMinRRR         = 2.0;  // Minimum Risk:Reward Ratio (1:2 per plan)

input group "=== Stop Loss Settings ==="
input int    InpFVGBuffer      = 10;   // SL/entry buffer in pips (10 = breathing room)

input group "=== Trade Settings ==="
input int    InpMaxDailyTrades = 2;    // Max trades per day (plan: max 2)
input bool   InpAllowMonday    = false;// Allow Monday trading (plan: NO)
input int    InpSTH_Lookback   = 20;   // Short-term High/Low lookback (H1 bars)
input int    InpMagicNumber    = 20250101; // EA Magic Number

input group "=== Alerts ==="
input bool   InpPopupAlerts    = true;                           // Enable popup alerts on new setup
input bool   InpPushAlerts     = false;                          // Enable push notifications
input bool   InpEmailAlerts    = true;                           // Enable email alerts for balance milestones
input string InpAlertEmail     = "solutionsphanaso@gmail.com";   // ⚠ Configure in MT5 Tools→Options→Email→To
input double InpBalanceLowAlert = 100.0;                         // Email alert: balance drops to or below ($)
// Milestone alerts fire once each when balance first crosses: $10,000 | $100,000 | $500,000 | $1,000,000

//============================================================
//  GLOBAL VARIABLES
//============================================================

CTrade        trade;
CPositionInfo pos;

int      g_DailyCount   = 0;
datetime g_LastDay      = 0;
double   g_PipSize      = 0;

// Asian session data (refreshed each new day)
double   g_AsianHigh        = 0;
double   g_AsianLow         = 0;
bool     g_AsianFVGBullish  = false;
bool     g_AsianFVGBearish  = false;
bool     g_AllAsianBullish  = false;
bool     g_AllAsianBearish  = false;
int      g_AsianLastBar     = -1;
datetime g_AsianDate        = 0;

// Balance alert flags (lifetime — not reset daily)
bool     g_BalanceLowAlertSent = false;
bool     g_Milestone10k        = false;
bool     g_Milestone100k       = false;
bool     g_Milestone500k       = false;
bool     g_Milestone1m         = false;

// Per-day setup guards
bool     g_FVGBuyDone         = false;
bool     g_StraightBuyDone    = false;
bool     g_FVGSellDone        = false;
bool     g_StraightSellDone   = false;
bool     g_AsianSellSLHit     = false;
bool     g_AsianSellReentered = false;

// Bar tracker — EA only acts on newly opened H1 bars
datetime g_LastBar = 0;

//============================================================
//  INITIALISATION
//============================================================

int OnInit()
{
   if(StringFind(_Symbol, "US.30") < 0 && StringFind(_Symbol, "US30") < 0 && StringFind(_Symbol, "US_30") < 0)
   {
      string errMsg = "WRONG SYMBOL: This EA trades US.30 only. "
                      "Current chart is " + _Symbol + ". "
                      "Attach the EA to a US.30 / US_30 chart and retry.";
      Alert(errMsg);
      Print(errMsg);
      return INIT_FAILED;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_PipSize = (digits == 3 || digits == 5) ? _Point * 10.0 : _Point;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   PrintFormat("=== Nomshado Ngidi EA v1.02 Initialised ===");
   PrintFormat("Symbol: %s | Pip Size: %.5f", _Symbol, g_PipSize);
   PrintFormat("Risk per trade: Account Balance / 6 | Min RRR 1:%.1f", InpMinRRR);
   PrintFormat("Asian NY: %02d:00-%02d:00 | London KZ: %02d:00 | NY KZ: %02d:00-%02d:00",
               InpAsianStartNY, InpAsianEndNY, InpLondonStartNY, InpNYKillZoneNY, InpTradingEndNY);
   PrintFormat("Time base: Eastern Time (auto DST) — %s (UTC%d) | Max daily trades: %d",
               EasternOffset() == -4 ? "EDT" : "EST", EasternOffset(), InpMaxDailyTrades);
   if(!InpAllowMonday)
      Print("Monday filter: ACTIVE");
   Print("REMINDER: Check DXY, key Daily/Weekly levels, and news before each session.");

   g_LastBar = iTime(_Symbol, PERIOD_H1, 0);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   PrintFormat("EA removed. Reason code: %d", reason);
}

//============================================================
//  TRADE CLOSE — RR LOGGING
//============================================================

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(!HistoryDealSelect(dealTicket)) return;

   if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC)  != InpMagicNumber) return;
   if(HistoryDealGetString (dealTicket, DEAL_SYMBOL) != _Symbol)        return;
   if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY)  != DEAL_ENTRY_OUT) return;

   ulong  positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double closePrice = HistoryDealGetDouble (dealTicket, DEAL_PRICE);
   double profit     = HistoryDealGetDouble (dealTicket, DEAL_PROFIT);
   string label      = HistoryDealGetString (dealTicket, DEAL_COMMENT);
   long   dealType   = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   bool   wasBuy     = (dealType == DEAL_TYPE_SELL);

   if(!HistorySelectByPosition(positionId)) return;

   double entryPrice = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         entryPrice = HistoryDealGetDouble(d, DEAL_PRICE);
         break;
      }
   }
   if(entryPrice <= 0) return;

   double slPrice = 0, tpPrice = 0;
   for(int i = 0; i < HistoryOrdersTotal(); i++)
   {
      ulong ord = HistoryOrderGetTicket(i);
      if((ulong)HistoryOrderGetInteger(ord, ORDER_POSITION_ID) == positionId)
      {
         slPrice = HistoryOrderGetDouble(ord, ORDER_SL);
         tpPrice = HistoryOrderGetDouble(ord, ORDER_TP);
      }
   }

   double plannedRR = 0, actualRR = 0;
   if(wasBuy && slPrice > 0 && slPrice < entryPrice)
   {
      double risk = entryPrice - slPrice;
      plannedRR = (tpPrice > entryPrice) ? (tpPrice - entryPrice) / risk : 0;
      actualRR  = (closePrice - entryPrice) / risk;
   }
   else if(!wasBuy && slPrice > 0 && slPrice > entryPrice)
   {
      double risk = slPrice - entryPrice;
      plannedRR = (tpPrice < entryPrice) ? (entryPrice - tpPrice) / risk : 0;
      actualRR  = (entryPrice - closePrice) / risk;
   }

   string outcome = (profit > 0) ? "WIN" : (profit < 0) ? "LOSS" : "BREAKEVEN";
   PrintFormat(
      "=== RR LOG [%s] %s | Entry:%.5f  Close:%.5f  SL:%.5f  TP:%.5f"
      " | PlannedRR:1:%.2f | ActualRR:1:%.2f | P&L:%.2f | %s ===",
      label, wasBuy ? "BUY" : "SELL",
      entryPrice, closePrice, slPrice, tpPrice,
      plannedRR, actualRR, profit, outcome);
}

//============================================================
//  BALANCE EMAIL ALERTS
//============================================================

void FireMilestone(bool &flag, string milestone, double balance, string acct, string ts)
{
   if(flag) return;
   string subj = StringFormat("MILESTONE REACHED — %s on account %s!", milestone, acct);
   string body = StringFormat(
      "BALANCE MILESTONE — NomShadoNgidi EA\n\n"
      "Congratulations! Your balance has crossed %s.\n"
      "Current balance : $%.2f\n"
      "Milestone       : %s\n"
      "Account         : %s\n"
      "Symbol          : %s\n"
      "Time            : %s",
      milestone, balance, milestone, acct, _Symbol, ts);
   Print(subj);
   SendMail(subj, body);
   if(InpPopupAlerts) Alert(subj);
   if(InpPushAlerts)  SendNotification(subj);
   flag = true;
}

void CheckBalanceAlerts()
{
   if(!InpEmailAlerts) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string acct    = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string ts      = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

   if(!g_BalanceLowAlertSent && balance <= InpBalanceLowAlert)
   {
      string subj = StringFormat("⚠ LOW BALANCE on %s — $%.2f", _Symbol, balance);
      string body = StringFormat(
         "BALANCE ALERT — NomShadoNgidi EA\n\n"
         "Your account balance has dropped to $%.2f.\n"
         "Alert threshold : $%.2f\n"
         "Account         : %s\n"
         "Symbol          : %s\n"
         "Time            : %s\n\n"
         "Please review your account immediately.",
         balance, InpBalanceLowAlert, acct, _Symbol, ts);
      Print(subj);
      SendMail(subj, body);
      if(InpPopupAlerts) Alert(subj);
      if(InpPushAlerts)  SendNotification(subj);
      g_BalanceLowAlertSent = true;
   }
   else if(g_BalanceLowAlertSent && balance > InpBalanceLowAlert)
      g_BalanceLowAlertSent = false;

   if(balance >= 10000.0)   FireMilestone(g_Milestone10k,  "$10,000",    balance, acct, ts);
   if(balance >= 100000.0)  FireMilestone(g_Milestone100k, "$100,000",   balance, acct, ts);
   if(balance >= 500000.0)  FireMilestone(g_Milestone500k, "$500,000",   balance, acct, ts);
   if(balance >= 1000000.0) FireMilestone(g_Milestone1m,   "$1,000,000", balance, acct, ts);
}

//============================================================
//  MAIN TICK — only acts on newly opened H1 bar
//============================================================

void OnTick()
{
   CheckBalanceAlerts();

   datetime curBar = iTime(_Symbol, PERIOD_H1, 0);
   if(curBar == g_LastBar) return;
   g_LastBar = curBar;

   ResetDailyCount();
   CheckAsianSellSLReentry();

   if(!InpAllowMonday && IsMonday())     return;
   if(g_DailyCount >= InpMaxDailyTrades) return;
   if(!IsInTradingWindow())              return;

   AnalyseAsianSession();

   if(g_AsianSellSLHit && !g_AsianSellReentered)
   {
      TryAsianSellReentryBuy();
      return;
   }

   if(!ScanBuySetups())
      ScanSellSetups();
}

//============================================================
//  TIME HELPERS — Eastern Time with automatic US DST
//
//  ALL time calculations use TimeGMT() directly.
//  Broker server timezone is NEVER used for trading decisions.
//  BarTimeNY() is only used in AnalyseAsianSession to identify
//  which historical bars fall in the Asian session window.
//  All trigger/window checks use CurrentHour() exclusively.
//============================================================

// Day-of-week (Tomohiko Sakamoto). 0=Sun … 6=Sat.
int DayOfWeekFor(int year, int mon, int day)
{
   static int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
   if(mon < 3) year--;
   return (year + year/4 - year/100 + year/400 + t[mon-1] + day) % 7;
}

// Returns Eastern UTC offset: -4 (EDT/summer) or -5 (EST/winter).
// DST starts: 2nd Sunday of March  at 07:00 UTC (2:00 AM EST → springs to 3 AM)
// DST ends  : 1st Sunday of November at 06:00 UTC (2:00 AM EDT → falls to 1 AM)
int EasternOffset()
{
   MqlDateTime u;
   TimeToStruct(TimeGMT(), u);

   int dowMar1   = DayOfWeekFor(u.year, 3, 1);
   int marchSun2 = 1 + (7 - dowMar1) % 7 + 7;   // 2nd Sunday of March (day 8–14)

   int dowNov1   = DayOfWeekFor(u.year, 11, 1);
   int novSun1   = 1 + (7 - dowNov1) % 7;        // 1st Sunday of November (day 1–7)

   bool pastStart = (u.mon >  3) ||
                    (u.mon == 3 && u.day >  marchSun2) ||
                    (u.mon == 3 && u.day == marchSun2 && u.hour >= 7);

   bool beforeEnd = (u.mon <  11) ||
                    (u.mon == 11 && u.day <  novSun1) ||
                    (u.mon == 11 && u.day == novSun1 && u.hour < 6);

   return (pastStart && beforeEnd) ? -4 : -5;
}

// Current Eastern Time (auto DST), derived purely from UTC
datetime NowNY() { return TimeGMT() + EasternOffset() * 3600; }

// Current Eastern hour — used for ALL trading window and trigger decisions
int CurrentHour()
{
   MqlDateTime dt;
   TimeToStruct(NowNY(), dt);
   return dt.hour;
}

bool IsMonday()
{
   MqlDateTime dt;
   TimeToStruct(NowNY(), dt);
   return dt.day_of_week == 1;
}

bool IsInTradingWindow()
{
   int h = CurrentHour();
   return (h >= InpLondonStartNY && h <= InpTradingEndNY);
}

datetime TodayMidnight()
{
   MqlDateTime dt;
   TimeToStruct(NowNY(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

// Convert a broker-server-time bar open timestamp to Eastern Time.
// Used ONLY in AnalyseAsianSession to locate historical Asian session bars.
// NOT used for any trading trigger or window decision.
datetime BarTimeNY(int barIndex)
{
   int serverOffsetSecs = (int)((datetime)TimeCurrent() - (datetime)TimeGMT());
   return iTime(_Symbol, PERIOD_H1, barIndex) - serverOffsetSecs + EasternOffset() * 3600;
}

// NYtoServer is an identity — session inputs are in Eastern Time, CurrentHour() is also Eastern.
int NYtoServer(int nyHour) { return nyHour; }

void ResetDailyCount()
{
   datetime today = TodayMidnight();
   if(today != g_LastDay)
   {
      g_DailyCount          = 0;
      g_LastDay             = today;
      g_FVGBuyDone          = false;
      g_StraightBuyDone     = false;
      g_FVGSellDone         = false;
      g_StraightSellDone    = false;
      g_AsianSellSLHit      = false;
      g_AsianSellReentered  = false;
   }
}

double PipsToPrice(double pips) { return pips * g_PipSize; }
double PriceToPips(double dist) { return (g_PipSize > 0) ? dist / g_PipSize : 0; }

double CalcLotSize(double slPips)
{
   if(slPips <= 0) return 0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lots    = (balance / 6.0) / slPips / 10.0;

   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathRound(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   PrintFormat("CalcLotSize: balance=%.2f risk=%.2f SL=%.1f pips → lots=%.2f",
               balance, balance / 6.0, slPips, lots);
   return lots;
}

//============================================================
//  ASIAN SESSION ANALYSIS
//  Runs once per calendar day (cached by g_AsianDate).
//  BarTimeNY() is acceptable here — it only identifies which
//  historical bars are in the 19:00–00:00 Eastern window.
//  A 1-hour broker offset error would slightly shift the Asian
//  range but cannot trigger a trade at the wrong time.
//============================================================

void AnalyseAsianSession()
{
   datetime today = TodayMidnight();
   if(today == g_AsianDate) return;

   g_AsianHigh       = 0;
   g_AsianLow        = DBL_MAX;
   g_AsianFVGBullish = false;
   g_AsianFVGBearish = false;
   g_AllAsianBullish = true;
   g_AllAsianBearish = true;
   g_AsianLastBar    = -1;

   int  totalBars = iBars(_Symbol, PERIOD_H1);
   bool foundAny  = false;

   for(int i = 1; i < totalBars; i++)
   {
      MqlDateTime bDt;
      TimeToStruct(BarTimeNY(i), bDt);

      MqlDateTime bMidDt = bDt;
      bMidDt.hour = 0; bMidDt.min = 0; bMidDt.sec = 0;
      datetime bDay = StructToTime(bMidDt);

      if(bDay < today - 86400) break;
      if(bDay > today) continue;

      // Asian session wraps midnight: 19:00–00:00 Eastern
      bool inAsian = (bDt.hour >= InpAsianStartNY || bDt.hour < InpAsianEndNY);

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

         // Last Asian bar = the bar that opens at 23:00 (one before midnight)
         int sAsianLast = (InpAsianEndNY - 1 + 24) % 24;
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
      g_AsianLow = 0;

   if(g_AsianLastBar > 0)
   {
      int fvgType = DetectFVG(g_AsianLastBar);
      g_AsianFVGBullish = (fvgType ==  1);
      g_AsianFVGBearish = (fvgType == -1);
   }

   g_AsianDate = today;

   if(g_AllAsianBullish)
   {
      string msg = "⚠ CAUTION: All Asian candles BULLISH — potential SELL reversal on " + _Symbol;
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }

   PrintFormat("Asian session | High:%.5f Low:%.5f FVG:%s AllBull:%s AllBear:%s",
               g_AsianHigh, g_AsianLow,
               g_AsianFVGBullish ? "BULLISH" : g_AsianFVGBearish ? "BEARISH" : "NONE",
               g_AllAsianBullish ? "YES" : "NO",
               g_AllAsianBearish ? "YES" : "NO");
}

//============================================================
//  FVG DETECTION
//
//  2-candle pattern (bar numbering, newest→oldest):
//    bar[0] = current forming candle (entry bar)
//    bar[1] = most recently closed   (candle 2 — completes FVG)
//    bar[2] = previous closed        (candle 1 — starts FVG)
//    bar[3] = candle before the pair (SL reference)
//
//  FVG is defined by a GAP BETWEEN CANDLE BODIES (not wicks):
//  Bullish FVG: candle1 body top  <= candle2 body bottom  (body gap up)
//  Bearish FVG: candle1 body bottom >= candle2 body top   (body gap down)
//  Returns: 1=bullish, -1=bearish, 0=none
//============================================================

int DetectFVG(int startBar)
{
   if(startBar < 1 || startBar + 1 >= iBars(_Symbol, PERIOD_H1)) return 0;

   // Body top/bottom for each candle
   double c1BodyTop    = MathMax(iOpen(_Symbol, PERIOD_H1, startBar + 1), iClose(_Symbol, PERIOD_H1, startBar + 1));
   double c1BodyBottom = MathMin(iOpen(_Symbol, PERIOD_H1, startBar + 1), iClose(_Symbol, PERIOD_H1, startBar + 1));
   double c2BodyTop    = MathMax(iOpen(_Symbol, PERIOD_H1, startBar),     iClose(_Symbol, PERIOD_H1, startBar));
   double c2BodyBottom = MathMin(iOpen(_Symbol, PERIOD_H1, startBar),     iClose(_Symbol, PERIOD_H1, startBar));

   if(c1BodyTop    <= c2BodyBottom) return  1;   // bullish body gap
   if(c1BodyBottom >= c2BodyTop)    return -1;   // bearish body gap
   return 0;
}

bool GetFVGZone(int startBar, double &zoneHigh, double &zoneLow)
{
   int type = DetectFVG(startBar);
   if(type == 0) return false;

   double c1BodyTop    = MathMax(iOpen(_Symbol, PERIOD_H1, startBar + 1), iClose(_Symbol, PERIOD_H1, startBar + 1));
   double c1BodyBottom = MathMin(iOpen(_Symbol, PERIOD_H1, startBar + 1), iClose(_Symbol, PERIOD_H1, startBar + 1));
   double c2BodyTop    = MathMax(iOpen(_Symbol, PERIOD_H1, startBar),     iClose(_Symbol, PERIOD_H1, startBar));
   double c2BodyBottom = MathMin(iOpen(_Symbol, PERIOD_H1, startBar),     iClose(_Symbol, PERIOD_H1, startBar));

   if(type == 1)
   {
      zoneLow  = c1BodyTop;       // top of candle 1 body
      zoneHigh = c2BodyBottom;    // bottom of candle 2 body
   }
   else
   {
      zoneHigh = c1BodyBottom;    // bottom of candle 1 body
      zoneLow  = c2BodyTop;       // top of candle 2 body
   }
   return (zoneHigh > zoneLow);
}

//============================================================
//  MARKET STRUCTURE UTILITIES
//============================================================

// Short-term high: most recent bullish→bearish body transition ABOVE Asian High.
// TP for buy setups. Returns 0 if nothing qualifies outside the Asian range.
double GetSTHigh(int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      if(IsBearishCandle(i) && IsBullishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(level > g_AsianHigh) return level;
      }
   }

   // Fallback: highest bar high that is still above the Asian session high
   double h = 0;
   for(int i = 1; i <= lim; i++)
   {
      double barHigh = iHigh(_Symbol, PERIOD_H1, i);
      if(barHigh > g_AsianHigh && barHigh > h)
         h = barHigh;
   }
   return h;
}

// Short-term low: most recent bearish→bullish body transition BELOW Asian Low.
// TP for sell setups. Returns 0 if nothing qualifies outside the Asian range.
double GetSTLow(int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      if(IsBullishCandle(i) && IsBearishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(level < g_AsianLow) return level;
      }
   }

   // Fallback: lowest bar low that is still below the Asian session low
   double l = DBL_MAX;
   for(int i = 1; i <= lim; i++)
   {
      double barLow = iLow(_Symbol, PERIOD_H1, i);
      if(barLow < g_AsianLow && barLow < l)
         l = barLow;
   }
   return (l == DBL_MAX) ? 0 : l;
}

bool IsBullishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) > iOpen(_Symbol, PERIOD_H1, bar); }
bool IsBearishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) < iOpen(_Symbol, PERIOD_H1, bar); }

bool HasDownsideViolation()
{
   return iLow(_Symbol, PERIOD_H1, 2) < iLow(_Symbol, PERIOD_H1, 3);
}

bool HasUpsideViolation()
{
   return iHigh(_Symbol, PERIOD_H1, 2) > iHigh(_Symbol, PERIOD_H1, 3);
}

double AvgBodySize(int fromBar = 2, int count = 20)
{
   double total = 0;
   for(int i = fromBar; i < fromBar + count; i++)
      total += MathAbs(iClose(_Symbol, PERIOD_H1, i) - iOpen(_Symbol, PERIOD_H1, i));
   return total / count;
}

bool IsDailyBuyReversalPattern()
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 22) return false;

   double avgBody = 0;
   for(int i = 2; i < 22; i++)
      avgBody += MathAbs(iClose(_Symbol, PERIOD_D1, i) - iOpen(_Symbol, PERIOD_D1, i));
   avgBody /= 20.0;

   double d1Body   = iOpen(_Symbol, PERIOD_D1, 1) - iClose(_Symbol, PERIOD_D1, 1);
   bool   d1Bearish = iClose(_Symbol, PERIOD_D1, 1) < iOpen(_Symbol, PERIOD_D1, 1);
   return d1Bearish && d1Body > avgBody * 2.0;
}

bool IsDailySellReversalPattern()
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 22) return false;

   double avgBody = 0;
   for(int i = 2; i < 22; i++)
      avgBody += MathAbs(iClose(_Symbol, PERIOD_D1, i) - iOpen(_Symbol, PERIOD_D1, i));
   avgBody /= 20.0;

   double d1Body    = iClose(_Symbol, PERIOD_D1, 1) - iOpen(_Symbol, PERIOD_D1, 1);
   bool   d1Bullish = iClose(_Symbol, PERIOD_D1, 1) > iOpen(_Symbol, PERIOD_D1, 1);
   return d1Bullish && d1Body > avgBody * 2.0;
}

//============================================================
//  LONDON → NY KZ CANDLE DIRECTION CHECKS
//
//  These are called ONLY from TryStraightBuy/Sell at 6AM Eastern.
//  At that moment the bar layout is fixed:
//    bar[1] = 5AM candle  (trigger — checked separately)
//    bar[2] = 4AM candle  ─┐
//    bar[3] = 3AM candle   ├─ London KZ window (2AM–4AM)
//    bar[4] = 2AM candle  ─┘
//
//  Count = InpNYKillZoneNY - InpLondonStartNY = 5 - 2 = 3 bars.
//  Uses only bar indices — NO BarTimeNY(), NO timezone conversion.
//============================================================

// For Straight Buy: bars[2..4] (2AM–4AM) must be mostly bearish (≤1 bullish allowed).
bool BearishFromLondonToNYKZ()
{
   int count = InpNYKillZoneNY - InpLondonStartNY; // 3 bars: 4AM, 3AM, 2AM
   if(count <= 0) return false;
   int bullishCount = 0;
   for(int i = 2; i < 2 + count; i++)
      if(IsBullishCandle(i)) bullishCount++;
   return bullishCount <= 1;
}

// For Straight Sell: bars[2..4] (2AM–4AM) must be mostly bullish (≤1 bearish allowed).
bool BullishFromLondonToNYKZ()
{
   int count = InpNYKillZoneNY - InpLondonStartNY;
   if(count <= 0) return false;
   int bearishCount = 0;
   for(int i = 2; i < 2 + count; i++)
      if(IsBearishCandle(i)) bearishCount++;
   return bearishCount <= 1;
}

//============================================================
//  POSITION / ORDER HELPERS
//============================================================

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(pos.SelectByIndex(i))
         if(pos.Magic() == InpMagicNumber && pos.Symbol() == _Symbol)
            return true;
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

   bool   ok  = false;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(MathAbs(entry - ask) <= PipsToPrice(2.0))
      ok = trade.Buy(lots, _Symbol, 0, sl, tp, label);         // at market
   else if(entry < ask)
      ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);  // limit below market
   else
      ok = trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);   // stop above market

   if(ok)
   {
      g_DailyCount++;
      string msg = StringFormat("✓ BUY [%s] Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f",
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

   bool   ok  = false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(MathAbs(entry - bid) <= PipsToPrice(2.0))
      ok = trade.Sell(lots, _Symbol, 0, sl, tp, label);
   else if(entry > bid + PipsToPrice(2.0))
      ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
   else
   { PrintFormat("[%s] Entry %.5f below bid %.5f — SellStop not supported", label, entry, bid); return false; }

   if(ok)
   {
      g_DailyCount++;
      string msg = StringFormat("✓ SELL [%s] Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f",
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
//  BUY SETUPS
//============================================================

bool ScanBuySetups()
{
   int  hr        = CurrentHour();
   bool triggered = false;

   // Priority 1: FVG Asian Buy | 01:00–10:00 NY
   if(!triggered && g_AsianFVGBullish && hr >= InpFVGAsianWindowStartNY && hr <= InpTradingEndNY)
      triggered = TryFVGAsianBuy();

   // Priority 2: FVG Buy | 02:00–10:00 NY
   if(!triggered && hr >= InpLondonStartNY && hr <= InpTradingEndNY)
      triggered = TryFVGBuy();

   // Priority 3: Straight Buy | 06:00–10:00 NY (5AM candle must have just closed)
   if(!triggered && hr > InpNYKillZoneNY && hr <= InpTradingEndNY)
      triggered = TryStraightBuy();

   return triggered;
}

// FVG Asian Buy
// Trigger : bullish FVG on last Asian candle | 01:00–10:00 NY | Daily buy reversal required
// Entry   : market buy
// SL      : below Asian session low
// TP      : ST high above Asian High; fallback 1:3 RR if no level above Asian High
bool TryFVGAsianBuy()
{
   if(g_AsianLastBar < 0) return false;
   if(!IsDailyBuyReversalPattern()) return false;

   double zHigh, zLow;
   if(!GetFVGZone(g_AsianLastBar, zHigh, zLow)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = g_AsianLow - PipsToPrice(InpFVGBuffer);
   double tp    = GetSTHigh(InpSTH_Lookback);

   if(tp <= g_AsianHigh)
   {
      tp = entry + 3.0 * (entry - sl);
      PrintFormat("[FVG_Asian_Buy] No ST high above Asian High — using 1:3 RR TP: %.5f", tp);
   }

   if(tp <= entry) return false;
   return PlaceBuy(entry, sl, tp, "FVG_Asian_Buy");
}

// FVG Buy
// Trigger : downside violation of Asian range + bullish FVG | 02:00–10:00 NY
// Entry   : market if RRR >= min; otherwise buy limit at min-RRR price inside FVG
// SL      : below bar[2] low (the candle that swept down — always below the FVG gap)
// TP      : ST high above Asian High; fallback 1:3 RR
bool TryFVGBuy()
{
   if(g_StraightBuyDone)       { Print("[FVG_Buy] SKIP: straight buy already done today"); return false; }
   if(!HasDownsideViolation())  { PrintFormat("[FVG_Buy] SKIP: no downside violation (bar2.low=%.5f bar3.low=%.5f)", iLow(_Symbol,PERIOD_H1,2), iLow(_Symbol,PERIOD_H1,3)); return false; }
   if(DetectFVG(1) != 1)        { PrintFormat("[FVG_Buy] SKIP: no bullish FVG (bar2.high=%.5f bar1.low=%.5f)", iHigh(_Symbol,PERIOD_H1,2), iLow(_Symbol,PERIOD_H1,1)); return false; }

   double zHigh, zLow;
   if(!GetFVGZone(1, zHigh, zLow)) { Print("[FVG_Buy] SKIP: FVG zone invalid"); return false; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = iLow(_Symbol, PERIOD_H1, 2) - PipsToPrice(InpFVGBuffer);
   double tp  = GetSTHigh(InpSTH_Lookback);

   PrintFormat("[FVG_Buy] Conditions met | ask=%.5f sl=%.5f tp=%.5f AsianHigh=%.5f", ask, sl, tp, g_AsianHigh);

   if(sl >= ask) { PrintFormat("[FVG_Buy] SKIP: sl(%.5f) >= ask(%.5f)", sl, ask); return false; }

   if(tp <= g_AsianHigh)
   {
      tp = ask + 3.0 * (ask - sl);
      PrintFormat("[FVG_Buy] No ST high above Asian High — using 1:3 RR TP: %.5f", tp);
   }

   if(tp <= ask) { PrintFormat("[FVG_Buy] SKIP: tp(%.5f) <= ask(%.5f)", tp, ask); return false; }

   double entry;
   double marketRRR = (ask - sl > 0) ? (tp - ask) / (ask - sl) : 0;

   PrintFormat("[FVG_Buy] Market RRR=%.2f MinRRR=%.1f", marketRRR, InpMinRRR);

   if(marketRRR >= InpMinRRR)
   {
      entry = ask;
      PrintFormat("[FVG_Buy] RRR ok — market buy at %.5f", entry);
   }
   else
   {
      entry = (tp + InpMinRRR * sl) / (1.0 + InpMinRRR);
      PrintFormat("[FVG_Buy] RRR low — BuyLimit calculated at %.5f", entry);
      if(entry >= ask || entry <= sl) { PrintFormat("[FVG_Buy] SKIP: entry(%.5f) out of range ask=%.5f sl=%.5f", entry, ask, sl); return false; }
      double limitRRR = (entry - sl > 0) ? (tp - entry) / (entry - sl) : 0;
      if(limitRRR < InpMinRRR) { PrintFormat("[FVG_Buy] SKIP: limitRRR %.2f < %.1f", limitRRR, InpMinRRR); return false; }
      PrintFormat("[FVG_Buy] BuyLimit at %.5f | limitRRR=%.2f", entry, limitRRR);
   }

   bool ok = PlaceBuy(entry, sl, tp, "FVG_Buy");
   if(ok) g_FVGBuyDone = true;
   return ok;
}

// Straight Buy
//
// TIMING (bulletproof):
//   • Outer guard in ScanBuySetups:  CurrentHour() > 5  (hr >= 6)
//   • Inner guard here:              CurrentHour() == 6  (exactly the 6AM bar)
//   Together these guarantee the trade fires ONLY when the 5AM candle has
//   just closed as bar[1] and the 6AM bar has just opened.
//   CurrentHour() uses TimeGMT() directly — broker timezone has zero effect.
//
// Trigger : 5AM candle (bar[1]) closes bullish
//           bars[2..4] (2AM–4AM) mostly bearish (BearishFromLondonToNYKZ)
// Entry   : market buy
// SL      : below min(bar[1].low, bar[2].low)
// TP      : ST high above Asian High; if all Asian candles bearish → Asian High
bool TryStraightBuy()
{
   if(g_FVGBuyDone) return false;

   // Must be exactly 6AM Eastern — the first bar after the 5AM candle closes.
   // Uses CurrentHour() which is pure UTC-derived Eastern time, never broker clock.
   if(CurrentHour() != InpNYKillZoneNY + 1) return false;

   // Bars from London open (2AM) to NY KZ open (5AM) must be mostly bearish.
   // Uses fixed bar indices — no timezone conversion needed.
   if(!BearishFromLondonToNYKZ()) return false;

   // 5AM candle (bar[1]) must be bullish
   if(!IsBullishCandle(1)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = MathMin(iLow(_Symbol, PERIOD_H1, 1),
                          iLow(_Symbol, PERIOD_H1, 2)) - PipsToPrice(InpFVGBuffer);

   if(sl >= entry) return false;

   double tp;
   if(g_AllAsianBearish && g_AsianHigh > 0 && g_AsianHigh > entry)
      tp = g_AsianHigh;
   else
      tp = GetSTHigh(InpSTH_Lookback);

   if(tp <= entry) return false;

   bool ok = PlaceBuy(entry, sl, tp, "Straight_Buy");
   if(ok) g_StraightBuyDone = true;
   return ok;
}

//============================================================
//  FVG ASIAN SELL — SL REENTRY LOGIC
//============================================================

void CheckAsianSellSLReentry()
{
   if(g_AsianSellSLHit || g_AsianSellReentered) return;

   datetime dayStart = TodayMidnight();
   if(!HistorySelect(dayStart, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket,  DEAL_COMMENT) != "FVG_Asian_Sell") continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)   != InpMagicNumber)   continue;
      if(HistoryDealGetString(ticket,  DEAL_SYMBOL)  != _Symbol)          continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)   != DEAL_ENTRY_OUT)   continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0)
      {
         g_AsianSellSLHit = true;
         string msg = "⚠ FVG_Asian_Sell SL hit — re-entry BUY on next bar. Verify TP at daily equal highs.";
         Print(msg);
         if(InpPopupAlerts) Alert(msg);
         if(InpPushAlerts)  SendNotification(msg);
      }
      break;
   }
}

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
      string msg = "✓ Re-entry BUY after FVG_Asian_Sell SL hit. ⚠ Move TP to equal highs on D1.";
      Print(msg);
      if(InpPopupAlerts) Alert(msg);
      if(InpPushAlerts)  SendNotification(msg);
   }
   return ok;
}

//============================================================
//  SELL SETUPS
//============================================================

bool ScanSellSetups()
{
   int  hr        = CurrentHour();
   bool triggered = false;

   // Priority 1: FVG Asian Sell | 01:00–10:00 NY
   if(!triggered && g_AsianFVGBearish && hr >= InpFVGAsianWindowStartNY && hr <= InpTradingEndNY)
      triggered = TryFVGAsianSell();

   // Priority 2: FVG Sell | 02:00–10:00 NY
   if(!triggered && hr >= InpLondonStartNY && hr <= InpTradingEndNY)
      triggered = TryFVGSell();

   // Priority 3: Straight Sell | 06:00–10:00 NY (5AM candle must have just closed)
   if(!triggered && hr > InpNYKillZoneNY && hr <= InpTradingEndNY)
      triggered = TryStraightSell();

   return triggered;
}

// FVG Asian Sell
// Context: bearish FVG on last Asian candle | daily sell reversal required
// Window : 01:00–10:00 NY
// Entry  : sell limit at midpoint of bearish FVG zone
// SL     : above bar before FVG pair
// TP     : ST low below Asian Low
bool TryFVGAsianSell()
{
   if(g_AsianLastBar < 0) return false;
   if(!IsDailySellReversalPattern()) return false;

   double zHigh, zLow;
   if(!GetFVGZone(g_AsianLastBar, zHigh, zLow)) return false;

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = (zHigh + zLow) / 2.0;
   if(entry <= bid) return false;

   double sl = iHigh(_Symbol, PERIOD_H1, g_AsianLastBar + 2) + PipsToPrice(InpFVGBuffer);
   double tp = GetSTLow(InpSTH_Lookback);
   if(tp <= 0 || tp >= entry) return false;

   string dailyMsg = "⚠ FVG_Asian_Sell placed — check DAILY equal lows for primary TP target.";
   Print(dailyMsg);
   if(InpPopupAlerts) Alert(dailyMsg);

   return PlaceSell(entry, sl, tp, "FVG_Asian_Sell");
}

// FVG Sell
// Trigger : upside violation of Asian range + bearish FVG | 02:00–10:00 NY
// Entry   : market if RRR >= min; otherwise sell limit at min-RRR price
// SL      : above bar[2] high (the candle that spiked up — always above the FVG gap)
// TP      : ST low below Asian Low; if all Asian bullish → Asian Low
bool TryFVGSell()
{
   if(g_FVGSellDone)         return false;
   if(g_StraightSellDone)    return false;
   if(!HasUpsideViolation()) return false;
   if(DetectFVG(1) != -1)    return false;

   double zHigh, zLow;
   if(!GetFVGZone(1, zHigh, zLow)) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // SL above bar[2]'s high — the candle that made the upside violation.
   // bar[2].high is always above the FVG gap and thus always above current bid.
   // Using bar[3] was wrong: bar[3] sits at lower prices than bar[2] in an uptrend,
   // meaning the SL could be placed below the actual spike high (too tight).
   double sl  = iHigh(_Symbol, PERIOD_H1, 2) + PipsToPrice(InpFVGBuffer);

   double tp;
   if(g_AllAsianBullish && g_AsianLow > 0 && g_AsianLow < bid)
      tp = g_AsianLow;
   else
      tp = GetSTLow(InpSTH_Lookback);

   if(tp <= 0 || tp >= bid || sl <= bid) return false;

   double entry;
   double marketRRR = (sl - bid > 0) ? (bid - tp) / (sl - bid) : 0;

   if(marketRRR >= InpMinRRR)
   {
      entry = bid;
   }
   else
   {
      entry = (tp + InpMinRRR * sl) / (1.0 + InpMinRRR);
      if(entry <= bid || entry >= sl) return false;
      double limitRRR = (sl - entry > 0) ? (entry - tp) / (sl - entry) : 0;
      if(limitRRR < InpMinRRR) return false;
      PrintFormat("[FVG_Sell] Market RRR %.2f < %.1f — SellLimit at %.5f", marketRRR, InpMinRRR, entry);
   }

   bool ok = PlaceSell(entry, sl, tp, "FVG_Sell");
   if(ok) g_FVGSellDone = true;
   return ok;
}

// Straight Sell
//
// TIMING (bulletproof — mirrors Straight Buy):
//   • Outer guard: CurrentHour() > 5  (hr >= 6)
//   • Inner guard: CurrentHour() == 6 (exactly 6AM bar)
//   The 5AM candle must have just closed as bar[1].
//
// Trigger : bar[1] (5AM) closes bearish with a wick above bar[2]'s high
//           bars[2..4] (2AM–4AM) mostly bullish (BullishFromLondonToNYKZ)
//           bar[2] or bar[3] must be bullish (prior formation)
// Entry   : market sell
// SL      : above max(bar[1].high, bar[2].high)
// TP      : ST low below Asian Low; if all Asian candles bearish → Asian Low
bool TryStraightSell()
{
   if(g_FVGSellDone) return false;

   // Must be exactly 6AM Eastern — the first bar after the 5AM candle closes.
   if(CurrentHour() != InpNYKillZoneNY + 1) return false;

   // Bars from London open (2AM) to NY KZ open (5AM) must be mostly bullish.
   if(!BullishFromLondonToNYKZ()) return false;

   // 5AM candle (bar[1]) must close bearish with a wick above bar[2]'s high
   if(!IsBearishCandle(1)) return false;
   if(iHigh(_Symbol, PERIOD_H1, 1) <= iHigh(_Symbol, PERIOD_H1, 2)) return false;

   // Prior bullish formation must exist
   if(!IsBullishCandle(2) && !IsBullishCandle(3)) return false;

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = MathMax(iHigh(_Symbol, PERIOD_H1, 1),
                          iHigh(_Symbol, PERIOD_H1, 2)) + PipsToPrice(InpFVGBuffer);

   if(sl <= entry) return false;

   double tp;
   if(g_AllAsianBearish && g_AsianLow > 0 && g_AsianLow < entry)
      tp = g_AsianLow;
   else
      tp = GetSTLow(InpSTH_Lookback);

   if(tp <= 0 || tp >= entry) return false;

   bool ok = PlaceSell(entry, sl, tp, "Straight_Sell");
   if(ok) g_StraightSellDone = true;
   return ok;
}

//+------------------------------------------------------------------+
//  END OF EA
//+------------------------------------------------------------------+
//
//  NOTES ON RE-ENTRIES (manual):
//  1. FVG Asia Sell SL hit → automated re-entry buy fires next bar
//  2. Straight buy/sell weak candle → switch direction manually
//
//  DXY CONFLUENCE (manual):
//  Check DXY before each session. Bullish DXY → favour sell setups.
//  Bearish DXY → favour buy setups.
//
//  KEY LEVELS (manual):
//  Mark Daily, 4H, Weekly, Monthly levels. EA uses short-term
//  highs/lows for TP — your marked levels take priority.
//
//+------------------------------------------------------------------+
