#property copyright "Aurum Steam Train - Bug Fixed"
#property link      ""
#property version   "7.31"
#property description "Professional Pattern Trading System - BUG FIXED"
#property description "XAU/USD Pattern Based | Trading Sessions"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CPositionInfo position;
CAccountInfo account;

// Indicator handles
int g_ATRHandle = INVALID_HANDLE;
ENUM_TIMEFRAMES g_ATRTimeframe = PERIOD_M15;
int g_ATRPeriod = 14;

int g_TrendEMAHandle = INVALID_HANDLE;
ENUM_TIMEFRAMES g_TrendTimeframe = PERIOD_H1;
int g_TrendPeriod = 200;

//+------------------------------------------------------------------+
//|                    ACCOUNT SETTINGS                               |
//+------------------------------------------------------------------+
input group "═══════ ACCOUNT TYPE ═══════"
input bool UseFTMO_Mode = false;               // Use FTMO Challenge Rules
input double FTMO_StartBalance = 10000;        // FTMO Starting Balance
input double FTMO_MaxDailyLoss = 500;          // FTMO Max Daily Loss
input double FTMO_MaxTotalLoss = 1000;         // FTMO Max Total Loss
input double FTMO_ProfitTarget = 1000;         // FTMO Profit Target
input bool StopAtProfitTarget = false;         // Stop Trading at Profit Target
input bool StopAtMaxDailyDrawdown = true;      // Stop Trading at Max Daily DD

input group "═══════ RISK MANAGEMENT ═══════"
input bool UseFixedLots = false;               // Use Fixed Lot Size
input double FixedLotSize = 0.1;               // Fixed Lot Size
input double RiskPercent = 1.0;                // Risk Per Trade (%)
input bool OneTradeAtATime = true;             // Only One Trade At A Time
input int MagicNumber = 777777;                // Magic Number

//+------------------------------------------------------------------+
//|              PATTERN LOT SIZES                                    |
//+------------------------------------------------------------------+
input group "═══════ PATTERN LOT SIZES ═══════"
input bool UsePatternLots = true;              // Use Individual Pattern Lots
input double LiquidityGrab_Lots = 0.1;         // Liquidity Grab Lots
input double VReversal_Lots = 0.1;             // V-Reversal Lots
input double RangeExpansion_Lots = 0.1;        // Range Expansion Lots

//+------------------------------------------------------------------+
//|              XAU/USD PATTERN SETTINGS                             |
//+------------------------------------------------------------------+
input group "═══════ PATTERN RECOGNITION ═══════"
input ENUM_TIMEFRAMES PT_Timeframe = PERIOD_M15;  // Pattern Timeframe
input double PT_RiskReward = 2.5;                 // Risk:Reward Ratio
input int PT_LookbackBars = 20;                   // Pattern Lookback Bars

// Gold-Specific Patterns
input bool PT_EnableLiquidityGrab = true;         // Liquidity Grab Pattern
input int PT_LiquidityLookback = 10;              // Liquidity Level Lookback

input bool PT_EnableV_Reversal = true;            // V-Shape Reversal
input double PT_VReversalMinMove = 200;           // Min Move (points)

input bool PT_EnableRangeExpansion = true;        // Range Expansion Pattern
input double PT_ExpansionRatio = 1.5;             // Expansion Ratio

//+------------------------------------------------------------------+
//|              TRADING SESSIONS                                     |
//+------------------------------------------------------------------+
input group "═══════ TRADING SESSIONS (Server Time) ═══════"
input bool EnableAsianSession = true;          // Enable Asian Session
input int AsianStartHour = 0;                  // Asian Start Hour (00:00)
input int AsianEndHour = 8;                    // Asian End Hour (08:00)

input bool EnableLondonSession = true;         // Enable London Session
input int LondonStartHour = 8;                 // London Start Hour (08:00)
input int LondonEndHour = 16;                  // London End Hour (16:00)

input bool EnableNewYorkSession = true;        // Enable New York Session
input int NewYorkStartHour = 13;               // NY Start Hour (13:00)
input int NewYorkEndHour = 22;                 // NY End Hour (22:00)

input bool TradeSessionOverlaps = true;        // Trade During Overlaps

//+------------------------------------------------------------------+
//|              PATTERN FILTERS                                      |
//+------------------------------------------------------------------+
input group "═══════ PATTERN FILTERS ═══════"
input double PF_MinCandleBody = 20;            // Min Candle Body (points)
input double PF_MinPatternHeight = 50;         // Min Pattern Height (points)
input int PF_MinVolatilityBars = 5;            // Min Volatility Check Bars
input double PF_VolatilityMultiplier = 0.5;    // Min Volatility vs Avg

//+------------------------------------------------------------------+
//|              STRATEGY ENHANCEMENTS                                |
//+------------------------------------------------------------------+
input group "═══════ STRATEGY ENHANCEMENTS ═══════"
input bool UseTrendFilter = true;                  // Require higher timeframe trend alignment
input ENUM_TIMEFRAMES Trend_Timeframe = PERIOD_H1; // Trend confirmation timeframe
input int Trend_EMAPeriod = 200;                   // EMA period for trend filter
input double Trend_SlopePoints = 2.0;              // Min EMA slope (points) to confirm trend

input bool UseATRStops = true;                     // Use ATR-adjusted stops
input int ATR_Period = 14;                         // ATR period for dynamic buffers
input double ATR_StopMultiplier = 1.2;             // ATR multiplier for stop buffer
input bool EnableATRTrailing = true;               // Use ATR trailing stop once in profit
input double TrailStartRR = 1.5;                   // Start trailing after reaching this R multiple
input double ATR_TrailMultiplier = 1.0;            // ATR multiplier for trailing distance

//+------------------------------------------------------------------+
//|              TRADING HOURS & SESSIONS                             |
//+------------------------------------------------------------------+
input group "═══════ TRADING TIMES ═══════"
input bool AvoidMonday = true;                 // Avoid Monday Trading
input bool AvoidFriday = true;                 // Avoid Friday (after 16:00)
input double MaxSpreadPoints = 30;             // Max Spread (points)

