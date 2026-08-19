//+------------------------------------------------------------------+
//|                       NomShadoNgidi_EA.mq5                       |
//|            Expert Advisor — Nomshado Ngidi Trading Plan          |
//|           Instrument: US30 / US_30 / US.30  |  Version 1.75        |
//+------------------------------------------------------------------+
//
//  ⚠ THIS EA WILL ONLY RUN ON US_30 (also accepted: US.30, US30)
//  It will REFUSE to load on any other instrument.
//
//  SETUP MODELS IMPLEMENTED:
//  BUY  → FVG Asian Buy | FVG Buy | Straight Buy
//  SELL → FVG Asian Sell | FVG Sell | Straight Sell
//
//  v1.75 CHANGES (from v1.74):
//  • AsianBreakDirection(): faulty FVG pattern now detected directly in this function
//    Added CheckFaultyBullishFVG() and CheckFaultyBearishFVG() helpers that scan
//    today's 02:00–09:00 ET bars for the faulty pattern
//    Previously g_FaultyLowSweep/g_FaultyHighSweep was only set by TryFVGBuy/TryFVGSell,
//    meaning if the bot loaded after the London FVG window (06:00+), the flags were never
//    set and sell/buy setups still skipped. Now AsianBreakDirection() detects and sets
//    the flags itself when firstIsLow+highAlsoRan or firstIsHigh+lowAlsoRan are seen.
//
//  v1.74 CHANGES (from v1.73):
//  • AsianBreakDirection(): "broke BOTH levels on same bar → no trade" rule relaxed
//    When a single bar breaks both Asian High and Low:
//      - If no direction established yet → use bar's CLOSE to decide:
//          close > Asian High = swept Low, closed above High → SELL direction
//          close < Asian Low  = swept High, closed below Low  → BUY direction
//          close between levels                               → ambiguous, no trade
//      - If direction already established → record highAlsoRan/lowAlsoRan as normal
//    This allows sweep+FVG candles (where a single bar creates the FVG pattern by
//    sweeping one level and closing beyond the other) to be evaluated by TryFVGBuy/Sell
//
//  v1.73 CHANGES (from v1.72):
//  • Faulty FVG / Liquidity Sweep pattern detection added
//    If a bullish FVG forms BUT the middle candle's low is below the previous candle's low
//    (i.e. candle 2 swept below candle 1 before gapping up):
//      → g_FaultyLowSweep = true; BUY skipped; wait for Asian High to break → SELL
//    Symmetrically for bearish FVG with middle candle high > previous candle high:
//      → g_FaultyHighSweep = true; SELL skipped; wait for Asian Low to break → BUY
//  • AsianBreakDirection() restructured: no longer returns early on first break;
//    continues to scan and applies faulty-sweep direction override at end
//  • Block guards added to all 4 setup functions (TryFVGBuy, TryStraightBuy,
//    TryFVGSell, TryStraightSell) for g_FaultyLowSweep / g_FaultyHighSweep
//  • Flags reset daily in ResetDailyCount()
//  • Fixed duplicate g_DailyCount / g_LastDay assignment in ResetDailyCount()
//
//  v1.72 CHANGES (from v1.71):
//  • Straight Buy/Sell window: changed hr < InpTradingEndNY → hr <= InpTradingEndNY
//    Fix: 09:00 ET bearish/bullish candle now correctly triggers at 10:00 ET bar open
//    Previously the 09:00 ET candle could never be bar[1] because hr=10 was excluded
//  • News filter removed from OnTick — news days handled manually by trader
//
//  v1.71 CHANGES (from v1.70):
//  • News filter: block now lifts at the START of the next full H1 candle after release
//    e.g. CPI at 08:30 ET → entries allowed from 09:00 ET candle open onwards
//    Formula: blockEnd = (evTimeET / 3600 + 1) * 3600 (next hour boundary)
//
//  v1.70 CHANGES (from v1.69):
//  • News filter: widened CalendarValueHistory window from exact server day
//    to ±36h around now — prevents timezone mismatch dropping today's events
//  • News filter: added today-only ET date guard so wider window doesn't
//    accidentally block on tomorrow's events
//  • News filter: added diagnostic log showing how many USD events were found
//    and listing each matched high-impact event with its ET time
//
//  v1.69 CHANGES (from v1.68):
//  • News filter: added full event name matching alongside abbreviations
//    Now catches "Consumer Price Index" (not just "CPI") and
//    "Producer Price Index" (not just "PPI") from MT5 calendar
//
//  v1.68 CHANGES (from v1.67):
//  • FVG Buy / FVG Sell: replaced strict "next candle only" gate with TP-reached check
//    Entry stays valid on any candle after the FVG forms, as long as the TP level
//    (STHigh for buys / STLow for sells) has not yet been hit
//    If TP already reached → SKIP; if no STH/STL found → fallback TP as before
//
//  v1.67 CHANGES (from v1.66):
//  • FVG Buy / FVG Sell: entry only fires on the candle immediately after the FVG
//    fvgBar must == 1 (FVG confirmed by bar[1], entry on bar[0])
//    If FVG is older (fvgBar > 1), skip — opportunity has passed
//
//  v1.66 CHANGES (from v1.65):
//  • FVG Buy / FVG Sell: upgraded from 2-candle body-gap to standard 3-candle FVG
//    Old: bodyHigh < prevLow (body of bar[i] entirely below bar[i+1] low)
//    New: iHigh(i) < iLow(i+2)  / iLow(i) > iHigh(i+2)  — proper ICT/SMC 3-bar pattern
//    FVG zone = gap between candle 1 (bar[i+2]) and candle 3 (bar[i]), candle 2 is the big move
//
//  v1.65 CHANGES (from v1.64):
//  • FVG Buy restricted to London KZ only (02:00–06:00 ET)
//    Backtest data: London FVG Buy = 56% WR vs NY FVG Buy = 31% WR (flat ROI)
//    FVG Sell unchanged — NY FVG Sell is the strongest sub-category (62% WR)
//
//  v1.64 CHANGES (from v1.63):
//  • CalcLotSize: replaced SYMBOL_MARGIN_INITIAL with OrderCalcMargin() for
//    the margin cap. SYMBOL_MARGIN_INITIAL returns 0 on BlackBull demo accounts,
//    causing the fallback to use stated 1:500 leverage (~$105/lot) instead of the
//    real ~$522/lot — so 20+ lots were attempted and rejected with "No money."
//    OrderCalcMargin() asks MT5 directly and always returns the real charge.
//    Same fix applied in CheckScaleIn().
//
//  v1.63 CHANGES (from v1.62):
//  • Scale-in: when BlackBull margin caps the initial lot size below the
//    intended size, the bot adds more lots as floating profit frees up margin.
//    All add-ons use the same SL and TP as the original position.
//    Enable/disable via InpScaleIn input. Target lot size is stored before
//    the margin cap and reset each trading day.
//
//  v1.62 CHANGES (from v1.61):
//  • Break-even trigger changed from 50% to 65% of entry→TP distance
//    e.g. 1:7R trade triggers at 4.55R instead of 3.5R
//
//  v1.61 CHANGES (from v1.60):
//  • Removed BothAsianLevelsBroken block — first break direction is the signal
//    Asian session is the range; breaks happen from 1am ET onwards. If Low breaks
//    first then High also breaks later, the BUY direction still stands and setups
//    are attempted normally. AsianBreakDirection() already tracks first-break correctly.
//
//  v1.60 CHANGES (from v1.59):
//  • Straight Buy / Sell window extended: bar[1] can now close at 10:00 ET
//    Previously hourNY > 9 blocked the 09:00–10:00 candle from triggering entry
//    Now hourNY > 10 allows entry at the 10:00 open based on the 09:00 close bar
//
//  v1.59 CHANGES (from v1.58):
//  • CalcLotSize: enforce minimum 0.1 lot step (BlackBull only accepts 0.1 increments)
//    Lots now always round to 1 decimal place (e.g. 0.17 → 0.2, 0.14 → 0.1)
//    Prevents order rejection from invalid volume on BlackBull US30
//
//  v1.58 CHANGES (from v1.57):
//  • Same-day BE trigger changed to 50% of entry→TP distance (midpoint)
//    e.g. 1:7R trade → triggers at 3.5R; 1:2R trade → triggers at 1R
//    SL moves to entry the moment price reaches the midpoint between entry and TP
//
//  v1.57 CHANGES (from v1.56):
//  • Same-day BE trigger corrected from 2R to 1.5R — when price reaches 1.5R
//    profit, SL moves to entry immediately
//  • Overnight losing trade: now closed immediately instead of leaving SL unchanged
//    (in-profit overnight trades still move SL to entry, unchanged)
//
//  v1.56 CHANGES (from v1.55):
//  • Added CheckBreakEven2R: when any open position reaches 2R profit (same day)
//    → SL moves to entry immediately for all setups
//  • Overnight break-even (CheckBreakEvenOvernight) unchanged — still moves SL
//    to entry on next day if trade is in profit
//
//  v1.55 CHANGES (from v1.54):
//  • Removed same-day 1.5R break-even (CheckStraightBreakEven) for all setups
//    SL now only moves to entry if the trade carries over to the next day
//    and is in profit (CheckBreakEvenOvernight — unchanged)
//
//  v1.54 CHANGES (from v1.53):
//  • GetSTHigh / GetSTLow: reverted scan direction back to pre-Asian bars
//    (bars before today's Asian session start at 19:00 ET yesterday).
//    Scans most-recent → oldest, returns the FIRST qualifying transition:
//    - Primary: bull→bear above Asian High (buy) / bear→bull below Asian Low (sell)
//    - Fallback: bull→bear above Ask / bear→bull below Bid
//    This matches the manual trade approach: nearest STH/STL going backwards
//    before today's Asian session, falling back further if none found nearby.
//  • Kept v1.53 fixes: else bug fixed, STH/STL used directly (no 1:2 cap)
//
//  v1.53 CHANGES (from v1.52):
//  • GetSTHigh / GetSTLow: now scan POST-Asian bars first (today from midnight ET)
//    for the nearest swing high/low above/below current price — this matches the
//    manual trade approach of using the nearest swing formed after the Asian session.
//    Pre-Asian bars remain as fallback if nothing qualifies post-Asian.
//  • TryStraightBuy / TryStraightSell: TP now uses the STH/STL directly (no longer
//    overrides to 1:2 when STH is found). Fallback (3R / Asian level) only runs
//    when no valid STH/STL is found.
//  • Fixed missing `else` bug: fallback TP block was running unconditionally,
//    overriding a valid STH/STL with the 3R level (caused the 52574 TP today).
//
//  v1.52 CHANGES (from v1.51):
//  • Straight Buy / Sell window start moved from 05:00 ET to 06:00 ET
//    - Was: fires when any candle closes at 05:00–09:00 ET
//    - Now: fires when any candle closes at 06:00–09:00 ET
//    - Prevents the 05:00 ET (4:00 bar close) from triggering straight entries
//    - InpNYKillZoneNY default changed from 5 to 6
//
//  v1.51 CHANGES (from v1.50):
//  • OnInit guard: now prints which condition blocked the startup scan
//    e.g. "[Init] Guard: InWindow=Y NewsBlock=N DailyCount=0:Y BothBroken=Y"
//  • TryFVGBuy / TryFVGSell: prints each bar in the 02:00–09:00 ET scan window
//    showing body vs prevHigh/prevLow and the gap, so you can see exactly why
//    no FVG is found when the scan returns empty
//
//  v1.50 CHANGES (from v1.49):
//  • FVG Buy / FVG Sell: when RR < 1:2, now places a visible LIMIT ORDER
//    in MT5's order book at the exact price that achieves 1:2 RR
//    (was: invisible tick-by-tick monitoring then market order)
//    - RR >= 1:2 → market entry immediately (unchanged)
//    - 1.5 <= RR < 1:2 → place BuyLimit/SellLimit at (tp + 2*sl) / 3
//    - RR < 1.5 → skip (insufficient setup quality)
//  • Removed CheckFVGPendingEntry (tick monitoring) — no longer needed
//  • Removed g_FVGBuyPending12 / g_FVGSellPending12 global variables
//
//  v1.33 CHANGES (from v1.32):
//  • Straight Buy / Sell window corrected:
//    - Candles closing 05:00–09:00 ET are valid triggers
//    - Last valid entry is at 10:00 open (09:00 candle close)
//    - 10:00 candle close excluded (would result in 11:00 entry)
//
//  v1.32 CHANGES (from v1.31):
//  • FVG Buy / FVG Sell: corrected FVG detection to match manual trading definition:
//    - Bullish FVG: bar[1] BODY (open to close) is entirely above bar[2] HIGH
//    - Bearish FVG: bar[1] BODY (open to close) is entirely below bar[2] LOW
//    - No minimum gap size threshold
//    - Asian Low break still required for FVG Buy
//    - Asian High break still required for FVG Sell
//    - Entry: market order immediately when bar[1] closes in FVG
//    - SL: low of bar[2] minus buffer (buy) / high of bar[2] plus buffer (sell)
//  • Fallback TP corrected from 3% of price to 3R from entry:
//    - Buy:  TP = higher of (entry + 3×SLdistance) or Asian High
//    - Sell: TP = lower  of (entry - 3×SLdistance) or Asian Low
//    - Applies to all 4 setups: FVG Buy, FVG Sell, Straight Buy, Straight Sell
//
//  v1.31 CHANGES (from v1.30):
//  • Break-even rule for any carried-over trade:
//    - If a trade is still open on the NEXT trading day after it was opened
//    - AND the trade is currently in profit → SL moved to entry (break even)
//    - If trade is in a loss → SL stays at original level
//    - CheckBreakEvenOvernight() called at start of every OnTick
//
//  v1.30 CHANGES (from v1.28):
//  • News filter rework — new rule:
//    - If CPI/PPI/NFP is scheduled today:
//        Block ALL entries from midnight (00:00 ET) until news release time
//        Allow entries again 30 minutes AFTER the release
//    - If no news today: EA trades normally all day during kill zones
//    - DST handled automatically (EA runs on Eastern Time throughout)
//  • InpNewsMinsBefore removed — no longer needed (block starts at midnight)
//  • InpNewsMinsAfter retained — controls how long after news entries are blocked
//  • FVG Buy / FVG Sell: added fallback TP when no STH/STL found
//    Buy:  TP = higher of (3% above entry) or Asian session High
//    Sell: TP = lower  of (3% below entry) or Asian session Low
//    Same rule applied to Straight Buy / Straight Sell
//
//  v1.28 CHANGES (from v1.27):
//  • FVG Asian Buy / Sell: full rework
//    - Entry only at 01:00 ET (candle after Asian session closes at 00:00)
//    - Daily filter: D1 bar[1] must show a reversal candle BEFORE entry:
//        Buy  → lower wick breaks below D1 bar[2] low  OR bullish engulfing
//        Sell → upper wick breaks above D1 bar[2] high OR bearish engulfing
//    - SL: Asian session High (sell) or Low (buy) — not H1 bar[1] wick
//    - TP: scan D1 bars from bar[2] backwards; find first bar whose
//        high (buy) is below reversal candle's low, OR
//        low  (sell) is above reversal candle's high
//      Keep scanning indefinitely until a valid level is found
//  • Added helper: GetD1ReversalTP() for buy and sell
//  • Added helper: HasD1BullishReversal() and HasD1BearishReversal()
//
//  v1.27 CHANGES (from v1.26):
//  • PlaceBuy / PlaceSell: removed 1:2 TP lock — TP now always goes to the
//    actual STH (buys) or STL (sells) level as identified by GetSTHigh/GetSTLow
//  • Minimum RRR check (>= 1.5) retained — trades with RRR below 1.5 still skipped
//  • RRR in journal/alerts now reflects true planned RR to the STH/STL
//
//  v1.26 CHANGES (from v1.25):
//  • Removed minimum SL distance filter — lot size adjusts to margin instead
//  • CalcLotSize margin cap retained: lots scaled down to max affordable
//
//  v1.25 CHANGES (from v1.24):
//  • CalcLotSize: added margin cap — lots reduced to max affordable based on
//    free margin (handles BlackBull 1:100 effective margin on indices)
//  • PlaceBuy / PlaceSell: added minimum SL distance of 30 price points
//    Prevents doji candle wicks generating 30-40+ lot calculations
//
//  v1.24 CHANGES (from v1.23):
//  • CalcLotSize: fixed formula to include g_PipSize
//    Correct: lots = risk / (slPips × g_PipSize × contractSize)
//    This fixes BlackBull US30 where g_PipSize=0.1 was causing
//    lots to be calculated 10x too small, then rounded up to minimum
//  NOTE: Starting balance of $50 is too small for BlackBull US30.
//    Minimum viable balance ≈ $200 (margin per 0.1 lot ≈ $49 at current prices)
//
//  v1.23 CHANGES (from v1.22):
//  • Risk model restored to balance/6 (hardcoded per trading plan)
//    InpRiskPercent input removed — not configurable
//
//  v1.22 CHANGES (from v1.21):
//  • CalcLotSize: replaced hardcoded /10 with SYMBOL_TRADE_CONTRACT_SIZE
//    - AvaTrade US_30:  contract size = 10 → lots = risk / (slPips × 10)
//    - BlackBull US30:  contract size = 1  → lots = risk / (slPips × 1)
//    - FTMO and others: auto-detected — no manual adjustment needed
//  • Symbol check updated to accept US30 (BlackBull label)
//
//  v1.21 CHANGES (from v1.20):
//  • All-bullish Asian session TP override added to TryStraightSell and TryFVGSell:
//    if g_AllAsianBullish == true → TP is overridden to g_AsianLow
//    (fade the bullish session, target the bottom of Asian range)
//    Normal TP logic (STH/STL 1.5 RR → lock at 1:2) applies otherwise
//
//  v1.20 CHANGES (from v1.19):
//  • TP logic changed for all 4 setup types:
//    - If STH/STL gives RRR >= 1.5 → TP locked at exactly 1:2 RR
//    - If STH/STL gives RRR <  1.5 → trade skipped entirely
//    - If no STH/STL found → fallback TP set at 1:2 RR (was 1:3)
//  • InpMinRRR parameter now unused (logic hardcoded at 1.5 threshold / 1:2 target)
//
//  v1.19 CHANGES (from v1.18):
//  • FVG Asian Buy and FVG Asian Sell setups REMOVED entirely
//    Active setups: FVG Buy, FVG Sell, Straight Buy, Straight Sell
//
//  v1.18 FIXES — SL placement refinement (from v1.17):
//  • Straight Buy  SL: MathMax(iLow(bar[1]), iLow(bar[2]))  - buffer
//    (highest of two previous lows — tighter stop closer to entry)
//  • Straight Sell SL: MathMin(iHigh(bar[1]), iHigh(bar[2])) + buffer
//    (lowest of two previous highs — tighter stop closer to entry)
//  • FVG Buy/Sell SL unchanged: bar[1] wick only
//
//  v1.17 FIXES — SL placement (from v1.16):
//  • ALL setup types: SL now placed at wick of previous candle (bar[1])
//    BUY  SL = iLow(bar[1])  - buffer
//    SELL SL = iHigh(bar[1]) + buffer
//  • Replaces all previous SL logic (Asian Low/High, GetSTLowForSL, GetSTHighForSL)
//
//  v1.16 FIXES (from v1.15):
//  • SELL SL: reverted from Asian High back to GetSTHighForSL (nearest swing
//    high above entry). Charts show sell SL = sweep candle high, not Asian High.
//    Logic is ASYMMETRIC by design:
//    BUY  SL = Asian Low - buffer   (the swept low is the reference)
//    SELL SL = nearest swing high above entry + buffer (the sweep candle high)
//  • Removed "entry must be below Asian High" check from TryStraightSell —
//    valid sells can fire when price is still above Asian High after the sweep
//
//  v1.15 CHANGES — Manual journal alignment (from v1.14):
//  • Risk model: changed from balance/6 (16.7%) to InpRiskPercent% (default 1%)
//    Manual journal shows all losses = exactly -1% → confirms 1% risk per trade
//  • SL placement: ALL setups now use Asian Low (buys) or Asian High (sells)
//    Manual charts show pink SL zone sits at Asian session range boundary,
//    NOT at nearest H1 swing low/high as previously coded
//  • These two changes are the primary reason EA results diverged from manual journal
//
//  v1.14 CHANGES (from v1.12):
//  • Fallback 1:3 RR TP RESTORED in TryStraightBuy and TryStraightSell
//    — confirmed intentional per manual trading plan: if price is at chart
//      extreme with no visible STH/STL, use 1:3 RR as take profit target
//  • v1.13 pullback filters (IsBullishCandle/MostlyBearishPrior) NOT included
//    — those were overly restrictive and blocked all trades
//
//  v1.12 FIXES retained:
//  • Trading end boundary: hr < InpTradingEndNY (was <=) — 5 locations
//  • TryStraightBuy: entry must be >= Asian Low
//  • TryStraightSell: entry must be <= Asian High
//
//  v1.12 FIXES (applied to v1.11 (7)):
//  • Bug 1 (CRITICAL): Trading end boundary — ALL hr <= InpTradingEndNY changed
//    to hr < InpTradingEndNY. Affects IsInTradingWindow, ScanBuySetups (x2),
//    ScanSellSetups (x2). Prevents trades firing at the 10:00 bar open.
//  • Bug 2: TryStraightBuy — entry must be >= Asian Low. Asian Low sweep means
//    price must return ABOVE Asian Low before a buy is valid.
//  • Bug 3: TryStraightSell — entry must be <= Asian High. Symmetric to above.
//  • Bug 4: Fallback 1:3 TP removed from TryStraightBuy and TryStraightSell.
//    Both now SKIP if no valid STH/STL is found — no unstructured targets.
//
//  v1.08 CHANGES (to match manual backtest journal):
//  • AutoBias D1 filter REMOVED — was blocking valid trades
//  • IsDailyBullishReversal / IsDailyBearishReversal REMOVED — same
//  • GetSTHigh: now finds true H1 swing high (3-bar pattern); no longer
//    requires level to be above the Asian session high
//  • GetSTLow:  now finds true H1 swing low  (3-bar pattern); no longer
//    requires level to be below the Asian session low
//  • TryStraightBuy:  fires across full London+NY window (02:00–10:00 ET),
//    not locked to 6AM only; simplified trigger
//  • TryStraightSell: same window fix
//  • TryFVGBuy:  HasDownsideViolation check relaxed — fires if FVG present
//  • TryFVGSell: HasUpsideViolation  check relaxed — fires if FVG present
//
//  HOW TO INSTALL:
//  1. Copy this file to: MT5 → File → Open Data Folder → MQL5 → Experts
//  2. Restart MetaTrader 5 (or press F5 in MetaEditor)
//  3. Drag the EA onto your US_30 H1 chart
//  4. Ensure "Allow Algo Trading" is enabled in MT5
//
//+------------------------------------------------------------------+
#property copyright   "Nomshado Ngidi"
#property version     "1.75"
#property description "MT5 EA — Nomshado Ngidi Trading Plan v1.75"
#property description "⚠ Instrument: US30 / US_30 / US.30 ONLY"
#property description "Setups: FVG Buy/Sell, Asian FVG, Straight Buy/Sell"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//============================================================
//  EXECUTION MODE ENUM
//============================================================

