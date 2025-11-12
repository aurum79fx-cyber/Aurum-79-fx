#property copyright "OpenAI Assistant"
#property link      "https://openai.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

input string          InpSymbol                     = "XAUUSD";          // Trading symbol (leave empty for chart symbol)
input ENUM_TIMEFRAMES InpSignalTimeframe            = PERIOD_M5;          // Signal timeframe
input ulong           InpMagic                      = 556001;             // Expert magic number
input double          InpRiskPercent                = 0.60;               // Risk per trade (% of equity)
input double          InpMaxSpreadPoints            = 45;                 // Maximum spread in points
input int             InpMaxTradesPerDay            = 6;                  // Maximum trades per day
input int             InpCooldownMinutes            = 15;                 // Cooldown between trades (minutes)
input int             InpSessionStart               = 700;                // Session start (HHmm)
input int             InpSessionEnd                 = 2200;               // Session end (HHmm)
input bool            InpAllowBuy                   = true;               // Allow long trades
input bool            InpAllowSell                  = true;               // Allow short trades
input bool            InpLimitSameDirection         = true;               // Allow only one position per direction

input int             InpStructureLookback          = 60;                 // Bars to scan for structure
input int             InpStructureDepth             = 2;                  // Swing confirmation depth
input double          InpStructureBufferPoints      = 30;                 // Buffer beyond swing (points)
input int             InpImpulseBodyPoints          = 120;                // Minimum body size to qualify as impulse (points)
input int             InpImpulseRangePoints         = 180;                // Minimum total range for impulse candle (points)
input int             InpVolumeLookback             = 30;                 // Lookback for average tick volume
input double          InpVolumeMultiplier           = 1.60;               // Multiplier over average tick volume
input double          InpMinStopDistancePoints      = 180;                // Minimum stop distance (points)

input bool            InpUsePartialClose            = true;               // Enable partial TP
input double          InpPartialCloseRatio          = 0.50;               // Fraction to close at first target
input double          InpPartialTP_R                = 1.50;               // RR multiple for partial TP
input double          InpFinalTP_R                  = 3.00;               // RR multiple for final TP
input bool            InpUseBreakEven               = true;               // Shift SL to BE
input double          InpBreakEvenTrigger_R         = 1.00;               // RR to trigger break-even
input bool            InpUseTrailingATR             = true;               // Enable ATR trailing stop
input int             InpATRPeriod                  = 14;                 // ATR period
input double          InpATRMultiplier              = 1.50;               // ATR multiplier for trailing

input color           InpHudBackground              = clrBlack;           // HUD background
input color           InpHudText                    = clrGold;            // HUD text color
input int             InpHudCorner                  = CORNER_RIGHT_UPPER; // HUD corner
input int             InpHudXOffset                 = 20;                 // HUD X offset (pixels)
input int             InpHudYOffset                 = 20;                 // HUD Y offset (pixels)

struct SwingPoint
  {
   int               shift;
   double            price;
   datetime          time;
  };

CTrade              trade;
datetime            g_lastSignalBarTime = 0;
datetime            g_lastTradeTime = 0;
datetime            g_lastDay = 0;
int                 g_tradesToday = 0;
int                 g_lastSignalDirection = 0;
double              g_lastRiskPoints = 0.0;
double              g_lastATR = 0.0;
int                 g_atrHandle = INVALID_HANDLE;
string              g_symbol;

int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingByDefault();
   g_symbol = (InpSymbol == "" ? _Symbol : InpSymbol);

   if(!SymbolInfoInteger(g_symbol, SYMBOL_SELECT))
     {
      if(!SymbolSelect(g_symbol, true))
        {
         Print("Failed to select symbol: ", g_symbol);
         return(INIT_FAILED);
        }
     }

   g_atrHandle = iATR(g_symbol, InpSignalTimeframe, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle.");
      return(INIT_FAILED);
     }

   ResetDailyCounters();
   SetupHud();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   DestroyHud();
  }