//+------------------------------------------------------------------+
//|              TRADE MANAGEMENT                                     |
//+------------------------------------------------------------------+
input group "═══════ TRADE MANAGEMENT ═══════"
input double BE_CashProfit = 50;               // Cash Breakeven Trigger ($)
input double BE_OffsetPoints = 10;             // BE Offset (points)
input bool UsePartialTP = true;                // Use Partial TP
input double PartialTP_Percent = 50;           // Close % at 1R

//+------------------------------------------------------------------+
//|              DISPLAY & LOGGING                                    |
//+------------------------------------------------------------------+
input group "═══════ DISPLAY SETTINGS ═══════"
input bool ShowHUD = true;                     // Show HUD Display
input bool ShowDebugInfo = false;              // Show Debug Information

//+------------------------------------------------------------------+
//|              GLOBAL VARIABLES                                     |
//+------------------------------------------------------------------+

// Statistics
int totalWins = 0;
int totalLosses = 0;
double totalProfit = 0;
double totalLoss = 0;
double winRate = 0;
datetime statsLastUpdate = 0;

// Strategy counters
int PT_Wins = 0, PT_Losses = 0;

// Pattern counters
int LiquidityGrab_Count = 0;
int VReversal_Count = 0;
int RangeExpansion_Count = 0;

// FTMO tracking
double dailyStartBalance = 0;
double initialBalance = 0;
datetime ftmoCurrentDay = 0;
bool profitTargetReached = false;
bool maxDailyDrawdownHit = false;
double dailyProfitLoss = 0;
double totalProfitLoss = 0;

// Trade management
datetime lastBarTime = 0;

// Session tracking
string currentSession = "NONE";

// Global variable names for persistence
string GV_InitialBalance = "AST_InitialBalance_" + IntegerToString(MagicNumber);
string GV_DailyStartBalance = "AST_DailyStartBalance_" + IntegerToString(MagicNumber);
string GV_CurrentDay = "AST_CurrentDay_" + IntegerToString(MagicNumber);
string GV_LiquidityCount = "AST_LiquidityCount_" + IntegerToString(MagicNumber);
string GV_VReversalCount = "AST_VReversalCount_" + IntegerToString(MagicNumber);
string GV_ExpansionCount = "AST_ExpansionCount_" + IntegerToString(MagicNumber);