enum ENUM_EXEC_MODE
{
   EXEC_AUTO   = 0,  // Auto — market if within 2 pips of ask/bid, else limit/stop pending
   EXEC_MARKET = 1,  // Always market execution
   EXEC_LIMIT  = 2   // Always pending order
};

//============================================================
//  INPUT PARAMETERS
//============================================================

input group "=== Session Times (Eastern Time — auto DST) ==="
input int    InpAsianStartNY          = 19;  // Asian Session Start — NY time (plan: 19:00)
input int    InpAsianEndNY            = 0;   // Asian Session End   — NY time (plan: 00:00)
input int    InpFVGAsianWindowStartNY = 1;   // FVG Asian setups window start — NY time (plan: 01:00)
input int    InpLondonStartNY         = 2;   // London Kill Zone Start — NY time (plan: 02:00)
input int    InpNYKillZoneNY          = 6;   // NY Kill Zone Start — NY time (plan: 06:00)
input int    InpTradingEndNY          = 10;  // Trading Window End — NY time (plan: 10:00)

input group "=== Risk Management ==="
// Risk per trade = balance / 6 (hardcoded per trading plan)
input double InpMinRRR         = 2.0;  // Minimum Risk:Reward Ratio (1:2)
input bool   InpScaleIn        = true; // Scale into position as profit frees margin

input group "=== Stop Loss Settings ==="
input int    InpFVGBuffer      = 5;    // SL/entry buffer in pips

input group "=== Trade Settings ==="
input ENUM_EXEC_MODE InpExecMode      = EXEC_AUTO;
input int    InpMaxDailyTrades        = 1;
input bool   InpAllowMonday           = false;
input int    InpPendingCancelHour     = 11;
input int    InpSTH_Lookback          = 20;  // H1 bars to look back for swing high/low
input int    InpMagicNumber           = 20250101;
input double InpD1ReversalBodyRatio   = 0.5; // kept for FVG Asian only (optional)

input group "=== News Filter (CPI / PPI / NFP) ==="
input bool   InpNewsFilter        = true;
// v1.30: no entries from midnight until news release time
// InpNewsMinsAfter controls how long AFTER the release entries remain blocked
input int    InpNewsMinsAfter     = 30;  // Minutes to wait after news before trading again

input group "=== Alerts ==="
input bool   InpPopupAlerts    = true;
input bool   InpPushAlerts     = false;
input bool   InpEmailAlerts    = true;
input string InpAlertEmail     = "solutionsphanaso@gmail.com";
input double InpBalanceLowAlert = 100.0;

//============================================================
//  GLOBAL VARIABLES
//============================================================

CTrade        trade;
CPositionInfo pos;

int      g_DailyCount   = 0;
datetime g_LastDay      = 0;
double   g_PipSize      = 0;