void OnTick()
  {
   if(SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      return;

   datetime currentDay = GetTradingDay(TimeCurrent());
   if(currentDay != g_lastDay)
      ResetDailyCounters();

   UpdateHud();
   ManageOpenPositions();

   if(!IsNewSignalBar())
      return;

   if(!IsTradingSession(TimeCurrent()))
      return;

   if(!SpreadWithinLimits())
      return;

   if(g_tradesToday >= InpMaxTradesPerDay)
      return;

   if(TimeCurrent() - g_lastTradeTime < InpCooldownMinutes * 60)
      return;

   int direction = 0;
   double entryPrice = 0.0, stopLoss = 0.0, tpFinal = 0.0;
   SwingPoint swingRef = {0};
   if(!EvaluateSignal(direction, entryPrice, stopLoss, tpFinal, swingRef))
      return;

   if(direction > 0 && !InpAllowBuy)
      return;
   if(direction < 0 && !InpAllowSell)
      return;

   if(InpLimitSameDirection && HasOpenPosition(direction))
      return;

   double stopPoints = MathAbs(entryPrice - stopLoss) / _Point;
   if(stopPoints < InpMinStopDistancePoints)
      return;

   double lotSize = CalculateRiskLot(stopLoss, direction);
   if(lotSize <= 0.0)
      return;

   bool result = false;
   if(direction > 0)
      result = trade.Buy(lotSize, g_symbol, 0.0, stopLoss, tpFinal);
   else
      result = trade.Sell(lotSize, g_symbol, 0.0, stopLoss, tpFinal);

   if(result)
     {
      g_tradesToday++;
      g_lastTradeTime = TimeCurrent();
      g_lastSignalDirection = direction;
      g_lastRiskPoints = stopPoints;
      PrintFormat("Trade opened %s | Lots: %.2f | SL: %.2f | TP: %.2f",
                  (direction > 0 ? "BUY" : "SELL"), lotSize, stopLoss, tpFinal);
     }
   else
     {
      Print("Order send failed: ", GetLastError());
     }
  }

bool EvaluateSignal(int &direction, double &entryPrice, double &stopLoss, double &tpFinal, SwingPoint &swingRef)
  {
   direction = 0;
   entryPrice = 0.0;
   stopLoss = 0.0;
   tpFinal = 0.0;

   SwingPoint swingHigh = {0}, swingLow = {0};
   if(!FindRecentSwing(true, swingHigh) || !FindRecentSwing(false, swingLow))
      return(false);

   if(swingHigh.shift <= 0 || swingLow.shift <= 0)
      return(false);

   double close1 = iClose(g_symbol, InpSignalTimeframe, 1);
   double open1  = iOpen(g_symbol, InpSignalTimeframe, 1);
   double high1  = iHigh(g_symbol, InpSignalTimeframe, 1);
   double low1   = iLow(g_symbol, InpSignalTimeframe, 1);
   long   vol1   = (long)iVolume(g_symbol, InpSignalTimeframe, 1);

   if(!ImpulseFilter(open1, close1, high1, low1, vol1))
      return(false);

   double buffer = InpStructureBufferPoints * _Point;

   if(close1 > swingHigh.price + buffer && open1 < swingHigh.price && swingLow.shift < swingHigh.shift)
     {
      direction = 1;
      swingRef = swingLow;
     }
   else
   if(close1 < swingLow.price - buffer && open1 > swingLow.price && swingHigh.shift < swingLow.shift)
     {
      direction = -1;
      swingRef = swingHigh;
     }
   else
     {
      return(false);
     }

   double price = (direction > 0 ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) : SymbolInfoDouble(g_symbol, SYMBOL_BID));
   if(price <= 0.0)
      return(false);

   entryPrice = price;
   stopLoss   = (direction > 0 ? swingRef.price - buffer : swingRef.price + buffer);

   double stopPoints = MathAbs(entryPrice - stopLoss) / _Point;
   if(stopPoints < InpMinStopDistancePoints)
      return(false);

   tpFinal = (direction > 0 ? entryPrice + stopPoints * _Point * InpFinalTP_R
                            : entryPrice - stopPoints * _Point * InpFinalTP_R);

   return(true);
  }

