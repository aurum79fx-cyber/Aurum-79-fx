#property copyright "GPT-5 Codex"
#property link      ""
#property version   "1.000"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- constants
#define EA_NAME                    "Gold Price Action Breakout EA"
#define MAGIC_NUMBER               7052025
#define HUD_OBJECT_NAME            "GoldBreakoutHUD"
#define OBJ_PREFIX                 "GoldBreakout"

//--- user inputs
input ENUM_TIMEFRAMES  InpAnalysisTimeframe       = PERIOD_M5;            // Price action timeframe
input double           InpRiskPerTrade            = 1.00;                 // Percent risk per trade
input double           InpMaxDailyLossPercent     = 5.00;                 // Daily loss stop (percent of equity)
input double           InpMaxConcurrentRisk       = 3.00;                 // Max combined open risk (percent of equity)
input int              InpMaxOpenPositions        = 1;                    // Maximum concurrent positions
input bool             InpAllowLongs              = true;                 // Enable buy setups
input bool             InpAllowShorts             = true;                 // Enable sell setups

input int              InpStructureLookbackBars   = 180;                  // Bars to scan for structure pivots
input int              InpPivotLeft               = 3;                    // Left pivot strength
input int              InpPivotRight              = 2;                    // Right pivot strength
input double           InpBreakoutBufferPoints    = 50;                   // Extra points above/below swing for breakout validation
input double           InpStopBufferPoints        = 100;                  // Buffer added beyond swing for stop-loss

input int              InpAverageLookback         = 20;                   // Lookback for candle averages
input double           InpBodyFactor              = 1.8;                  // Body size multiplier versus average
input double           InpRangeFactor             = 1.5;                  // Range size multiplier versus average
input double           InpVolumeFactor            = 1.6;                  // Volume multiplier versus average

input int              InpATRPeriod               = 14;                   // ATR period
input double           InpATRStopMultiplier       = 1.0;                  // ATR multiplier for safety cushion
input double           InpTargetRR                = 2.5;                  // Reward-to-risk target
input double           InpBreakEvenRR             = 1.0;                  // R multiple to move stop to break-even
input double           InpBreakEvenOffsetPoints   = 20;                   // Offset added when moving to break-even
input double           InpPartialCloseRR          = 1.5;                  // R multiple for partial close
input double           InpPartialClosePercent     = 50.0;                 // Volume percent to close partially
input double           InpTrailStartRR            = 1.2;                  // R multiple to start ATR trailing
input double           InpATRTrailMultiplier      = 1.2;                  // ATR multiplier for trailing stop

input bool             InpUseSessionFilter        = true;                 // Trade only core sessions
input int              InpLondonSessionStart      = 7;                    // London session start hour (server time)
input int              InpLondonSessionEnd        = 17;                   // London session end hour
input int              InpNYSessionStart          = 13;                   // New York session start hour
input int              InpNYSessionEnd            = 22;                   // New York session end hour

input bool             InpPauseAfterLoss          = true;                 // Pause after losing trade
input int              InpLossPauseMinutes        = 30;                   // Pause duration in minutes

input double           InpMaxSpreadPoints         = 400;                  // Maximum spread (points)
input bool             InpDrawStructureLevels     = true;                 // Display structure levels on chart
input bool             InpShowHUD                 = true;                 // Show on-chart HUD
input color            InpHUDTextColor            = clrWhite;
input color            InpHUDBorderColor          = clrDarkSlateGray;
input color            InpHUDBackgroundColor      = clrDimGray;
input int              InpHUDCorner               = CORNER_RIGHT_UPPER;
input int              InpHUDXDistance            = 20;
input int              InpHUDYDistance            = 20;

//--- enums and structs
enum TrendDirection
  {
   TREND_NEUTRAL = 0,
   TREND_BULLISH,
   TREND_BEARISH
  };

struct MarketStructureInfo
  {
   double    lastSwingHigh;
   double    prevSwingHigh;
   double    lastSwingLow;
   double    prevSwingLow;
   int       lastSwingHighIndex;
   int       prevSwingHighIndex;
   int       lastSwingLowIndex;
   int       prevSwingLowIndex;
  };

struct SignalSetup
  {
   bool      isValid;
   ENUM_ORDER_TYPE orderType;
   double    entryPrice;
   double    stopLoss;
   double    takeProfit;
   datetime  signalTime;
   double    riskDistance;
   double    rMultipleTarget;
  };

struct PositionState
  {
   ulong     ticket;
   bool      breakEvenSet;
   bool      partialCompleted;
  };