double   g_AsianHigh        = 0;
double   g_AsianLow         = 0;
bool     g_AsianFVGBullish  = false;
bool     g_AllAsianBullish  = false;  // v1.21: true if all Asian session candles were bullish
bool     g_AsianFVGBearish  = false;
bool     g_AllAsianBearish  = false;
int      g_AsianLastBar     = -1;
datetime g_AsianDate        = 0;

bool     g_BalanceLowAlertSent = false;
bool     g_Milestone1k         = false;
bool     g_Milestone5k         = false;
bool     g_Milestone10k        = false;
bool     g_Milestone50k        = false;
bool     g_Milestone100k       = false;
bool     g_Milestone500k       = false;
bool     g_Milestone1m         = false;

bool     g_FVGBuyDone              = false;
bool     g_StraightBuyDone         = false;
bool     g_FVGSellDone             = false;
bool     g_StraightSellDone        = false;
bool     g_FaultyLowSweep          = false;  // Asian Low broke with faulty bullish FVG → wait for High→SELL
bool     g_FaultyHighSweep         = false;  // Asian High broke with faulty bearish FVG → wait for Low→BUY

double   g_TargetLots              = 0;  // intended lots before margin cap (for scale-in)

bool     g_AsianSellSLHit          = false;
bool     g_AsianSellReentered      = false;
bool     g_PendingsCancelledToday  = false;

datetime g_LastBar = 0;

//============================================================
//  INITIALISATION
//============================================================

int OnInit()
{
   if(StringFind(_Symbol, "US.30") < 0 && StringFind(_Symbol, "US30") < 0 && StringFind(_Symbol, "US_30") < 0)
   {
      string errMsg = "WRONG SYMBOL: This EA trades US.30 only. Current chart is " + _Symbol;
      Alert(errMsg);
      Print(errMsg);
      return INIT_FAILED;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_PipSize = (digits == 3 || digits == 5) ? _Point * 10.0 : _Point;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   PrintFormat("=== Nomshado Ngidi EA v1.75 Initialised ===");
   PrintFormat("Symbol: %s | Pip Size: %.5f", _Symbol, g_PipSize);
   PrintFormat("Risk per trade: Balance / 6 (%.2f%%) | Min RRR 1:%.1f", 100.0/6.0, InpMinRRR);
   PrintFormat("London KZ: %02d:00 | NY KZ: %02d:00–%02d:00",
               InpLondonStartNY, InpNYKillZoneNY, InpTradingEndNY);
   PrintFormat("Time base: Eastern Time (auto DST) — %s (UTC%d) | Max daily trades: %d",
               EasternOffset() == -4 ? "EDT" : "EST", EasternOffset(), InpMaxDailyTrades);
   if(!InpAllowMonday)
      Print("Monday filter: ACTIVE");
   if(InpNewsFilter)
      PrintFormat("News filter: ACTIVE — CPI/PPI/NFP blocks entries from midnight until release + %dm after",
                  InpNewsMinsAfter);

   g_LastBar = iTime(_Symbol, PERIOD_H1, 0);

   // v1.47: Immediately scan for existing FVGs on init — don't wait for next bar close
   // This ensures pending 1:2 levels are set even if EA is restarted mid-session
   ResetDailyCount();
   AnalyseAsianSession();
   {
      bool dbgWin  = IsInTradingWindow();
      bool dbgNews = IsHighImpactNewsWindow();
      bool dbgCnt  = (g_DailyCount == 0);
      PrintFormat("[Init] Guard: InWindow=%s NewsBlock=%s DailyCount=0:%s",
                  dbgWin?"Y":"N", dbgNews?"Y":"N", dbgCnt?"Y":"N");
      if(dbgWin && !dbgNews && dbgCnt)
      {
         Print("[Init] Scanning for existing FVGs on startup...");
         if(!ScanBuySetups()) ScanSellSetups();
      }
   }

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
      { entryPrice = HistoryDealGetDouble(d, DEAL_PRICE); break; }
   }
   if(entryPrice <= 0) return;

   double slPrice = 0, tpPrice = 0;
   for(int i = 0; i < HistoryOrdersTotal(); i++)
   {
      ulong ord = HistoryOrderGetTicket(i);
      if((ulong)HistoryOrderGetInteger(ord, ORDER_POSITION_ID) == positionId)
      { slPrice = HistoryOrderGetDouble(ord, ORDER_SL); tpPrice = HistoryOrderGetDouble(ord, ORDER_TP); }
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
      "Account         : %s\n"
      "Symbol          : %s\n"
      "Time            : %s",
      milestone, balance, acct, _Symbol, ts);
   Print(subj);
   SendMail(subj, body);
   if(InpPopupAlerts) Alert(subj);
   if(InpPushAlerts)  SendNotification(subj);
   flag = true;
}

void CheckBalanceAlerts()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string acct    = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   string ts      = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);

   if(!g_BalanceLowAlertSent && balance <= InpBalanceLowAlert)
   {
      string subj = StringFormat("LOW BALANCE on %s — $%.2f", _Symbol, balance);
      string body = StringFormat(
         "BALANCE ALERT — NomShadoNgidi EA\n\n"
         "Your account balance has dropped to $%.2f.\n"
         "Alert threshold : $%.2f\n"
         "Account         : %s\n"
         "Symbol          : %s\n"
         "Time            : %s",
         balance, InpBalanceLowAlert, acct, _Symbol, ts);
      Print(subj);
      if(InpEmailAlerts) SendMail(subj, body);
      if(InpPopupAlerts) Alert(subj);
      if(InpPushAlerts)  SendNotification(subj);
      g_BalanceLowAlertSent = true;
   }
   else if(g_BalanceLowAlertSent && balance > InpBalanceLowAlert)
      g_BalanceLowAlertSent = false;

   if(balance >= 1000.0)    FireMilestone(g_Milestone1k,   "$1,000",     balance, acct, ts);
   if(balance >= 5000.0)    FireMilestone(g_Milestone5k,   "$5,000",     balance, acct, ts);
   if(balance >= 10000.0)   FireMilestone(g_Milestone10k,  "$10,000",    balance, acct, ts);
   if(balance >= 50000.0)   FireMilestone(g_Milestone50k,  "$50,000",    balance, acct, ts);
   if(balance >= 100000.0)  FireMilestone(g_Milestone100k, "$100,000",   balance, acct, ts);
   if(balance >= 500000.0)  FireMilestone(g_Milestone500k, "$500,000",   balance, acct, ts);
   if(balance >= 1000000.0) FireMilestone(g_Milestone1m,   "$1,000,000", balance, acct, ts);
}

//============================================================
//  PENDING ORDER CLEANUP
//============================================================

void CancelPendingOrders()
{
   int cancelled = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL)           != _Symbol)       continue;
      if((int)OrderGetInteger(ORDER_MAGIC)      != InpMagicNumber) continue;

      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(otype != ORDER_TYPE_BUY_LIMIT  && otype != ORDER_TYPE_SELL_LIMIT &&
         otype != ORDER_TYPE_BUY_STOP   && otype != ORDER_TYPE_SELL_STOP) continue;

      if(trade.OrderDelete(ticket)) cancelled++;
      else PrintFormat("[CancelPending] FAILED ticket #%I64u — error %d", ticket, GetLastError());
   }
   g_PendingsCancelledToday = true;
   if(cancelled > 0)
      PrintFormat("[CancelPending] Cancelled %d pending order(s) at %02d:00 ET", cancelled, InpPendingCancelHour);
}

// CheckBreakEvenMidpoint — all setups, same day
// When price reaches 65% of the way from entry to TP → move SL to entry
// e.g. 1:7R trade → triggers at 4.55R; 1:2R trade → triggers at 1.3R
void CheckBreakEvenMidpoint()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))               continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double tp      = PositionGetDouble(POSITION_TP);
      long   posType = PositionGetInteger(POSITION_TYPE);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(tp <= 0) continue; // no TP set

      // Already at or past break-even
      if(posType == POSITION_TYPE_BUY  && sl >= entry) continue;
      if(posType == POSITION_TYPE_SELL && sl <= entry) continue;

      // Trigger = midpoint between entry and TP
      double trigger = entry + 0.65 * (tp - entry);

      bool hit = (posType == POSITION_TYPE_BUY)  ? (bid >= trigger) :
                 (posType == POSITION_TYPE_SELL) ? (ask <= trigger) : false;

      if(hit)
      {
         double pct = MathAbs(trigger - entry) / MathAbs(entry - sl);
         if(trade.PositionModify(ticket, entry, tp))
            PrintFormat("[BE_Mid] Ticket #%I64u — price at 65%% to TP (%.5f, %.1fR) → SL moved to entry %.5f",
                        ticket, trigger, pct, entry);
         else
            PrintFormat("[BE_Mid] FAILED to modify ticket #%I64u — error %d",
                        ticket, GetLastError());
      }
   }
}

// CheckBreakEvenOvernight (v1.31)
// If any open trade was opened on a PREVIOUS trading day:
//   in profit → move SL to entry price (break even)
//   at a loss → close the trade immediately

void CheckBreakEvenOvernight()
{
   datetime todayMidnight = TodayMidnight();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))           continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      datetime openTime  = (datetime)PositionGetInteger(POSITION_TIME);
      double   entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double   currentSL  = PositionGetDouble(POSITION_SL);
      double   currentTP  = PositionGetDouble(POSITION_TP);
      long     posType    = PositionGetInteger(POSITION_TYPE);

      // Only act if trade was opened BEFORE today
      if(openTime >= todayMidnight) continue;

      // Check if already at break even (avoid unnecessary modify)
      if(MathAbs(currentSL - entryPrice) < g_PipSize) continue;

      // Check if trade is in profit
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      bool inProfit = (posType == POSITION_TYPE_BUY)  ? (bid > entryPrice) :
                      (posType == POSITION_TYPE_SELL) ? (ask < entryPrice) : false;

      if(!inProfit)
      {
         PrintFormat("[BreakEven] Ticket #%I64u opened %s — in LOSS, closing trade",
                     ticket, TimeToString(openTime, TIME_DATE));
         if(!trade.PositionClose(ticket))
            PrintFormat("[BreakEven] FAILED to close ticket #%I64u — error %d",
                        ticket, GetLastError());
         continue;
      }

      // Move SL to entry
      if(trade.PositionModify(ticket, entryPrice, currentTP))
         PrintFormat("[BreakEven] Ticket #%I64u opened %s — in profit, SL moved to entry %.5f",
                     ticket, TimeToString(openTime, TIME_DATE), entryPrice);
      else
         PrintFormat("[BreakEven] FAILED to modify ticket #%I64u — error %d",
                     ticket, GetLastError());
   }
}

// CheckScaleIn (v1.63)
// After the initial position is opened, if the intended lot size was capped by
// broker margin, this function adds more lots whenever profit frees up enough
// margin — until the total position equals the originally intended lot size.
// All add-ons share the same SL and TP as the first open position.
void CheckScaleIn()
{
   if(!InpScaleIn)      return;
   if(g_TargetLots <= 0) return;

   // Gather info from open positions
   double totalLots = 0;
   long   direction = -999;
   double firstSL   = 0;
   double firstTP   = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))                          continue;
      if(PositionGetString (POSITION_SYMBOL) != _Symbol)          continue;
      if(PositionGetInteger(POSITION_MAGIC)  != InpMagicNumber)   continue;

      totalLots += PositionGetDouble(POSITION_VOLUME);
      if(direction == -999)
      {
         direction = PositionGetInteger(POSITION_TYPE);
         firstSL   = PositionGetDouble(POSITION_SL);
         firstTP   = PositionGetDouble(POSITION_TP);
      }
   }

   if(totalLots <= 0 || direction == -999) return;  // no open position
   if(totalLots >= g_TargetLots - 0.05)   return;   // already at or near target

   double effectiveStep = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), 0.1);
   double minLot        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   // How many more lots are still needed
   double neededLots = NormalizeDouble(
      MathRound((g_TargetLots - totalLots) / effectiveStep) * effectiveStep, 1);
   if(neededLots < minLot) return;

   // Check how many lots current free margin can afford (v1.64: use OrderCalcMargin)
   double marginPerLot = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginPerLot))
      marginPerLot = 0;
   if(marginPerLot <= 0)
      marginPerLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   if(marginPerLot <= 0)
   {
      double price        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contractSize <= 0) contractSize = 1;
      double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(leverage <= 0) leverage = 100;
      marginPerLot = (price * contractSize) / leverage;
   }
   if(marginPerLot <= 0) return;

   double freeMargin    = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double maxAffordable = NormalizeDouble(
      MathFloor((freeMargin * 0.9) / marginPerLot / effectiveStep) * effectiveStep, 1);
   if(maxAffordable < minLot) return;  // not enough margin yet

   double addLots = NormalizeDouble(
      MathRound(MathMin(neededLots, maxAffordable) / effectiveStep) * effectiveStep, 1);
   if(addLots < minLot) return;

   PrintFormat("[ScaleIn] Open=%.1f Target=%.1f Adding=%.1f (freeMargin=%.2f marginPerLot=%.2f)",
               totalLots, g_TargetLots, addLots, freeMargin, marginPerLot);

   bool ok = false;
   if(direction == POSITION_TYPE_BUY)
      ok = trade.Buy (addLots, _Symbol, 0, firstSL, firstTP, "ScaleIn");
   else if(direction == POSITION_TYPE_SELL)
      ok = trade.Sell(addLots, _Symbol, 0, firstSL, firstTP, "ScaleIn");

   if(ok)
      PrintFormat("[ScaleIn] Added %.1f lots — total now ~%.1f / %.1f target",
                  addLots, totalLots + addLots, g_TargetLots);
   else
      PrintFormat("[ScaleIn] FAILED to add %.1f lots — error %d", addLots, GetLastError());
}