bool FindRecentSwing(const bool high, SwingPoint &swing)
  {
   swing.shift = -1;
   int bars = Bars(g_symbol, InpSignalTimeframe);
   if(bars <= InpStructureLookback + InpStructureDepth + 5)
      return(false);

   for(int shift = InpStructureDepth; shift <= InpStructureLookback + InpStructureDepth; ++shift)
     {
      if(high && IsSwingHigh(shift))
        {
         swing.shift = shift;
         swing.price = iHigh(g_symbol, InpSignalTimeframe, shift);
         swing.time  = iTime(g_symbol, InpSignalTimeframe, shift);
         break;
        }
      if(!high && IsSwingLow(shift))
        {
         swing.shift = shift;
         swing.price = iLow(g_symbol, InpSignalTimeframe, shift);
         swing.time  = iTime(g_symbol, InpSignalTimeframe, shift);
         break;
        }
     }
   return(swing.shift != -1);
  }

bool IsSwingHigh(const int shift)
  {
   double ref = iHigh(g_symbol, InpSignalTimeframe, shift);
   if(ref == 0.0)
      return(false);
   for(int depth = 1; depth <= InpStructureDepth; ++depth)
     {
      int backShift = shift - depth;
      int forwardShift = shift + depth;
      if(backShift < 1)
         return(false);
      if(forwardShift >= Bars(g_symbol, InpSignalTimeframe))
         return(false);
      if(iHigh(g_symbol, InpSignalTimeframe, shift + depth) >= ref)
         return(false);
      if(iHigh(g_symbol, InpSignalTimeframe, shift - depth) > ref)
         return(false);
     }
   return(true);
  }

bool IsSwingLow(const int shift)
  {
   double ref = iLow(g_symbol, InpSignalTimeframe, shift);
   if(ref == 0.0)
      return(false);
   for(int depth = 1; depth <= InpStructureDepth; ++depth)
     {
      int backShift = shift - depth;
      int forwardShift = shift + depth;
      if(backShift < 1)
         return(false);
      if(forwardShift >= Bars(g_symbol, InpSignalTimeframe))
         return(false);
      if(iLow(g_symbol, InpSignalTimeframe, shift + depth) <= ref)
         return(false);
      if(iLow(g_symbol, InpSignalTimeframe, shift - depth) < ref)
         return(false);
     }
   return(true);
  }

bool ImpulseFilter(const double open, const double close, const double high, const double low, const long volume)
  {
   double bodyPoints = MathAbs(close - open) / _Point;
   double rangePoints = MathAbs(high - low) / _Point;
   if(bodyPoints < InpImpulseBodyPoints || rangePoints < InpImpulseRangePoints)
      return(false);

   double avgVolume = AverageVolume(InpVolumeLookback);
   if(avgVolume <= 0.0)
      return(false);

   if(volume < avgVolume * InpVolumeMultiplier)
      return(false);

   return(true);
  }

double AverageVolume(const int lookback)
  {
   if(lookback <= 0)
      return(0.0);

   long total = 0;
   int counted = 0;
   for(int shift = 2; shift < lookback + 2; ++shift)
     {
      long vol = (long)iVolume(g_symbol, InpSignalTimeframe, shift);
      if(vol > 0)
        {
         total += vol;
         counted++;
        }
     }
   if(counted == 0)
      return(0.0);
   return((double)total / (double)counted);
  }