//+------------------------------------------------------------------+
// Function declarations
//+------------------------------------------------------------------+
void InitializeIndicators();
void ReleaseIndicators();
void CheckPatterns();
void CheckLiquidityGrab();
void CheckVReversal();
void CheckRangeExpansion();
bool IsInTradingSession();
string GetCurrentSession();
bool CheckVolatility();
double CalculateLotSize(double riskPoints);
double GetPatternLotSize(string patternType, double riskPoints);
bool SpreadOK();
bool HasAnyPosition();
bool HasPositionByComment(string commentPrefix);
void ManagePositions();
void CheckFTMO_Rules();
void CloseAllPositions();
void LoadTradeStatistics();
void UpdateTradeStatistics();
void UpdateHUD();
void LoadGlobalVariables();
void SaveGlobalVariables();
bool PassesPatternFilters(double candleBodyPoints, double patternHeightPoints, string patternName);
bool TrendFilterAllows(int direction);
double GetATR(ENUM_TIMEFRAMES timeframe, int period, int shift);
string TimeframeToString(ENUM_TIMEFRAMES timeframe);

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // BUG FIX: Changed from FOK to IOC for better order execution
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(50);
   trade.SetAsyncMode(false);
   trade.SetTypeFilling(ORDER_FILLING_IOC);  // FIXED: Was ORDER_FILLING_FOK

   // Initialize indicator handles for enhanced logic
   InitializeIndicators();

   // BUG FIX: Load persistent values from global variables
   LoadGlobalVariables();

   // BUG FIX: Improved initialization logic with proper balance tracking
   if(UseFTMO_Mode)
   {
      // Check if we have stored initial balance
      if(GlobalVariableCheck(GV_InitialBalance))
      {
         initialBalance = GlobalVariableGet(GV_InitialBalance);
      }
      else
      {
         initialBalance = FTMO_StartBalance;
         GlobalVariableSet(GV_InitialBalance, initialBalance);
      }

      // Get the daily start balance from storage or use current
      datetime storedDay = (datetime)GlobalVariableGet(GV_CurrentDay);
      datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);

      if(storedDay == currentDay && GlobalVariableCheck(GV_DailyStartBalance))
      {
         dailyStartBalance = GlobalVariableGet(GV_DailyStartBalance);
      }
      else
      {
         dailyStartBalance = account.Balance();
         GlobalVariableSet(GV_DailyStartBalance, dailyStartBalance);
         GlobalVariableSet(GV_CurrentDay, (double)currentDay);
      }
   }
   else
   {
      // For non-FTMO mode, also use persistent storage
      if(GlobalVariableCheck(GV_InitialBalance))
      {
         initialBalance = GlobalVariableGet(GV_InitialBalance);
      }
      else
      {
         initialBalance = account.Balance();
         GlobalVariableSet(GV_InitialBalance, initialBalance);
      }

      datetime storedDay = (datetime)GlobalVariableGet(GV_CurrentDay);
      datetime currentDay = iTime(_Symbol, PERIOD_D1, 0);

      if(storedDay == currentDay && GlobalVariableCheck(GV_DailyStartBalance))
      {
         dailyStartBalance = GlobalVariableGet(GV_DailyStartBalance);
      }
      else
      {
         dailyStartBalance = account.Balance();
         GlobalVariableSet(GV_DailyStartBalance, dailyStartBalance);
         GlobalVariableSet(GV_CurrentDay, (double)currentDay);
      }
   }

   ftmoCurrentDay = iTime(_Symbol, PERIOD_D1, 0);
   profitTargetReached = false;
   maxDailyDrawdownHit = false;

   LoadTradeStatistics();

   Print("╔════════════════════════════════════════════════╗");
   Print("║      THE AURUM STEAM TRAIN - Pattern EA       ║");
   Print("║          XAU/USD Pattern Recognition           ║");
   Print("║       v7.31 BUG FIXED - SESSIONS EDITION       ║");
   Print("╚════════════════════════════════════════════════╝");
   Print("✅ BUGS FIXED:");
   Print("   • ORDER_FILLING changed from FOK to IOC");
   Print("   • Daily balance tracking improved");
   Print("   • Pattern counters now persistent");
   Print("   • Statistics update optimized");
   Print("   • FTMO balance calculation corrected");
   Print("════════════════════════════════════════════════");
   Print("✅ Active Patterns: Liquidity Grab, V-Reversal,");
   Print("   Range Expansion");
   Print("💎 ONE TRADE AT A TIME: ", OneTradeAtATime ? "ENABLED" : "DISABLED");
   Print("💰 CASH BREAKEVEN: £", BE_CashProfit, " (Always Active)");
   Print("════════════════════════════════════════════════");
   Print("📍 TRADING SESSIONS (Server Time):");
   if(EnableAsianSession) Print("   🌏 ASIAN: ", AsianStartHour, ":00 - ", AsianEndHour, ":00");
   if(EnableLondonSession) Print("   🇬🇧 LONDON: ", LondonStartHour, ":00 - ", LondonEndHour, ":00");
   if(EnableNewYorkSession) Print("   🇺🇸 NEW YORK: ", NewYorkStartHour, ":00 - ", NewYorkEndHour, ":00");
   Print("════════════════════════════════════════════════");
   Print("💾 Initial Balance: £", initialBalance);
   Print("💾 Daily Start Balance: £", dailyStartBalance);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // BUG FIX: Save pattern counters before exit
   SaveGlobalVariables();
   ReleaseIndicators();
   Comment("");
   Print("THE AURUM STEAM TRAIN - EA Removed | Counters Saved");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(ShowHUD) UpdateHUD();
   UpdateTradeStatistics();

   if(UseFTMO_Mode)
   {
      CheckFTMO_Rules();
      if(StopAtProfitTarget && profitTargetReached) return;
      if(StopAtMaxDailyDrawdown && maxDailyDrawdownHit) return;
   }

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int dayOfWeek = timeStruct.day_of_week;
   int currentHour = timeStruct.hour;

   if(AvoidMonday && dayOfWeek == 1) return;
   if(AvoidFriday && dayOfWeek == 5 && currentHour >= 16) return;
   if(!SpreadOK()) return;

   // Check if we're in an allowed trading session
   if(!IsInTradingSession()) return;

   ManagePositions();

   datetime currentBarTime = iTime(_Symbol, PT_Timeframe, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   CheckPatterns();
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                     |
//+------------------------------------------------------------------+
void InitializeIndicators()
{
   ReleaseIndicators();

   if(UseATRStops || EnableATRTrailing)
   {
      g_ATRTimeframe = PT_Timeframe;
      g_ATRPeriod = ATR_Period;
      g_ATRHandle = iATR(_Symbol, g_ATRTimeframe, g_ATRPeriod);
      if(g_ATRHandle == INVALID_HANDLE && ShowDebugInfo)
         Print("❌ Failed to create ATR handle: ", GetLastError());
   }

   if(UseTrendFilter)
   {
      g_TrendTimeframe = Trend_Timeframe;
      g_TrendPeriod = Trend_EMAPeriod;
      g_TrendEMAHandle = iMA(_Symbol, g_TrendTimeframe, g_TrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(g_TrendEMAHandle == INVALID_HANDLE && ShowDebugInfo)
         Print("❌ Failed to create Trend EMA handle: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Release indicator handles                                        |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   if(g_ATRHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_ATRHandle);
      g_ATRHandle = INVALID_HANDLE;
   }

   if(g_TrendEMAHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_TrendEMAHandle);
      g_TrendEMAHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Load Global Variables (BUG FIX: Pattern counter persistence)    |
//+------------------------------------------------------------------+
void LoadGlobalVariables()
{
   if(GlobalVariableCheck(GV_LiquidityCount))
      LiquidityGrab_Count = (int)GlobalVariableGet(GV_LiquidityCount);

   if(GlobalVariableCheck(GV_VReversalCount))
      VReversal_Count = (int)GlobalVariableGet(GV_VReversalCount);

   if(GlobalVariableCheck(GV_ExpansionCount))
      RangeExpansion_Count = (int)GlobalVariableGet(GV_ExpansionCount);
}

//+------------------------------------------------------------------+
//| Save Global Variables (BUG FIX: Pattern counter persistence)    |
//+------------------------------------------------------------------+
void SaveGlobalVariables()
{
   GlobalVariableSet(GV_LiquidityCount, LiquidityGrab_Count);
   GlobalVariableSet(GV_VReversalCount, VReversal_Count);
   GlobalVariableSet(GV_ExpansionCount, RangeExpansion_Count);
   GlobalVariableSet(GV_DailyStartBalance, dailyStartBalance);
   GlobalVariableSet(GV_CurrentDay, (double)ftmoCurrentDay);
}

//+------------------------------------------------------------------+
//| Check if current time is in allowed trading session              |
//+------------------------------------------------------------------+
bool IsInTradingSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   bool inAsian = false;
   bool inLondon = false;
   bool inNewYork = false;

   // Check Asian Session
   if(EnableAsianSession)
   {
      if(AsianStartHour < AsianEndHour)
      {
         if(currentHour >= AsianStartHour && currentHour < AsianEndHour)
            inAsian = true;
      }
      else // Crosses midnight
      {
         if(currentHour >= AsianStartHour || currentHour < AsianEndHour)
            inAsian = true;
      }
   }

   // Check London Session
   if(EnableLondonSession)
   {
      if(LondonStartHour < LondonEndHour)
      {
         if(currentHour >= LondonStartHour && currentHour < LondonEndHour)
            inLondon = true;
      }
      else // Crosses midnight
      {
         if(currentHour >= LondonStartHour || currentHour < LondonEndHour)
            inLondon = true;
      }
   }

   // Check New York Session
   if(EnableNewYorkSession)
   {
      if(NewYorkStartHour < NewYorkEndHour)
      {
         if(currentHour >= NewYorkStartHour && currentHour < NewYorkEndHour)
            inNewYork = true;
      }
      else // Crosses midnight
      {
         if(currentHour >= NewYorkStartHour || currentHour < NewYorkEndHour)
            inNewYork = true;
      }
   }

   // Update current session for HUD
   currentSession = GetCurrentSession();

   // Return true if in any enabled session
   return (inAsian || inLondon || inNewYork);
}

//+------------------------------------------------------------------+
//| Get Current Trading Session Name                                 |
//+------------------------------------------------------------------+
string GetCurrentSession()
{
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;

   string sessions = "";
   bool inAny = false;

   // Check all sessions
   if(EnableAsianSession)
   {
      if(AsianStartHour < AsianEndHour)
      {
         if(currentHour >= AsianStartHour && currentHour < AsianEndHour)
         {
            sessions += "ASIAN ";
            inAny = true;
         }
      }
      else
      {
         if(currentHour >= AsianStartHour || currentHour < AsianEndHour)
         {
            sessions += "ASIAN ";
            inAny = true;
         }
      }
   }

   if(EnableLondonSession)
   {
      if(LondonStartHour < LondonEndHour)
      {
         if(currentHour >= LondonStartHour && currentHour < LondonEndHour)
         {
            sessions += "LONDON ";
            inAny = true;
         }
      }
      else
      {
         if(currentHour >= LondonStartHour || currentHour < LondonEndHour)
         {
            sessions += "LONDON ";
            inAny = true;
         }
      }
   }

   if(EnableNewYorkSession)
   {
      if(NewYorkStartHour < NewYorkEndHour)
      {
         if(currentHour >= NewYorkStartHour && currentHour < NewYorkEndHour)
         {
            sessions += "NEW YORK ";
            inAny = true;
         }
      }
      else
      {
         if(currentHour >= NewYorkStartHour || currentHour < NewYorkEndHour)
         {
            sessions += "NEW YORK ";
            inAny = true;
         }
      }
   }

   if(!inAny) return "CLOSED";

   // Remove trailing space
   StringTrimRight(sessions);
   return sessions;
}

//+------------------------------------------------------------------+
//| Check if any position exists                                     |
//+------------------------------------------------------------------+
bool HasAnyPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get Pattern Lot Size                                             |
//+------------------------------------------------------------------+
double GetPatternLotSize(string patternType, double riskPoints)
{
   if(riskPoints <= 0)
      return 0.0;

   if(!UsePatternLots)
      return CalculateLotSize(riskPoints);

   double lots = 0.01;

   if(StringFind(patternType, "LiqGrab") >= 0) lots = LiquidityGrab_Lots;
   else if(StringFind(patternType, "VReversal") >= 0) lots = VReversal_Lots;
   else if(StringFind(patternType, "Expansion") >= 0) lots = RangeExpansion_Lots;
   else lots = CalculateLotSize(riskPoints);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check All XAU/USD Patterns                                       |
//+------------------------------------------------------------------+
void CheckPatterns()
{
   if(OneTradeAtATime && HasAnyPosition()) return;
   if(HasPositionByComment("PT_")) return;
   if(!CheckVolatility()) return;

   if(PT_EnableLiquidityGrab) CheckLiquidityGrab();
   if(PT_EnableV_Reversal) CheckVReversal();
   if(PT_EnableRangeExpansion) CheckRangeExpansion();
}

//+------------------------------------------------------------------+
//| Liquidity Grab Pattern                                           |
//+------------------------------------------------------------------+
void CheckLiquidityGrab()
{
   double swingHigh = 0;
   double swingLow = DBL_MAX;

   for(int i = 2; i <= PT_LiquidityLookback; i++)
   {
      double h = iHigh(_Symbol, PT_Timeframe, i);
      double l = iLow(_Symbol, PT_Timeframe, i);
      if(h > swingHigh) swingHigh = h;
      if(l < swingLow) swingLow = l;
   }

   double h1 = iHigh(_Symbol, PT_Timeframe, 1);
   double l1 = iLow(_Symbol, PT_Timeframe, 1);
   double o1 = iOpen(_Symbol, PT_Timeframe, 1);
   double c1 = iClose(_Symbol, PT_Timeframe, 1);

   double patternHeightPoints = (swingHigh - swingLow) / _Point;
   double candleBodyPoints = MathAbs(c1 - o1) / _Point;

   if(!PassesPatternFilters(candleBodyPoints, patternHeightPoints, "PT_LiqGrab"))
      return;

   double atr = UseATRStops ? GetATR(PT_Timeframe, ATR_Period, 1) : 0.0;
   double baseBuffer = 15 * _Point;
   double slBuffer = baseBuffer;
   if(UseATRStops && atr > 0)
      slBuffer = MathMax(baseBuffer, atr * ATR_StopMultiplier);

   // Bearish Liquidity Grab
   if(h1 > swingHigh && c1 < swingHigh - (20 * _Point))
   {
      if(UseTrendFilter && !TrendFilterAllows(-1))
      {
         if(ShowDebugInfo) Print("PT_LiqGrab_Short rejected by trend filter");
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = h1 + slBuffer;
         double risk = sl - bid;
         if(risk <= 0) return;
         double tp = bid - (risk * PT_RiskReward);

         double lots = GetPatternLotSize("PT_LiqGrab_Short", risk);

         // BUG FIX: Added error handling for trade execution
         if(lots > 0)
         {
            if(trade.Sell(lots, _Symbol, bid, sl, tp, "PT_LiqGrab_Short"))
            {
               LiquidityGrab_Count++;
               SaveGlobalVariables(); // Save counter immediately
               Print("💧 LIQUIDITY GRAB SHORT (swept ", DoubleToString(swingHigh, _Digits), ") | Lots:", lots, " | Session:", currentSession);
            }
            else
            {
               Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
            }
         }
      }
   }

   // Bullish Liquidity Grab
   if(l1 < swingLow && c1 > swingLow + (20 * _Point))
   {
      if(UseTrendFilter && !TrendFilterAllows(1))
      {
         if(ShowDebugInfo) Print("PT_LiqGrab_Long rejected by trend filter");
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = l1 - slBuffer;
         double risk = ask - sl;
         if(risk <= 0) return;
         double tp = ask + (risk * PT_RiskReward);

         double lots = GetPatternLotSize("PT_LiqGrab_Long", risk);

         // BUG FIX: Added error handling for trade execution
         if(lots > 0)
         {
            if(trade.Buy(lots, _Symbol, ask, sl, tp, "PT_LiqGrab_Long"))
            {
               LiquidityGrab_Count++;
               SaveGlobalVariables(); // Save counter immediately
               Print("💧 LIQUIDITY GRAB LONG (swept ", DoubleToString(swingLow, _Digits), ") | Lots:", lots, " | Session:", currentSession);
            }
            else
            {
               Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| V-Shape Reversal                                                 |
//+------------------------------------------------------------------+
void CheckVReversal()
{
   double h1 = iHigh(_Symbol, PT_Timeframe, 2);
   double l1 = iLow(_Symbol, PT_Timeframe, 2);
   double c1 = iClose(_Symbol, PT_Timeframe, 2);

   double h2 = iHigh(_Symbol, PT_Timeframe, 1);
   double l2 = iLow(_Symbol, PT_Timeframe, 1);
   double o2 = iOpen(_Symbol, PT_Timeframe, 1);
   double c2 = iClose(_Symbol, PT_Timeframe, 1);

   double bodyPoints = MathAbs(c2 - o2) / _Point;
   double patternHeightPoints = (h2 - l2) / _Point;

   if(!PassesPatternFilters(bodyPoints, patternHeightPoints, "PT_VReversal"))
      return;

   double atr = UseATRStops ? GetATR(PT_Timeframe, ATR_Period, 1) : 0.0;
   double baseBuffer = 15 * _Point;
   double slBuffer = baseBuffer;
   if(UseATRStops && atr > 0)
      slBuffer = MathMax(baseBuffer, atr * ATR_StopMultiplier);

   // Bullish V-Reversal
   double downMove = c1 - l2;
   double upMove = c2 - l2;

   if(downMove > PT_VReversalMinMove * _Point && upMove > PT_VReversalMinMove * _Point && c2 > c1)
   {
      if(UseTrendFilter && !TrendFilterAllows(1))
      {
         if(ShowDebugInfo) Print("PT_VReversal_Long rejected by trend filter");
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = l2 - slBuffer;
         double risk = ask - sl;
         if(risk <= 0) return;
         double tp = ask + (risk * PT_RiskReward);

         double lots = GetPatternLotSize("PT_VReversal_Long", risk);

         // BUG FIX: Added error handling for trade execution
         if(lots > 0)
         {
            if(trade.Buy(lots, _Symbol, ask, sl, tp, "PT_VReversal_Long"))
            {
               VReversal_Count++;
               SaveGlobalVariables(); // Save counter immediately
               Print("📐 V-REVERSAL LONG | Move:", DoubleToString(downMove/_Point, 0), "pts | Lots:", lots, " | Session:", currentSession);
            }
            else
            {
               Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
            }
         }
      }
   }

   // Bearish V-Reversal
   double upMove2 = h2 - c1;
   double downMove2 = h2 - c2;

   if(upMove2 > PT_VReversalMinMove * _Point && downMove2 > PT_VReversalMinMove * _Point && c2 < c1)
   {
      if(UseTrendFilter && !TrendFilterAllows(-1))
      {
         if(ShowDebugInfo) Print("PT_VReversal_Short rejected by trend filter");
      }
      else
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = h2 + slBuffer;
         double risk = sl - bid;
         if(risk <= 0) return;
         double tp = bid - (risk * PT_RiskReward);

         double lots = GetPatternLotSize("PT_VReversal_Short", risk);

         // BUG FIX: Added error handling for trade execution
         if(lots > 0)
         {
            if(trade.Sell(lots, _Symbol, bid, sl, tp, "PT_VReversal_Short"))
            {
               VReversal_Count++;
               SaveGlobalVariables(); // Save counter immediately
               Print("📐 INVERTED V-REVERSAL SHORT | Move:", DoubleToString(upMove2/_Point, 0), "pts | Lots:", lots, " | Session:", currentSession);
            }
            else
            {
               Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Range Expansion Pattern                                          |
//+------------------------------------------------------------------+
void CheckRangeExpansion()
{
   double avgRange = 0;
   for(int i = 2; i <= 10; i++)
   {
      avgRange += iHigh(_Symbol, PT_Timeframe, i) - iLow(_Symbol, PT_Timeframe, i);
   }
   avgRange /= 9;

   double h1 = iHigh(_Symbol, PT_Timeframe, 1);
   double l1 = iLow(_Symbol, PT_Timeframe, 1);
   double o1 = iOpen(_Symbol, PT_Timeframe, 1);
   double c1 = iClose(_Symbol, PT_Timeframe, 1);
   double range1 = h1 - l1;

   double bodyPoints = MathAbs(c1 - o1) / _Point;
   double patternHeightPoints = range1 / _Point;

   if(!PassesPatternFilters(bodyPoints, patternHeightPoints, "PT_RangeExpansion"))
      return;

   if(range1 > avgRange * PT_ExpansionRatio)
   {
      double atr = UseATRStops ? GetATR(PT_Timeframe, ATR_Period, 1) : 0.0;
      double baseBuffer = 10 * _Point;
      double slBuffer = baseBuffer;
      if(UseATRStops && atr > 0)
         slBuffer = MathMax(baseBuffer, atr * ATR_StopMultiplier);

      double expansionMultiple = (avgRange == 0) ? 0 : range1 / avgRange;

      // Bullish Expansion
      if(c1 > o1 && c1 > h1 - range1 * 0.3)
      {
         if(UseTrendFilter && !TrendFilterAllows(1))
         {
            if(ShowDebugInfo) Print("PT_Expansion_Long rejected by trend filter");
         }
         else
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double sl = l1 - slBuffer;
            double risk = ask - sl;
            if(risk <= 0) return;
            double tp = ask + (risk * PT_RiskReward);

            double lots = GetPatternLotSize("PT_Expansion_Long", risk);

            // BUG FIX: Added error handling for trade execution
            if(lots > 0)
            {
               if(trade.Buy(lots, _Symbol, ask, sl, tp, "PT_Expansion_Long"))
               {
                  RangeExpansion_Count++;
                  SaveGlobalVariables(); // Save counter immediately
                  Print("📏 RANGE EXPANSION LONG | ", DoubleToString(expansionMultiple, 2), "x avg | Lots:", lots, " | Session:", currentSession);
               }
               else
               {
                  Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
      // Bearish Expansion
      else if(c1 < o1 && c1 < l1 + range1 * 0.3)
      {
         if(UseTrendFilter && !TrendFilterAllows(-1))
         {
            if(ShowDebugInfo) Print("PT_Expansion_Short rejected by trend filter");
         }
         else
         {
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double sl = h1 + slBuffer;
            double risk = sl - bid;
            if(risk <= 0) return;
            double tp = bid - (risk * PT_RiskReward);

            double lots = GetPatternLotSize("PT_Expansion_Short", risk);

            // BUG FIX: Added error handling for trade execution
            if(lots > 0)
            {
               if(trade.Sell(lots, _Symbol, bid, sl, tp, "PT_Expansion_Short"))
               {
                  RangeExpansion_Count++;
                  SaveGlobalVariables(); // Save counter immediately
                  Print("📏 RANGE EXPANSION SHORT | ", DoubleToString(expansionMultiple, 2), "x avg | Lots:", lots, " | Session:", currentSession);
               }
               else
               {
                  Print("❌ Trade failed: ", trade.ResultRetcodeDescription());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Volatility Filter                                          |
//+------------------------------------------------------------------+
bool CheckVolatility()
{
   double avgRange = 0;
   for(int i = 1; i <= PF_MinVolatilityBars; i++)
   {
      avgRange += iHigh(_Symbol, PT_Timeframe, i) - iLow(_Symbol, PT_Timeframe, i);
   }
   avgRange /= PF_MinVolatilityBars;

   double barRange = iHigh(_Symbol, PT_Timeframe, 1) - iLow(_Symbol, PT_Timeframe, 1);

   return barRange >= avgRange * PF_VolatilityMultiplier;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPoints)
{
   if(riskPoints <= 0)
      return 0.0;

   if(UseFixedLots) return FixedLotSize;

   double accountSize = UseFTMO_Mode ? FTMO_StartBalance : account.Balance();
   double riskAmount = accountSize * (RiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize == 0 || tickValue == 0) return FixedLotSize;

   double lots = (riskAmount / riskPoints) * (tickSize / tickValue);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Check Spread (BUG FIX: Proper point conversion)                 |
//+------------------------------------------------------------------+
bool SpreadOK()
{
   // BUG FIX: Proper spread calculation in points
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   return spread <= MaxSpreadPoints;
}

//+------------------------------------------------------------------+
//| Has Position By Comment                                          |
//+------------------------------------------------------------------+
bool HasPositionByComment(string commentPrefix)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber)
      {
         if(StringFind(position.Comment(), commentPrefix) >= 0)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage Positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   long stopLevelPointsLong = 0;
   if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL, stopLevelPointsLong))
      stopLevelPointsLong = 0;
   double stopLevelDistance = (double)stopLevelPointsLong * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!position.SelectByIndex(i)) continue;
      if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;

      ulong ticket = position.Ticket();
      double openPrice = position.PriceOpen();
      double sl = position.StopLoss();
      double tp = position.TakeProfit();
      double lots = position.Volume();
      string comment = position.Comment();

      if(sl == 0) continue;

      double risk = MathAbs(openPrice - sl);
      if(risk <= 0) continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profit = position.Profit();

      // Cash Breakeven
      if(profit >= BE_CashProfit)
      {
         if(position.PositionType() == POSITION_TYPE_BUY)
         {
            double newSL = openPrice + BE_OffsetPoints * _Point;
            if(newSL > sl)
            {
               if(trade.PositionModify(ticket, newSL, tp))
               {
                  Print("💰 CASH BE MOVED at £", profit, " | ", comment);
               }
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL)
         {
            double newSL = openPrice - BE_OffsetPoints * _Point;
            if(newSL < sl)
            {
               if(trade.PositionModify(ticket, newSL, tp))
               {
                  Print("💰 CASH BE MOVED at £", profit, " | ", comment);
               }
            }
         }
      }

      // Partial TP
      if(UsePartialTP && StringFind(comment, "_Partial") < 0)
      {
         if(position.PositionType() == POSITION_TYPE_BUY && bid >= openPrice + risk)
         {
            double closeLots = NormalizeDouble(lots * (PartialTP_Percent / 100.0), 2);
            if(closeLots >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               if(trade.PositionClosePartial(ticket, closeLots))
               {
                  Print("📊 PARTIAL TP | ", comment);
               }
            }
         }
         else if(position.PositionType() == POSITION_TYPE_SELL && ask <= openPrice - risk)
         {
            double closeLots = NormalizeDouble(lots * (PartialTP_Percent / 100.0), 2);
            if(closeLots >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               if(trade.PositionClosePartial(ticket, closeLots))
               {
                  Print("📊 PARTIAL TP | ", comment);
               }
            }
         }
      }

      // ATR-based trailing stop
      if(EnableATRTrailing && TrailStartRR > 0.0)
      {
         double atrTrail = GetATR(PT_Timeframe, ATR_Period, 1);
         if(atrTrail > 0)
         {
            double rrProgress = 0.0;
            if(position.PositionType() == POSITION_TYPE_BUY)
               rrProgress = (bid - openPrice) / risk;
            else if(position.PositionType() == POSITION_TYPE_SELL)
               rrProgress = (openPrice - ask) / risk;

            if(rrProgress >= TrailStartRR)
            {
               double desiredSL = sl;
               if(position.PositionType() == POSITION_TYPE_BUY)
               {
                  desiredSL = bid - atrTrail * ATR_TrailMultiplier;
                  if(stopLevelDistance > 0)
                     desiredSL = MathMin(desiredSL, bid - stopLevelDistance);
                  desiredSL = MathMax(desiredSL, openPrice); // never trail below entry
                  if(desiredSL > sl)
                  {
                     if(trade.PositionModify(ticket, desiredSL, tp))
                     {
                        Print("🛡️ ATR TRAIL UPDATED | ", comment, " | SL:", DoubleToString(desiredSL, _Digits));
                     }
                     else if(ShowDebugInfo)
                     {
                        Print("❌ ATR trail failed: ", trade.ResultRetcodeDescription());
                     }
                  }
               }
               else if(position.PositionType() == POSITION_TYPE_SELL)
               {
                  desiredSL = ask + atrTrail * ATR_TrailMultiplier;
                  if(stopLevelDistance > 0)
                     desiredSL = MathMax(desiredSL, ask + stopLevelDistance);
                  desiredSL = MathMin(desiredSL, openPrice); // never trail above entry
                  if(desiredSL < sl)
                  {
                     if(trade.PositionModify(ticket, desiredSL, tp))
                     {
                        Print("🛡️ ATR TRAIL UPDATED | ", comment, " | SL:", DoubleToString(desiredSL, _Digits));
                     }
                     else if(ShowDebugInfo)
                     {
                        Print("❌ ATR trail failed: ", trade.ResultRetcodeDescription());
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check FTMO Rules (BUG FIX: Improved daily balance tracking)     |
//+------------------------------------------------------------------+
void CheckFTMO_Rules()
{
   datetime newDay = iTime(_Symbol, PERIOD_D1, 0);
   if(newDay != ftmoCurrentDay)
   {
      ftmoCurrentDay = newDay;
      // BUG FIX: Store the balance at the START of the day before any trading
      dailyStartBalance = account.Balance();
      GlobalVariableSet(GV_DailyStartBalance, dailyStartBalance);
      GlobalVariableSet(GV_CurrentDay, (double)newDay);
      profitTargetReached = false;
      maxDailyDrawdownHit = false;

      Print("🔄 NEW TRADING DAY | Daily Start Balance: £", dailyStartBalance);
   }

   double currentBalance = account.Balance();
   double currentEquity = account.Equity();

   // BUG FIX: Calculate daily P&L using equity for open positions
   // This ensures floating losses are considered for drawdown limits
   dailyProfitLoss = currentEquity - dailyStartBalance;
   totalProfitLoss = currentEquity - initialBalance;

   // BUG FIX: Use equity-based drawdown, not just closed balance
   if(dailyProfitLoss <= -FTMO_MaxDailyLoss)
   {
      CloseAllPositions();
      maxDailyDrawdownHit = true;
      Print("⚠️ ALERT: FTMO Daily Loss Limit Breached!");
      Print("   Daily Start: £", dailyStartBalance, " | Current Equity: £", currentEquity);
      Print("   Daily Loss: £", dailyProfitLoss);
      return;
   }

   if(totalProfitLoss <= -FTMO_MaxTotalLoss)
   {
      CloseAllPositions();
      Print("⚠️ ALERT: FTMO Maximum Loss Limit Breached!");
      Print("   Initial Balance: £", initialBalance, " | Current Equity: £", currentEquity);
      Print("   Total Loss: £", totalProfitLoss);
      ExpertRemove();
      return;
   }

   if(totalProfitLoss >= FTMO_ProfitTarget && !profitTargetReached)
   {
      profitTargetReached = true;
      Print("🎉 Profit target reached: £", totalProfitLoss);
      if(StopAtProfitTarget) CloseAllPositions();
   }
}

//+------------------------------------------------------------------+
//| Close All Positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber)
      {
         if(!trade.PositionClose(position.Ticket()))
         {
            Print("❌ Failed to close position ", position.Ticket(), ": ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Load Trade Statistics                                            |
//+------------------------------------------------------------------+
void LoadTradeStatistics()
{
   totalWins = 0;
   totalLosses = 0;
   totalProfit = 0;
   totalLoss = 0;
   PT_Wins = 0;
   PT_Losses = 0;

   if(!HistorySelect(0, TimeCurrent())) return;

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double netProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                         HistoryDealGetDouble(ticket, DEAL_SWAP) +
                         HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);

      if(netProfit > 0)
      {
         totalWins++;
         totalProfit += netProfit;
         if(StringFind(comment, "PT_") >= 0) PT_Wins++;
      }
      else if(netProfit < 0)
      {
         totalLosses++;
         totalLoss += netProfit;
         if(StringFind(comment, "PT_") >= 0) PT_Losses++;
      }
   }

   int totalTrades = totalWins + totalLosses;
   winRate = (totalTrades > 0) ? ((double)totalWins / totalTrades) * 100.0 : 0.0;
   statsLastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Update Trade Statistics (BUG FIX: Optimized update logic)       |
//+------------------------------------------------------------------+
void UpdateTradeStatistics()
{
   // BUG FIX: Only check every 5 seconds AND only update if deals changed
   if(TimeCurrent() - statsLastUpdate < 5) return;

   static int lastKnownDeals = 0;
   if(!HistorySelect(0, TimeCurrent())) return;

   int currentDeals = HistoryDealsTotal();

   // BUG FIX: Only reload stats if the number of deals has changed
   if(currentDeals != lastKnownDeals)
   {
      LoadTradeStatistics();
      lastKnownDeals = currentDeals;
   }

   statsLastUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Update HUD                                                       |
//+------------------------------------------------------------------+
void UpdateHUD()
{
   double balance = account.Balance();
   double equity = account.Equity();
   double profit = equity - balance;

   int posCount = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         posCount++;
   }

   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   string currentTime = StringFormat("%02d:%02d", timeStruct.hour, timeStruct.min);

   string hud = "";
   hud += "╔═══════════════════════════════════════════════╗\n";
   hud += "║   🚂 THE AURUM STEAM TRAIN - SESSIONS 🚂     ║\n";
   hud += "║      XAU/USD Pattern Recognition v7.31 FIXED  ║\n";
   hud += "╚═══════════════════════════════════════════════╝\n";
   hud += "Server Time: " + currentTime + " | Session: " + currentSession + "\n";
   hud += "Mode: " + (OneTradeAtATime ? "ONE TRADE 💎" : "MULTIPLE") + " | Cash BE: £" + DoubleToString(BE_CashProfit, 0) + "\n";
   hud += "Balance: £" + DoubleToString(balance, 2) + " | Equity: £" + DoubleToString(equity, 2) + "\n";
   hud += "Floating: £" + DoubleToString(profit, 2) + " | Positions: " + IntegerToString(posCount) + "\n";
   hud += "Pattern Lots: " + (UsePatternLots ? "CUSTOM 🎯" : "GLOBAL") + "\n";
   hud += "Trend Filter: " + (UseTrendFilter ? (TimeframeToString(Trend_Timeframe) + " EMA" ) : "OFF") + "\n";
   if(UseATRStops || EnableATRTrailing)
   {
      hud += "ATR Risk: " + (UseATRStops ? ("Stops " + DoubleToString(ATR_StopMultiplier, 1) + "x") : "Stops OFF");
      hud += " | Trail: " + (EnableATRTrailing ? (DoubleToString(ATR_TrailMultiplier, 1) + "x @" + DoubleToString(TrailStartRR, 1) + "R") : "OFF") + "\n";
   }
   hud += "═══════════════════════════════════════════════\n";

   if(UseFTMO_Mode)
   {
      hud += "🛡️ FTMO: ";
      hud += profitTargetReached ? "✅ TARGET" : maxDailyDrawdownHit ? "🛑 DD HIT" : "🟢 ACTIVE";
      hud += "\nDaily: £" + DoubleToString(dailyProfitLoss, 2);
      hud += " | Total: £" + DoubleToString(totalProfitLoss, 2) + "\n";
      hud += "Daily Start: £" + DoubleToString(dailyStartBalance, 2) + "\n";
      hud += "═══════════════════════════════════════════════\n";
   }

   hud += "📊 STATS: " + IntegerToString(totalWins) + "W/" + IntegerToString(totalLosses) + "L | ";
   hud += DoubleToString(winRate, 1) + "%\n";
   hud += "📊 Patterns: " + IntegerToString(PT_Wins) + "W/" + IntegerToString(PT_Losses) + "L\n";

   hud += "═══════════════════════════════════════════════\n";
   hud += "📋 ACTIVE PATTERNS (v7.31 FIXED)\n";
   hud += "💧 Liquidity Grab: " + IntegerToString(LiquidityGrab_Count) + "\n";
   hud += "📐 V-Reversal: " + IntegerToString(VReversal_Count) + "\n";
   hud += "📏 Range Expansion: " + IntegerToString(RangeExpansion_Count) + "\n";

   hud += "═══════════════════════════════════════════════\n";
   hud += "🌍 TRADING SESSIONS (Server Time)\n";
   if(EnableAsianSession)
      hud += "🌏 ASIAN: " + IntegerToString(AsianStartHour) + ":00-" + IntegerToString(AsianEndHour) + ":00\n";
   if(EnableLondonSession)
      hud += "🇬🇧 LONDON: " + IntegerToString(LondonStartHour) + ":00-" + IntegerToString(LondonEndHour) + ":00\n";
   if(EnableNewYorkSession)
      hud += "🇺🇸 NEW YORK: " + IntegerToString(NewYorkStartHour) + ":00-" + IntegerToString(NewYorkEndHour) + ":00\n";

   if(maxDailyDrawdownHit)
      hud += "⚠️ MAX DD HIT - TRADING STOPPED\n";

   Comment(hud);
}

//+------------------------------------------------------------------+
//| Pattern filter helper                                            |
//+------------------------------------------------------------------+
bool PassesPatternFilters(double candleBodyPoints, double patternHeightPoints, string patternName)
{
   if(candleBodyPoints < PF_MinCandleBody)
   {
      if(ShowDebugInfo)
         Print(patternName, " rejected | Candle body too small: ", DoubleToString(candleBodyPoints, 1), " < ", PF_MinCandleBody);
      return false;
   }

   if(patternHeightPoints < PF_MinPatternHeight)
   {
      if(ShowDebugInfo)
         Print(patternName, " rejected | Pattern height too small: ", DoubleToString(patternHeightPoints, 1), " < ", PF_MinPatternHeight);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Trend filter helper                                              |
//+------------------------------------------------------------------+
bool TrendFilterAllows(int direction)
{
   if(!UseTrendFilter || direction == 0)
      return true;

   int handle = g_TrendEMAHandle;
   if(handle == INVALID_HANDLE)
   {
      handle = iMA(_Symbol, Trend_Timeframe, Trend_EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(handle == INVALID_HANDLE)
         return true; // fail open to avoid blocking EA if indicator unavailable
   }

   double emaBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   int copied = CopyBuffer(handle, 0, 0, 2, emaBuffer);

   if(handle != g_TrendEMAHandle)
      IndicatorRelease(handle);

   if(copied < 2)
      return true;

   double emaCurrent = emaBuffer[0];
   double emaPrev = emaBuffer[1];
   double slopePoints = (emaCurrent - emaPrev) / _Point;

   double price = iClose(_Symbol, Trend_Timeframe, 0);

   if(direction > 0)
   {
      if(price <= emaCurrent)
         return false;
      return slopePoints >= Trend_SlopePoints;
   }
   else if(direction < 0)
   {
      if(price >= emaCurrent)
         return false;
      return slopePoints <= -Trend_SlopePoints;
   }

   return true;
}

//+------------------------------------------------------------------+
//| ATR helper                                                       |
//+------------------------------------------------------------------+
double GetATR(ENUM_TIMEFRAMES timeframe, int period, int shift)
{
   int handle = g_ATRHandle;
   if(handle == INVALID_HANDLE || timeframe != g_ATRTimeframe || period != g_ATRPeriod)
   {
      handle = iATR(_Symbol, timeframe, period);
      if(handle == INVALID_HANDLE)
         return 0.0;
   }

   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int copied = CopyBuffer(handle, 0, shift, 1, atrBuffer);

   if(handle != g_ATRHandle)
      IndicatorRelease(handle);

   if(copied <= 0)
      return 0.0;

   return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Timeframe to string helper                                       |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES timeframe)
{
   switch(timeframe)
   {
      case PERIOD_M1:   return "M1";
      case PERIOD_M5:   return "M5";
      case PERIOD_M15:  return "M15";
      case PERIOD_M30:  return "M30";
      case PERIOD_H1:   return "H1";
      case PERIOD_H4:   return "H4";
      case PERIOD_D1:   return "D1";
      case PERIOD_W1:   return "W1";
      case PERIOD_MN1:  return "MN";
      default:          return "TF(" + IntegerToString((int)timeframe) + ")";
   }
}
//+------------------------------------------------------------------+