//============================================================
//  MAIN TICK
//============================================================

void OnTick()
{
   CheckBreakEvenOvernight();
   CheckBreakEvenMidpoint();
   CheckScaleIn();
   CheckBalanceAlerts();

   if(!g_PendingsCancelledToday && CurrentHour() >= InpPendingCancelHour)
      CancelPendingOrders();

   datetime curBar = iTime(_Symbol, PERIOD_H1, 0);
   if(curBar == g_LastBar) return;
   g_LastBar = curBar;

   ResetDailyCount();
   CheckAsianSellSLReentry();

   if(!InpAllowMonday && IsMonday())      return;
   if(g_DailyCount >= InpMaxDailyTrades)  return;
   if(!IsInTradingWindow())               return;
   // News filter removed — handle news days manually

   AnalyseAsianSession();

   // v1.61: BothBroken block removed — first break direction is the signal regardless of second break

   if(g_AsianSellSLHit && !g_AsianSellReentered)
   {
      TryAsianSellReentryBuy();
      return;
   }

   if(!ScanBuySetups())
      ScanSellSetups();
}

// BothAsianLevelsBroken — v1.42
// Returns true if BOTH Asian High AND Low have been broken on separate bars today
// If true → no trade should be fired for the rest of the day
bool BothAsianLevelsBroken()
{
   if(g_AsianHigh <= 0 || g_AsianLow <= 0) return false;

   bool highBroken = false;
   bool lowBroken  = false;
   datetime todayMid = TodayMidnight();
   int totalBars = iBars(_Symbol, PERIOD_H1);

   for(int i = 1; i < totalBars; i++)
   {
      datetime barTime = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTime, bDt);
      datetime barDay = barTime - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;
      if(bDt.hour < 1) continue;

      if(iHigh(_Symbol, PERIOD_H1, i) > g_AsianHigh) highBroken = true;
      if(iLow (_Symbol, PERIOD_H1, i) < g_AsianLow)  lowBroken  = true;

      if(highBroken && lowBroken) return true;
   }
   return false;
}

//============================================================
//  TIME HELPERS — Eastern Time with automatic US DST
//============================================================

int DayOfWeekFor(int year, int mon, int day)
{
   static int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
   if(mon < 3) year--;
   return (year + year/4 - year/100 + year/400 + t[mon-1] + day) % 7;
}

int EasternOffset()
{
   MqlDateTime u;
   TimeToStruct(TimeGMT(), u);

   int dowMar1   = DayOfWeekFor(u.year, 3, 1);
   int marchSun2 = 1 + (7 - dowMar1) % 7 + 7;

   int dowNov1   = DayOfWeekFor(u.year, 11, 1);
   int novSun1   = 1 + (7 - dowNov1) % 7;

   bool pastStart = (u.mon >  3) ||
                    (u.mon == 3 && u.day >  marchSun2) ||
                    (u.mon == 3 && u.day == marchSun2 && u.hour >= 7);
   bool beforeEnd = (u.mon <  11) ||
                    (u.mon == 11 && u.day <  novSun1) ||
                    (u.mon == 11 && u.day == novSun1 && u.hour < 6);

   return (pastStart && beforeEnd) ? -4 : -5;
}

datetime NowNY()    { return TimeGMT() + EasternOffset() * 3600; }

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

// Trading window: London KZ start through end of NY KZ (02:00–10:00 ET)
bool IsInTradingWindow()
{
   int h = CurrentHour();
   return (h >= InpLondonStartNY && h < InpTradingEndNY);
}

datetime TodayMidnight()
{
   MqlDateTime dt;
   TimeToStruct(NowNY(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

datetime BarTimeNY(int barIndex)
{
   int serverOffsetSecs = (int)((datetime)TimeCurrent() - (datetime)TimeGMT());
   return iTime(_Symbol, PERIOD_H1, barIndex) - serverOffsetSecs + EasternOffset() * 3600;
}

void ResetDailyCount()
{
   datetime today = TodayMidnight();
   if(today != g_LastDay)
   {
      g_DailyCount              = 0;
      g_LastDay                 = today;
      g_FVGBuyDone              = false;
      g_StraightBuyDone         = false;
      g_FVGSellDone             = false;
      g_StraightSellDone        = false;
      g_AsianSellSLHit          = false;
      g_AsianSellReentered      = false;
      g_PendingsCancelledToday  = false;
      g_TargetLots              = 0;
      g_FaultyLowSweep          = false;
      g_FaultyHighSweep         = false;
   }
}

double PipsToPrice(double pips) { return pips * g_PipSize; }
double PriceToPips(double dist) { return (g_PipSize > 0) ? dist / g_PipSize : 0; }

double CalcLotSize(double slPips)
{
   if(slPips <= 0) return 0;
   double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
   // Trading plan: risk = balance / 6
   double riskAmount   = balance / 6.0;
   // v1.24: correct formula accounts for pip size AND contract size
   // P&L per lot = contract_size × sl_price_distance
   // sl_price_distance = slPips × g_PipSize
   // Therefore: lots = risk / (slPips × g_PipSize × contractSize)
   // AvaTrade US_30: contractSize=10, g_PipSize=1.0 → lots = risk / (slPips × 10)
   // BlackBull US30: contractSize=1,  g_PipSize=0.1 → lots = risk / (slPips × 0.1 × 1) = risk / (sl_price_dist)
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize <= 0) contractSize = 1;
   double pipSz = (g_PipSize > 0) ? g_PipSize : 1.0;
   double lots    = riskAmount / (slPips * pipSz * contractSize);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   // BlackBull only accepts 0.1 lot increments — enforce minimum step of 0.1
   double effectiveStep = MathMax(step, 0.1);
   lots = NormalizeDouble(MathRound(lots / effectiveStep) * effectiveStep, 1);
   lots = MathMax(minLot, MathMin(maxLot, lots));

   // v1.63: save intended lot size before margin cap for scale-in
   g_TargetLots = lots;

   // v1.64: use OrderCalcMargin() — asks MT5 for the real margin it will charge per lot.
   // SYMBOL_MARGIN_INITIAL returns 0 on BlackBull demo accounts, causing the price/leverage
   // fallback to underestimate by 5x (uses stated 1:500 vs real 1:100 effective leverage).
   // OrderCalcMargin() bypasses all of that and gives the true broker charge.
   double marginPerLot = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginPerLot))
      marginPerLot = 0;
   if(marginPerLot <= 0)
      marginPerLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
   if(marginPerLot <= 0)
   {
      double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
      if(leverage <= 0) leverage = 100;
      marginPerLot = (price * contractSize) / leverage;
   }
   if(marginPerLot > 0)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double maxAffordable = NormalizeDouble(MathFloor((freeMargin * 0.9) / marginPerLot / effectiveStep) * effectiveStep, 1);
      maxAffordable = MathMax(minLot, maxAffordable);
      if(lots > maxAffordable)
      {
         PrintFormat("CalcLotSize: margin cap applied — reduced from %.1f to %.1f (marginPerLot=%.2f freeMargin=%.2f)",
                     lots, maxAffordable, marginPerLot, freeMargin);
         lots = maxAffordable;
      }
   }

   PrintFormat("CalcLotSize: balance=%.2f risk=%.2f contractSize=%.0f pipSize=%.2f SL=%.1f pips → lots=%.1f",
               balance, riskAmount, contractSize, pipSz, slPips, lots);
   return lots;
}

//============================================================
//  ASIAN SESSION ANALYSIS
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

         int sAsianLast = (InpAsianEndNY - 1 + 24) % 24;
         if(bDt.hour == sAsianLast) g_AsianLastBar = i;
      }
   }

   if(!foundAny)
   { g_AsianLow = 0; g_AllAsianBullish = false; g_AllAsianBearish = false; }
   else if(g_AsianLow == DBL_MAX)
      g_AsianLow = 0;

   if(g_AsianLastBar > 0)
   {
      int fvgType = DetectFVG(g_AsianLastBar);
      g_AsianFVGBullish = (fvgType ==  1);
      g_AsianFVGBearish = (fvgType == -1);
   }

   g_AsianDate = today;

   PrintFormat("Asian session | High:%.5f Low:%.5f FVG:%s AllBull:%s AllBear:%s",
               g_AsianHigh, g_AsianLow,
               g_AsianFVGBullish ? "BULLISH" : g_AsianFVGBearish ? "BEARISH" : "NONE",
               g_AllAsianBullish ? "YES" : "NO",
               g_AllAsianBearish ? "YES" : "NO");
}

//============================================================
//  FVG DETECTION
//============================================================

int DetectFVG(int startBar)
{
   if(startBar < 0 || startBar + 1 >= iBars(_Symbol, PERIOD_H1)) return 0;

   double c1High  = iHigh (_Symbol, PERIOD_H1, startBar + 1);
   double c1Low   = iLow  (_Symbol, PERIOD_H1, startBar + 1);
   double c2Open  = iOpen (_Symbol, PERIOD_H1, startBar);
   double c2Close = iClose(_Symbol, PERIOD_H1, startBar);

   double c2BodyTop    = MathMax(c2Open, c2Close);
   double c2BodyBottom = MathMin(c2Open, c2Close);

   if(c2BodyBottom > c1High) return  1;
   if(c2BodyTop    < c1Low)  return -1;
   return 0;
}

bool GetFVGZone(int startBar, double &zoneHigh, double &zoneLow)
{
   int type = DetectFVG(startBar);
   if(type == 0) return false;

   double c1High  = iHigh (_Symbol, PERIOD_H1, startBar + 1);
   double c1Low   = iLow  (_Symbol, PERIOD_H1, startBar + 1);
   double c2Open  = iOpen (_Symbol, PERIOD_H1, startBar);
   double c2Close = iClose(_Symbol, PERIOD_H1, startBar);

   double c2BodyTop    = MathMax(c2Open, c2Close);
   double c2BodyBottom = MathMin(c2Open, c2Close);

   if(type == 1)  { zoneLow  = c1High;    zoneHigh = c2BodyBottom; }
   else           { zoneHigh = c1Low;     zoneLow  = c2BodyTop;    }

   return (zoneHigh > zoneLow);
}

//============================================================
//  MARKET STRUCTURE — SWING HIGH / LOW
//
//  v1.08: Uses true 3-bar swing pattern on H1.
//  The Asian High/Low requirement has been REMOVED — TP is now
//  simply the nearest H1 swing high (for buys) or swing low
//  (for sells) within the lookback window, exactly as traded
//  manually in the backtest journal.
//
//  Swing High: bar[i].high > bar[i+1].high AND bar[i].high > bar[i-1].high
//  Swing Low:  bar[i].low  < bar[i+1].low  AND bar[i].low  < bar[i-1].low
//============================================================

// GetSTHigh — TP for buy setups.
// Scans backwards (most-recent first) through bars BEFORE today's Asian session start.
// Returns the nearest bull→bear body transition whose open is above the Asian High.
// No fallback — if none qualifies, returns 0 and TryStraightBuy uses 3R fallback.
double GetSTHigh(int lookback = 20)
{
   int lim = iBars(_Symbol, PERIOD_H1) - 2;
   datetime asianStart = TodayMidnight() - (24 - InpAsianStartNY) * 3600;

   for(int i = 1; i <= lim; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      if(barTimeET >= asianStart) continue; // skip today's Asian and post-Asian bars

      if(IsBearishCandle(i) && IsBullishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(g_AsianHigh > 0 && level > g_AsianHigh)
         {
            PrintFormat("[GetSTHigh] Bull→Bear above Asian High at bar[%d] (pre-Asian): %.5f", i, level);
            return level;
         }
      }
   }

   PrintFormat("[GetSTHigh] No valid STH found before Asian session");
   return 0;
}

// GetSTLow — TP for sell setups.
// Scans backwards (most-recent first) through bars BEFORE today's Asian session start.
// Returns the nearest bear→bull body transition whose open is below the Asian Low.
// No fallback — if none qualifies, returns 0 and TryStraightSell uses 3R fallback.
double GetSTLow(int lookback = 20)
{
   int lim = iBars(_Symbol, PERIOD_H1) - 2;
   datetime asianStart = TodayMidnight() - (24 - InpAsianStartNY) * 3600;

   for(int i = 1; i <= lim; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      if(barTimeET >= asianStart) continue; // skip today's Asian and post-Asian bars

      if(IsBullishCandle(i) && IsBearishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(g_AsianLow > 0 && level < g_AsianLow)
         {
            PrintFormat("[GetSTLow] Bear→Bull below Asian Low at bar[%d] (pre-Asian): %.5f", i, level);
            return level;
         }
      }
   }

   PrintFormat("[GetSTLow] No valid STL found before Asian session");
   return 0;
}