double CalculateRiskLot(const double stopLoss, const int direction)
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent / 100.0);
   if(riskMoney <= 0.0)
      return(0.0);

   double price = (direction > 0 ? SymbolInfoDouble(g_symbol, SYMBOL_ASK) : SymbolInfoDouble(g_symbol, SYMBOL_BID));
   if(price <= 0.0)
      return(0.0);

   double stopDistance = MathAbs(price - stopLoss);
   if(stopDistance <= 0.0)
      return(0.0);

   double tickValue = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double contractSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0 || contractSize <= 0.0)
      return(0.0);

   double pointValue = tickValue * (_Point / tickSize);
   double moneyPerLot = (stopDistance / _Point) * pointValue;
   if(moneyPerLot <= 0.0)
      return(0.0);

   double volume = riskMoney / moneyPerLot;

   double minLot   = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double lotStep  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   volume = MathMax(minLot, MathMin(volume, maxLot));
   volume = NormalizeLot(volume, lotStep);

   return(volume);
  }

double NormalizeLot(double volume, double step)
  {
   if(step <= 0.0)
      return(volume);
   return(MathFloor(volume / step) * step);
  }

bool HasOpenPosition(const int direction)
  {
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != g_symbol)
         continue;
      long type = PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && type == POSITION_TYPE_BUY)
         return(true);
      if(direction < 0 && type == POSITION_TYPE_SELL)
         return(true);
     }
   return(false);
  }

void ManageOpenPositions()
  {
   UpdateAtr();

   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol)
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double initialVolume = PositionGetDouble(POSITION_VOLUME_INITIAL);

      if(entry <= 0.0 || volume <= 0.0)
         continue;

      double currentPrice = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(g_symbol, SYMBOL_BID)
                                                       : SymbolInfoDouble(g_symbol, SYMBOL_ASK));
      double stopPoints = MathAbs(entry - sl) / _Point;
      if(stopPoints <= 0.0)
         continue;

      double rrPricePartial = (type == POSITION_TYPE_BUY ? entry + stopPoints * _Point * InpPartialTP_R
                                                         : entry - stopPoints * _Point * InpPartialTP_R);
      double rrPriceBE      = (type == POSITION_TYPE_BUY ? entry + stopPoints * _Point * InpBreakEvenTrigger_R
                                                         : entry - stopPoints * _Point * InpBreakEvenTrigger_R);

      if(InpUsePartialClose && volume == initialVolume)
        {
         if((type == POSITION_TYPE_BUY && currentPrice >= rrPricePartial) ||
            (type == POSITION_TYPE_SELL && currentPrice <= rrPricePartial))
           {
            double closeVolume = NormalizeLot(initialVolume * InpPartialCloseRatio,
                                              SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP));
            if(closeVolume > 0.0 && closeVolume < volume)
               trade.PositionClosePartial(ticket, closeVolume);
           }
        }

      if(InpUseBreakEven)
        {
         bool beReached = (type == POSITION_TYPE_BUY ? currentPrice >= rrPriceBE
                                                     : currentPrice <= rrPriceBE);
         bool beSet = (type == POSITION_TYPE_BUY ? sl >= entry : sl <= entry);
         if(beReached && !beSet)
           {
            double newSL = entry + (type == POSITION_TYPE_BUY ? 1 : -1) * (_Point * InpStructureBufferPoints);
            trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
           }
        }

      if(InpUseTrailingATR && g_lastATR > 0.0)
        {
         double trailDistance = g_lastATR * InpATRMultiplier;
         double desiredSL = (type == POSITION_TYPE_BUY ? currentPrice - trailDistance
                                                       : currentPrice + trailDistance);

         bool adjust = false;
         if(type == POSITION_TYPE_BUY && desiredSL > sl)
            adjust = true;
         if(type == POSITION_TYPE_SELL && desiredSL < sl)
            adjust = true;

         if(adjust)
            trade.PositionModify(ticket, desiredSL, PositionGetDouble(POSITION_TP));
        }
     }
  }

void UpdateAtr()
  {
   if(g_atrHandle == INVALID_HANDLE)
      return;

   double buffer[3];
   if(CopyBuffer(g_atrHandle, 0, 1, 3, buffer) > 0)
      g_lastATR = buffer[0];
  }