//--- globals
CTrade            g_trade;
CPositionInfo     g_position;
MqlRates          g_rates[];
double            g_atrBuffer[];
int               g_atrHandle               = INVALID_HANDLE;
datetime          g_lastBarTime             = 0;
TrendDirection    g_currentTrend            = TREND_NEUTRAL;
datetime          g_lastBullishSignalTime   = 0;
datetime          g_lastBearishSignalTime   = 0;
double            g_lastBullishStructure    = 0.0;
double            g_lastBearishStructure    = 0.0;

double            g_dayOpeningEquity        = 0.0;
int               g_dayKey                  = -1;
bool              g_tradingPaused           = false;
datetime          g_pauseStartTime          = 0;

double            g_tickSize                = 0.0;
double            g_tickValue               = 0.0;
double            g_point                   = 0.0;
double            g_volumeMin               = 0.0;
double            g_volumeMax               = 0.0;
double            g_volumeStep              = 0.0;
double            g_stopsLevel              = 0.0;

PositionState     g_positionStates[];

//--- forward declarations
bool     RefreshMarketData(const int requiredBars, bool &isNewBar);
bool     CalculateMarketStructure(const int index, MarketStructureInfo &info);
TrendDirection DetermineTrend(const MarketStructureInfo &info);
bool     CalculateAverages(const int index, const int lookback, double &avgBody, double &avgRange, double &avgVolume);
bool     DetectBullishSignal(const MarketStructureInfo &info, SignalSetup &signal);
bool     DetectBearishSignal(const MarketStructureInfo &info, SignalSetup &signal);
bool     ValidateCandleStrength(const int index, const bool bullish, const double avgBody, const double avgRange, const double avgVolume);
bool     CheckSpread() ;
double   CalculatePositionVolume(const SignalSetup &signal);
double   NormalizeVolume(const double volume);
bool     CanTradeNow(const SignalSetup &signal);
bool     PlaceTrade(const SignalSetup &signal);
void     UpdateDailyState();
void     ManageOpenPositions();
void     ManagePosition(const ulong ticket);
int      EnsurePositionState(const ulong ticket);
double   CalculateOpenPositionsRiskPct();
bool     IsWithinSessions();
void     UpdateHUD();
void     DrawStructureLevels(const MarketStructureInfo &info);
void     RemoveStructureObjects();
string   TrendToString(const TrendDirection trend);
string   FormatDouble(const double value, const int digits);
int      BuildDayKey(const datetime timeValue);

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_trade.SetExpertMagicNumber(MAGIC_NUMBER);
   g_trade.SetDeviationInPoints(20);

   g_point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_volumeMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_volumeMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   g_stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;

   if(g_point <= 0 || g_tickSize <= 0 || g_tickValue <= 0)
     {
      Print(EA_NAME, ": Invalid symbol properties for ", _Symbol);
      return(INIT_FAILED);
     }

   g_atrHandle = iATR(_Symbol, InpAnalysisTimeframe, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print(EA_NAME, ": Failed to create ATR handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }

   ArraySetAsSeries(g_rates, true);
   ArraySetAsSeries(g_atrBuffer, true);

   UpdateDailyState();

   if(InpShowHUD)
      UpdateHUD();

   Print(EA_NAME, " initialized successfully on ", _Symbol, " timeframe ", EnumToString(InpAnalysisTimeframe));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);

   if(InpShowHUD)
     {
      ObjectDelete(0, HUD_OBJECT_NAME);
     }

   RemoveStructureObjects();
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   bool isNewAnalysisBar = false;

   const int barsNeeded = MathMax(InpStructureLookbackBars + InpPivotLeft + InpPivotRight + 5,
                                  InpAverageLookback + 10);

   if(!RefreshMarketData(barsNeeded, isNewAnalysisBar))
     {
      UpdateHUD();
      return;
     }

   UpdateDailyState();
   ManageOpenPositions();

   if(InpShowHUD)
      UpdateHUD();

   if(!isNewAnalysisBar)
      return;

   if(!IsWithinSessions())
      return;

   MarketStructureInfo structureInfo;
   if(!CalculateMarketStructure(1, structureInfo))
      return;

   g_currentTrend = DetermineTrend(structureInfo);

   DrawStructureLevels(structureInfo);

   SignalSetup bullishSignal;
   SignalSetup bearishSignal;

   if(InpAllowLongs && DetectBullishSignal(structureInfo, bullishSignal))
      PlaceTrade(bullishSignal);

   if(InpAllowShorts && DetectBearishSignal(structureInfo, bearishSignal))
      PlaceTrade(bearishSignal);
  }

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD &&
      trans.symbol == _Symbol &&
      trans.entry == DEAL_ENTRY_OUT)
     {
      if(InpPauseAfterLoss && trans.profit < 0.0)
        {
         g_tradingPaused  = true;
         g_pauseStartTime = TimeCurrent();
         Print(EA_NAME, ": Trading paused for ", InpLossPauseMinutes,
               " minutes after loss of ", DoubleToString(trans.profit, 2));
        }
     }
  }