// GetSTLowForSL — nearest bearish→bullish body transition below current price (SL for buys)
double GetSTLowForSL(double currentPrice, int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      if(IsBullishCandle(i) && IsBearishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(level < currentPrice)
            return level;
      }
   }
   // Fallback: lowest low below current price
   double l = DBL_MAX;
   for(int i = 1; i <= lim; i++)
   {
      double barLow = iLow(_Symbol, PERIOD_H1, i);
      if(barLow < currentPrice && barLow < l) l = barLow;
   }
   return (l == DBL_MAX) ? 0 : l;
}

// GetSTHighForSL — nearest bullish→bearish body transition above current price (SL for sells)
double GetSTHighForSL(double currentPrice, int lookback = 20)
{
   int lim = MathMin(lookback, iBars(_Symbol, PERIOD_H1) - 2);

   for(int i = 1; i <= lim; i++)
   {
      if(IsBearishCandle(i) && IsBullishCandle(i + 1))
      {
         double level = iOpen(_Symbol, PERIOD_H1, i);
         if(level > currentPrice)
            return level;
      }
   }
   // Fallback: highest high above current price
   double h = 0;
   for(int i = 1; i <= lim; i++)
   {
      double barHigh = iHigh(_Symbol, PERIOD_H1, i);
      if(barHigh > currentPrice && barHigh > h) h = barHigh;
   }
   return h;
}

bool IsBullishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) > iOpen(_Symbol, PERIOD_H1, bar); }
bool IsBearishCandle(int bar) { return iClose(_Symbol, PERIOD_H1, bar) < iOpen(_Symbol, PERIOD_H1, bar); }

// MostlyBearish: checks prior n bars for bearish bias (for buy setups)
// At least 2 of the prior 3 bars bearish = bearish structure before the buy
bool MostlyBearishPrior()
{
   int bearCount = 0;
   for(int i = 2; i <= 4; i++)
      if(IsBearishCandle(i)) bearCount++;
   return bearCount >= 2;
}

// MostlyBullish: checks prior n bars for bullish bias (for sell setups)
// At least 2 of the prior 3 bars bullish = bullish structure before the sell
bool MostlyBullishPrior()
{
   int bullCount = 0;
   for(int i = 2; i <= 4; i++)
      if(IsBullishCandle(i)) bullCount++;
   return bullCount >= 2;
}

// IsHighImpactNewsWindow — v1.39 rework
//
// Rule: If CPI/PPI/NFP is scheduled today (ET):
//   - Block ALL entries from midnight (00:00 ET) until the release time
//   - Allow entries again InpNewsMinsAfter minutes after the release
//   - CRITICAL: bar[1] close time must also be AFTER the blockEnd window
//   - On news days: if BOTH Asian High AND Low broken → block all day
// ALL days: if both Asian High AND Low broken on separate bars → no trade
bool IsHighImpactNewsWindow()
{
   if(!InpNewsFilter) return false;

   // Get today's date range — use a wide ±36h window to avoid timezone mismatch
   datetime nowServer    = TimeCurrent();
   int      serverOffset = (int)((datetime)TimeCurrent() - (datetime)TimeGMT());
   datetime dayStart     = nowServer - 36 * 3600;
   datetime dayEnd       = nowServer + 36 * 3600;

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, dayStart, dayEnd, "USD");
   PrintFormat("[NEWS] CalendarValueHistory: %d USD events in window", count);

   // Current time in Eastern Time
   datetime nowET = NowNY();

   // Bar[1] close time in Eastern Time
   datetime bar1CloseET = BarTimeNY(1) + 3600; // bar[1] open + 1hr = close time

   // Midnight ET today (00:00 ET)
   MqlDateTime nowETdt;
   TimeToStruct(nowET, nowETdt);
   MqlDateTime midnightETdt = nowETdt;
   midnightETdt.hour = 0; midnightETdt.min = 0; midnightETdt.sec = 0;
   datetime midnightET = StructToTime(midnightETdt);

   bool newsFoundToday = false;

   if(count > 0)
   {
      for(int i = 0; i < count; i++)
      {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev)) continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH)  continue;

         string name = ev.name;
         if(StringFind(name, "CPI")             < 0 &&
            StringFind(name, "Consumer Price")  < 0 &&
            StringFind(name, "PPI")             < 0 &&
            StringFind(name, "Producer Price")  < 0 &&
            StringFind(name, "Nonfarm")         < 0) continue;

         newsFoundToday = true;

         // Convert event server time → GMT → Eastern Time
         datetime evTimeGMT = values[i].time - serverOffset;
         datetime evTimeET  = evTimeGMT + EasternOffset() * 3600;
         // Block lifts at the START of the next full hour candle after the release
         // e.g. CPI at 08:30 ET → block ends at 09:00 ET (next H1 candle open)
         datetime blockEnd  = (datetime)((evTimeET / 3600 + 1) * 3600);

         // Only act on events scheduled for today (ET date) — skip yesterday/tomorrow
         datetime tomorrowET = midnightET + 86400;
         if(evTimeET < midnightET || evTimeET >= tomorrowET) continue;

         PrintFormat("[NEWS] Found today: %s at %s ET (importance=HIGH)", name, TimeToString(evTimeET, TIME_MINUTES));

         // Block from midnight ET until news release
         if(nowET >= midnightET && nowET < evTimeET)
         {
            PrintFormat("[NEWS FILTER] Blocked — %s at %s ET. No entries until %s ET",
                        name, TimeToString(evTimeET, TIME_MINUTES),
                        TimeToString(blockEnd, TIME_MINUTES));
            return true;
         }

         // Block for InpNewsMinsAfter minutes after release
         if(nowET >= evTimeET && nowET < blockEnd)
         {
            PrintFormat("[NEWS FILTER] Blocked — %s released at %s ET. Entries allowed at %s ET",
                        name, TimeToString(evTimeET, TIME_MINUTES),
                        TimeToString(blockEnd, TIME_MINUTES));
            return true;
         }
      }
   }

   // v1.42: Both levels broken check moved to OnTick (applies ALL days, not just news)

   return false;
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

// v1.75: Scan today's 02:00–09:00 ET bars for a faulty bullish FVG
// (3-candle bullish FVG where middle candle low < previous candle low = liquidity sweep)
bool CheckFaultyBullishFVG()
{
   int totalBars = iBars(_Symbol, PERIOD_H1);
   datetime todayMid = TodayMidnight();
   for(int i = 1; i < totalBars; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTimeET, bDt);
      datetime barDay = barTimeET - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;
      if(bDt.hour < 2 || bDt.hour > 9) continue;
      double c3Low  = iLow (_Symbol, PERIOD_H1, i);
      double c1High = iHigh(_Symbol, PERIOD_H1, i + 2);
      if(c3Low > c1High)
      {
         bool faulty = (iLow(_Symbol, PERIOD_H1, i + 1) < iLow(_Symbol, PERIOD_H1, i + 2));
         PrintFormat("[FaultyCheck] Bullish FVG at bar[%d] %02d:00 ET — faulty=%s (mid low %.2f vs prev low %.2f)",
                     i, bDt.hour, faulty?"YES":"NO",
                     iLow(_Symbol, PERIOD_H1, i+1), iLow(_Symbol, PERIOD_H1, i+2));
         return faulty;
      }
   }
   return false;
}

// v1.75: Scan today's 02:00–09:00 ET bars for a faulty bearish FVG
// (3-candle bearish FVG where middle candle high > previous candle high = liquidity sweep)
bool CheckFaultyBearishFVG()
{
   int totalBars = iBars(_Symbol, PERIOD_H1);
   datetime todayMid = TodayMidnight();
   for(int i = 1; i < totalBars; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTimeET, bDt);
      datetime barDay = barTimeET - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;
      if(bDt.hour < 2 || bDt.hour > 9) continue;
      double c3High = iHigh(_Symbol, PERIOD_H1, i);
      double c1Low  = iLow (_Symbol, PERIOD_H1, i + 2);
      if(c3High < c1Low)
      {
         bool faulty = (iHigh(_Symbol, PERIOD_H1, i + 1) > iHigh(_Symbol, PERIOD_H1, i + 2));
         PrintFormat("[FaultyCheck] Bearish FVG at bar[%d] %02d:00 ET — faulty=%s (mid high %.2f vs prev high %.2f)",
                     i, bDt.hour, faulty?"YES":"NO",
                     iHigh(_Symbol, PERIOD_H1, i+1), iHigh(_Symbol, PERIOD_H1, i+2));
         return faulty;
      }
   }
   return false;
}

// Returns: 1 if Asian Low was broken first (buy setup), -1 if Asian High broken first (sell setup), 0 if neither
// v1.35: fixed — checks HIGH first on each bar, then LOW, scanning oldest→newest
// If a single bar breaks BOTH levels, the HIGH break takes priority (sell) since
// price must have gone up before coming down within the same candle
int AsianBreakDirection()
{
   if(g_AsianHigh <= 0 || g_AsianLow <= 0) return 0;

   datetime todayMid = TodayMidnight();

   // Collect bar indices from today starting at 01:00 ET onwards
   int indices[];
   int totalBars = iBars(_Symbol, PERIOD_H1);
   for(int i = 1; i < totalBars; i++)
   {
      datetime barTime = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTime, bDt);

      datetime barDay = barTime - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;  // gone into yesterday

      if(bDt.hour < 1) continue;   // skip bars before 01:00 ET

      ArrayResize(indices, ArraySize(indices) + 1);
      indices[ArraySize(indices) - 1] = i;
   }

   // Iterate oldest→newest — first break determines direction.
   // v1.73: continue scanning after first break to detect faulty-sweep overrides.
   bool firstIsLow   = false;
   bool firstIsHigh  = false;
   bool highAlsoRan  = false;  // High broken on a bar AFTER the first Low break
   bool lowAlsoRan   = false;  // Low broken on a bar AFTER the first High break

   for(int j = ArraySize(indices) - 1; j >= 0; j--)
   {
      int i = indices[j];
      double barLow  = iLow (_Symbol, PERIOD_H1, i);
      double barHigh = iHigh(_Symbol, PERIOD_H1, i);

      bool brokeHigh = (barHigh > g_AsianHigh);
      bool brokeLow  = (barLow  < g_AsianLow);

      MqlDateTime dbDt;
      TimeToStruct(BarTimeNY(i), dbDt);
      PrintFormat("[AsianBreak] Scanning bar[%d] %02d:00 ET — High=%.5f brokeHigh=%s | Low=%.5f brokeLow=%s",
                  i, dbDt.hour, barHigh, brokeHigh?"YES":"NO", barLow, brokeLow?"YES":"NO");

      if(brokeHigh && brokeLow)
      {
         PrintFormat("[AsianBreak] Bar[%d] %02d:00 ET broke BOTH levels on same bar — checking close for FVG direction", i, dbDt.hour);
         if(!firstIsLow && !firstIsHigh)
         {
            // v1.74: use close to determine real direction (sweep+FVG pattern)
            double barClose = iClose(_Symbol, PERIOD_H1, i);
            if(barClose > g_AsianHigh)
            {
               PrintFormat("[AsianBreak] Bar[%d] swept Low, closed above Asian High (%.2f) → SELL direction", i, dbDt.hour, barClose);
               firstIsHigh = true;
            }
            else if(barClose < g_AsianLow)
            {
               PrintFormat("[AsianBreak] Bar[%d] swept High, closed below Asian Low (%.2f) → BUY direction", i, dbDt.hour, barClose);
               firstIsLow = true;
            }
            else
            {
               PrintFormat("[AsianBreak] Bar[%d] close %.2f between levels — ambiguous → no trade", i, dbDt.hour, barClose);
               return 0;
            }
         }
         else
         {
            // Direction already established — track the opposite break for faulty-sweep detection
            if(firstIsLow)  { PrintFormat("[AsianBreak] Bar[%d] high also ran (after Low break)", i, dbDt.hour); highAlsoRan = true; }
            if(firstIsHigh) { PrintFormat("[AsianBreak] Bar[%d] low also ran (after High break)", i, dbDt.hour); lowAlsoRan  = true; }
         }
         continue;  // skip normal single-break tracking below
      }

      if(!firstIsLow && !firstIsHigh)
      {
         if(brokeLow)  { PrintFormat("[AsianBreak] Asian Low broken at bar[%d] %02d:00 ET → BUY",  i, dbDt.hour); firstIsLow  = true; }
         if(brokeHigh) { PrintFormat("[AsianBreak] Asian High broken at bar[%d] %02d:00 ET → SELL", i, dbDt.hour); firstIsHigh = true; }
      }
      else
      {
         if(firstIsLow  && brokeHigh) highAlsoRan = true;
         if(firstIsHigh && brokeLow)  lowAlsoRan  = true;
      }
   }

   // v1.75: Faulty-sweep overrides — detect faulty pattern here too, so it works even when
   // TryFVGBuy/TryFVGSell never ran (e.g. bot loaded after the London FVG window closed)
   if(firstIsLow && highAlsoRan)
   {
      if(!g_FaultyLowSweep) g_FaultyLowSweep = CheckFaultyBullishFVG();
      if(g_FaultyLowSweep)
      { Print("[AsianBreak] Faulty low sweep + Asian High broken → direction flipped to SELL"); return -1; }
   }
   if(firstIsHigh && lowAlsoRan)
   {
      if(!g_FaultyHighSweep) g_FaultyHighSweep = CheckFaultyBearishFVG();
      if(g_FaultyHighSweep)
      { Print("[AsianBreak] Faulty high sweep + Asian Low broken → direction flipped to BUY"); return  1; }
   }

   if(firstIsLow)  return  1;
   if(firstIsHigh) return -1;
   return 0;
}