bool IsNewSignalBar()
  {
   datetime time1 = iTime(g_symbol, InpSignalTimeframe, 1);
   if(time1 == 0)
      return(false);

   if(time1 == g_lastSignalBarTime)
      return(false);

   g_lastSignalBarTime = time1;
   return(true);
  }

bool SpreadWithinLimits()
  {
   double spread = (SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID)) / _Point;
   return(spread <= InpMaxSpreadPoints);
  }

bool IsTradingSession(datetime t)
  {
   int hm = TimeHour(t) * 100 + TimeMinute(t);
   if(InpSessionStart <= InpSessionEnd)
      return(hm >= InpSessionStart && hm <= InpSessionEnd);
   return(hm >= InpSessionStart || hm <= InpSessionEnd);
  }

datetime GetTradingDay(datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return(StructToTime(dt));
  }

void ResetDailyCounters()
  {
   g_tradesToday = 0;
   g_lastDay = GetTradingDay(TimeCurrent());
  }

void SetupHud()
  {
   string panel = HudPanelName();
   if(ObjectFind(0, panel) != -1)
      return;

   ObjectCreate(0, panel, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, panel, OBJPROP_CORNER, InpHudCorner);
   ObjectSetInteger(0, panel, OBJPROP_XDISTANCE, InpHudXOffset);
   ObjectSetInteger(0, panel, OBJPROP_YDISTANCE, InpHudYOffset);
   ObjectSetInteger(0, panel, OBJPROP_BGCOLOR, InpHudBackground);
   ObjectSetInteger(0, panel, OBJPROP_COLOR, InpHudBackground);
   ObjectSetInteger(0, panel, OBJPROP_ALPHABLEND, 160);
   ObjectSetInteger(0, panel, OBJPROP_WIDTH, 260);
   ObjectSetInteger(0, panel, OBJPROP_HEIGHT, 150);

   string label = HudTextName();
   ObjectCreate(0, label, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, label, OBJPROP_CORNER, InpHudCorner);
   ObjectSetInteger(0, label, OBJPROP_XDISTANCE, InpHudXOffset + 10);
   ObjectSetInteger(0, label, OBJPROP_YDISTANCE, InpHudYOffset + 10);
   ObjectSetInteger(0, label, OBJPROP_COLOR, InpHudText);
   ObjectSetInteger(0, label, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, label, OBJPROP_FONT, "Arial");
   ObjectSetString(0, label, OBJPROP_TEXT, "");
  }

void UpdateHud()
  {
   string label = HudTextName();
   if(ObjectFind(0, label) == -1)
      SetupHud();

   double spread = (SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID)) / _Point;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   string bias = "Neutral";
   if(g_lastSignalDirection > 0)
      bias = "Bullish BOS";
   else if(g_lastSignalDirection < 0)
      bias = "Bearish BOS";

   string hudText;
   hudText  = "XAUUSD BOS EA\n";
   hudText += "Equity: " + DoubleToString(equity, 2) + "\n";
   hudText += "Balance: " + DoubleToString(balance, 2) + "\n";
   hudText += "Spread (pts): " + DoubleToString(spread, 1) + "\n";
   hudText += "Trades today: " + IntegerToString(g_tradesToday) + " / " + IntegerToString(InpMaxTradesPerDay) + "\n";
   hudText += "Risk per trade: " + DoubleToString(InpRiskPercent, 2) + "%\n";
   hudText += "Last risk (pts): " + DoubleToString(g_lastRiskPoints, 1) + "\n";
   hudText += "ATR(" + IntegerToString(InpATRPeriod) + "): " + DoubleToString(g_lastATR, _Digits) + "\n";
   hudText += "Bias: " + bias + "\n";

   ObjectSetString(0, label, OBJPROP_TEXT, hudText);
  }

void DestroyHud()
  {
   ObjectDelete(0, HudPanelName());
   ObjectDelete(0, HudTextName());
  }

string HudPanelName()
  {
   return("BOS_EA_PANEL");
  }

string HudTextName()
  {
   return("BOS_EA_TEXT");
  }