//+------------------------------------------------------------------+
//| Refreshes market data arrays                                     |
//+------------------------------------------------------------------+
bool RefreshMarketData(const int requiredBars, bool &isNewBar)
  {
   isNewBar = false;

   const int copiedRates = CopyRates(_Symbol, InpAnalysisTimeframe, 0, requiredBars, g_rates);
   if(copiedRates < requiredBars)
     {
      Print(EA_NAME, ": Not enough rate data. Copied ", copiedRates, " of ", requiredBars);
      return(false);
     }

   if(g_atrHandle != INVALID_HANDLE)
     {
      if(CopyBuffer(g_atrHandle, 0, 0, requiredBars, g_atrBuffer) < requiredBars)
        {
         Print(EA_NAME, ": Failed to copy ATR buffer. Error: ", GetLastError());
         return(false);
        }
     }

   const datetime currentBarTime = g_rates[0].time;
   if(currentBarTime != g_lastBarTime)
     {
      g_lastBarTime = currentBarTime;
      isNewBar      = true;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Determines market structure pivots                               |
//+------------------------------------------------------------------+
bool CalculateMarketStructure(const int index, MarketStructureInfo &info)
  {
   ZeroMemory(info);

   const int barsAvailable = ArraySize(g_rates);
   if(index + InpPivotLeft + InpPivotRight >= barsAvailable)
      return(false);

   const int searchLimit = MathMin(InpStructureLookbackBars, barsAvailable - index - InpPivotRight - 1);

   int lastHighIndex = -1;
   int prevHighIndex = -1;
   int lastLowIndex  = -1;
   int prevLowIndex  = -1;

   for(int i = index + InpPivotRight; i < index + searchLimit; ++i)
     {
      bool isHigh = true;
      bool isLow  = true;

      const double priceHigh = g_rates[i].high;
      const double priceLow  = g_rates[i].low;

      for(int l = 1; l <= InpPivotLeft; ++l)
        {
         if(g_rates[i + l].high > priceHigh)
            isHigh = false;
         if(g_rates[i + l].low < priceLow)
            isLow = false;
        }

      for(int r = 1; r <= InpPivotRight; ++r)
        {
         if(g_rates[i - r].high >= priceHigh)
            isHigh = false;
         if(g_rates[i - r].low <= priceLow)
            isLow = false;
        }

      if(isHigh)
        {
         if(lastHighIndex == -1)
            lastHighIndex = i;
         else if(prevHighIndex == -1)
           {
            prevHighIndex = i;
            break;
           }
        }
     }

   for(int i = index + InpPivotRight; i < index + searchLimit; ++i)
     {
      bool isHigh = true;
      bool isLow  = true;

      const double priceHigh = g_rates[i].high;
      const double priceLow  = g_rates[i].low;

      for(int l = 1; l <= InpPivotLeft; ++l)
        {
         if(g_rates[i + l].high > priceHigh)
            isHigh = false;
         if(g_rates[i + l].low < priceLow)
            isLow = false;
        }

      for(int r = 1; r <= InpPivotRight; ++r)
        {
         if(g_rates[i - r].high >= priceHigh)
            isHigh = false;
         if(g_rates[i - r].low <= priceLow)
            isLow = false;
        }

      if(isLow)
        {
         if(lastLowIndex == -1)
            lastLowIndex = i;
         else if(prevLowIndex == -1)
           {
            prevLowIndex = i;
            break;
           }
        }
     }

   if(lastHighIndex == -1 || lastLowIndex == -1)
      return(false);

   info.lastSwingHigh      = g_rates[lastHighIndex].high;
   info.lastSwingHighIndex = lastHighIndex;
   info.lastSwingLow       = g_rates[lastLowIndex].low;
   info.lastSwingLowIndex  = lastLowIndex;

   if(prevHighIndex != -1)
     {
      info.prevSwingHigh      = g_rates[prevHighIndex].high;
      info.prevSwingHighIndex = prevHighIndex;
     }
   else
     {
      info.prevSwingHigh      = info.lastSwingHigh;
      info.prevSwingHighIndex = lastHighIndex;
     }

   if(prevLowIndex != -1)
     {
      info.prevSwingLow      = g_rates[prevLowIndex].low;
      info.prevSwingLowIndex = prevLowIndex;
     }
   else
     {
      info.prevSwingLow      = info.lastSwingLow;
      info.prevSwingLowIndex = lastLowIndex;
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Determine trend direction                                        |
//+------------------------------------------------------------------+
TrendDirection DetermineTrend(const MarketStructureInfo &info)
  {
   if(info.lastSwingHigh > info.prevSwingHigh && info.lastSwingLow > info.prevSwingLow)
      return(TREND_BULLISH);

   if(info.lastSwingHigh < info.prevSwingHigh && info.lastSwingLow < info.prevSwingLow)
      return(TREND_BEARISH);

   return(TREND_NEUTRAL);
  }

//+------------------------------------------------------------------+
//| Calculate moving averages for candle characteristics              |
//+------------------------------------------------------------------+
bool CalculateAverages(const int index, const int lookback, double &avgBody, double &avgRange, double &avgVolume)
  {
   avgBody   = 0.0;
   avgRange  = 0.0;
   avgVolume = 0.0;

   if(index + lookback >= ArraySize(g_rates))
      return(false);

   for(int i = index; i < index + lookback; ++i)
     {
      avgBody   += MathAbs(g_rates[i].close - g_rates[i].open);
      avgRange  += (g_rates[i].high - g_rates[i].low);
      avgVolume += g_rates[i].tick_volume;
     }

   avgBody   /= lookback;
   avgRange  /= lookback;
   avgVolume /= lookback;

   return(true);
  }

//+------------------------------------------------------------------+
//| Validates strong candle characteristics                          |
//+------------------------------------------------------------------+
bool ValidateCandleStrength(const int index, const bool bullish, const double avgBody, const double avgRange, const double avgVolume)
  {
   const MqlRates &bar = g_rates[index];
   const double body   = MathAbs(bar.close - bar.open);
   const double range  = (bar.high - bar.low);
   const double volume = bar.tick_volume;

   if(bullish && bar.close <= bar.open)
      return(false);
   if(!bullish && bar.close >= bar.open)
      return(false);

   if(body < avgBody * InpBodyFactor)
      return(false);
   if(range < avgRange * InpRangeFactor)
      return(false);
   if(volume < avgVolume * InpVolumeFactor)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Detect bullish breakout signal                                   |
//+------------------------------------------------------------------+
bool DetectBullishSignal(const MarketStructureInfo &info, SignalSetup &signal)
  {
   ZeroMemory(signal);
   signal.isValid = false;

   if(g_currentTrend == TREND_BEARISH)
      return(false);

   const int index = 1; // last closed candle

   double avgBody, avgRange, avgVolume;
   if(!CalculateAverages(index + 1, InpAverageLookback, avgBody, avgRange, avgVolume))
      return(false);

   if(!ValidateCandleStrength(index, true, avgBody, avgRange, avgVolume))
      return(false);

   const double candleClose = g_rates[index].close;
   const double breakoutLevel = info.lastSwingHigh + InpBreakoutBufferPoints * g_point;

   if(candleClose <= breakoutLevel)
      return(false);

   const datetime signalTime = g_rates[index].time;
   if(signalTime == g_lastBullishSignalTime)
      return(false);

   const double swingLow = info.lastSwingLow - InpStopBufferPoints * g_point;
   double stopLoss       = swingLow;

   const double atrValue = (ArraySize(g_atrBuffer) > index) ? g_atrBuffer[index] : 0.0;
   if(atrValue > 0.0)
      stopLoss = MathMin(stopLoss, candleClose - atrValue * InpATRStopMultiplier);

   if(stopLoss >= candleClose - g_stopsLevel)
      stopLoss = candleClose - MathMax(g_stopsLevel, atrValue * InpATRStopMultiplier);

   if(stopLoss < 0.0)
      stopLoss = candleClose - (200 * g_point);

   const double stopDistance = candleClose - stopLoss;
   if(stopDistance <= g_stopsLevel)
      return(false);

   double takeProfit = candleClose + stopDistance * InpTargetRR;

   signal.isValid        = true;
   signal.orderType      = ORDER_TYPE_BUY;
   signal.entryPrice     = NormalizeDouble(candleClose, _Digits);
   signal.stopLoss       = NormalizeDouble(stopLoss, _Digits);
   signal.takeProfit     = NormalizeDouble(takeProfit, _Digits);
   signal.signalTime     = signalTime;
   signal.riskDistance   = stopDistance;
   signal.rMultipleTarget= InpTargetRR;

   return(true);
  }

//+------------------------------------------------------------------+
//| Detect bearish breakout signal                                   |
//+------------------------------------------------------------------+
bool DetectBearishSignal(const MarketStructureInfo &info, SignalSetup &signal)
  {
   ZeroMemory(signal);
   signal.isValid = false;

   if(g_currentTrend == TREND_BULLISH)
      return(false);

   const int index = 1;

   double avgBody, avgRange, avgVolume;
   if(!CalculateAverages(index + 1, InpAverageLookback, avgBody, avgRange, avgVolume))
      return(false);

   if(!ValidateCandleStrength(index, false, avgBody, avgRange, avgVolume))
      return(false);

   const double candleClose = g_rates[index].close;
   const double breakoutLevel = info.lastSwingLow - InpBreakoutBufferPoints * g_point;

   if(candleClose >= breakoutLevel)
      return(false);

   const datetime signalTime = g_rates[index].time;
   if(signalTime == g_lastBearishSignalTime)
      return(false);

   const double swingHigh = info.lastSwingHigh + InpStopBufferPoints * g_point;
   double stopLoss        = swingHigh;

   const double atrValue = (ArraySize(g_atrBuffer) > index) ? g_atrBuffer[index] : 0.0;
   if(atrValue > 0.0)
      stopLoss = MathMax(stopLoss, candleClose + atrValue * InpATRStopMultiplier);

   if(stopLoss <= candleClose + g_stopsLevel)
      stopLoss = candleClose + MathMax(g_stopsLevel, atrValue * InpATRStopMultiplier);

   if(stopLoss <= 0.0)
      stopLoss = candleClose + (200 * g_point);

   const double stopDistance = stopLoss - candleClose;
   if(stopDistance <= g_stopsLevel)
      return(false);

   double takeProfit = candleClose - stopDistance * InpTargetRR;

   signal.isValid        = true;
   signal.orderType      = ORDER_TYPE_SELL;
   signal.entryPrice     = NormalizeDouble(candleClose, _Digits);
   signal.stopLoss       = NormalizeDouble(stopLoss, _Digits);
   signal.takeProfit     = NormalizeDouble(takeProfit, _Digits);
   signal.signalTime     = signalTime;
   signal.riskDistance   = stopDistance;
   signal.rMultipleTarget= InpTargetRR;

   return(true);
  }

//+------------------------------------------------------------------+
//| Checks current spread                                            |
//+------------------------------------------------------------------+
bool CheckSpread()
  {
   const double spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return(spreadPoints <= InpMaxSpreadPoints || InpMaxSpreadPoints <= 0);
  }

//+------------------------------------------------------------------+
//| Calculates position volume based on risk                         |
//+------------------------------------------------------------------+
double CalculatePositionVolume(const SignalSetup &signal)
  {
   double stopDistance = MathAbs(signal.entryPrice - signal.stopLoss);
   if(stopDistance <= g_point)
      return(0.0);

   const double riskAmount = AccountEquity() * (InpRiskPerTrade / 100.0);
   if(riskAmount <= 0.0)
      return(0.0);

   double ticks = stopDistance / g_tickSize;
   if(ticks <= 0.0)
      return(0.0);

   double volume = riskAmount / (ticks * g_tickValue);
   volume = NormalizeVolume(volume);

   if(volume < g_volumeMin)
      volume = g_volumeMin;
   if(volume > g_volumeMax)
      volume = g_volumeMax;

   return(volume);
  }

//+------------------------------------------------------------------+
//| Normalize volume to broker step                                  |
//+------------------------------------------------------------------+
double NormalizeVolume(const double volume)
  {
   if(g_volumeStep <= 0.0)
      return(volume);

   const double normalized = MathFloor(volume / g_volumeStep + 0.5) * g_volumeStep;
   return(normalized);
  }

//+------------------------------------------------------------------+
//| Determine if trading is allowed                                  |
//+------------------------------------------------------------------+
bool CanTradeNow(const SignalSetup &signal)
  {
   if(!signal.isValid)
      return(false);

   if(!CheckSpread())
     {
      Print(EA_NAME, ": Spread filter blocks trade.");
      return(false);
     }

   if(g_tradingPaused)
     {
      if(TimeCurrent() - g_pauseStartTime >= InpLossPauseMinutes * 60)
         g_tradingPaused = false;
      else
         return(false);
     }

   if(InpMaxDailyLossPercent > 0.0)
     {
      const double minEquity = g_dayOpeningEquity * (1.0 - InpMaxDailyLossPercent / 100.0);
      if(AccountEquity() <= minEquity)
        {
         Print(EA_NAME, ": Daily loss limit reached. Trading suspended.");
         return(false);
        }
     }

   if(InpMaxConcurrentRisk > 0.0)
     {
      const double openRisk = CalculateOpenPositionsRiskPct();
      if(openRisk + InpRiskPerTrade > InpMaxConcurrentRisk + 1e-6)
        {
         Print(EA_NAME, ": Concurrent risk filter blocks trade. Current: ",
               DoubleToString(openRisk, 2), "%");
         return(false);
        }
     }

   // Count current symbol positions
  int openCount = 0;
  for(int i = PositionsTotal() - 1; i >= 0; --i)
    {
     if(!PositionSelectByIndex(i))
        continue;
     const string symbol = PositionGetString(POSITION_SYMBOL);
     if(symbol == _Symbol)
        ++openCount;
    }

   if(openCount >= InpMaxOpenPositions)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Places market trade                                              |
//+------------------------------------------------------------------+
bool PlaceTrade(const SignalSetup &signal)
  {
   if(!CanTradeNow(signal))
      return(false);

   const double volume = CalculatePositionVolume(signal);
   if(volume < g_volumeMin - (g_volumeStep * 0.5))
     {
      Print(EA_NAME, ": Volume below minimum. Calculated volume ", DoubleToString(volume, 2));
      return(false);
     }

   bool result = false;
   string comment = (signal.orderType == ORDER_TYPE_BUY) ? "BOS-Buy" : "BOS-Sell";

   if(signal.orderType == ORDER_TYPE_BUY)
     {
      const double ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      result = g_trade.Buy(volume, _Symbol, ask, signal.stopLoss, signal.takeProfit, comment);
      if(result)
        {
         g_lastBullishSignalTime = signal.signalTime;
         g_lastBullishStructure  = signal.entryPrice;
        }
     }
   else if(signal.orderType == ORDER_TYPE_SELL)
     {
      const double bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      result = g_trade.Sell(volume, _Symbol, bid, signal.stopLoss, signal.takeProfit, comment);
      if(result)
        {
         g_lastBearishSignalTime = signal.signalTime;
         g_lastBearishStructure  = signal.entryPrice;
        }
     }

   if(result)
     {
      Print(EA_NAME, ": Placed ", comment, " volume ", DoubleToString(volume, 2),
            " SL ", DoubleToString(signal.stopLoss, _Digits),
            " TP ", DoubleToString(signal.takeProfit, _Digits));
     }
   else
     {
      Print(EA_NAME, ": Trade placement failed. Retcode ", g_trade.ResultRetcode(),
            " / ", g_trade.ResultRetcodeDescription());
     }

   return(result);
  }

//+------------------------------------------------------------------+
//| Maintain daily state and reset                                   |
//+------------------------------------------------------------------+
void UpdateDailyState()
  {
   const datetime now = TimeCurrent();
   const int dayKey   = BuildDayKey(now);

   if(dayKey != g_dayKey)
     {
      g_dayKey           = dayKey;
      g_dayOpeningEquity = AccountEquity();
      g_tradingPaused    = false;
      g_pauseStartTime   = 0;
      ArrayFree(g_positionStates);
      Print(EA_NAME, ": Daily state reset. Opening equity ", DoubleToString(g_dayOpeningEquity, 2));
     }
  }

//+------------------------------------------------------------------+
//| Manage all open positions                                        |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
  for(int i = PositionsTotal() - 1; i >= 0; --i)
    {
     if(!PositionSelectByIndex(i))
        continue;
     const string symbol = PositionGetString(POSITION_SYMBOL);
     if(symbol != _Symbol)
        continue;
     const ulong ticket = PositionGetInteger(POSITION_TICKET);
     ManagePosition(ticket);
    }
  }

//+------------------------------------------------------------------+
//| Manage individual position                                       |
//+------------------------------------------------------------------+
void ManagePosition(const ulong ticket)
  {
   if(!g_position.SelectByTicket(ticket))
      return;

   const double entryPrice = g_position.PriceOpen();
   double stopLoss         = g_position.StopLoss();
   double takeProfit       = g_position.TakeProfit();
   const double volume     = g_position.Volume();

   if(volume <= 0.0)
      return;

   const ENUM_POSITION_TYPE type = g_position.PositionType();
   const double currentPrice = (type == POSITION_TYPE_BUY) ?
      SymbolInfoDouble(_Symbol, SYMBOL_BID) :
      SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   const double stopDistance = (type == POSITION_TYPE_BUY) ?
      entryPrice - stopLoss :
      stopLoss - entryPrice;

   if(stopDistance <= 0.0)
      return;

   double rMultiple = (type == POSITION_TYPE_BUY) ?
      (currentPrice - entryPrice) / stopDistance :
      (entryPrice - currentPrice) / stopDistance;

   const int idx = EnsurePositionState(ticket);
   if(idx < 0)
      return;

   // Break-even management
   if(!g_positionStates[idx].breakEvenSet &&
      InpBreakEvenRR > 0.0 &&
      rMultiple >= InpBreakEvenRR)
     {
      double newSL = (type == POSITION_TYPE_BUY) ?
         entryPrice + InpBreakEvenOffsetPoints * g_point :
         entryPrice - InpBreakEvenOffsetPoints * g_point;
      newSL = NormalizeDouble(newSL, _Digits);

      if((type == POSITION_TYPE_BUY && (stopLoss < newSL)) ||
         (type == POSITION_TYPE_SELL && (stopLoss > newSL)))
        {
         if(g_trade.PositionModify(_Symbol, newSL, takeProfit))
           {
            g_positionStates[idx].breakEvenSet = true;
            Print(EA_NAME, ": Ticket ", ticket, " moved to break-even.");
            stopLoss = newSL;
           }
        }
     }

   // Partial close
   if(!g_positionStates[idx].partialCompleted &&
      InpPartialClosePercent > 0.0 &&
      rMultiple >= InpPartialCloseRR)
     {
      const double closeVolume = NormalizeVolume(volume * InpPartialClosePercent / 100.0);
      if(closeVolume >= g_volumeMin && closeVolume < volume)
        {
         if(g_trade.PositionClosePartial(_Symbol, closeVolume))
           {
            g_positionStates[idx].partialCompleted = true;
            Print(EA_NAME, ": Ticket ", ticket, " partial close executed.");
           }
        }
     }

   // ATR trailing
   if(InpATRTrailMultiplier > 0.0 &&
      rMultiple >= InpTrailStartRR &&
      ArraySize(g_atrBuffer) > 1)
     {
      const double atr = g_atrBuffer[1];
      if(atr > 0.0)
        {
         double newSL = (type == POSITION_TYPE_BUY) ?
            currentPrice - atr * InpATRTrailMultiplier :
            currentPrice + atr * InpATRTrailMultiplier;

         if((type == POSITION_TYPE_BUY && newSL > stopLoss) ||
            (type == POSITION_TYPE_SELL && newSL < stopLoss))
           {
            newSL = NormalizeDouble(newSL, _Digits);
            if(g_trade.PositionModify(_Symbol, newSL, takeProfit))
               stopLoss = newSL;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Ensure position state record exists                              |
//+------------------------------------------------------------------+
int EnsurePositionState(const ulong ticket)
  {
   const int total = ArraySize(g_positionStates);
   for(int i = 0; i < total; ++i)
     {
      if(g_positionStates[i].ticket == ticket)
         return(i);
     }

   const int newSize = total + 1;
   ArrayResize(g_positionStates, newSize);

   g_positionStates[total].ticket           = ticket;
   g_positionStates[total].breakEvenSet     = false;
   g_positionStates[total].partialCompleted = false;

   return(total);
  }

//+------------------------------------------------------------------+
//| Sum open positions risk percentage                               |
//+------------------------------------------------------------------+
double CalculateOpenPositionsRiskPct()
  {
   double totalRisk = 0.0;
   const double equity = AccountEquity();
   if(equity <= 0.0)
      return(0.0);

  for(int i = PositionsTotal() - 1; i >= 0; --i)
    {
     if(!PositionSelectByIndex(i))
        continue;
     if(PositionGetString(POSITION_SYMBOL) != _Symbol)
        continue;

     const double volume      = PositionGetDouble(POSITION_VOLUME);
     const double stopLoss    = PositionGetDouble(POSITION_SL);
     const double entryPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
     const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

     if(stopLoss <= 0.0 || volume <= 0.0)
        continue;

     double distance = (type == POSITION_TYPE_BUY) ?
        entryPrice - stopLoss :
        stopLoss - entryPrice;

     if(distance <= 0.0)
        continue;

     const double ticks = distance / g_tickSize;
     const double riskValue = ticks * g_tickValue * volume;
     totalRisk += (riskValue / equity) * 100.0;
    }

   return(totalRisk);
  }

//+------------------------------------------------------------------+
//| Session filter                                                    |
//+------------------------------------------------------------------+
bool IsWithinSessions()
  {
   if(!InpUseSessionFilter)
      return(true);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int hour = dt.hour;

   const bool inLondon = (hour >= InpLondonSessionStart && hour < InpLondonSessionEnd);
   const bool inNY     = (hour >= InpNYSessionStart && hour < InpNYSessionEnd);

   return(inLondon || inNY);
  }

//+------------------------------------------------------------------+
//| Update HUD                                                        |
//+------------------------------------------------------------------+
void UpdateHUD()
  {
   if(!InpShowHUD)
     {
      ObjectDelete(0, HUD_OBJECT_NAME);
      return;
     }

   if(!ObjectFind(0, HUD_OBJECT_NAME))
     {
      ObjectCreate(0, HUD_OBJECT_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_COLOR, InpHUDTextColor);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_CORNER, InpHUDCorner);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_XDISTANCE, InpHUDXDistance);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_YDISTANCE, InpHUDYDistance);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_BGCOLOR, InpHUDBackgroundColor);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_BORDER_COLOR, InpHUDBorderColor);
      ObjectSetInteger(0, HUD_OBJECT_NAME, OBJPROP_FONTSIZE, 9);
      ObjectSetString(0, HUD_OBJECT_NAME, OBJPROP_FONT, "Segoe UI");
     }

   const double spreadPoints = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   const double dailyPnL     = AccountEquity() - g_dayOpeningEquity;
   const double openRisk     = CalculateOpenPositionsRiskPct();
   const string trendText    = TrendToString(g_currentTrend);

   string tradeState = "Active";
   if(g_tradingPaused)
     {
      const int minutesLeft = (int)MathMax(0.0, (InpLossPauseMinutes * 60.0 - (TimeCurrent() - g_pauseStartTime)) / 60.0);
      tradeState = "Paused (" + IntegerToString(minutesLeft) + "m)";
     }

   string text = EA_NAME + "\n";
   text += "Trend: " + trendText + "\n";
   text += "Daily P/L: " + FormatDouble(dailyPnL, 2) + " USD\n";
   text += "Open Risk: " + FormatDouble(openRisk, 2) + "% / Limit " + FormatDouble(InpMaxConcurrentRisk, 2) + "%\n";
   text += "Spread: " + FormatDouble(spreadPoints, 1) + " pts | "
           "Risk/Trade: " + FormatDouble(InpRiskPerTrade, 2) + "%\n";
   text += "Session Filter: " + (InpUseSessionFilter ? "On" : "Off") + " | Trading: " + tradeState + "\n";
   text += "Last Bull BOS: " + TimeToString(g_lastBullishSignalTime, TIME_DATE|TIME_MINUTES) + "\n";
   text += "Last Bear BOS: " + TimeToString(g_lastBearishSignalTime, TIME_DATE|TIME_MINUTES);

   ObjectSetString(0, HUD_OBJECT_NAME, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Draw structure levels                                             |
//+------------------------------------------------------------------+
void DrawStructureLevels(const MarketStructureInfo &info)
  {
   if(!InpDrawStructureLevels)
     {
      RemoveStructureObjects();
      return;
     }

   const string highName = OBJ_PREFIX + "_LastHigh";
   const string lowName  = OBJ_PREFIX + "_LastLow";

   if(!ObjectFind(0, highName))
      ObjectCreate(0, highName, OBJ_HLINE, 0, 0, info.lastSwingHigh);
   if(!ObjectFind(0, lowName))
      ObjectCreate(0, lowName, OBJ_HLINE, 0, 0, info.lastSwingLow);

   ObjectSetDouble(0, highName, OBJPROP_PRICE, info.lastSwingHigh);
   ObjectSetInteger(0, highName, OBJPROP_COLOR, clrLime);
   ObjectSetInteger(0, highName, OBJPROP_STYLE, STYLE_DOT);

   ObjectSetDouble(0, lowName, OBJPROP_PRICE, info.lastSwingLow);
   ObjectSetInteger(0, lowName, OBJPROP_COLOR, clrOrange);
   ObjectSetInteger(0, lowName, OBJPROP_STYLE, STYLE_DOT);
  }

//+------------------------------------------------------------------+
//| Remove structure drawings                                        |
//+------------------------------------------------------------------+
void RemoveStructureObjects()
  {
   ObjectDelete(0, OBJ_PREFIX + "_LastHigh");
   ObjectDelete(0, OBJ_PREFIX + "_LastLow");
  }

//+------------------------------------------------------------------+
//| Trend text representation                                        |
//+------------------------------------------------------------------+
string TrendToString(const TrendDirection trend)
  {
   switch(trend)
     {
      case TREND_BULLISH:
         return("Bullish");
      case TREND_BEARISH:
         return("Bearish");
      default:
         return("Neutral");
     }
  }

//+------------------------------------------------------------------+
//| Format double helper                                             |
//+------------------------------------------------------------------+
string FormatDouble(const double value, const int digits)
  {
   return(DoubleToString(value, digits));
  }

//+------------------------------------------------------------------+
//| Build integer day key                                            |
//+------------------------------------------------------------------+
int BuildDayKey(const datetime timeValue)
  {
   MqlDateTime dt;
   TimeToStruct(timeValue, dt);
   return(dt.year * 10000 + dt.mon * 100 + dt.day);
  }