// v1.40: Maximum lots per single order (BlackBull Markets limit)
#define MAX_LOTS_PER_ORDER 100.0

bool PlaceBuy(double entry, double sl, double tp, string label)
{
   double slPips = PriceToPips(entry - sl);
   double tpPips = PriceToPips(tp - entry);

   if(slPips <= 0 || tpPips <= 0)
   { PrintFormat("[%s] Invalid SL/TP (slPips=%.1f tpPips=%.1f)", label, slPips, tpPips); return false; }

   // v1.27: STH RRR must be >= 1.5 — TP stays at actual STH level (no 1:2 lock)
   double rawRRR = tpPips / slPips;
   if(rawRRR < 1.5)
   { PrintFormat("[%s] SKIP: STH RRR %.2f below 1.5 minimum", label, rawRRR); return false; }
   PrintFormat("[%s] STH RRR %.2f >= 1.5 — TP set to actual STH: %.5f", label, rawRRR, tp);

   double totalLots = CalcLotSize(slPips);
   if(totalLots <= 0) { PrintFormat("[%s] Lot calc returned 0", label); return false; }

   // v1.40: Split into multiple MAX_LOTS_PER_ORDER orders if needed
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool   anyOk  = false;
   double remaining = totalLots;
   int    orderNum  = 1;

   while(remaining >= minLot)
   {
      double lots = MathMin(remaining, MAX_LOTS_PER_ORDER);
      lots = MathRound(lots / step) * step;
      if(lots < minLot) break;

      bool ok = false;
      if(InpExecMode == EXEC_MARKET)
         ok = trade.Buy(lots, _Symbol, 0, sl, tp, label);
      else if(InpExecMode == EXEC_LIMIT)
      {
         if(entry < ask) ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
         else            ok = trade.BuyStop (lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
      }
      else
      {
         if(MathAbs(entry - ask) <= PipsToPrice(2.0))
            ok = trade.Buy(lots, _Symbol, 0, sl, tp, label);
         else if(entry < ask)
            ok = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
         else
            ok = trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
      }

      if(ok)
      {
         anyOk = true;
         string msg = StringFormat("BUY [%s] Order %d/%d Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f RRR:1:%.2f",
                                   label, orderNum, (int)MathCeil(totalLots/MAX_LOTS_PER_ORDER),
                                   entry, sl, tp, lots, tpPips/slPips);
         Print(msg);
         if(orderNum == 1)
         {
            if(InpPopupAlerts) Alert(msg);
            if(InpPushAlerts)  SendNotification(msg);
         }
      }
      else
         PrintFormat("BUY FAILED [%s] Order %d Code:%d %s", label, orderNum, trade.ResultRetcode(), trade.ResultComment());

      remaining -= lots;
      orderNum++;
   }

   if(anyOk) g_DailyCount++;
   return anyOk;
}

bool PlaceSell(double entry, double sl, double tp, string label)
{
   double slPips = PriceToPips(sl - entry);
   double tpPips = PriceToPips(entry - tp);

   if(slPips <= 0 || tpPips <= 0)
   { PrintFormat("[%s] Invalid SL/TP (slPips=%.1f tpPips=%.1f)", label, slPips, tpPips); return false; }

   // v1.27: STL RRR must be >= 1.5 — TP stays at actual STL level (no 1:2 lock)
   double rawRRR = tpPips / slPips;
   if(rawRRR < 1.5)
   { PrintFormat("[%s] SKIP: STL RRR %.2f below 1.5 minimum", label, rawRRR); return false; }
   PrintFormat("[%s] STL RRR %.2f >= 1.5 — TP set to actual STL: %.5f", label, rawRRR, tp);

   double totalLots = CalcLotSize(slPips);
   if(totalLots <= 0) { PrintFormat("[%s] Lot calc returned 0", label); return false; }

   // v1.40: Split into multiple MAX_LOTS_PER_ORDER orders if needed
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool   anyOk  = false;
   double remaining = totalLots;
   int    orderNum  = 1;

   while(remaining >= minLot)
   {
      double lots = MathMin(remaining, MAX_LOTS_PER_ORDER);
      lots = MathRound(lots / step) * step;
      if(lots < minLot) break;

      bool ok = false;
      if(InpExecMode == EXEC_MARKET)
         ok = trade.Sell(lots, _Symbol, 0, sl, tp, label);
      else if(InpExecMode == EXEC_LIMIT)
      {
         if(entry > bid) ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
         else            ok = trade.SellStop (lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
      }
      else
      {
         if(MathAbs(entry - bid) <= PipsToPrice(2.0))
            ok = trade.Sell(lots, _Symbol, 0, sl, tp, label);
         else if(entry > bid)
            ok = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
         else
            ok = trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_DAY, 0, label);
      }

      if(ok)
      {
         anyOk = true;
         string msg = StringFormat("SELL [%s] Order %d/%d Entry:%.5f SL:%.5f TP:%.5f Lots:%.2f RRR:1:%.2f",
                                   label, orderNum, (int)MathCeil(totalLots/MAX_LOTS_PER_ORDER),
                                   entry, sl, tp, lots, tpPips/slPips);
         Print(msg);
         if(orderNum == 1)
         {
            if(InpPopupAlerts) Alert(msg);
            if(InpPushAlerts)  SendNotification(msg);
         }
      }
      else
         PrintFormat("SELL FAILED [%s] Order %d Code:%d %s", label, orderNum, trade.ResultRetcode(), trade.ResultComment());

      remaining -= lots;
      orderNum++;
   }

   if(anyOk) g_DailyCount++;
   return anyOk;
}

//============================================================
//  BUY SETUPS
//============================================================

bool ScanBuySetups()
{
   int  hr        = CurrentHour();
   bool triggered = false;

   // v1.65: FVG Buy — London KZ only (02:00–06:00). Backtest: 56% WR London vs 31% NY.
   if(!triggered && hr >= InpLondonStartNY && hr < InpNYKillZoneNY)
      triggered = TryFVGBuy();

   // Priority 3: Straight Buy — NY KZ only (05:00–10:00)
   if(!triggered && hr >= InpNYKillZoneNY && hr <= InpTradingEndNY)
      triggered = TryStraightBuy();

   return triggered;
}

// ============================================================
//  D1 REVERSAL HELPERS (v1.28)
// ============================================================

// HasD1BullishReversal — checks D1 bar[1] for a bullish reversal signal:
//   1. Pin bar / hammer: lower wick of bar[1] breaks below bar[2] low
//   2. Bullish engulfing: bar[1] is bullish AND body fully covers bar[2] body
bool HasD1BullishReversal()
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 3) return false;

   double d1_1_Low   = iLow  (_Symbol, PERIOD_D1, 1);
   double d1_2_Low   = iLow  (_Symbol, PERIOD_D1, 2);
   double d1_1_Open  = iOpen (_Symbol, PERIOD_D1, 1);
   double d1_1_Close = iClose(_Symbol, PERIOD_D1, 1);
   double d1_2_Open  = iOpen (_Symbol, PERIOD_D1, 2);
   double d1_2_Close = iClose(_Symbol, PERIOD_D1, 2);

   // Pin bar / hammer: lower wick breaks below previous candle's low
   bool isPinBar = (d1_1_Low < d1_2_Low);

   // Bullish engulfing: bar[1] bullish body fully covers bar[2] body
   double body1High = MathMax(d1_1_Open, d1_1_Close);
   double body1Low  = MathMin(d1_1_Open, d1_1_Close);
   double body2High = MathMax(d1_2_Open, d1_2_Close);
   double body2Low  = MathMin(d1_2_Open, d1_2_Close);
   bool isEngulfing = (d1_1_Close > d1_1_Open) &&   // bar[1] is bullish
                      (body1High  >= body2High)  &&   // covers top of bar[2]
                      (body1Low   <= body2Low);        // covers bottom of bar[2]

   if(isPinBar)   PrintFormat("[D1Filter] Bullish pin bar — bar[1] low %.5f < bar[2] low %.5f", d1_1_Low, d1_2_Low);
   if(isEngulfing) PrintFormat("[D1Filter] Bullish engulfing on D1 bar[1]");

   return (isPinBar || isEngulfing);
}

// HasD1BearishReversal — checks D1 bar[1] for a bearish reversal signal:
//   1. Pin bar / shooting star: upper wick of bar[1] breaks above bar[2] high
//   2. Bearish engulfing: bar[1] is bearish AND body fully covers bar[2] body
bool HasD1BearishReversal()
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 3) return false;

   double d1_1_High  = iHigh (_Symbol, PERIOD_D1, 1);
   double d1_2_High  = iHigh (_Symbol, PERIOD_D1, 2);
   double d1_1_Open  = iOpen (_Symbol, PERIOD_D1, 1);
   double d1_1_Close = iClose(_Symbol, PERIOD_D1, 1);
   double d1_2_Open  = iOpen (_Symbol, PERIOD_D1, 2);
   double d1_2_Close = iClose(_Symbol, PERIOD_D1, 2);

   // Pin bar / shooting star: upper wick breaks above previous candle's high
   bool isPinBar = (d1_1_High > d1_2_High);

   // Bearish engulfing: bar[1] bearish body fully covers bar[2] body
   double body1High = MathMax(d1_1_Open, d1_1_Close);
   double body1Low  = MathMin(d1_1_Open, d1_1_Close);
   double body2High = MathMax(d1_2_Open, d1_2_Close);
   double body2Low  = MathMin(d1_2_Open, d1_2_Close);
   bool isEngulfing = (d1_1_Close < d1_1_Open) &&   // bar[1] is bearish
                      (body1High  >= body2High)  &&   // covers top of bar[2]
                      (body1Low   <= body2Low);        // covers bottom of bar[2]

   if(isPinBar)    PrintFormat("[D1Filter] Bearish pin bar — bar[1] high %.5f > bar[2] high %.5f", d1_1_High, d1_2_High);
   if(isEngulfing) PrintFormat("[D1Filter] Bearish engulfing on D1 bar[1]");

   return (isPinBar || isEngulfing);
}

// GetD1ReversalTP — scans D1 bars from bar[2] backwards to find TP level
// For Buy:  finds first D1 bar whose HIGH is BELOW the reversal candle's LOW
// For Sell: finds first D1 bar whose LOW  is ABOVE the reversal candle's HIGH
// Scans indefinitely until a valid level is found
double GetD1ReversalTP(bool isBuy)
{
   int d1Bars = iBars(_Symbol, PERIOD_D1);
   if(d1Bars < 3) return 0;

   double reversalLow  = iLow (_Symbol, PERIOD_D1, 1);  // reversal candle low
   double reversalHigh = iHigh(_Symbol, PERIOD_D1, 1);  // reversal candle high

   for(int i = 2; i < d1Bars; i++)
   {
      if(isBuy)
      {
         double barHigh = iHigh(_Symbol, PERIOD_D1, i);
         if(barHigh < reversalLow)
         {
            PrintFormat("[D1ReversalTP] Buy TP = D1 bar[%d] high %.5f (below reversal low %.5f)", i, barHigh, reversalLow);
            return barHigh;
         }
      }
      else
      {
         double barLow = iLow(_Symbol, PERIOD_D1, i);
         if(barLow > reversalHigh)
         {
            PrintFormat("[D1ReversalTP] Sell TP = D1 bar[%d] low %.5f (above reversal high %.5f)", i, barLow, reversalHigh);
            return barLow;
         }
      }
   }

   PrintFormat("[D1ReversalTP] No valid TP level found — skipping");
   return 0;
}

// FVG Asian Buy (v1.28 rework)
// Trigger : bullish FVG on 00:00 Asian candle + D1 bar[1] bullish reversal
// Entry   : at 01:00 ET only (market order at open of that candle)
// SL      : Asian session Low minus buffer
// TP      : D1 reversal TP (first D1 bar[2+] whose high is below D1 bar[1] low)
bool TryFVGAsianBuy()
{
   // Only fire at 01:00 ET
   if(CurrentHour() != InpFVGAsianWindowStartNY)
   { Print("[FVG_Asian_Buy] SKIP: not 01:00 ET"); return false; }

   // Must have a bullish FVG on the last Asian candle (00:00 candle)
   if(g_AsianLastBar < 0) { Print("[FVG_Asian_Buy] SKIP: no Asian last bar"); return false; }
   if(!g_AsianFVGBullish) { Print("[FVG_Asian_Buy] SKIP: no bullish FVG on Asian last bar"); return false; }

   // D1 filter: yesterday's candle must show a bullish reversal
   if(!HasD1BullishReversal())
   { Print("[FVG_Asian_Buy] SKIP: no D1 bullish reversal on bar[1]"); return false; }

   // SL = Asian session Low minus buffer
   if(g_AsianLow <= 0) { Print("[FVG_Asian_Buy] SKIP: Asian Low not set"); return false; }
   double sl  = g_AsianLow - PipsToPrice(InpFVGBuffer);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(sl <= 0 || sl >= ask)
   { PrintFormat("[FVG_Asian_Buy] SKIP: invalid SL %.5f vs ask %.5f", sl, ask); return false; }

   // TP = D1 reversal level (first D1 bar whose high is below reversal candle low)
   double tp = GetD1ReversalTP(true);
   if(tp <= 0 || tp <= ask)
   { PrintFormat("[FVG_Asian_Buy] SKIP: no valid D1 TP found or TP %.5f <= ask %.5f", tp, ask); return false; }

   double rrr = (ask - sl > 0) ? (tp - ask) / (ask - sl) : 0;
   if(rrr < InpMinRRR)
   { PrintFormat("[FVG_Asian_Buy] SKIP: RRR %.2f < minimum %.1f", rrr, InpMinRRR); return false; }

   PrintFormat("[FVG_Asian_Buy] entry=%.5f sl=%.5f (Asian Low) tp=%.5f (D1 level) RRR=%.2f", ask, sl, tp, rrr);
   return PlaceBuy(ask, sl, tp, "FVG_Asian_Buy");
}

// FVG Buy (v1.46 rework)
// When FVG bar closes:
//   RR >= 1:2 → enter at market immediately
//   RR < 1:2  → wait for next candle; if price reaches 1:2 during next candle → market
//               if fill candle closes with RR <= 1:1.5 → place limit at exact 1:2 price
//               if limit price invalid (below SL) → skip
bool TryFVGBuy()
{
   if(g_DailyCount >= InpMaxDailyTrades) return false;
   if(g_StraightBuyDone || g_FVGBuyDone || g_FVGSellDone || g_StraightSellDone) return false;

   // v1.73: faulty low sweep active → skip all BUY setups, wait for High break → SELL
   if(g_FaultyLowSweep)
   { Print("[FVG_Buy] SKIP: faulty low sweep active — waiting for Asian High break → SELL"); return false; }

   if(AsianBreakDirection() != 1)
   { Print("[FVG_Buy] SKIP: Asian Low not broken first"); return false; }

   // Scan 02:00–09:00 ET for most recent bullish FVG
   int fvgBar    = -1;
   int totalBars = iBars(_Symbol, PERIOD_H1);
   datetime todayMid = TodayMidnight();

   for(int i = 1; i < totalBars; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTimeET, bDt);
      datetime barDay = barTimeET - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;
      if(bDt.hour < 2 || bDt.hour > 9) continue;

      double c3Low  = iLow (_Symbol, PERIOD_H1, i);      // bar[i]   = candle 3 (newest)
      double c1High = iHigh(_Symbol, PERIOD_H1, i + 2);  // bar[i+2] = candle 1 (oldest)

      if(c3Low > c1High)
      {
         fvgBar = i;
         PrintFormat("[FVG_Buy] 3-bar bullish FVG at bar[%d] %02d:00 ET — bar[%d] low %.2f > bar[%d] high %.2f (gap %.2f pts)",
                     i, bDt.hour, i, c3Low, i+2, c1High, c3Low - c1High);
         break;
      }
      else
      {
         PrintFormat("[FVG_Buy] bar[%d] %02d:00 ET: low=%.2f bar[%d]High=%.2f gap=%.2f — no FVG",
                     i, bDt.hour, c3Low, i+2, c1High, c3Low - c1High);
      }
   }

   if(fvgBar < 0)
   { Print("[FVG_Buy] SKIP: no bullish FVG in 02:00–09:00 ET"); return false; }

   // v1.73: Faulty bullish FVG — middle candle (bar[fvgBar+1]) swept below previous candle (bar[fvgBar+2])
   // This is a liquidity grab; skip BUY, set flag, wait for Asian High break → SELL
   if(iLow(_Symbol, PERIOD_H1, fvgBar + 1) < iLow(_Symbol, PERIOD_H1, fvgBar + 2))
   {
      g_FaultyLowSweep = true;
      PrintFormat("[FVG_Buy] SKIP: faulty FVG — bar[%d] low %.2f swept below bar[%d] low %.2f. Waiting for Asian High break → SELL",
                  fvgBar + 1, iLow(_Symbol, PERIOD_H1, fvgBar + 1),
                  fvgBar + 2, iLow(_Symbol, PERIOD_H1, fvgBar + 2));
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl  = iLow(_Symbol, PERIOD_H1, fvgBar + 1) - PipsToPrice(InpFVGBuffer);
   double tp  = GetSTHigh(InpSTH_Lookback);

   if(sl <= 0 || sl >= ask)
   { PrintFormat("[FVG_Buy] SKIP: invalid SL %.5f", sl); return false; }

   // TP already reached — price has already moved past the target
   if(tp > 0 && tp <= ask)
   { PrintFormat("[FVG_Buy] SKIP: TP (STHigh %.2f) already reached — ask %.2f", tp, ask); return false; }

   if(tp <= ask)
   {
      double tp3R      = ask + 3.0 * (ask - sl);
      double tpAsianHi = (g_AsianHigh > ask) ? g_AsianHigh : 0;
      tp = MathMax(tp3R, tpAsianHi);
      PrintFormat("[FVG_Buy] No STH — fallback TP: 3R=%.5f AsianHigh=%.5f → using %.5f", tp3R, tpAsianHi, tp);
   }

   // Check RR at current market price
   double rrr = (tp - ask) / (ask - sl);

   // RR >= 1:2 → enter at market immediately
   if(rrr >= 2.0)
   {
      PrintFormat("[FVG_Buy] RR %.2f >= 1:2 — market entry at %.5f", rrr, ask);
      bool ok = PlaceBuy(ask, sl, tp, "FVG_Buy");
      if(ok) g_FVGBuyDone = true;
      return ok;
   }

   // RR < 1.5 → setup quality too poor, skip
   if(rrr < 1.5)
   {
      PrintFormat("[FVG_Buy] SKIP: RR %.2f < 1.5 at current price — insufficient quality", rrr);
      return false;
   }

   // 1.5 <= RR < 1:2 → place BuyLimit at the price that gives exactly 1:2
   // entry12 = (tp + 2*sl) / 3  →  gives reward:risk = 2.0 exactly
   double entry12 = (tp + 2.0 * sl) / 3.0;

   if(entry12 <= sl || entry12 >= ask)
   { PrintFormat("[FVG_Buy] SKIP: 1:2 entry level %.5f invalid (sl=%.5f ask=%.5f)", entry12, sl, ask); return false; }

   PrintFormat("[FVG_Buy] RR %.2f — placing BuyLimit at 1:2 entry %.5f (sl=%.5f tp=%.5f)", rrr, entry12, sl, tp);
   bool ok = PlaceBuy(entry12, sl, tp, "FVG_Buy");
   if(ok) g_FVGBuyDone = true;
   return ok;
}

// Straight Buy (v1.32 rework)
// Trigger : Asian Low broken first (01:00 ET onwards)
//           + any candle 05:00–10:00 ET closes bullish
//           + no FVG Buy has fired yet since 01:00 ET
// Entry   : market order immediately when bullish candle closes
// SL      : lowest low of bar[1] and bar[2] minus buffer
// TP      : actual STH, fallback to higher of 3R or Asian High
bool TryStraightBuy()
{
   if(g_DailyCount >= InpMaxDailyTrades) return false;
   if(g_FVGBuyDone || g_StraightBuyDone || g_FVGSellDone || g_StraightSellDone) return false;

   // v1.73: faulty low sweep active → skip all BUY setups, wait for High break → SELL
   if(g_FaultyLowSweep)
   { Print("[Straight_Buy] SKIP: faulty low sweep active — waiting for Asian High break → SELL"); return false; }

   // Asian Low must be broken first
   if(AsianBreakDirection() != 1)
   { Print("[Straight_Buy] SKIP: Asian Low not broken first"); return false; }

   // Fire on candles closing 06:00–10:00 ET (bar[1] closes at 10:00 → entry at 10:00 open)
   int hourNY = CurrentHour();
   if(hourNY < 6 || hourNY > 10)
   { PrintFormat("[Straight_Buy] SKIP: outside 06:00–10:00 close window (now %d:00)", hourNY); return false; }

   // Bar[1] must close bullish (close > open)
   double bar1Open  = iOpen (_Symbol, PERIOD_H1, 1);
   double bar1Close = iClose(_Symbol, PERIOD_H1, 1);
   if(bar1Close <= bar1Open)
   { Print("[Straight_Buy] SKIP: bar[1] not bullish"); return false; }

   PrintFormat("[Straight_Buy] Trigger: bar[1] bullish close=%.5f open=%.5f at %d:00 ET", bar1Close, bar1Open, hourNY);

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // SL = lowest low of bar[1] and bar[2] minus buffer
   double low1 = iLow(_Symbol, PERIOD_H1, 1);
   double low2 = iLow(_Symbol, PERIOD_H1, 2);
   double sl   = MathMin(low1, low2) - PipsToPrice(InpFVGBuffer);
   double tp   = GetSTHigh(InpSTH_Lookback);

   if(sl <= 0 || sl >= entry)
   { PrintFormat("[Straight_Buy] SKIP: invalid SL %.5f vs entry %.5f", sl, entry); return false; }

   // TP = nearest post-Asian swing high — use directly if RR >= 1.5
   // Fallback to max(3R, Asian High) only when no valid STH found
   if(tp > entry)
   {
      double rawRRR = (tp - entry) / (entry - sl);
      if(rawRRR < 1.5)
      { PrintFormat("[Straight_Buy] SKIP: STH RRR %.2f below 1.5 minimum", rawRRR); return false; }
      PrintFormat("[Straight_Buy] STH RRR %.2f — TP set to swing high: %.5f", rawRRR, tp);
   }
   else
   {
      double tp3R      = entry + 3.0 * (entry - sl);
      double tpAsianHi = (g_AsianHigh > entry) ? g_AsianHigh : 0;
      tp = MathMax(tp3R, tpAsianHi);
      PrintFormat("[Straight_Buy] No STH — fallback TP: 3R=%.5f AsianHigh=%.5f → using %.5f", tp3R, tpAsianHi, tp);
   }

   PrintFormat("[Straight_Buy] entry=%.5f sl=%.5f tp=%.5f RRR=%.2f",
               entry, sl, tp, (entry - sl > 0) ? (tp - entry) / (entry - sl) : 0);

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
      if(HistoryDealGetString (ticket, DEAL_COMMENT) != "FVG_Asian_Sell") continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC)   != InpMagicNumber)   continue;
      if(HistoryDealGetString (ticket, DEAL_SYMBOL)  != _Symbol)          continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY)   != DEAL_ENTRY_OUT)   continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0)
      {
         g_AsianSellSLHit = true;
         string msg = "FVG_Asian_Sell SL hit — re-entry BUY on next bar.";
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
   // v1.17: SL at wick (low) of previous candle bar[1]
   double sl    = iLow(_Symbol, PERIOD_H1, 1) - PipsToPrice(InpFVGBuffer);
   double tp    = GetSTHigh(InpSTH_Lookback);

   if(sl <= 0 || sl >= entry || tp <= entry) return false;

   bool ok = PlaceBuy(entry, sl, tp, "Asian_Sell_Reentry_Buy");
   if(ok)
   {
      g_AsianSellReentered = true;
      string msg = "Re-entry BUY after FVG_Asian_Sell SL hit. Check TP at equal highs on D1.";
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

   // Priority 1: FVG Sell — London + NY KZ (02:00–10:00)
   if(!triggered && hr >= InpLondonStartNY && hr < InpTradingEndNY)
      triggered = TryFVGSell();

   // Priority 3: Straight Sell — NY KZ only (05:00–10:00)
   if(!triggered && hr >= InpNYKillZoneNY && hr <= InpTradingEndNY)
      triggered = TryStraightSell();

   return triggered;
}

// FVG Asian Sell (v1.28 rework)
// Trigger : bearish FVG on 00:00 Asian candle + D1 bar[1] bearish reversal
// Entry   : at 01:00 ET only (market order at open of that candle)
// SL      : Asian session High plus buffer
// TP      : D1 reversal TP (first D1 bar[2+] whose low is above D1 bar[1] high)
bool TryFVGAsianSell()
{
   // Only fire at 01:00 ET
   if(CurrentHour() != InpFVGAsianWindowStartNY)
   { Print("[FVG_Asian_Sell] SKIP: not 01:00 ET"); return false; }

   // Must have a bearish FVG on the last Asian candle (00:00 candle)
   if(g_AsianLastBar < 0) { Print("[FVG_Asian_Sell] SKIP: no Asian last bar"); return false; }
   if(!g_AsianFVGBearish) { Print("[FVG_Asian_Sell] SKIP: no bearish FVG on Asian last bar"); return false; }

   // D1 filter: yesterday's candle must show a bearish reversal
   if(!HasD1BearishReversal())
   { Print("[FVG_Asian_Sell] SKIP: no D1 bearish reversal on bar[1]"); return false; }

   // SL = Asian session High plus buffer
   if(g_AsianHigh <= 0) { Print("[FVG_Asian_Sell] SKIP: Asian High not set"); return false; }
   double sl  = g_AsianHigh + PipsToPrice(InpFVGBuffer);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(sl <= bid)
   { PrintFormat("[FVG_Asian_Sell] SKIP: invalid SL %.5f vs bid %.5f", sl, bid); return false; }

   // TP = D1 reversal level (first D1 bar whose low is above reversal candle high)
   double tp = GetD1ReversalTP(false);
   if(tp <= 0 || tp >= bid)
   { PrintFormat("[FVG_Asian_Sell] SKIP: no valid D1 TP found or TP %.5f >= bid %.5f", tp, bid); return false; }

   double rrr = (sl - bid > 0) ? (bid - tp) / (sl - bid) : 0;
   if(rrr < InpMinRRR)
   { PrintFormat("[FVG_Asian_Sell] SKIP: RRR %.2f < minimum %.1f", rrr, InpMinRRR); return false; }

   PrintFormat("[FVG_Asian_Sell] entry=%.5f sl=%.5f (Asian High) tp=%.5f (D1 level) RRR=%.2f", bid, sl, tp, rrr);
   return PlaceSell(bid, sl, tp, "FVG_Asian_Sell");
}

// FVG Sell (v1.46 rework)
// When FVG bar closes:
//   RR >= 1:2 → enter at market immediately
//   RR < 1:2  → wait for next candle; if price reaches 1:2 during next candle → market
//               if fill candle closes with RR <= 1:1.5 → place limit at exact 1:2 price
//               if limit price invalid (above SL) → skip
bool TryFVGSell()
{
   if(g_DailyCount >= InpMaxDailyTrades) return false;
   if(g_FVGSellDone || g_StraightSellDone || g_FVGBuyDone || g_StraightBuyDone) return false;

   // v1.73: faulty high sweep active → skip all SELL setups, wait for Low break → BUY
   if(g_FaultyHighSweep)
   { Print("[FVG_Sell] SKIP: faulty high sweep active — waiting for Asian Low break → BUY"); return false; }

   if(AsianBreakDirection() != -1)
   { Print("[FVG_Sell] SKIP: Asian High not broken first"); return false; }

   // Scan 02:00–09:00 ET for most recent bearish FVG
   int fvgBar    = -1;
   int totalBars = iBars(_Symbol, PERIOD_H1);
   datetime todayMid = TodayMidnight();

   for(int i = 1; i < totalBars; i++)
   {
      datetime barTimeET = BarTimeNY(i);
      MqlDateTime bDt;
      TimeToStruct(barTimeET, bDt);
      datetime barDay = barTimeET - bDt.hour * 3600 - bDt.min * 60 - bDt.sec;
      if(barDay < todayMid) break;
      if(bDt.hour < 2 || bDt.hour > 9) continue;

      double c3High = iHigh(_Symbol, PERIOD_H1, i);      // bar[i]   = candle 3 (newest)
      double c1Low  = iLow (_Symbol, PERIOD_H1, i + 2);  // bar[i+2] = candle 1 (oldest)

      if(c3High < c1Low)
      {
         fvgBar = i;
         PrintFormat("[FVG_Sell] 3-bar bearish FVG at bar[%d] %02d:00 ET — bar[%d] high %.2f < bar[%d] low %.2f (gap %.2f pts)",
                     i, bDt.hour, i, c3High, i+2, c1Low, c1Low - c3High);
         break;
      }
      else
      {
         PrintFormat("[FVG_Sell] bar[%d] %02d:00 ET: high=%.2f bar[%d]Low=%.2f gap=%.2f — no FVG",
                     i, bDt.hour, c3High, i+2, c1Low, c3High - c1Low);
      }
   }

   if(fvgBar < 0)
   { Print("[FVG_Sell] SKIP: no bearish FVG in 02:00–09:00 ET"); return false; }

   // v1.73: Faulty bearish FVG — middle candle (bar[fvgBar+1]) swept above previous candle (bar[fvgBar+2])
   // This is a liquidity grab; skip SELL, set flag, wait for Asian Low break → BUY
   if(iHigh(_Symbol, PERIOD_H1, fvgBar + 1) > iHigh(_Symbol, PERIOD_H1, fvgBar + 2))
   {
      g_FaultyHighSweep = true;
      PrintFormat("[FVG_Sell] SKIP: faulty FVG — bar[%d] high %.2f swept above bar[%d] high %.2f. Waiting for Asian Low break → BUY",
                  fvgBar + 1, iHigh(_Symbol, PERIOD_H1, fvgBar + 1),
                  fvgBar + 2, iHigh(_Symbol, PERIOD_H1, fvgBar + 2));
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = iHigh(_Symbol, PERIOD_H1, fvgBar + 1) + PipsToPrice(InpFVGBuffer);
   double tp  = GetSTLow(InpSTH_Lookback);

   if(sl <= bid)
   { PrintFormat("[FVG_Sell] SKIP: invalid SL %.5f", sl); return false; }

   // TP already reached — price has already moved past the target
   if(tp > 0 && tp >= bid)
   { PrintFormat("[FVG_Sell] SKIP: TP (STLow %.2f) already reached — bid %.2f", tp, bid); return false; }

   if(tp <= 0)
   {
      double tp3R      = bid - 3.0 * (sl - bid);
      double tpAsianLo = (g_AsianLow > 0 && g_AsianLow < bid) ? g_AsianLow : tp3R;
      tp = MathMin(tp3R, tpAsianLo);
      PrintFormat("[FVG_Sell] No STL — fallback TP: 3R=%.5f AsianLow=%.5f → using %.5f", tp3R, tpAsianLo, tp);
   }

   if(g_AllAsianBullish && g_AsianLow > 0 && g_AsianLow < bid)
   {
      tp = g_AsianLow;
      PrintFormat("[FVG_Sell] All-bull Asian — TP overridden to Asian Low: %.5f", tp);
   }

   // Check RR at current market price
   double rrr = (bid - tp) / (sl - bid);

   // RR >= 1:2 → enter at market immediately
   if(rrr >= 2.0)
   {
      PrintFormat("[FVG_Sell] RR %.2f >= 1:2 — market entry at %.5f", rrr, bid);
      bool ok = PlaceSell(bid, sl, tp, "FVG_Sell");
      if(ok) g_FVGSellDone = true;
      return ok;
   }

   // RR < 1.5 → setup quality too poor, skip
   if(rrr < 1.5)
   {
      PrintFormat("[FVG_Sell] SKIP: RR %.2f < 1.5 at current price — insufficient quality", rrr);
      return false;
   }

   // 1.5 <= RR < 1:2 → place SellLimit at the price that gives exactly 1:2
   // entry12 = (tp + 2*sl) / 3  →  gives reward:risk = 2.0 exactly
   double entry12 = (tp + 2.0 * sl) / 3.0;

   if(entry12 >= sl || entry12 <= tp)
   { PrintFormat("[FVG_Sell] SKIP: 1:2 entry level %.5f invalid (sl=%.5f tp=%.5f)", entry12, sl, tp); return false; }

   PrintFormat("[FVG_Sell] RR %.2f — placing SellLimit at 1:2 entry %.5f (sl=%.5f tp=%.5f)", rrr, entry12, sl, tp);
   bool ok = PlaceSell(entry12, sl, tp, "FVG_Sell");
   if(ok) g_FVGSellDone = true;
   return ok;
}

// Straight Sell (London + NY KZ — full window 02:00–10:00 ET)
//
// v1.08 CHANGES:
//   • Window: fires across full London+NY window, NOT locked to 6AM only
//   • Trigger: bar[1] closed bearish + prior 3 bars mostly bullish (pullback)
//   • SL: nearest H1 swing high above entry (+ buffer)
//   • TP: nearest H1 swing low below entry (no Asian Low requirement)
// Straight Sell (v1.32 rework)
// Trigger : Asian High broken first (01:00 ET onwards)
//           + any candle 05:00–09:00 ET closes bearish
//           + no FVG Sell has fired yet since 01:00 ET
// Entry   : market order immediately when bearish candle closes
// SL      : highest high of bar[1] and bar[2] plus buffer
// TP      : actual STL, fallback to lower of 3R or Asian Low
bool TryStraightSell()
{
   if(g_DailyCount >= InpMaxDailyTrades) return false;
   if(g_FVGSellDone || g_StraightSellDone || g_FVGBuyDone || g_StraightBuyDone) return false;

   // v1.73: faulty high sweep active → skip all SELL setups, wait for Low break → BUY
   if(g_FaultyHighSweep)
   { Print("[Straight_Sell] SKIP: faulty high sweep active — waiting for Asian Low break → BUY"); return false; }

   // Asian High must be broken first
   if(AsianBreakDirection() != -1)
   { Print("[Straight_Sell] SKIP: Asian High not broken first"); return false; }

   // Fire on candles closing 06:00–10:00 ET (bar[1] closes at 10:00 → entry at 10:00 open)
   int hourNY = CurrentHour();
   if(hourNY < 6 || hourNY > 10)
   { PrintFormat("[Straight_Sell] SKIP: outside 06:00–10:00 close window (now %d:00)", hourNY); return false; }

   // Bar[1] must close bearish (close < open)
   double bar1Open  = iOpen (_Symbol, PERIOD_H1, 1);
   double bar1Close = iClose(_Symbol, PERIOD_H1, 1);
   if(bar1Close >= bar1Open)
   { Print("[Straight_Sell] SKIP: bar[1] not bearish"); return false; }

   PrintFormat("[Straight_Sell] Trigger: bar[1] bearish close=%.5f open=%.5f at %d:00 ET", bar1Close, bar1Open, hourNY);

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // SL = highest high of bar[1] and bar[2] plus buffer
   double high1 = iHigh(_Symbol, PERIOD_H1, 1);
   double high2 = iHigh(_Symbol, PERIOD_H1, 2);
   double sl    = MathMax(high1, high2) + PipsToPrice(InpFVGBuffer);
   double tp    = GetSTLow(InpSTH_Lookback);

   if(sl <= entry)
   { PrintFormat("[Straight_Sell] SKIP: invalid SL %.5f vs entry %.5f", sl, entry); return false; }

   // TP = nearest post-Asian swing low — use directly if RR >= 1.5
   // Fallback to min(3R, Asian Low) only when no valid STL found
   if(tp > 0 && tp < entry)
   {
      double rawRRR = (entry - tp) / (sl - entry);
      if(rawRRR < 1.5)
      { PrintFormat("[Straight_Sell] SKIP: STL RRR %.2f below 1.5 minimum", rawRRR); return false; }
      PrintFormat("[Straight_Sell] STL RRR %.2f — TP set to swing low: %.5f", rawRRR, tp);
   }
   else
   {
      double tp3R      = entry - 3.0 * (sl - entry);
      double tpAsianLo = (g_AsianLow > 0 && g_AsianLow < entry) ? g_AsianLow : tp3R;
      tp = MathMin(tp3R, tpAsianLo);
      PrintFormat("[Straight_Sell] No STL — fallback TP: 3R=%.5f AsianLow=%.5f → using %.5f", tp3R, tpAsianLo, tp);
   }

   // If all Asian candles were bullish → TP overridden to Asian Low
   if(g_AllAsianBullish && g_AsianLow > 0 && g_AsianLow < entry)
   {
      tp = g_AsianLow;
      PrintFormat("[Straight_Sell] All-bull Asian session — TP overridden to Asian Low: %.5f", tp);
   }

   PrintFormat("[Straight_Sell] entry=%.5f sl=%.5f tp=%.5f RRR=%.2f",
               entry, sl, tp, (sl - entry > 0) ? (entry - tp) / (sl - entry) : 0);

   bool ok = PlaceSell(entry, sl, tp, "Straight_Sell");
   if(ok) g_StraightSellDone = true;
   return ok;
}

//+------------------------------------------------------------------+
//  END OF EA v1.08
//+------------------------------------------------------------------+
//
//  SUMMARY OF v1.08 CHANGES (matched to manual backtest journal):
//
//  1. GetSTHigh — true 3-bar H1 swing high pattern; Asian High filter REMOVED
//  2. GetSTLow  — true 3-bar H1 swing low  pattern; Asian Low  filter REMOVED
//  3. GetSTLowForSL  — new: finds nearest swing low below price (SL for buys)
//  4. GetSTHighForSL — new: finds nearest swing high above price (SL for sells)
//  5. TryFVGAsianBuy  — AutoBias() and IsDailyBullishReversal() REMOVED
//  6. TryFVGAsianSell — AutoBias() and IsDailyBearishReversal() REMOVED
//  7. TryFVGBuy  — HasDownsideViolation() REMOVED; fires on any bullish FVG
//  8. TryFVGSell — fires on any bearish FVG
//  9. TryStraightBuy  — window: 02:00–10:00 ET (was: 6AM only)
//                        trigger: bar[1] bullish + MostlyBearishPrior()
//  10. TryStraightSell — window: 02:00–10:00 ET (was: 6AM only)
//                         trigger: bar[1] bearish + MostlyBullishPrior()
//  11. All SL placement now uses GetSTLowForSL / GetSTHighForSL
//      (nearest H1 swing low/high) instead of Asian range levels
//
//+------------------------------------------------------------------+
