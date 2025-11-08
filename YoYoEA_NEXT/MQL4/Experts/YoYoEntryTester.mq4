#property strict
#property version   "1.24"
#property description "Entry evaluation EA for MA, RSI, CCI, and MACD strategies."

//--- input parameters
input string InpProfileName     = "Default";
input double InpLots            = 0.10;
input int    InpStopLossPips    = 50;
input int    InpTakeProfitPips  = 50;
input int    InpSlippage        = 3;

input bool   InpEnableMA        = true;
input bool   InpEnableCCI       = true;
input bool   InpEnableRSI       = true;
input bool   InpEnableMACD      = true;
input bool   InpEnableStoch     = true;
input bool   InpUseATRStops     = false;
input bool   InpUseAtrBandConfig = false;
input string InpAtrBandConfigFile = "";

input int    InpATRPeriod       = 14;

//--- indicator parameters (fixed as per requirements, exposed for fine tuning if needed)
input int    InpFastMAPeriod    = 14;
input int    InpSlowMAPeriod    = 200;

input int    InpRSIPeriod       = 14;
input double InpRSIBuyLevel     = 30.0;
input double InpRSISellLevel    = 70.0;

input int    InpCCIPeriod       = 14;
input double InpCCIUpperLevel   = 100.0;
input double InpCCILowerLevel   = -100.0;

input int    InpMACDFastEMA     = 12;
input int    InpMACDSlowEMA     = 26;
input int    InpMACDSignalSMA   = 9;

input int    InpStochKPeriod    = 14;
input int    InpStochDPeriod    = 3;
input int    InpStochSlowing    = 3;
input double InpStochBuyLevel   = 20.0;
input double InpStochSellLevel  = 80.0;

input double InpATRStopMultiplier      = 3.0;
input double InpATRTakeProfitMultiplier = 2.0;
input double InpMaxSpreadPips          = 0.0;
input bool   InpUseRiskBasedLots       = false;
input double InpRiskPercent            = 1.0;
input int    InpCooldownMinutes        = 0;
input int    InpLossStreakPause        = 0;
input int    InpLossPauseMinutes       = 0;
input bool   InpAllowOppositePositions = false;
input bool   InpUseTradingSessions     = false;
input int    InpSessionStartHour       = 0;
input int    InpSessionEndHour         = 24;
input bool   InpSessionSkipFriday      = false;
input int    InpFridayCutoffHour       = 21;
input bool   InpEnableBreakEven        = true;
input double InpBreakEvenAtrTrigger    = 1.6;
input int    InpBreakEvenOffsetPips    = 3;
input bool   InpEnableAtrTrailing      = true;
input double InpTrailingAtrTrigger     = 2.2;
input double InpTrailingAtrStep        = 1.0;
input int    InpTrailingMinStepPips    = 2;
input bool   InpEnableGlobalMultiPositions = false;
input int    InpMaxTotalPositions          = 0;
input int    InpMaxPositionsPerStrategy = 1;
input double InpMultiPositionEquityThreshold = 0.0;
input double InpLotReductionEquityThreshold  = 0.0;
input double InpLotReductionFactor           = 1.0;
input int    InpMagicPrefix                 = 10100;

//--- strategy meta definitions
enum StrategyIndex
  {
   STRAT_MA = 0,
   STRAT_RSI,
   STRAT_CCI,
   STRAT_MACD,
   STRAT_STOCH,
   STRAT_TOTAL
  };

struct StrategyState
  {
   string   name;
   string   comment;
   int      magic;
   bool     enabled;
   datetime lastBarTime;
   int      lastDirection; // 1 = buy, -1 = sell, 0 = none
   datetime lastTradeTime;
   int      lossStreak;
   datetime lossPauseUntil;
  };

StrategyState g_strategies[STRAT_TOTAL];
string        g_profileLabel;
string        g_resultLogFileName;
string        g_parameterLogFileName;
string        g_runId;
int           g_exitLoggedTickets[];
int           g_enabledStrategyCount = 0;
int           g_totalPositionCap     = 1;
bool          g_multiPositionActive  = false;
double        g_effectiveLots        = 0.0;

#define RESULT_LOG_COLUMNS 19

enum StopUpdateReason
  {
   STOP_UPDATE_NONE = 0,
   STOP_UPDATE_INITIAL,
   STOP_UPDATE_BREAK_EVEN,
   STOP_UPDATE_TRAILING
  };

struct TradeMetadata
  {
   int    ticket;
   double entryPrice;
   double entryAtr;
   double stopLoss;
   double takeProfit;
   int    direction;
   StopUpdateReason lastStopReason;
   bool   breakEvenEnabled;
   double breakEvenAtrTrigger;
   int    breakEvenOffsetPips;
   bool   trailingEnabled;
   double trailingAtrTrigger;
   double trailingAtrStep;
   int    trailingMinStepPips;
  };

TradeMetadata g_tradeMetadata[];

enum StopMode
  {
   STOP_MODE_GLOBAL = 0,
   STOP_MODE_ATR,
   STOP_MODE_PIPS
  };

enum TradeAttemptResult
  {
   TRADE_ATTEMPT_SKIPPED = 0,
   TRADE_ATTEMPT_PLACED,
   TRADE_ATTEMPT_CONSUMED
  };

struct StrategyBandSetting
  {
   bool     configured;
   bool     enabled;
   StopMode mode;
   double   atrStopMultiplier;
   double   atrTakeProfitMultiplier;
   int      stopLossPips;
   int      takeProfitPips;
   bool     breakEvenEnabled;
   bool     breakEvenEnabledSpecified;
   double   breakEvenAtrTrigger;
   int      breakEvenOffsetPips;
   bool     trailingEnabled;
   bool     trailingEnabledSpecified;
   double   trailingAtrTrigger;
   double   trailingAtrStep;
   int      trailingMinStepPips;
  };

struct BandConfig
  {
   double minAtr;
   double maxAtr;
   StrategyBandSetting strategySettings[STRAT_TOTAL];
  };

BandConfig g_bandConfigs[];
bool       g_bandConfigLoaded = false;
string     g_bandConfigPath   = "";
string     g_strategyCsvPrefixes[] = {"MA", "RSI", "CCI", "MACD", "STOCH"};
const int  kStrategyMagicOffsets[STRAT_TOTAL] = {1, 2, 3, 4, 5};
const int  kLegacyStrategyMagics[STRAT_TOTAL] = {10101, 10201, 10301, 10401, 10501};
const long kMaxIntValue = 2147483647;

//+------------------------------------------------------------------+
//| Utility: derive magic number for strategy                        |
//+------------------------------------------------------------------+
int GetStrategyMagic(const StrategyIndex index)
  {
   if(index < 0 || index >= STRAT_TOTAL)
      return(InpMagicPrefix);

   int offset = kStrategyMagicOffsets[index];
   return(InpMagicPrefix + offset);
  }

//+------------------------------------------------------------------+
//| Utility: get maximum configured magic offset                     |
//+------------------------------------------------------------------+
int GetMaximumMagicOffset()
  {
   int maxOffset = 0;
   for(int i = 0; i < STRAT_TOTAL; i++)
     {
      if(kStrategyMagicOffsets[i] > maxOffset)
         maxOffset = kStrategyMagicOffsets[i];
     }
   return(maxOffset);
  }

//+------------------------------------------------------------------+
//| Utility: sanitise profile name for file usage                    |
//+------------------------------------------------------------------+
string SanitiseProfileName(string profile)
  {
   profile = StringTrimLeft(StringTrimRight(profile));
   if(StringLen(profile) == 0)
      profile = "Default";

   string invalid = "\\/:*?\"<>|";
   for(int i = 0; i < StringLen(profile); i++)
     {
      int ch = StringGetChar(profile, i);
      for(int j = 0; j < StringLen(invalid); j++)
        {
         if(ch == StringGetChar(invalid, j))
           {
            StringSetChar(profile, i, '_');
            break;
           }
        }
     }
   return(profile);
  }

//+------------------------------------------------------------------+
//| Utility: build per-run identifier for logging                    |
//+------------------------------------------------------------------+
string BuildRunIdentifier()
  {
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   return(StringFormat("%04d%02d%02d_%02d%02d%02d",
                       dt.year,
                       dt.mon,
                       dt.day,
                       dt.hour,
                       dt.min,
                       dt.sec));
  }

//+------------------------------------------------------------------+
//| Utility: calculate pip size for current symbol                   |
//+------------------------------------------------------------------+
double PipSize()
  {
   double point  = MarketInfo(Symbol(), MODE_POINT);
   int    digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   if(digits == 3 || digits == 5)
      return(point * 10.0);

   return(point);
  }

//+------------------------------------------------------------------+
//| Utility: derive decimal digits for a lot step                    |
//+------------------------------------------------------------------+
int StepToDigits(const double step)
  {
   if(step <= 0.0)
      return(2);

   double scaled = step;
   int    digits = 0;

   while(digits < 8 && MathAbs(MathRound(scaled) - scaled) > 1e-8)
     {
      scaled *= 10.0;
      digits++;
     }

   if(digits < 0)
      digits = 0;
   if(digits > 8)
      digits = 8;

   return(digits);
  }

//+------------------------------------------------------------------+
//| Utility: normalize requested lot size                           |
//+------------------------------------------------------------------+
double NormalizeLotSize(const double requestedLots)
  {
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);

   double normalized = requestedLots;

   if(normalized < 0.0)
      normalized = 0.0;

   if(maxLot > 0.0 && normalized > maxLot)
      normalized = maxLot;

   if(minLot > 0.0 && normalized < minLot)
      normalized = minLot;

   if(lotStep > 0.0)
     {
      int stepDigits = StepToDigits(lotStep);
      double rawSteps = (normalized - minLot) / lotStep;
      if(rawSteps < 0.0)
         rawSteps = 0.0;
      double steps = MathFloor(rawSteps + 1e-8);

      normalized = minLot + steps * lotStep;
      normalized = NormalizeDouble(normalized, stepDigits);
     }
   else
     {
      normalized = NormalizeDouble(normalized, 2);
     }

   if(minLot > 0.0 && normalized < minLot)
      normalized = NormalizeDouble(minLot, 2);
   if(maxLot > 0.0 && normalized > maxLot)
      normalized = NormalizeDouble(maxLot, 2);

   return(normalized);
  }

//+------------------------------------------------------------------+
//| Utility: calculate current spread in pips                        |
//+------------------------------------------------------------------+
double CurrentSpreadPips()
  {
   double spreadPoints = MarketInfo(Symbol(), MODE_SPREAD);
   double point        = MarketInfo(Symbol(), MODE_POINT);
   double pip          = PipSize();

   if(pip <= 0.0)
      return(0.0);

   double priceSpread = spreadPoints * point;
   return(priceSpread / pip);
  }

//+------------------------------------------------------------------+
//| Utility: risk-based lot calculation                              |
//+------------------------------------------------------------------+
double CalculateRiskBasedLots(const double stopDistancePips)
  {
   double distance = MathAbs(stopDistancePips);
   if(distance <= 0.0)
      return(0.0);

   double riskAmount = AccountEquity() * (InpRiskPercent / 100.0);
   if(riskAmount <= 0.0)
      return(0.0);

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double pip       = PipSize();

   if(tickSize <= 0.0 || pip <= 0.0 || tickValue <= 0.0)
      return(0.0);

   double pipValue = tickValue * (pip / tickSize);
   if(pipValue <= 0.0)
      return(0.0);

   double lots = riskAmount / (distance * pipValue);
   return(lots);
  }

//+------------------------------------------------------------------+
//| Utility: minimum allowed distance for stops                      |
//+------------------------------------------------------------------+
double GetMinimumStopDistance()
  {
   double point       = MarketInfo(Symbol(), MODE_POINT);
   double stopLevel   = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double freezeLevel = MarketInfo(Symbol(), MODE_FREEZELEVEL);

   double minDistance = MathMax(stopLevel, freezeLevel) * point;
   if(minDistance <= 0.0)
      minDistance = point;

   return(minDistance);
  }

//+------------------------------------------------------------------+
//| Utility: check if proposed stop improves current stop            |
//+------------------------------------------------------------------+
bool IsBetterStopLoss(const int orderType,
                      const double currentStop,
                      const double newStop)
  {
   if(newStop <= 0.0)
      return(false);

   if(currentStop <= 0.0)
      return(true);

   if(orderType == OP_BUY)
      return(newStop > currentStop + 1e-8);

   if(orderType == OP_SELL)
      return(newStop < currentStop - 1e-8);

   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: trading session guard                                   |
//+------------------------------------------------------------------+
bool IsTradingSessionOpen()
  {
   if(!InpUseTradingSessions)
      return(true);

   datetime now = TimeCurrent();
   int      hour = TimeHour(now);
   if(hour < InpSessionStartHour || hour >= InpSessionEndHour)
      return(false);

   int dow = TimeDayOfWeek(now);
   if(InpSessionSkipFriday && dow == 5)
     {
      if(hour >= InpFridayCutoffHour)
         return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Utility: strategy cooldown check                                 |
//+------------------------------------------------------------------+
bool IsStrategyInCooldown(const StrategyState &state)
  {
   datetime now = TimeCurrent();

   if(InpCooldownMinutes > 0 && state.lastTradeTime > 0)
     {
      datetime resumeTime = state.lastTradeTime + InpCooldownMinutes * 60;
      if(now < resumeTime)
         return(true);
     }

   if(InpLossStreakPause > 0 && state.lossStreak >= InpLossStreakPause)
     {
      if(InpLossPauseMinutes == 0)
         return(true);

      if(state.lossPauseUntil > 0 && now < state.lossPauseUntil)
         return(true);

      if(state.lossPauseUntil == 0 && InpLossPauseMinutes > 0)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: check for opposite open positions                       |
//+------------------------------------------------------------------+
bool HasOppositeStrategyPosition(StrategyIndex currentIndex,
                                 const int direction)
  {
   if(InpAllowOppositePositions || direction == 0)
      return(false);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      int orderType = OrderType();
      if(orderType != OP_BUY && orderType != OP_SELL)
         continue;

      int magic = OrderMagicNumber();
      int stratIndex = FindStrategyIndexByMagic(magic);
      if(stratIndex < 0 || stratIndex == currentIndex)
         continue;

      if(direction > 0 && orderType == OP_SELL)
         return(true);

      if(direction < 0 && orderType == OP_BUY)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: count open positions for a given magic number           |
//+------------------------------------------------------------------+
int CountOpenPositionsForMagic(const int magic)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int orderType = OrderType();
      if(orderType != OP_BUY && orderType != OP_SELL)
         continue;
      if(OrderMagicNumber() == magic)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Utility: count all strategy positions for current symbol         |
//+------------------------------------------------------------------+
int CountTotalOpenStrategyPositions()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;
      int orderType = OrderType();
      if(orderType != OP_BUY && orderType != OP_SELL)
         continue;
      int magic = OrderMagicNumber();
      if(FindStrategyIndexByMagic(magic) >= 0)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Utility: calculate configured total position cap                 |
//+------------------------------------------------------------------+
int CalculateConfiguredTotalPositionCap()
  {
   int baseCap = 1;

   if(InpEnableGlobalMultiPositions)
     {
      if(InpMaxTotalPositions > 0)
         baseCap = InpMaxTotalPositions;
      else
        {
         int activeStrategies = g_enabledStrategyCount;
         if(activeStrategies <= 0)
            activeStrategies = STRAT_TOTAL;
         baseCap = InpMaxPositionsPerStrategy * activeStrategies;
        }
     }

   if(baseCap < 1)
      baseCap = 1;

   return(baseCap);
  }

//+------------------------------------------------------------------+
//| Utility: current total position limit                            |
//+------------------------------------------------------------------+
int GetCurrentTotalPositionLimit()
  {
   if(!g_multiPositionActive)
      return(1);
   if(g_totalPositionCap <= 0)
      return(1);
   return(g_totalPositionCap);
  }

//+------------------------------------------------------------------+
//| Utility: refresh multi-position and lot controls                 |
//+------------------------------------------------------------------+
void UpdateDynamicPositionControls()
  {
   double equity = AccountEquity();

   int configuredCap = CalculateConfiguredTotalPositionCap();
   if(configuredCap < 1)
      configuredCap = 1;
   g_totalPositionCap = configuredCap;

   bool allowMulti = (InpEnableGlobalMultiPositions && configuredCap > 1);
   if(allowMulti && InpMultiPositionEquityThreshold > 0.0)
     {
      if(equity < InpMultiPositionEquityThreshold - 1e-8)
         allowMulti = false;
     }
   g_multiPositionActive = allowMulti;

   double lotFactor = InpLotReductionFactor;
   if(lotFactor <= 0.0)
      lotFactor = 1.0;
   if(lotFactor > 1.0)
      lotFactor = 1.0;

   double lots = InpLots;
   if(!InpUseRiskBasedLots && InpLotReductionEquityThreshold > 0.0 &&
      equity < InpLotReductionEquityThreshold - 1e-8)
     {
      lots = InpLots * lotFactor;
     }
   if(lots <= 0.0)
      lots = InpLots;
   g_effectiveLots = lots;
  }

//+------------------------------------------------------------------+
//| Utility: reset loss pause after cooldown                         |
//+------------------------------------------------------------------+
void RefreshLossPause(StrategyState &state)
  {
   if(state.lossPauseUntil > 0 && TimeCurrent() >= state.lossPauseUntil)
     {
      state.lossPauseUntil = 0;
      if(state.lossStreak >= InpLossStreakPause && InpLossPauseMinutes > 0)
         state.lossStreak = 0;
     }
  }

//+------------------------------------------------------------------+
//| Utility: check if strategy already has an open trade             |
//+------------------------------------------------------------------+
bool HasOpenPosition(const StrategyState &state)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() == Symbol() && OrderMagicNumber() == state.magic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: trim whitespace                                         |
//+------------------------------------------------------------------+
string TrimString(string value)
  {
   return(StringTrimLeft(StringTrimRight(value)));
  }

//+------------------------------------------------------------------+
//| Utility: strip UTF-8 BOM if present                               |
//+------------------------------------------------------------------+
string StripUtf8Bom(string value)
  {
   if(StringLen(value) == 0)
      return(value);

   if(StringGetChar(value, 0) == 0xFEFF)
      return(StringSubstr(value, 1));

   return(value);
  }

//+------------------------------------------------------------------+
//| Utility: uppercase helper                                        |
//+------------------------------------------------------------------+
string ToUpper(const string value)
  {
   string temp = value;
   StringToUpper(temp);
   return(temp);
  }

//+------------------------------------------------------------------+
//| Utility: compare header token with expected key                  |
//+------------------------------------------------------------------+
bool HeaderKeyEquals(const string header,
                     const string prefix,
                     const string suffix)
  {
   string combined = prefix + "_" + suffix;
   return(StringCompare(ToUpper(header), ToUpper(combined), false) == 0);
  }

//+------------------------------------------------------------------+
//| Utility: case-insensitive comparer                               |
//+------------------------------------------------------------------+
bool EqualsIgnoreCase(const string a, const string b)
  {
   return(StringCompare(a, b, false) == 0);
  }

//+------------------------------------------------------------------+
//| Utility: split CSV line preserving empty fields                  |
//+------------------------------------------------------------------+
int SplitCsvLine(const string line, string &columns[])
  {
   ArrayResize(columns, 0);

   int length = StringLen(line);
   int start  = 0;

   for(int i = 0; i <= length; i++)
     {
      bool atSeparator = (i < length && StringGetChar(line, i) == ',');
      bool atEnd       = (i == length);
      if(atSeparator || atEnd)
        {
         int tokenLength = i - start;
         string token = (tokenLength > 0 ? StringSubstr(line, start, tokenLength) : "");

         int index = ArraySize(columns);
         ArrayResize(columns, index + 1);
         columns[index] = token;

         start = i + 1;
        }
     }

   return(ArraySize(columns));
  }

//+------------------------------------------------------------------+
//| Utility: initialise band setting defaults                        |
//+------------------------------------------------------------------+
void InitStrategyBandSetting(StrategyBandSetting &setting)
  {
   setting.configured               = false;
   setting.enabled                  = true;
   setting.mode                     = STOP_MODE_GLOBAL;
   setting.atrStopMultiplier        = -1.0;
   setting.atrTakeProfitMultiplier  = -1.0;
   setting.stopLossPips             = -1;
   setting.takeProfitPips           = -1;
   setting.breakEvenEnabled         = false;
   setting.breakEvenEnabledSpecified = false;
   setting.breakEvenAtrTrigger      = -1.0;
   setting.breakEvenOffsetPips      = -1;
   setting.trailingEnabled          = false;
   setting.trailingEnabledSpecified = false;
   setting.trailingAtrTrigger       = -1.0;
   setting.trailingAtrStep          = -1.0;
   setting.trailingMinStepPips      = -1;
  }

//+------------------------------------------------------------------+
//| Utility: initialise band config                                  |
//+------------------------------------------------------------------+
void InitBandConfig(BandConfig &config)
  {
   config.minAtr = 0.0;
   config.maxAtr = DBL_MAX;
   for(int i = 0; i < STRAT_TOTAL; i++)
      InitStrategyBandSetting(config.strategySettings[i]);
  }

//+------------------------------------------------------------------+
//| Utility: parse boolean text                                      |
//+------------------------------------------------------------------+
bool ParseBoolValue(const string text, const bool defaultValue)
  {
   string trimmed = TrimString(text);
   if(StringLen(trimmed) == 0)
      return(defaultValue);

   if(trimmed == "1")
      return(true);
   if(trimmed == "0")
      return(false);

   if(EqualsIgnoreCase(trimmed, "TRUE") ||
      EqualsIgnoreCase(trimmed, "ON") ||
      EqualsIgnoreCase(trimmed, "YES"))
      return(true);

   if(EqualsIgnoreCase(trimmed, "FALSE") ||
      EqualsIgnoreCase(trimmed, "OFF") ||
      EqualsIgnoreCase(trimmed, "NO"))
      return(false);

   return(defaultValue);
  }

//+------------------------------------------------------------------+
//| Utility: parse double text                                       |
//+------------------------------------------------------------------+
bool ParseDoubleValue(const string text, double &value)
  {
   string trimmed = TrimString(text);
   trimmed = StripUtf8Bom(trimmed);
   if(StringLen(trimmed) == 0)
      return(false);

   if(!IsNumericString(trimmed))
      return(false);

   value = StrToDouble(trimmed);
   return(true);
  }

//+------------------------------------------------------------------+
//| Utility: parse integer text                                      |
//+------------------------------------------------------------------+
bool ParseIntValue(const string text, int &value)
  {
   string trimmed = TrimString(text);
   trimmed = StripUtf8Bom(trimmed);
   if(StringLen(trimmed) == 0)
      return(false);

   if(!IsIntegerString(trimmed))
      return(false);

   value = (int)StrToInteger(trimmed);
   return(true);
  }

//+------------------------------------------------------------------+
//| Utility: check if string is numeric                              |
//+------------------------------------------------------------------+
bool IsNumericString(const string text)
  {
   int len = StringLen(text);
   if(len == 0)
      return(false);

   bool hasDigit = false;
   int  dotCount = 0;

   for(int i = 0; i < len; i++)
     {
      int ch = StringGetChar(text, i);
      if(ch >= '0' && ch <= '9')
        {
         hasDigit = true;
         continue;
        }
      if(ch == '.')
        {
         dotCount++;
         if(dotCount > 1)
            return(false);
         continue;
        }
      if((ch == '+' || ch == '-') && i == 0)
         continue;
      return(false);
     }

   return(hasDigit);
  }

//+------------------------------------------------------------------+
//| Utility: check if string is integer numeric                       |
//+------------------------------------------------------------------+
bool IsIntegerString(const string text)
  {
   int len = StringLen(text);
   if(len == 0)
      return(false);

   bool hasDigit = false;
   for(int i = 0; i < len; i++)
     {
      int ch = StringGetChar(text, i);
      if(ch >= '0' && ch <= '9')
        {
         hasDigit = true;
         continue;
        }
      if((ch == '+' || ch == '-') && i == 0)
         continue;
      return(false);
     }

   return(hasDigit);
  }

//+------------------------------------------------------------------+
//| Utility: strip enclosing quotes                                  |
//+------------------------------------------------------------------+
string StripEnclosingQuotes(string value)
  {
   int len = StringLen(value);
   if(len >= 2)
     {
      int first = StringGetChar(value, 0);
      int last  = StringGetChar(value, len - 1);
      if((first == '"' && last == '"') || (first == '\'' && last == '\''))
         return(StringSubstr(value, 1, len - 2));
     }
   return(value);
  }

//+------------------------------------------------------------------+
//| Utility: parse stop mode text                                    |
//+------------------------------------------------------------------+
StopMode ParseStopModeValue(const string text)
  {
   string trimmed = TrimString(text);
   if(StringLen(trimmed) == 0)
      return(STOP_MODE_GLOBAL);

   if(EqualsIgnoreCase(trimmed, "ATR"))
      return(STOP_MODE_ATR);
   if(EqualsIgnoreCase(trimmed, "PIPS") || EqualsIgnoreCase(trimmed, "PIP"))
      return(STOP_MODE_PIPS);
   if(EqualsIgnoreCase(trimmed, "GLOBAL") || EqualsIgnoreCase(trimmed, "DEFAULT"))
      return(STOP_MODE_GLOBAL);

   return(STOP_MODE_GLOBAL);
  }

//+------------------------------------------------------------------+
//| Utility: convert boolean to text                                 |
//+------------------------------------------------------------------+
string BoolToText(const bool value)
  {
   return(value ? "true" : "false");
  }

//+------------------------------------------------------------------+
//| Utility: convert stop mode enum to text                          |
//+------------------------------------------------------------------+
string StopModeToText(const StopMode mode)
  {
   switch(mode)
     {
      case STOP_MODE_ATR:
         return("ATR");
      case STOP_MODE_PIPS:
         return("PIPS");
      case STOP_MODE_GLOBAL:
      default:
         return("GLOBAL");
     }
  }

//+------------------------------------------------------------------+
//| Log helper: dump single strategy band setting                    |
//+------------------------------------------------------------------+
void LogStrategyBandSetting(const string bandLabel,
                            const int stratIndex,
                            const StrategyBandSetting &setting)
  {
   string strategyName = g_strategies[stratIndex].name;
   if(StringLen(strategyName) == 0)
      strategyName = IntegerToString(stratIndex);

   if(!setting.configured)
     {
      PrintFormat("%s %s: configured=false", bandLabel, strategyName);
      return;
     }

   string message = bandLabel + " " + strategyName +
                    ": enabled=" + BoolToText(setting.enabled) +
                    " mode=" + StopModeToText(setting.mode);

   if(setting.mode == STOP_MODE_ATR)
     {
      message += " atrSL=" + DoubleToString(setting.atrStopMultiplier, 4) +
                 " atrTP=" + DoubleToString(setting.atrTakeProfitMultiplier, 4);
     }
   else if(setting.mode == STOP_MODE_PIPS)
     {
      message += " slPips=" + IntegerToString(setting.stopLossPips) +
                 " tpPips=" + IntegerToString(setting.takeProfitPips);
     }

   message += " BE=" + BoolToText(setting.breakEvenEnabled) +
              " beAtr=" + DoubleToString(setting.breakEvenAtrTrigger, 4) +
              " beOffset=" + IntegerToString(setting.breakEvenOffsetPips) +
              " Trail=" + BoolToText(setting.trailingEnabled) +
              " trailAtr=" + DoubleToString(setting.trailingAtrTrigger, 4) +
              " trailStep=" + DoubleToString(setting.trailingAtrStep, 4) +
              " trailMin=" + IntegerToString(setting.trailingMinStepPips);

   Print(message);
  }

//+------------------------------------------------------------------+
//| Log helper: dump all band configurations                         |
//+------------------------------------------------------------------+
void LogBandConfigurations()
  {
   if(!g_bandConfigLoaded)
     {
      Print("ATR band configuration not loaded.");
      return;
     }

   int total = ArraySize(g_bandConfigs);
   PrintFormat("ATR band configuration summary (rows=%d, file='%s')",
               total,
               g_bandConfigPath);

   for(int i = 0; i < total; i++)
     {
      BandConfig band = g_bandConfigs[i];
      string maxAtrText = (band.maxAtr == DBL_MAX
                           ? "infinity"
                           : DoubleToString(band.maxAtr, 6));
      PrintFormat("Band[%d]: minAtr=%s maxAtr=%s",
                  i,
                  DoubleToString(band.minAtr, 6),
                  maxAtrText);

      string bandLabel = "Band[" + IntegerToString(i) + "]";
      for(int strat = 0; strat < STRAT_TOTAL; strat++)
         LogStrategyBandSetting(bandLabel, strat, band.strategySettings[strat]);
     }
  }

//+------------------------------------------------------------------+
//| Utility: open parameter log handle (truncate or append)          |
//+------------------------------------------------------------------+
int OpenParameterLogFile(const bool append)
  {
   if(StringLen(g_parameterLogFileName) == 0)
      return(INVALID_HANDLE);

   int modeFlags = FILE_CSV | FILE_SHARE_READ;
   if(append)
      modeFlags |= FILE_READ | FILE_WRITE;
   else
      modeFlags |= FILE_WRITE;

   int handle = FileOpen(g_parameterLogFileName, modeFlags, ',');
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to open parameter log file ", g_parameterLogFileName,
            " (append=", BoolToText(append), ") . Error: ", GetLastError());
      return(INVALID_HANDLE);
     }

   if(append)
      FileSeek(handle, 0, SEEK_END);

   return(handle);
  }

//+------------------------------------------------------------------+
//| Log helper: write parameter snapshot to dedicated CSV            |
//+------------------------------------------------------------------+
void WriteParameterSnapshot(const string safeProfile)
  {
   int handle = OpenParameterLogFile(false);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "param", "value");
   FileWrite(handle, "section", "initial_inputs");
   FileWrite(handle, "run_id", g_runId);
   FileWrite(handle,
             "timestamp",
             TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   FileWrite(handle, "profile_label", g_profileLabel);
   FileWrite(handle, "profile_safe_name", safeProfile);
   FileWrite(handle, "profile_input_name", InpProfileName);
   FileWrite(handle, "lots", DoubleToString(InpLots, 2));
   FileWrite(handle, "stop_loss_pips", IntegerToString(InpStopLossPips));
   FileWrite(handle, "take_profit_pips", IntegerToString(InpTakeProfitPips));
   FileWrite(handle, "slippage", IntegerToString(InpSlippage));
   FileWrite(handle, "enable_ma", BoolToText(InpEnableMA));
   FileWrite(handle, "enable_cci", BoolToText(InpEnableCCI));
   FileWrite(handle, "enable_rsi", BoolToText(InpEnableRSI));
   FileWrite(handle, "enable_macd", BoolToText(InpEnableMACD));
   FileWrite(handle, "enable_stoch", BoolToText(InpEnableStoch));
   FileWrite(handle, "use_atr_stops", BoolToText(InpUseATRStops));
   FileWrite(handle, "use_atr_band_config", BoolToText(InpUseAtrBandConfig));
   FileWrite(handle, "atr_band_config_file", InpAtrBandConfigFile);
   FileWrite(handle, "atr_period", IntegerToString(InpATRPeriod));
   FileWrite(handle, "fast_ma_period", IntegerToString(InpFastMAPeriod));
   FileWrite(handle, "slow_ma_period", IntegerToString(InpSlowMAPeriod));
   FileWrite(handle, "rsi_period", IntegerToString(InpRSIPeriod));
   FileWrite(handle, "rsi_buy_level", DoubleToString(InpRSIBuyLevel, 4));
   FileWrite(handle, "rsi_sell_level", DoubleToString(InpRSISellLevel, 4));
   FileWrite(handle, "cci_period", IntegerToString(InpCCIPeriod));
   FileWrite(handle, "cci_upper_level", DoubleToString(InpCCIUpperLevel, 4));
   FileWrite(handle, "cci_lower_level", DoubleToString(InpCCILowerLevel, 4));
   FileWrite(handle, "macd_fast_ema", IntegerToString(InpMACDFastEMA));
   FileWrite(handle, "macd_slow_ema", IntegerToString(InpMACDSlowEMA));
   FileWrite(handle, "macd_signal_sma", IntegerToString(InpMACDSignalSMA));
   FileWrite(handle, "stoch_k_period", IntegerToString(InpStochKPeriod));
   FileWrite(handle, "stoch_d_period", IntegerToString(InpStochDPeriod));
   FileWrite(handle, "stoch_slowing", IntegerToString(InpStochSlowing));
   FileWrite(handle, "stoch_buy_level", DoubleToString(InpStochBuyLevel, 4));
   FileWrite(handle, "stoch_sell_level", DoubleToString(InpStochSellLevel, 4));
   FileWrite(handle, "atr_stop_multiplier", DoubleToString(InpATRStopMultiplier, 4));
   FileWrite(handle,
             "atr_takeprofit_multiplier",
             DoubleToString(InpATRTakeProfitMultiplier, 4));
   FileWrite(handle, "max_spread_pips", DoubleToString(InpMaxSpreadPips, 4));
   FileWrite(handle, "use_risk_based_lots", BoolToText(InpUseRiskBasedLots));
   FileWrite(handle, "risk_percent", DoubleToString(InpRiskPercent, 4));
   FileWrite(handle, "cooldown_minutes", IntegerToString(InpCooldownMinutes));
   FileWrite(handle, "loss_streak_pause", IntegerToString(InpLossStreakPause));
   FileWrite(handle, "loss_pause_minutes", IntegerToString(InpLossPauseMinutes));
   FileWrite(handle,
             "allow_opposite_positions",
             BoolToText(InpAllowOppositePositions));
   FileWrite(handle, "use_trading_sessions", BoolToText(InpUseTradingSessions));
   FileWrite(handle, "session_start_hour", IntegerToString(InpSessionStartHour));
   FileWrite(handle, "session_end_hour", IntegerToString(InpSessionEndHour));
   FileWrite(handle, "session_skip_friday", BoolToText(InpSessionSkipFriday));
   FileWrite(handle, "friday_cutoff_hour", IntegerToString(InpFridayCutoffHour));
   FileWrite(handle, "enable_break_even", BoolToText(InpEnableBreakEven));
   FileWrite(handle,
             "break_even_atr_trigger",
             DoubleToString(InpBreakEvenAtrTrigger, 4));
   FileWrite(handle,
             "break_even_offset_pips",
             IntegerToString(InpBreakEvenOffsetPips));
   FileWrite(handle, "enable_atr_trailing", BoolToText(InpEnableAtrTrailing));
   FileWrite(handle,
             "trailing_atr_trigger",
             DoubleToString(InpTrailingAtrTrigger, 4));
   FileWrite(handle, "trailing_atr_step", DoubleToString(InpTrailingAtrStep, 4));
   FileWrite(handle,
             "trailing_min_step_pips",
             IntegerToString(InpTrailingMinStepPips));
   FileWrite(handle,
             "enable_global_multi_positions",
             BoolToText(InpEnableGlobalMultiPositions));
   FileWrite(handle, "max_total_positions", IntegerToString(InpMaxTotalPositions));
   FileWrite(handle,
             "max_positions_per_strategy",
             IntegerToString(InpMaxPositionsPerStrategy));
   FileWrite(handle,
             "multi_position_equity_threshold",
             DoubleToString(InpMultiPositionEquityThreshold, 4));
   FileWrite(handle,
             "lot_reduction_equity_threshold",
             DoubleToString(InpLotReductionEquityThreshold, 4));
   FileWrite(handle, "lot_reduction_factor", DoubleToString(InpLotReductionFactor, 4));
   FileWrite(handle, "magic_prefix", IntegerToString(InpMagicPrefix));
   FileWrite(handle, "magic_ma", IntegerToString(GetStrategyMagic(STRAT_MA)));
   FileWrite(handle, "magic_rsi", IntegerToString(GetStrategyMagic(STRAT_RSI)));
   FileWrite(handle, "magic_cci", IntegerToString(GetStrategyMagic(STRAT_CCI)));
   FileWrite(handle, "magic_macd", IntegerToString(GetStrategyMagic(STRAT_MACD)));
   FileWrite(handle, "magic_stoch", IntegerToString(GetStrategyMagic(STRAT_STOCH)));

   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Log helper: dump loaded ATR band config into parameter log       |
//+------------------------------------------------------------------+
void AppendBandConfigSnapshot()
  {
   if(!g_bandConfigLoaded)
      return;

   int handle = OpenParameterLogFile(true);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "section", "atr_band_config");
   FileWrite(handle, "band_file", g_bandConfigPath);

   int totalBands = ArraySize(g_bandConfigs);
   FileWrite(handle, "band_count", IntegerToString(totalBands));

   for(int bandIndex = 0; bandIndex < totalBands; bandIndex++)
     {
      BandConfig band = g_bandConfigs[bandIndex];
      string bandPrefix = "band[" + IntegerToString(bandIndex) + "]";
      FileWrite(handle,
                bandPrefix + ".min_atr",
                DoubleToString(band.minAtr, 6));

      string maxAtrText = (band.maxAtr == DBL_MAX
                           ? "infinity"
                           : DoubleToString(band.maxAtr, 6));
      FileWrite(handle, bandPrefix + ".max_atr", maxAtrText);

      for(int strat = 0; strat < STRAT_TOTAL; strat++)
        {
         StrategyBandSetting setting = band.strategySettings[strat];
         string stratLabel = g_strategyCsvPrefixes[strat];
         string stratPrefix = bandPrefix + "." + stratLabel;

         FileWrite(handle,
                   stratPrefix + ".configured",
                   BoolToText(setting.configured));
         if(!setting.configured)
            continue;

         FileWrite(handle, stratPrefix + ".enabled", BoolToText(setting.enabled));
         FileWrite(handle, stratPrefix + ".mode", StopModeToText(setting.mode));

         FileWrite(handle,
                   stratPrefix + ".atr_stop_multiplier",
                   DoubleToString(setting.atrStopMultiplier, 6));
         FileWrite(handle,
                   stratPrefix + ".atr_takeprofit_multiplier",
                   DoubleToString(setting.atrTakeProfitMultiplier, 6));
         FileWrite(handle,
                   stratPrefix + ".stop_loss_pips",
                   IntegerToString(setting.stopLossPips));
         FileWrite(handle,
                   stratPrefix + ".take_profit_pips",
                   IntegerToString(setting.takeProfitPips));

         FileWrite(handle,
                   stratPrefix + ".break_even_enabled",
                   BoolToText(setting.breakEvenEnabled));
         FileWrite(handle,
                   stratPrefix + ".break_even_atr",
                   DoubleToString(setting.breakEvenAtrTrigger, 6));
         FileWrite(handle,
                   stratPrefix + ".break_even_offset_pips",
                   IntegerToString(setting.breakEvenOffsetPips));

         FileWrite(handle,
                   stratPrefix + ".trailing_enabled",
                   BoolToText(setting.trailingEnabled));
         FileWrite(handle,
                   stratPrefix + ".trailing_atr_trigger",
                   DoubleToString(setting.trailingAtrTrigger, 6));
         FileWrite(handle,
                   stratPrefix + ".trailing_atr_step",
                   DoubleToString(setting.trailingAtrStep, 6));
         FileWrite(handle,
                   stratPrefix + ".trailing_min_step_pips",
                   IntegerToString(setting.trailingMinStepPips));
        }
     }

   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Log helper: dump input parameter snapshot                        |
//+------------------------------------------------------------------+
void LogInputParameters(const string safeProfile)
  {
   Print("---- YoYoEntryTester Parameter Snapshot ----");
   PrintFormat("RunId='%s' ParameterLog='%s'", g_runId, g_parameterLogFileName);
   PrintFormat("ProfileLabel='%s' SafeProfile='%s'", g_profileLabel, safeProfile);
   PrintFormat("Lots=%.2f StopLossPips=%d TakeProfitPips=%d Slippage=%d",
               InpLots,
               InpStopLossPips,
               InpTakeProfitPips,
               InpSlippage);
   PrintFormat("Strategy enable flags: MA=%s RSI=%s CCI=%s MACD=%s STOCH=%s",
               BoolToText(InpEnableMA),
               BoolToText(InpEnableRSI),
               BoolToText(InpEnableCCI),
               BoolToText(InpEnableMACD),
               BoolToText(InpEnableStoch));
   PrintFormat("ATR settings: period=%d useATRStops=%s stopMult=%.4f takeMult=%.4f",
               InpATRPeriod,
               BoolToText(InpUseATRStops),
               InpATRStopMultiplier,
               InpATRTakeProfitMultiplier);
   PrintFormat("Default pip stops: stopLossPips=%d takeProfitPips=%d",
               InpStopLossPips,
               InpTakeProfitPips);
   PrintFormat("Band config usage: enabled=%s inputFile='%s'",
               BoolToText(InpUseAtrBandConfig),
               InpAtrBandConfigFile);
   PrintFormat("Risk settings: maxSpreadPips=%.2f useRiskLots=%s riskPercent=%.2f",
               InpMaxSpreadPips,
               BoolToText(InpUseRiskBasedLots),
               InpRiskPercent);
   PrintFormat("Cooldown settings: cooldownMins=%d lossPause=%d lossPauseMins=%d",
               InpCooldownMinutes,
               InpLossStreakPause,
               InpLossPauseMinutes);
   string maxTotalText = (InpMaxTotalPositions > 0
                          ? IntegerToString(InpMaxTotalPositions)
                          : "auto");
   PrintFormat("Position control: allowOpposite=%s globalMulti=%s maxTotal=%s",
               BoolToText(InpAllowOppositePositions),
               BoolToText(InpEnableGlobalMultiPositions),
               maxTotalText);
   PrintFormat("Break-even: enabled=%s atrTrigger=%.4f offsetPips=%d",
               BoolToText(InpEnableBreakEven),
               InpBreakEvenAtrTrigger,
               InpBreakEvenOffsetPips);
   PrintFormat("Trailing ATR: enabled=%s atrTrigger=%.4f atrStep=%.4f minStepPips=%d",
               BoolToText(InpEnableAtrTrailing),
               InpTrailingAtrTrigger,
               InpTrailingAtrStep,
               InpTrailingMinStepPips);
   PrintFormat("Session filter: enabled=%s startHour=%d endHour=%d skipFriday=%s fridayCutoff=%d",
               BoolToText(InpUseTradingSessions),
               InpSessionStartHour,
               InpSessionEndHour,
               BoolToText(InpSessionSkipFriday),
               InpFridayCutoffHour);
   PrintFormat("Multi-position control: maxPerStrategy=%d equityThreshold=%.2f",
               InpMaxPositionsPerStrategy,
               InpMultiPositionEquityThreshold);
   PrintFormat("Lot reduction: equityThreshold=%.2f factor=%.2f",
               InpLotReductionEquityThreshold,
               InpLotReductionFactor);
   PrintFormat("Magic numbers: prefix=%d MA=%d RSI=%d CCI=%d MACD=%d STOCH=%d",
               InpMagicPrefix,
               GetStrategyMagic(STRAT_MA),
               GetStrategyMagic(STRAT_RSI),
               GetStrategyMagic(STRAT_CCI),
               GetStrategyMagic(STRAT_MACD),
               GetStrategyMagic(STRAT_STOCH));
   WriteParameterSnapshot(safeProfile);
 }

//+------------------------------------------------------------------+
//| Apply CSV-derived values to band setting                         |
//+------------------------------------------------------------------+
bool ApplyBandSetting(StrategyBandSetting &setting,
                      const string strategyLabel,
                      const string enableText,
                      const string modeText,
                      const string slText,
                      const string tpText,
                      const string breakEvenEnableText,
                      const string breakEvenAtrText,
                      const string breakEvenOffsetText,
                      const string trailingEnableText,
                      const string trailingAtrText,
                      const string trailingStepText,
                      const string trailingMinStepText,
                      string &errorMessage)
  {
   errorMessage    = "";
   string trimmedEnable = StripUtf8Bom(TrimString(enableText));
   string trimmedMode   = StripUtf8Bom(TrimString(modeText));
   string trimmedSl     = StripUtf8Bom(TrimString(slText));
   string trimmedTp     = StripUtf8Bom(TrimString(tpText));
   string trimmedBeEn   = StripUtf8Bom(TrimString(breakEvenEnableText));
   string trimmedBeAtr  = StripUtf8Bom(TrimString(breakEvenAtrText));
   string trimmedBeOff  = StripUtf8Bom(TrimString(breakEvenOffsetText));
   string trimmedTrEn   = StripUtf8Bom(TrimString(trailingEnableText));
   string trimmedTrAtr  = StripUtf8Bom(TrimString(trailingAtrText));
   string trimmedTrStep = StripUtf8Bom(TrimString(trailingStepText));
   string trimmedTrMin  = StripUtf8Bom(TrimString(trailingMinStepText));

   bool hasContent = (StringLen(trimmedEnable) > 0 ||
                      StringLen(trimmedMode) > 0 ||
                      StringLen(trimmedSl) > 0 ||
                      StringLen(trimmedTp) > 0 ||
                      StringLen(trimmedBeEn) > 0 ||
                      StringLen(trimmedBeAtr) > 0 ||
                      StringLen(trimmedBeOff) > 0 ||
                      StringLen(trimmedTrEn) > 0 ||
                      StringLen(trimmedTrAtr) > 0 ||
                      StringLen(trimmedTrStep) > 0 ||
                      StringLen(trimmedTrMin) > 0);
   if(!hasContent)
     {
      setting.configured = false;
      return(true);
     }

   setting.configured              = true;
   bool parsedEnable               = ParseBoolValue(trimmedEnable, true);
   StopMode parsedMode             = ParseStopModeValue(trimmedMode);
   setting.enabled                 = parsedEnable;
   setting.mode                    = parsedMode;
   setting.atrStopMultiplier       = -1.0;
   setting.atrTakeProfitMultiplier = -1.0;
   setting.stopLossPips            = -1;
   setting.takeProfitPips          = -1;
   setting.breakEvenEnabled        = false;
   setting.breakEvenEnabledSpecified = false;
   setting.breakEvenAtrTrigger     = -1.0;
   setting.breakEvenOffsetPips     = -1;
   setting.trailingEnabled         = false;
   setting.trailingEnabledSpecified = false;
   setting.trailingAtrTrigger      = -1.0;
   setting.trailingAtrStep         = -1.0;
   setting.trailingMinStepPips     = -1;

   if(setting.mode == STOP_MODE_ATR)
     {
      double value = 0.0;
      if(StringLen(trimmedSl) > 0)
        {
         if(!ParseDoubleValue(trimmedSl, value))
           {
            errorMessage = StringFormat("%s SL value '%s' is not numeric", strategyLabel, trimmedSl);
            return(false);
           }
         setting.atrStopMultiplier = value;
        }
      if(StringLen(trimmedTp) > 0)
        {
         if(!ParseDoubleValue(trimmedTp, value))
           {
            errorMessage = StringFormat("%s TP value '%s' is not numeric", strategyLabel, trimmedTp);
            return(false);
           }
         setting.atrTakeProfitMultiplier = value;
        }
     }
   else if(setting.mode == STOP_MODE_PIPS)
     {
      int ivalue = 0;
      if(StringLen(trimmedSl) > 0)
        {
         if(!ParseIntValue(trimmedSl, ivalue))
           {
            errorMessage = StringFormat("%s SL value '%s' is not integer", strategyLabel, trimmedSl);
            return(false);
           }
         setting.stopLossPips = ivalue;
        }
      if(StringLen(trimmedTp) > 0)
        {
         if(!ParseIntValue(trimmedTp, ivalue))
           {
            errorMessage = StringFormat("%s TP value '%s' is not integer", strategyLabel, trimmedTp);
            return(false);
           }
         setting.takeProfitPips = ivalue;
        }
     }

   double parsedDouble = 0.0;
   int parsedInt       = 0;
   if(StringLen(trimmedBeEn) > 0)
     {
      setting.breakEvenEnabled = ParseBoolValue(trimmedBeEn, false);
      setting.breakEvenEnabledSpecified = true;
     }
   if(StringLen(trimmedBeAtr) > 0)
     {
      if(!ParseDoubleValue(trimmedBeAtr, parsedDouble))
        {
         errorMessage = StringFormat("%s BE_ATR value '%s' is not numeric", strategyLabel, trimmedBeAtr);
         return(false);
        }
      setting.breakEvenAtrTrigger = parsedDouble;
     }
   if(StringLen(trimmedBeOff) > 0)
     {
      if(!ParseIntValue(trimmedBeOff, parsedInt))
        {
         errorMessage = StringFormat("%s BE_OFFSET value '%s' is not integer", strategyLabel, trimmedBeOff);
         return(false);
        }
      setting.breakEvenOffsetPips = parsedInt;
     }
   if(StringLen(trimmedTrEn) > 0)
     {
      setting.trailingEnabled = ParseBoolValue(trimmedTrEn, false);
      setting.trailingEnabledSpecified = true;
     }
   if(StringLen(trimmedTrAtr) > 0)
     {
      if(!ParseDoubleValue(trimmedTrAtr, parsedDouble))
        {
         errorMessage = StringFormat("%s TRAIL_ATR value '%s' is not numeric", strategyLabel, trimmedTrAtr);
         return(false);
        }
      setting.trailingAtrTrigger = parsedDouble;
     }
   if(StringLen(trimmedTrStep) > 0)
     {
      if(!ParseDoubleValue(trimmedTrStep, parsedDouble))
        {
         errorMessage = StringFormat("%s TRAIL_STEP value '%s' is not numeric", strategyLabel, trimmedTrStep);
         return(false);
        }
      setting.trailingAtrStep = parsedDouble;
     }
   if(StringLen(trimmedTrMin) > 0)
     {
      if(!ParseIntValue(trimmedTrMin, parsedInt))
        {
         errorMessage = StringFormat("%s TRAIL_MIN value '%s' is not integer", strategyLabel, trimmedTrMin);
         return(false);
        }
      setting.trailingMinStepPips = parsedInt;
     }

   PrintFormat("ApplyBandSetting result: strategy='%s' enableText='%s' -> %s modeText='%s' -> %s slText='%s' tpText='%s' beEnable='%s' beAtr='%s' beOffset='%s' trEnable='%s' trAtr='%s' trStep='%s' trMin='%s'",
               strategyLabel,
               trimmedEnable,
               BoolToText(setting.enabled),
               trimmedMode,
               StopModeToText(setting.mode),
               trimmedSl,
               trimmedTp,
               trimmedBeEn,
               trimmedBeAtr,
               trimmedBeOff,
               trimmedTrEn,
               trimmedTrAtr,
               trimmedTrStep,
               trimmedTrMin);

   return(true);
  }

//+------------------------------------------------------------------+
//| Load ATR band configuration from file                            |
//+------------------------------------------------------------------+
bool LoadAtrBandConfig(const string safeProfile)
  {
   ArrayResize(g_bandConfigs, 0);
   g_bandConfigLoaded = false;
   g_bandConfigPath   = "";

   if(!InpUseAtrBandConfig)
      return(false);

   string fileName = TrimString(InpAtrBandConfigFile);
   fileName = StripEnclosingQuotes(fileName);
   if(StringLen(fileName) == 0 ||
      (IsNumericString(fileName) && MathAbs(StrToDouble(fileName)) < 0.0000001))
      fileName = "AtrBandConfig_" + safeProfile + ".csv";

   StringReplace(fileName, "{PROFILE}", safeProfile);
   StringReplace(fileName, "{profile}", safeProfile);
   g_bandConfigPath = fileName;

   int handle = FileOpen(fileName, FILE_READ | FILE_SHARE_READ | FILE_TXT);
   if(handle == INVALID_HANDLE)
     {
      int err = GetLastError();
      PrintFormat("ATR band config file '%s' could not be opened (error %d).", fileName, err);
      return(false);
     }

   bool headerConsumed = false;
  int  loadedRows     = 0;
  const int columnsPerStrategy = 11;
  int strategyColumnIndex[];
  ArrayResize(strategyColumnIndex, STRAT_TOTAL * columnsPerStrategy);
  for(int strat = 0; strat < STRAT_TOTAL; strat++)
    {
     for(int offset = 0; offset < columnsPerStrategy; offset++)
        {
         int idx = 2 + (strat * columnsPerStrategy) + offset;
         strategyColumnIndex[(strat * columnsPerStrategy) + offset] = idx;
        }
     }

   while(!FileIsEnding(handle))
     {
      ResetLastError();
      string rawLine = FileReadString(handle);
      int lastError = GetLastError();
      if(lastError == ERR_END_OF_FILE && StringLen(rawLine) == 0)
         break;

      rawLine = StripUtf8Bom(rawLine);
      StringReplace(rawLine, "\r", "");
      rawLine = TrimString(rawLine);
      rawLine = StripUtf8Bom(rawLine);
      if(StringLen(rawLine) == 0)
         continue;
      if(StringGetChar(rawLine, 0) == '#')
         continue;

      string columns[];
      int columnCount = SplitCsvLine(rawLine, columns);
      if(columnCount <= 0)
         continue;

      for(int colIndex = 0; colIndex < columnCount; colIndex++)
         columns[colIndex] = StripUtf8Bom(columns[colIndex]);

      string firstCell = StripUtf8Bom(TrimString(columns[0]));
      columns[0] = firstCell;
      if(!headerConsumed)
        {
         if(StringCompare(firstCell, "MINATR", false) == 0)
           {
            for(int strat = 0; strat < STRAT_TOTAL; strat++)
              {
               for(int offset = 0; offset < columnsPerStrategy; offset++)
                  strategyColumnIndex[(strat * columnsPerStrategy) + offset] = -1;
              }

            for(int col = 0; col < columnCount; col++)
              {
               string header = StripUtf8Bom(TrimString(columns[col]));
               for(int strat = 0; strat < STRAT_TOTAL; strat++)
                 {
                  string prefix = g_strategyCsvPrefixes[strat];
                  if(HeaderKeyEquals(header, prefix, "ENABLE"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 0] = col;
                  else if(HeaderKeyEquals(header, prefix, "MODE"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 1] = col;
                  else if(HeaderKeyEquals(header, prefix, "SL"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 2] = col;
                  else if(HeaderKeyEquals(header, prefix, "TP"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 3] = col;
                  else if(HeaderKeyEquals(header, prefix, "BE_ENABLE"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 4] = col;
                  else if(HeaderKeyEquals(header, prefix, "BE_ATR") ||
                          HeaderKeyEquals(header, prefix, "BE_TRIGGER"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 5] = col;
                  else if(HeaderKeyEquals(header, prefix, "BE_OFFSET"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 6] = col;
                  else if(HeaderKeyEquals(header, prefix, "TRAIL_ENABLE"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 7] = col;
                  else if(HeaderKeyEquals(header, prefix, "TRAIL_ATR") ||
                          HeaderKeyEquals(header, prefix, "TRAIL_TRIGGER"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 8] = col;
                  else if(HeaderKeyEquals(header, prefix, "TRAIL_STEP"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 9] = col;
                  else if(HeaderKeyEquals(header, prefix, "TRAIL_MIN") ||
                          HeaderKeyEquals(header, prefix, "TRAIL_MIN_STEP"))
                     strategyColumnIndex[(strat * columnsPerStrategy) + 10] = col;
                 }
              }

            for(int strat = 0; strat < STRAT_TOTAL; strat++)
              {
               for(int offset = 0; offset < columnsPerStrategy; offset++)
                 {
                  int defaultIndex = 2 + (strat * columnsPerStrategy) + offset;
                  int mappingIndex = strategyColumnIndex[(strat * columnsPerStrategy) + offset];
                  if(mappingIndex < 0)
                     strategyColumnIndex[(strat * columnsPerStrategy) + offset] = defaultIndex;
                 }
              }

            headerConsumed = true;
            continue;
           }
        }
      headerConsumed = true;

      double minAtrValue = 0.0;
      if(!ParseDoubleValue(columns[0], minAtrValue))
        {
         PrintFormat("Skipping ATR band row due to invalid MINATR value '%s'. Line='%s'", columns[0], rawLine);
         continue;
        }

      double maxAtrValue = DBL_MAX;
      bool hasMax = false;
      if(columnCount > 1)
        {
         string maxText = StripUtf8Bom(TrimString(columns[1]));
         if(StringLen(maxText) > 0)
           {
            if(!ParseDoubleValue(maxText, maxAtrValue))
              {
               PrintFormat("Skipping ATR band row due to invalid MAXATR value '%s'. Line='%s'", maxText, rawLine);
               continue;
              }
            hasMax = true;
           }
        }
      if(!hasMax || maxAtrValue <= minAtrValue)
         maxAtrValue = DBL_MAX;

      PrintFormat("Band row parsed: rawMin='%s' rawMax='%s'",
                  columns[0],
                  (columnCount > 1 ? columns[1] : ""));

      BandConfig tempConfig;
      InitBandConfig(tempConfig);
      tempConfig.minAtr = minAtrValue;
      tempConfig.maxAtr = maxAtrValue;

      bool   rowValid      = true;
      string rowErrorCause = "";

      for(int strat = 0; strat < STRAT_TOTAL; strat++)
        {
         int baseOffset = strat * columnsPerStrategy;
         string enableText = "";
         string modeText   = "";
         string slText     = "";
         string tpText     = "";
         string beEnableText = "";
         string beAtrText    = "";
         string beOffsetText = "";
         string trEnableText = "";
         string trAtrText    = "";
         string trStepText   = "";
         string trMinText    = "";

         int enableIndex = strategyColumnIndex[baseOffset];
         int modeIndex   = strategyColumnIndex[baseOffset + 1];
         int slIndex     = strategyColumnIndex[baseOffset + 2];
         int tpIndex     = strategyColumnIndex[baseOffset + 3];
         int beEnableIndex = strategyColumnIndex[baseOffset + 4];
         int beAtrIndex    = strategyColumnIndex[baseOffset + 5];
         int beOffsetIndex = strategyColumnIndex[baseOffset + 6];
         int trEnableIndex = strategyColumnIndex[baseOffset + 7];
         int trAtrIndex    = strategyColumnIndex[baseOffset + 8];
         int trStepIndex   = strategyColumnIndex[baseOffset + 9];
         int trMinIndex    = strategyColumnIndex[baseOffset + 10];

         if(enableIndex >= 0 && enableIndex < columnCount)
            enableText = StripUtf8Bom(TrimString(columns[enableIndex]));
         if(modeIndex >= 0 && modeIndex < columnCount)
            modeText = StripUtf8Bom(TrimString(columns[modeIndex]));
         if(slIndex >= 0 && slIndex < columnCount)
            slText = StripUtf8Bom(TrimString(columns[slIndex]));
         if(tpIndex >= 0 && tpIndex < columnCount)
            tpText = StripUtf8Bom(TrimString(columns[tpIndex]));
         if(beEnableIndex >= 0 && beEnableIndex < columnCount)
            beEnableText = StripUtf8Bom(TrimString(columns[beEnableIndex]));
         if(beAtrIndex >= 0 && beAtrIndex < columnCount)
            beAtrText = StripUtf8Bom(TrimString(columns[beAtrIndex]));
         if(beOffsetIndex >= 0 && beOffsetIndex < columnCount)
            beOffsetText = StripUtf8Bom(TrimString(columns[beOffsetIndex]));
         if(trEnableIndex >= 0 && trEnableIndex < columnCount)
            trEnableText = StripUtf8Bom(TrimString(columns[trEnableIndex]));
         if(trAtrIndex >= 0 && trAtrIndex < columnCount)
            trAtrText = StripUtf8Bom(TrimString(columns[trAtrIndex]));
         if(trStepIndex >= 0 && trStepIndex < columnCount)
            trStepText = StripUtf8Bom(TrimString(columns[trStepIndex]));
         if(trMinIndex >= 0 && trMinIndex < columnCount)
            trMinText = StripUtf8Bom(TrimString(columns[trMinIndex]));

         string parseError = "";
         if(!ApplyBandSetting(tempConfig.strategySettings[strat],
                              g_strategyCsvPrefixes[strat],
                              enableText,
                              modeText,
                              slText,
                              tpText,
                              beEnableText,
                              beAtrText,
                              beOffsetText,
                              trEnableText,
                              trAtrText,
                              trStepText,
                              trMinText,
                              parseError))
           {
            rowValid      = false;
            rowErrorCause = parseError;
            break;
           }
        }

      if(!rowValid)
        {
         PrintFormat("Skipping ATR band row for MINATR '%s' due to %s. Line='%s'",
                     columns[0],
                     rowErrorCause,
                     rawLine);
         continue;
        }

      int index = ArraySize(g_bandConfigs);
      ArrayResize(g_bandConfigs, index + 1);
      g_bandConfigs[index] = tempConfig;
      loadedRows++;
     }

   FileClose(handle);

   if(loadedRows <= 0)
     {
      ArrayResize(g_bandConfigs, 0);
      PrintFormat("ATR band config file '%s' did not contain any usable rows.", fileName);
      return(false);
     }

   int total = ArraySize(g_bandConfigs);
   for(int i = 0; i < total - 1; i++)
     {
      for(int j = i + 1; j < total; j++)
        {
         if(g_bandConfigs[i].minAtr > g_bandConfigs[j].minAtr)
           {
            BandConfig temp    = g_bandConfigs[i];
            g_bandConfigs[i] = g_bandConfigs[j];
            g_bandConfigs[j] = temp;
           }
        }
     }

   g_bandConfigLoaded = true;
   PrintFormat("Loaded %d ATR band configuration rows from '%s'.", loadedRows, fileName);
   return(true);
  }

//+------------------------------------------------------------------+
//| Resolve band setting for current ATR                             |
//+------------------------------------------------------------------+
bool ResolveBandSetting(StrategyIndex index,
                        const double atrValue,
                        StrategyBandSetting &outSetting)
  {
   if(!g_bandConfigLoaded || atrValue <= 0.0)
      return(false);

   int total = ArraySize(g_bandConfigs);
   for(int i = 0; i < total; i++)
     {
      BandConfig band = g_bandConfigs[i];
      double maxAtr = band.maxAtr;
      bool inRange = (atrValue >= band.minAtr &&
                      (maxAtr == DBL_MAX ? true : atrValue < maxAtr));
      if(!inRange)
         continue;

      StrategyBandSetting setting = band.strategySettings[index];
      if(setting.configured)
        {
         outSetting = setting;
         return(true);
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: find strategy index by magic number                     |
//+------------------------------------------------------------------+
int FindStrategyIndexByMagic(const int magic)
  {
   for(int i = 0; i < STRAT_TOTAL; i++)
     {
      if(g_strategies[i].magic == magic)
         return(i);
     }
   for(int i = 0; i < STRAT_TOTAL; i++)
     {
      if(kLegacyStrategyMagics[i] == magic)
         return(i);
     }
   return(-1);
  }

int FindTradeMetadataIndex(const int ticket)
  {
   for(int i = ArraySize(g_tradeMetadata) - 1; i >= 0; i--)
     {
      if(g_tradeMetadata[i].ticket == ticket)
         return(i);
     }
   return(-1);
  }

void RegisterTradeMetadata(const int ticket,
                           const int direction,
                           const double entryAtrValue,
                           const bool breakEvenEnabled,
                           const double breakEvenAtrTrigger,
                           const int breakEvenOffsetPips,
                           const bool trailingEnabled,
                           const double trailingAtrTrigger,
                           const double trailingAtrStep,
                           const int trailingMinStepPips)
  {
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
      return;

   TradeMetadata meta;
   meta.ticket        = ticket;
   meta.entryPrice    = OrderOpenPrice();
   meta.entryAtr      = entryAtrValue;
   meta.stopLoss      = OrderStopLoss();
   meta.takeProfit    = OrderTakeProfit();
   meta.direction     = direction;
   meta.lastStopReason = STOP_UPDATE_INITIAL;
   meta.breakEvenAtrTrigger     = (breakEvenAtrTrigger >= 0.0 ? breakEvenAtrTrigger : InpBreakEvenAtrTrigger);
   meta.breakEvenOffsetPips     = (breakEvenOffsetPips >= 0 ? breakEvenOffsetPips : InpBreakEvenOffsetPips);
   meta.breakEvenEnabled        = breakEvenEnabled;
   meta.trailingAtrTrigger      = (trailingAtrTrigger >= 0.0 ? trailingAtrTrigger : InpTrailingAtrTrigger);
   meta.trailingAtrStep         = (trailingAtrStep >= 0.0 ? trailingAtrStep : InpTrailingAtrStep);
   meta.trailingMinStepPips     = (trailingMinStepPips >= 0 ? trailingMinStepPips : InpTrailingMinStepPips);
   meta.trailingEnabled         = trailingEnabled;

   double pip = PipSize();
   double tolerance = (pip > 0.0 ? pip * 0.1 : 0.0001);
   double breakEvenStop = (direction > 0
                           ? meta.entryPrice + meta.breakEvenOffsetPips * pip
                           : meta.entryPrice - meta.breakEvenOffsetPips * pip);
   if(meta.stopLoss > 0.0 &&
      MathAbs(meta.stopLoss - breakEvenStop) <= tolerance + 1e-8)
      meta.lastStopReason = STOP_UPDATE_BREAK_EVEN;

   int index = FindTradeMetadataIndex(ticket);
   if(index >= 0)
      g_tradeMetadata[index] = meta;
   else
     {
      int size = ArraySize(g_tradeMetadata);
      ArrayResize(g_tradeMetadata, size + 1);
      g_tradeMetadata[size] = meta;
     }
  }

void UpdateTradeStopMetadata(const int ticket,
                             const double newStop,
                             const StopUpdateReason reason)
  {
   int index = FindTradeMetadataIndex(ticket);
   if(index < 0)
      return;

   g_tradeMetadata[index].stopLoss = newStop;
   if(reason != STOP_UPDATE_NONE)
      g_tradeMetadata[index].lastStopReason = reason;
  }

void RemoveTradeMetadata(const int ticket)
  {
   int index = FindTradeMetadataIndex(ticket);
   if(index < 0)
      return;

   int last = ArraySize(g_tradeMetadata) - 1;
   if(index != last && last >= 0)
      g_tradeMetadata[index] = g_tradeMetadata[last];
   if(last >= 0)
      ArrayResize(g_tradeMetadata, last);
  }

void InitialiseTradeMetadata()
  {
   ArrayResize(g_tradeMetadata, 0);

   double fallbackAtrValue = 0.0;
   if(Bars > 1)
      fallbackAtrValue = iATR(NULL, 0, InpATRPeriod, 1);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol() != Symbol())
         continue;

      int orderType = OrderType();
      if(orderType != OP_BUY && orderType != OP_SELL)
         continue;

      int direction = (orderType == OP_BUY ? 1 : -1);
      int magic = OrderMagicNumber();
      int stratIndex = FindStrategyIndexByMagic(magic);

      bool   breakEvenEnabled    = InpEnableBreakEven;
      double breakEvenAtrTrigger = InpBreakEvenAtrTrigger;
      int    breakEvenOffset     = InpBreakEvenOffsetPips;
      bool   trailingEnabled     = InpEnableAtrTrailing;
      double trailingAtrTrigger  = InpTrailingAtrTrigger;
      double trailingAtrStep     = InpTrailingAtrStep;
      int    trailingMinStep     = InpTrailingMinStepPips;

      double entryAtrValue = fallbackAtrValue;
      datetime openTime = OrderOpenTime();
      int openShift = iBarShift(NULL, 0, openTime, false);
      if(openShift >= 0)
        {
         int atrShift = openShift + 1;
         if(atrShift >= Bars)
            atrShift = Bars - 1;
         if(atrShift < 0)
            atrShift = 0;
         double historicalAtr = iATR(NULL, 0, InpATRPeriod, atrShift);
         if(historicalAtr > 0.0)
            entryAtrValue = historicalAtr;
        }
      if(entryAtrValue <= 0.0 && fallbackAtrValue > 0.0)
         entryAtrValue = fallbackAtrValue;

      if(stratIndex >= 0)
        {
         StrategyBandSetting bandSetting;
         InitStrategyBandSetting(bandSetting);
         if(ResolveBandSetting((StrategyIndex)stratIndex, entryAtrValue, bandSetting))
           {
            if(bandSetting.breakEvenEnabledSpecified)
               breakEvenEnabled = bandSetting.breakEvenEnabled;

            if(bandSetting.breakEvenAtrTrigger >= 0.0)
               breakEvenAtrTrigger = bandSetting.breakEvenAtrTrigger;
            if(bandSetting.breakEvenOffsetPips >= 0)
               breakEvenOffset = bandSetting.breakEvenOffsetPips;

            if(bandSetting.trailingEnabledSpecified)
               trailingEnabled = bandSetting.trailingEnabled;

            if(bandSetting.trailingAtrTrigger >= 0.0)
               trailingAtrTrigger = bandSetting.trailingAtrTrigger;
            if(bandSetting.trailingAtrStep >= 0.0)
               trailingAtrStep = bandSetting.trailingAtrStep;
            if(bandSetting.trailingMinStepPips >= 0)
               trailingMinStep = bandSetting.trailingMinStepPips;
           }
        }

      RegisterTradeMetadata(OrderTicket(),
                            direction,
                            entryAtrValue,
                            breakEvenEnabled,
                            breakEvenAtrTrigger,
                            breakEvenOffset,
                            trailingEnabled,
                            trailingAtrTrigger,
                            trailingAtrStep,
                            trailingMinStep);

     }
  }

//+------------------------------------------------------------------+
//| Utility: ensure result log header exists                         |
//+------------------------------------------------------------------+
bool EnsureResultLogHeader()
  {
   int handle = FileOpen(g_resultLogFileName,
                         FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE,
                         ',');
   if(handle == INVALID_HANDLE)
     {
      handle = FileOpen(g_resultLogFileName,
                        FILE_CSV | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE,
                        ',');
      if(handle == INVALID_HANDLE)
        {
         Print("Failed to create result log file ", g_resultLogFileName,
               ". Error: ", GetLastError());
         return(false);
        }
      FileWrite(handle,
                "timestamp",
                "run_id",
                "event",
                "symbol",
                "profile",
                "strategy",
                "direction",
                "ticket",
                "volume",
                "price",
                "atr_entry",
                "atr_exit",
                "indicator",
                "profit",
                "swap",
                "commission",
                "net",
                "pips",
                "exit_reason");
      FileClose(handle);
      return(true);
     }

   if(FileSize(handle) == 0)
     {
      FileWrite(handle,
                "timestamp",
                "run_id",
                "event",
                "symbol",
                "profile",
                "strategy",
                "direction",
                "ticket",
                "volume",
                "price",
                "atr_entry",
                "atr_exit",
                "indicator",
                "profit",
                "swap",
                "commission",
                "net",
                "pips",
                "exit_reason");
     }
   FileClose(handle);
   return(true);
  }

//+------------------------------------------------------------------+
//| Utility: load previously logged exit tickets                     |
//+------------------------------------------------------------------+
void LoadLoggedExitTickets()
  {
   ArrayResize(g_exitLoggedTickets, 0);

    int handle = FileOpen(g_resultLogFileName,
                          FILE_CSV | FILE_READ | FILE_SHARE_READ | FILE_SHARE_WRITE,
                          ',');
   if(handle == INVALID_HANDLE)
      return;

   if(FileSize(handle) == 0)
     {
      FileClose(handle);
      return;
     }

   // Skip header line (supports legacy column counts)
   while(!FileIsEnding(handle))
     {
      FileReadString(handle);
      if(FileIsLineEnding(handle))
         break;
     }

   while(!FileIsEnding(handle))
     {
      string rowFields[];
      ArrayResize(rowFields, 0);
      bool rowRead = false;

      while(!FileIsEnding(handle))
        {
         string value = FileReadString(handle);
         int size = ArraySize(rowFields);
         ArrayResize(rowFields, size + 1);
         rowFields[size] = value;
         rowRead = true;

         if(FileIsLineEnding(handle))
            break;
        }

      if(!rowRead)
         break;

      if(ArraySize(rowFields) == 0)
         continue;

      int eventIndex = (ArraySize(rowFields) >= RESULT_LOG_COLUMNS ? 2 : 1);
      string eventValue = (ArraySize(rowFields) > eventIndex ? rowFields[eventIndex] : "");
      if(StringLen(eventValue) == 0)
         continue;

      if(eventValue == "EXIT")
        {
         int ticketIndex = (ArraySize(rowFields) >= RESULT_LOG_COLUMNS ? 7 : 6);
         string ticketText = (ArraySize(rowFields) > ticketIndex ? rowFields[ticketIndex] : "");
         if(StringLen(ticketText) == 0)
            continue;

         int ticket = (int)StringToInteger(ticketText);
         int size   = ArraySize(g_exitLoggedTickets);
         ArrayResize(g_exitLoggedTickets, size + 1);
         g_exitLoggedTickets[size] = ticket;
        }
     }

   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Utility: check if exit already logged                            |
//+------------------------------------------------------------------+
bool IsExitLogged(const int ticket)
  {
   for(int i = 0; i < ArraySize(g_exitLoggedTickets); i++)
     {
      if(g_exitLoggedTickets[i] == ticket)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Utility: mark exit ticket as logged                              |
//+------------------------------------------------------------------+
void MarkExitLogged(const int ticket)
  {
   int size = ArraySize(g_exitLoggedTickets);
   ArrayResize(g_exitLoggedTickets, size + 1);
   g_exitLoggedTickets[size] = ticket;
  }

//+------------------------------------------------------------------+
//| Utility: log trade events with PnL information                   |
//+------------------------------------------------------------------+
void LogTradeEvent(const StrategyState &state,
                   const string eventType,
                   const int direction,
                   const int ticket,
                   const double volume,
                   const double price,
                   const double entryAtrValue,
                   const double exitAtrValue,
                   const double indicatorValue,
                   const double profit,
                   const double swapValue,
                   const double commissionValue,
                   const double netProfit,
                   const double pipsValue,
                   const datetime eventTime,
                   const string exitReason)
  {
   int handle = FileOpen(g_resultLogFileName,
                         FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE,
                         ',');
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to open result log file ", g_resultLogFileName,
            ". Error: ", GetLastError());
      return;
     }

   FileSeek(handle, 0, SEEK_END);

   string directionText = "";
   if(direction > 0)
      directionText = "BUY";
   else if(direction < 0)
      directionText = "SELL";

   string priceText      = (price == EMPTY_VALUE ? "" : DoubleToString(price, Digits));
   string entryAtrText   = (entryAtrValue == EMPTY_VALUE ? "" : DoubleToString(entryAtrValue, 6));
   string exitAtrText    = (exitAtrValue == EMPTY_VALUE ? "" : DoubleToString(exitAtrValue, 6));
   string indicatorText  = (indicatorValue == EMPTY_VALUE ? "" : DoubleToString(indicatorValue, 6));
   string profitText     = (profit == EMPTY_VALUE ? "" : DoubleToString(profit, 2));
   string swapText       = (swapValue == EMPTY_VALUE ? "" : DoubleToString(swapValue, 2));
   string commissionText = (commissionValue == EMPTY_VALUE ? "" : DoubleToString(commissionValue, 2));
   string netText        = (netProfit == EMPTY_VALUE ? "" : DoubleToString(netProfit, 2));
   string pipsText       = (pipsValue == EMPTY_VALUE ? "" : DoubleToString(pipsValue, 1));
   double lotStep        = MarketInfo(Symbol(), MODE_LOTSTEP);
   int    volumeDigits   = StepToDigits(lotStep);
   string volumeText     = (volume == EMPTY_VALUE ? "" : DoubleToString(volume, volumeDigits));
   string reasonText     = exitReason;

   FileWrite(handle,
             TimeToString(eventTime, TIME_DATE | TIME_SECONDS),
             g_runId,
             eventType,
             Symbol(),
             g_profileLabel,
             state.name,
             directionText,
             IntegerToString(ticket),
             volumeText,
             priceText,
             entryAtrText,
             exitAtrText,
             indicatorText,
             profitText,
             swapText,
             commissionText,
             netText,
             pipsText,
             reasonText);

   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Utility: place trade with SL/TP                                  |
//+------------------------------------------------------------------+
TradeAttemptResult ExecuteEntry(const StrategyState &state,
                                const int direction,
                                const double atrValue,
                                const double indicatorValue,
                                const bool hasBandSetting,
                                const StrategyBandSetting &bandSetting)
  {
   if(hasBandSetting && bandSetting.configured && !bandSetting.enabled)
     {
      PrintFormat("Band disabled: strategy=%s ATR=%.6f -> entry skipped", state.name, atrValue);
      return(TRADE_ATTEMPT_SKIPPED);
     }

   RefreshRates();

   if(InpMaxSpreadPips > 0.0)
     {
      double spreadPips = CurrentSpreadPips();
      if(spreadPips > InpMaxSpreadPips + 1e-6)
        {
         PrintFormat("Spread %.2f pips exceeds limit %.2f for %s. Entry skipped.",
                     spreadPips,
                     InpMaxSpreadPips,
                     state.name);
         return(TRADE_ATTEMPT_SKIPPED);
        }
     }

   int    cmd   = (direction > 0 ? OP_BUY : OP_SELL);
   double price = (cmd == OP_BUY ? Ask : Bid);
   double pip   = PipSize();

   double minStopDistance = GetMinimumStopDistance();
   if(minStopDistance <= 0.0)
      minStopDistance = (pip > 0.0 ? pip : Point);

   int totalOpenPositions = CountTotalOpenStrategyPositions();
   int totalLimit = GetCurrentTotalPositionLimit();
   if(totalLimit > 0 && totalOpenPositions >= totalLimit)
      return(TRADE_ATTEMPT_SKIPPED);

   int stratOpen = CountOpenPositionsForMagic(state.magic);
   if(stratOpen >= InpMaxPositionsPerStrategy)
      return(TRADE_ATTEMPT_SKIPPED);

   double requestedLots  = (InpUseRiskBasedLots ? InpLots : g_effectiveLots);
   double normalizedLots = 0.0;

   double sl = 0.0;
   double tp = 0.0;
   double stopDistancePips = 0.0;

   bool   useAtrStops              = InpUseATRStops;
   double atrStopMultiplier        = InpATRStopMultiplier;
   double atrTakeProfitMultiplier  = InpATRTakeProfitMultiplier;
   int    stopLossPips             = InpStopLossPips;
   int    takeProfitPips           = InpTakeProfitPips;
   bool   breakEvenEnabled         = InpEnableBreakEven;
   double breakEvenAtrTrigger      = InpBreakEvenAtrTrigger;
   int    breakEvenOffsetPips      = InpBreakEvenOffsetPips;
   bool   trailingEnabled          = InpEnableAtrTrailing;
   double trailingAtrTrigger       = InpTrailingAtrTrigger;
   double trailingAtrStep          = InpTrailingAtrStep;
   int    trailingMinStepPips      = InpTrailingMinStepPips;

   if(hasBandSetting && bandSetting.configured)
     {
      if(bandSetting.mode == STOP_MODE_ATR)
        {
         useAtrStops = true;
         if(bandSetting.atrStopMultiplier >= 0.0)
            atrStopMultiplier = bandSetting.atrStopMultiplier;
         if(bandSetting.atrTakeProfitMultiplier >= 0.0)
            atrTakeProfitMultiplier = bandSetting.atrTakeProfitMultiplier;
        }
      else if(bandSetting.mode == STOP_MODE_PIPS)
        {
         useAtrStops = false;
         if(bandSetting.stopLossPips >= 0)
            stopLossPips = bandSetting.stopLossPips;
         if(bandSetting.takeProfitPips >= 0)
            takeProfitPips = bandSetting.takeProfitPips;
        }
      if(bandSetting.breakEvenEnabledSpecified)
         breakEvenEnabled = bandSetting.breakEvenEnabled;
      if(bandSetting.breakEvenAtrTrigger >= 0.0)
         breakEvenAtrTrigger = bandSetting.breakEvenAtrTrigger;
      if(bandSetting.breakEvenOffsetPips >= 0)
         breakEvenOffsetPips = bandSetting.breakEvenOffsetPips;
      if(bandSetting.trailingEnabledSpecified)
         trailingEnabled = bandSetting.trailingEnabled;
      if(bandSetting.trailingAtrTrigger >= 0.0)
         trailingAtrTrigger = bandSetting.trailingAtrTrigger;
      if(bandSetting.trailingAtrStep >= 0.0)
         trailingAtrStep = bandSetting.trailingAtrStep;
      if(bandSetting.trailingMinStepPips >= 0)
         trailingMinStepPips = bandSetting.trailingMinStepPips;
     }

   if(useAtrStops && atrValue <= 0.0)
     {
      PrintFormat("ATR value unavailable for %s (ATR=%.6f). Falling back to pip-based stops.",
                  state.name,
                  atrValue);
      useAtrStops = false;
     }

   if(useAtrStops)
     {
      if(atrStopMultiplier > 0.0)
        {
         double dist = atrValue * atrStopMultiplier;
         if(dist < minStopDistance)
            dist = minStopDistance;
         sl = (cmd == OP_BUY ? price - dist : price + dist);
         sl = NormalizeDouble(sl, Digits);
         double pipDivisor = (pip > 0.0 ? pip : Point);
         if(pipDivisor > 0.0)
            stopDistancePips = dist / pipDivisor;
        }

      if(atrTakeProfitMultiplier > 0.0)
        {
         double dist = atrValue * atrTakeProfitMultiplier;
         if(dist < minStopDistance)
            dist = minStopDistance;
         tp = (cmd == OP_BUY ? price + dist : price - dist);
         tp = NormalizeDouble(tp, Digits);
        }
     }
   else
     {
      if(stopLossPips > 0)
        {
         double dist = stopLossPips * pip;
         if(dist < minStopDistance)
            dist = minStopDistance;
         sl = (cmd == OP_BUY ? price - dist : price + dist);
         sl = NormalizeDouble(sl, Digits);
         if(pip > 0.0)
            stopDistancePips = dist / pip;
         else
            stopDistancePips = stopLossPips;
        }

      if(takeProfitPips > 0)
        {
         double dist = takeProfitPips * pip;
         if(dist < minStopDistance)
            dist = minStopDistance;
         tp = (cmd == OP_BUY ? price + dist : price - dist);
         tp = NormalizeDouble(tp, Digits);
        }
     }

   if(InpUseRiskBasedLots)
     {
      if(stopDistancePips <= 0.0)
        {
         PrintFormat("Risk-based lot sizing skipped for %s because stop distance is %.2f pips.",
                     state.name,
                     stopDistancePips);
         return(TRADE_ATTEMPT_SKIPPED);
        }

      double riskLots = CalculateRiskBasedLots(stopDistancePips);
      if(riskLots <= 0.0)
        {
         PrintFormat("Risk-based lot calculation failed for %s (stopPips=%.2f). Entry skipped.",
                     state.name,
                     stopDistancePips);
         return(TRADE_ATTEMPT_SKIPPED);
        }

      requestedLots = riskLots;
     }

   normalizedLots = NormalizeLotSize(requestedLots);
   if(normalizedLots <= 0.0)
     {
      PrintFormat("Normalized lot size is non-positive for strategy=%s (requested=%.4f)", state.name, requestedLots);
      return(TRADE_ATTEMPT_CONSUMED);
     }

   if(MathAbs(normalizedLots - requestedLots) > 1e-8)
     {
      PrintFormat("Lot size adjusted for %s: requested=%.4f normalized=%.4f",
                  state.name,
                  requestedLots,
                  normalizedLots);
     }

   double freeMarginAfter = AccountFreeMarginCheck(Symbol(), cmd, normalizedLots);
   if(freeMarginAfter < 0.0)
     {
      PrintFormat("Insufficient margin for %s: requestedLots=%.4f normalizedLots=%.4f",
                  state.name,
                  requestedLots,
                  normalizedLots);
      return(TRADE_ATTEMPT_CONSUMED);
     }

   string comment = state.comment;
   ResetLastError();
   int ticket = OrderSend(Symbol(),
                          cmd,
                          normalizedLots,
                          price,
                          InpSlippage,
                          sl,
                          tp,
                          comment,
                          state.magic,
                          0,
                          (cmd == OP_BUY ? clrBlue : clrRed));

   if(ticket < 0)
     {
      Print("OrderSend failed for ", state.name,
            ". Error: ", GetLastError());
      return(TRADE_ATTEMPT_CONSUMED);
     }

   if(OrderSelect(ticket, SELECT_BY_TICKET))
     {
     LogTradeEvent(state,
                   "ENTRY",
                   direction,
                   ticket,
                   OrderLots(),
                   OrderOpenPrice(),
                   atrValue,
                   EMPTY_VALUE,
                   indicatorValue,
                   EMPTY_VALUE,
                   EMPTY_VALUE,
                   EMPTY_VALUE,
                   EMPTY_VALUE,
                   EMPTY_VALUE,
                   OrderOpenTime(),
                   "");
      RegisterTradeMetadata(ticket,
                            direction,
                            atrValue,
                            breakEvenEnabled,
                            breakEvenAtrTrigger,
                            breakEvenOffsetPips,
                            trailingEnabled,
                            trailingAtrTrigger,
                            trailingAtrStep,
                            trailingMinStepPips);
     }
   else
     {
      Print("OrderSelect failed for ticket ", ticket,
            ". Error: ", GetLastError());
     }

   return(TRADE_ATTEMPT_PLACED);
  }

//+------------------------------------------------------------------+
//| Evaluate MA cross                                                |
//+------------------------------------------------------------------+
int EvaluateMA(double &indicatorValue)
  {
   if(Bars < MathMax(InpFastMAPeriod, InpSlowMAPeriod) + 2)
      return(0);

   double fastPrev = iMA(NULL, 0, InpFastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2);
   double fastCurr = iMA(NULL, 0, InpFastMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
   double slowPrev = iMA(NULL, 0, InpSlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 2);
   double slowCurr = iMA(NULL, 0, InpSlowMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);

   indicatorValue = fastCurr - slowCurr;

   if(fastPrev <= slowPrev && fastCurr > slowCurr)
      return(1);

   if(fastPrev >= slowPrev && fastCurr < slowCurr)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Evaluate RSI thresholds                                          |
//+------------------------------------------------------------------+
int EvaluateRSI(double &indicatorValue)
  {
   if(Bars < InpRSIPeriod + 2)
      return(0);

   indicatorValue = iRSI(NULL, 0, InpRSIPeriod, PRICE_CLOSE, 1);
   if(indicatorValue < InpRSIBuyLevel)
      return(1);

   if(indicatorValue > InpRSISellLevel)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Evaluate CCI thresholds                                          |
//+------------------------------------------------------------------+
int EvaluateCCI(double &indicatorValue)
  {
   if(Bars < InpCCIPeriod + 2)
      return(0);

   indicatorValue = iCCI(NULL, 0, InpCCIPeriod, PRICE_TYPICAL, 1);

   if(indicatorValue > InpCCIUpperLevel)
      return(1);

   if(indicatorValue < InpCCILowerLevel)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Evaluate MACD signal cross                                       |
//+------------------------------------------------------------------+
int EvaluateMACD(double &indicatorValue)
  {
   if(Bars < InpMACDSlowEMA + InpMACDSignalSMA + 2)
      return(0);

   double macdPrevMain = iMACD(NULL, 0, InpMACDFastEMA, InpMACDSlowEMA, InpMACDSignalSMA, PRICE_CLOSE, MODE_MAIN, 2);
   double macdCurrMain = iMACD(NULL, 0, InpMACDFastEMA, InpMACDSlowEMA, InpMACDSignalSMA, PRICE_CLOSE, MODE_MAIN, 1);
   double macdPrevSig  = iMACD(NULL, 0, InpMACDFastEMA, InpMACDSlowEMA, InpMACDSignalSMA, PRICE_CLOSE, MODE_SIGNAL, 2);
   double macdCurrSig  = iMACD(NULL, 0, InpMACDFastEMA, InpMACDSlowEMA, InpMACDSignalSMA, PRICE_CLOSE, MODE_SIGNAL, 1);

   indicatorValue = macdCurrMain;

   if(macdPrevMain <= macdPrevSig && macdCurrMain > macdCurrSig)
      return(1);

   if(macdPrevMain >= macdPrevSig && macdCurrMain < macdCurrSig)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Evaluate Stochastic cross                                        |
//+------------------------------------------------------------------+
int EvaluateStochastic(double &indicatorValue)
  {
   int requiredBars = MathMax(InpStochKPeriod, MathMax(InpStochDPeriod, InpStochSlowing)) + 2;
   if(Bars < requiredBars)
      return(0);

   double kPrev = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   double dPrev = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH, MODE_SIGNAL, 2);
   double kCurr = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double dCurr = iStochastic(NULL, 0, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, MODE_SMA, STO_LOWHIGH, MODE_SIGNAL, 1);

   indicatorValue = kCurr;

   if(kPrev <= dPrev && kCurr > dCurr && kCurr < InpStochBuyLevel && dCurr < InpStochBuyLevel)
      return(1);

   if(kPrev >= dPrev && kCurr < dCurr && kCurr > InpStochSellLevel && dCurr > InpStochSellLevel)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Process individual strategy                                      |
//+------------------------------------------------------------------+
void ProcessStrategy(StrategyIndex index, const double atrValue)
  {
   StrategyState state = g_strategies[index];
   RefreshLossPause(state);
   g_strategies[index] = state;
   if(!state.enabled)
      return;

   StrategyBandSetting bandSetting;
   InitStrategyBandSetting(bandSetting);
   bool hasBandSetting = ResolveBandSetting(index, atrValue, bandSetting);
   if(hasBandSetting && !bandSetting.enabled)
     {
      PrintFormat("Band disabled: strategy=%s ATR=%.6f -> signal ignored", state.name, atrValue);
      return;
     }

   double indicatorValue = 0.0;
   int    direction      = 0;

   switch(index)
     {
      case STRAT_MA:
         direction = EvaluateMA(indicatorValue);
         break;
      case STRAT_RSI:
         direction = EvaluateRSI(indicatorValue);
         break;
      case STRAT_CCI:
         direction = EvaluateCCI(indicatorValue);
         break;
      case STRAT_MACD:
         direction = EvaluateMACD(indicatorValue);
         break;
     case STRAT_STOCH:
        direction = EvaluateStochastic(indicatorValue);
        break;
     }

  if(direction == 0)
     return;

   if(!IsTradingSessionOpen())
      return;

   if(IsStrategyInCooldown(state))
      return;

   if(HasOppositeStrategyPosition(index, direction))
      return;

   datetime signalBarTime = Time[1];

   if(state.lastBarTime == signalBarTime && state.lastDirection == direction)
      return;

   if(!g_multiPositionActive && HasOpenPosition(state))
      return;

   if(IsTradeContextBusy())
      return;

   if(!IsTradeAllowed(Symbol(), TimeCurrent()))
      return;

   TradeAttemptResult attempt = ExecuteEntry(state,
                                             direction,
                                             atrValue,
                                             indicatorValue,
                                             hasBandSetting,
                                             bandSetting);
   bool signalConsumed = (attempt == TRADE_ATTEMPT_PLACED ||
                          attempt == TRADE_ATTEMPT_CONSUMED);
   if(signalConsumed)
     {
      state.lastBarTime  = signalBarTime;
      state.lastDirection = direction;
      if(attempt == TRADE_ATTEMPT_PLACED)
         state.lastTradeTime = TimeCurrent();
      g_strategies[index] = state;
     }
  }

string DetermineExitReason(const int ticket,
                           const int direction,
                           const double openPrice,
                           const double closePrice,
                           const double stopLoss,
                           const double takeProfit,
                           const double netProfit)
  {
   double pip = PipSize();
   double tolerance = (pip > 0.0 ? pip * 0.1 : 0.0001);

   bool hasTp = (takeProfit > 0.0);
   bool hasSl = (stopLoss > 0.0);
   bool hitTp = (hasTp && MathAbs(closePrice - takeProfit) <= tolerance + 1e-8);
   bool hitSl = (hasSl && MathAbs(closePrice - stopLoss) <= tolerance + 1e-8);

   if(hitTp)
      return("TAKE_PROFIT");

  if(hitSl)
     {
      int metaIndex = FindTradeMetadataIndex(ticket);
      int beOffsetPips = InpBreakEvenOffsetPips;
      if(metaIndex >= 0)
        {
         TradeMetadata meta = g_tradeMetadata[metaIndex];
         StopUpdateReason reason = meta.lastStopReason;
         if(reason == STOP_UPDATE_BREAK_EVEN)
            return("STOP_BREAKEVEN");
         if(reason == STOP_UPDATE_TRAILING)
            return("STOP_TRAILING");
         if(meta.breakEvenOffsetPips >= 0)
            beOffsetPips = meta.breakEvenOffsetPips;
        }

      if(pip > 0.0)
        {
         double breakEvenStop = (direction > 0
                                 ? openPrice + beOffsetPips * pip
                                 : openPrice - beOffsetPips * pip);
         if(MathAbs(stopLoss - breakEvenStop) <= tolerance + 1e-8)
            return("STOP_BREAKEVEN");
        }
      return("STOP_LOSS");
     }

   if(netProfit > 0.0)
      return("MANUAL_PROFIT");

   if(netProfit < 0.0)
      return("MANUAL_LOSS");

   return("MANUAL_FLAT");
  }

//+------------------------------------------------------------------+
//| Check newly closed orders to log PnL                             |
//+------------------------------------------------------------------+
void CheckClosedOrders()
  {
   int total = OrdersHistoryTotal();
   bool processedNew = false;

   for(int i = total - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      int magic = OrderMagicNumber();
      int stratIndex = FindStrategyIndexByMagic(magic);
      if(stratIndex < 0)
         continue;

      int ticket = OrderTicket();
      if(IsExitLogged(ticket))
        {
         if(!processedNew)
            break;
         continue;
        }

      datetime closeTime = OrderCloseTime();
      if(closeTime == 0)
         continue;

      int direction = 0;
      if(OrderType() == OP_BUY)
         direction = 1;
      else if(OrderType() == OP_SELL)
         direction = -1;

      int metaIndex = FindTradeMetadataIndex(ticket);
      double entryAtr = EMPTY_VALUE;
      if(metaIndex >= 0)
         entryAtr = g_tradeMetadata[metaIndex].entryAtr;

      double volume     = OrderLots();
      double openPrice  = OrderOpenPrice();
      double closePrice = OrderClosePrice();
      double stopLoss   = OrderStopLoss();
      double takeProfit = OrderTakeProfit();
      double atrValue   = EMPTY_VALUE;
      int    closeShift = iBarShift(NULL, 0, closeTime, false);
      if(closeShift >= 0 && Bars > 0)
        {
         int atrShift = closeShift + 1;
         if(atrShift >= Bars)
            atrShift = Bars - 1;
         if(atrShift >= 0)
            atrValue = iATR(NULL, 0, InpATRPeriod, atrShift);
        }
      double profit     = OrderProfit();
      double swapValue  = OrderSwap();
      double commission = OrderCommission();
      double netProfit  = profit + swapValue + commission;
      string exitReason = DetermineExitReason(ticket,
                                              direction,
                                              openPrice,
                                              closePrice,
                                              stopLoss,
                                              takeProfit,
                                              netProfit);

      double pipValue = EMPTY_VALUE;
      double pipSize  = PipSize();
      if(pipSize > 0)
        {
         double diff = closePrice - openPrice;
         pipValue = diff / pipSize;
         if(direction < 0)
            pipValue = -pipValue;
        }

      LogTradeEvent(g_strategies[stratIndex],
                    "EXIT",
                    direction,
                    ticket,
                    volume,
                    closePrice,
                    entryAtr,
                    atrValue,
                    EMPTY_VALUE,
                    profit,
                    swapValue,
                    commission,
                    netProfit,
                    pipValue,
                    closeTime,
                    exitReason);

      StrategyState state = g_strategies[stratIndex];
      if(netProfit < 0.0)
        {
         state.lossStreak++;
         if(InpLossStreakPause > 0 && state.lossStreak >= InpLossStreakPause)
           {
            if(InpLossPauseMinutes > 0)
               state.lossPauseUntil = closeTime + InpLossPauseMinutes * 60;
            else
               state.lossPauseUntil = closeTime;
           }
        }
      else
        {
         state.lossStreak = 0;
         state.lossPauseUntil = 0;
        }
      g_strategies[stratIndex] = state;

      MarkExitLogged(ticket);
      RemoveTradeMetadata(ticket);
      processedNew = true;
     }
  }

//+------------------------------------------------------------------+
//| Manage break-even and ATR trailing stops for open orders         |
//+------------------------------------------------------------------+
void ManageOpenPositions(const double atrValue)
  {
   if(atrValue <= 0.0)
      return;

   double pip = PipSize();
   if(pip <= 0.0)
      return;

   double minStopDistance = GetMinimumStopDistance();
   if(minStopDistance <= 0.0)
      minStopDistance = pip;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      int orderType = OrderType();
      if(orderType != OP_BUY && orderType != OP_SELL)
         continue;

      int magic = OrderMagicNumber();
      int stratIndex = FindStrategyIndexByMagic(magic);
      if(stratIndex < 0)
         continue;

      RefreshRates();
      double currentPrice = (orderType == OP_BUY ? Bid : Ask);
      double openPrice    = OrderOpenPrice();
      double profitDistance = (orderType == OP_BUY
                               ? currentPrice - openPrice
                               : openPrice - currentPrice);
      if(profitDistance <= 0.0)
         continue;

      double currentStop = OrderStopLoss();
      double targetStop  = currentStop;
      bool   pendingUpdate = false;
      StopUpdateReason updateReason = STOP_UPDATE_NONE;

      int metaIndex = FindTradeMetadataIndex(OrderTicket());
      bool   breakEvenEnabled    = InpEnableBreakEven;
      double breakEvenAtrTrigger = InpBreakEvenAtrTrigger;
      int    breakEvenOffsetPips = InpBreakEvenOffsetPips;
      bool   trailingEnabled     = InpEnableAtrTrailing;
      double trailingAtrTrigger  = InpTrailingAtrTrigger;
      double trailingAtrStep     = InpTrailingAtrStep;
      int    trailingMinStepPips = InpTrailingMinStepPips;

      if(metaIndex < 0)
        {
         RegisterTradeMetadata(OrderTicket(),
                               (orderType == OP_BUY ? 1 : -1),
                               atrValue,
                               breakEvenEnabled,
                               breakEvenAtrTrigger,
                               breakEvenOffsetPips,
                               trailingEnabled,
                               trailingAtrTrigger,
                               trailingAtrStep,
                               trailingMinStepPips);
         metaIndex = FindTradeMetadataIndex(OrderTicket());
        }

      TradeMetadata meta;
      bool hasMeta = false;
      if(metaIndex >= 0)
        {
         meta = g_tradeMetadata[metaIndex];
         hasMeta = true;
         breakEvenEnabled     = meta.breakEvenEnabled;
         breakEvenAtrTrigger  = meta.breakEvenAtrTrigger;
         breakEvenOffsetPips  = meta.breakEvenOffsetPips;
         trailingEnabled      = meta.trailingEnabled;
         trailingAtrTrigger   = meta.trailingAtrTrigger;
         trailingAtrStep      = meta.trailingAtrStep;
         trailingMinStepPips  = meta.trailingMinStepPips;
        }

      if(!breakEvenEnabled && !trailingEnabled)
         continue;

      double atrForStopLogic = atrValue;
      if(hasMeta && meta.entryAtr > 0.0)
         atrForStopLogic = meta.entryAtr;

      double breakEvenTriggerDistance = (breakEvenAtrTrigger > 0.0 ? atrForStopLogic * breakEvenAtrTrigger : 0.0);
      double trailingTriggerDistance  = (trailingAtrTrigger > 0.0 ? atrForStopLogic * trailingAtrTrigger : 0.0);
      double trailingStepDistance     = (trailingAtrStep > 0.0 ? atrForStopLogic * trailingAtrStep : 0.0);
      double trailingMinStepDistance  = trailingMinStepPips * pip;
      if(trailingMinStepDistance <= 0.0)
         trailingMinStepDistance = pip;

      int normalizedBreakEvenOffset = breakEvenOffsetPips;
      if(normalizedBreakEvenOffset < 0)
         normalizedBreakEvenOffset = 0;

      double breakEvenStop = (orderType == OP_BUY
                              ? openPrice + normalizedBreakEvenOffset * pip
                              : openPrice - normalizedBreakEvenOffset * pip);
      bool breakEvenAvailable = false;

      if(breakEvenEnabled &&
         breakEvenAtrTrigger > 0.0 &&
         breakEvenTriggerDistance > 0.0 &&
         profitDistance >= breakEvenTriggerDistance - 1e-8)
        {
         if(orderType == OP_BUY)
           {
            double maxStop = currentPrice - minStopDistance;
            if(maxStop >= breakEvenStop - 1e-8)
              {
               breakEvenAvailable = true;
               if(IsBetterStopLoss(orderType, currentStop, breakEvenStop))
                 {
                  targetStop = breakEvenStop;
                  pendingUpdate = true;
                  updateReason = STOP_UPDATE_BREAK_EVEN;
                 }
              }
           }
         else
           {
            double minStop = currentPrice + minStopDistance;
            if(breakEvenStop >= minStop - 1e-8)
              {
               breakEvenAvailable = true;
               if(IsBetterStopLoss(orderType, currentStop, breakEvenStop))
                 {
                  targetStop = breakEvenStop;
                  pendingUpdate = true;
                  updateReason = STOP_UPDATE_BREAK_EVEN;
                 }
              }
           }
        }

      if(breakEvenEnabled && currentStop > 0.0)
        {
         if(orderType == OP_BUY && currentStop >= breakEvenStop - 1e-8)
            breakEvenAvailable = true;
         if(orderType == OP_SELL && currentStop <= breakEvenStop + 1e-8)
            breakEvenAvailable = true;
        }

      double trailingProtectStop = breakEvenStop;
      double trailingProtectDistance = normalizedBreakEvenOffset * pip;
      bool trailingProtectUnlocked = breakEvenAvailable;

      if(!trailingProtectUnlocked)
        {
         if(orderType == OP_BUY && currentStop >= trailingProtectStop - 1e-8)
            trailingProtectUnlocked = true;
         if(orderType == OP_SELL && currentStop <= trailingProtectStop + 1e-8)
            trailingProtectUnlocked = true;
        }

      if(!trailingProtectUnlocked && !breakEvenEnabled)
        {
         if(trailingProtectDistance <= 0.0)
            trailingProtectUnlocked = (profitDistance >= minStopDistance - 1e-8);
         else
            trailingProtectUnlocked = (profitDistance >= trailingProtectDistance - 1e-8);
        }

      if(trailingEnabled &&
         trailingTriggerDistance > 0.0 &&
         trailingStepDistance > 0.0 &&
         profitDistance >= trailingTriggerDistance - 1e-8)
        {
         double compareStop = (pendingUpdate ? targetStop : currentStop);

         if(orderType == OP_BUY)
           {
            double maxStop = currentPrice - minStopDistance;
            if(maxStop <= 0.0)
               continue;

            double trailingFloor = openPrice;
            if(trailingProtectUnlocked)
               trailingFloor = MathMax(trailingFloor, trailingProtectStop);

            if(trailingFloor > maxStop + 1e-8)
               continue;

           double candidate = currentPrice - trailingStepDistance;
           if(candidate > maxStop)
              candidate = maxStop;
           if(candidate < trailingFloor)
              candidate = trailingFloor;

            if(candidate < compareStop + trailingMinStepDistance)
              {
               candidate = compareStop + trailingMinStepDistance;
               if(candidate > maxStop)
                  candidate = maxStop;
               if(candidate < trailingFloor)
                  candidate = trailingFloor;
              }

            if(candidate < trailingFloor - 1e-8 || candidate > maxStop + 1e-8)
               continue;

            if(IsBetterStopLoss(orderType, compareStop, candidate))
              {
               targetStop = candidate;
               pendingUpdate = true;
               updateReason = STOP_UPDATE_TRAILING;
              }
           }
         else
           {
            double minStop = currentPrice + minStopDistance;
            double trailingCeiling = openPrice;
            if(trailingProtectUnlocked)
               trailingCeiling = MathMin(trailingCeiling, trailingProtectStop);

            if(trailingCeiling < minStop - 1e-8)
               continue;

           double candidate = currentPrice + trailingStepDistance;
           if(candidate < minStop)
              candidate = minStop;
           if(candidate > trailingCeiling)
              candidate = trailingCeiling;

            if(candidate > compareStop - trailingMinStepDistance)
              {
               candidate = compareStop - trailingMinStepDistance;
               if(candidate < minStop)
                  candidate = minStop;
               if(candidate > trailingCeiling)
                  candidate = trailingCeiling;
              }

            if(candidate > trailingCeiling + 1e-8 || candidate < minStop - 1e-8)
               continue;

            if(IsBetterStopLoss(orderType, compareStop, candidate))
              {
               targetStop = candidate;
               pendingUpdate = true;
               updateReason = STOP_UPDATE_TRAILING;
              }
           }
        }

      if(!pendingUpdate)
         continue;

      double takeProfit = OrderTakeProfit();
      if(!OrderModify(OrderTicket(),
                      OrderOpenPrice(),
                      NormalizeDouble(targetStop, Digits),
                      takeProfit,
                      0,
                      clrNONE))
        {
         Print("OrderModify failed for ticket ", OrderTicket(),
               ". Error: ", GetLastError());
         continue;
        }
      else
        {
         UpdateTradeStopMetadata(OrderTicket(), targetStop, updateReason);
        }
     }
  }


int OnInit()
  {
   if(InpLots <= 0.0)
     {
      Print("Invalid lot size: must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpStopLossPips < 0 || InpTakeProfitPips < 0)
     {
      Print("StopLoss and TakeProfit pips must be zero or positive.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpATRPeriod < 1)
     {
      Print("ATR period must be at least 1.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpFastMAPeriod <= 0 || InpSlowMAPeriod <= 0)
     {
      Print("MA periods must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpRSIPeriod <= 0)
     {
      Print("RSI period must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpCCIPeriod <= 0)
     {
      Print("CCI period must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpMACDFastEMA <= 0 || InpMACDSlowEMA <= 0 || InpMACDSignalSMA <= 0)
     {
      Print("MACD parameters must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(InpStochKPeriod <= 0 || InpStochDPeriod <= 0 || InpStochSlowing <= 0)
     {
      Print("Stochastic parameters must be greater than zero.");
      return(INIT_PARAMETERS_INCORRECT);
     }

  if(InpStochBuyLevel < 0.0 || InpStochSellLevel > 100.0 || InpStochBuyLevel >= InpStochSellLevel)
    {
     Print("Stochastic levels must satisfy 0 <= BuyLevel < SellLevel <= 100.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpMaxSpreadPips < 0.0)
    {
     Print("Max spread pips must be zero or positive.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpUseRiskBasedLots && InpRiskPercent <= 0.0)
    {
     Print("Risk percent must be greater than zero when risk-based lots are enabled.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpCooldownMinutes < 0 || InpLossStreakPause < 0 || InpLossPauseMinutes < 0)
    {
     Print("Cooldown and loss streak parameters must be zero or positive.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpUseTradingSessions)
    {
     if(InpSessionStartHour < 0 || InpSessionStartHour > 23 ||
        InpSessionEndHour <= 0 || InpSessionEndHour > 24 ||
        InpSessionStartHour >= InpSessionEndHour)
       {
        Print("Trading session hours must satisfy 0 <= start < end <= 24.");
        return(INIT_PARAMETERS_INCORRECT);
       }

     if(InpSessionSkipFriday && (InpFridayCutoffHour < 0 || InpFridayCutoffHour > 24))
       {
        Print("Friday cutoff hour must be between 0 and 24.");
        return(INIT_PARAMETERS_INCORRECT);
       }
    }

  if(InpUseATRStops)
    {
     if(InpATRStopMultiplier < 0.0 || InpATRTakeProfitMultiplier < 0.0)
       {
         Print("ATR multipliers must be zero or positive when ATR stops are enabled.");
         return(INIT_PARAMETERS_INCORRECT);
        }

      if(InpATRStopMultiplier == 0.0 && InpATRTakeProfitMultiplier == 0.0)
        {
         Print("At least one ATR multiplier must be greater than zero when ATR stops are enabled.");
         return(INIT_PARAMETERS_INCORRECT);
        }
     }

  if(InpEnableBreakEven)
    {
     if(InpBreakEvenAtrTrigger <= 0.0)
       {
        Print("Break-even ATR trigger must be greater than zero when break-even is enabled.");
        return(INIT_PARAMETERS_INCORRECT);
       }

     if(InpBreakEvenOffsetPips < 0)
       {
        Print("Break-even offset pips must be zero or positive.");
        return(INIT_PARAMETERS_INCORRECT);
       }
    }

  if(InpEnableAtrTrailing)
    {
     if(InpTrailingAtrTrigger <= 0.0 || InpTrailingAtrStep <= 0.0)
       {
        Print("Trailing ATR trigger and step must be greater than zero when ATR trailing is enabled.");
        return(INIT_PARAMETERS_INCORRECT);
       }

     if(InpTrailingMinStepPips < 0)
       {
        Print("Trailing minimum step pips must be zero or positive.");
        return(INIT_PARAMETERS_INCORRECT);
       }
    }

  if(InpMaxTotalPositions < 0)
    {
     Print("Max total positions must be zero or positive.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpMaxPositionsPerStrategy < 1)
    {
     Print("Max positions per strategy must be at least 1.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpLotReductionFactor < 0.0)
    {
     Print("Lot reduction factor must be zero or positive.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  if(InpMagicPrefix < 0)
    {
     Print("Magic prefix must be zero or positive.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  int maxMagicOffset = GetMaximumMagicOffset();
  long projectedMagic = (long)InpMagicPrefix + (long)maxMagicOffset;
  if(projectedMagic > kMaxIntValue)
    {
     Print("Magic prefix is too large. Resulting magic numbers exceed supported range.");
     return(INIT_PARAMETERS_INCORRECT);
    }

  g_strategies[STRAT_MA].name  = "MA_CROSS";
   g_strategies[STRAT_MA].comment = "MA";
   g_strategies[STRAT_MA].magic = GetStrategyMagic(STRAT_MA);
   g_strategies[STRAT_MA].enabled = InpEnableMA;
   g_strategies[STRAT_MA].lastBarTime = 0;
   g_strategies[STRAT_MA].lastDirection = 0;
   g_strategies[STRAT_MA].lastTradeTime = 0;
   g_strategies[STRAT_MA].lossStreak = 0;
   g_strategies[STRAT_MA].lossPauseUntil = 0;

   g_strategies[STRAT_RSI].name  = "RSI";
   g_strategies[STRAT_RSI].comment = "RSI";
   g_strategies[STRAT_RSI].magic = GetStrategyMagic(STRAT_RSI);
   g_strategies[STRAT_RSI].enabled = InpEnableRSI;
   g_strategies[STRAT_RSI].lastBarTime = 0;
   g_strategies[STRAT_RSI].lastDirection = 0;
   g_strategies[STRAT_RSI].lastTradeTime = 0;
   g_strategies[STRAT_RSI].lossStreak = 0;
   g_strategies[STRAT_RSI].lossPauseUntil = 0;

   g_strategies[STRAT_CCI].name  = "CCI";
   g_strategies[STRAT_CCI].comment = "CCI";
   g_strategies[STRAT_CCI].magic = GetStrategyMagic(STRAT_CCI);
   g_strategies[STRAT_CCI].enabled = InpEnableCCI;
   g_strategies[STRAT_CCI].lastBarTime = 0;
   g_strategies[STRAT_CCI].lastDirection = 0;
   g_strategies[STRAT_CCI].lastTradeTime = 0;
   g_strategies[STRAT_CCI].lossStreak = 0;
   g_strategies[STRAT_CCI].lossPauseUntil = 0;

   g_strategies[STRAT_MACD].name  = "MACD";
   g_strategies[STRAT_MACD].comment = "MACD";
   g_strategies[STRAT_MACD].magic = GetStrategyMagic(STRAT_MACD);
   g_strategies[STRAT_MACD].enabled = InpEnableMACD;
   g_strategies[STRAT_MACD].lastBarTime = 0;
   g_strategies[STRAT_MACD].lastDirection = 0;
   g_strategies[STRAT_MACD].lastTradeTime = 0;
   g_strategies[STRAT_MACD].lossStreak = 0;
   g_strategies[STRAT_MACD].lossPauseUntil = 0;

   g_strategies[STRAT_STOCH].name  = "STOCH";
   g_strategies[STRAT_STOCH].comment = "STOCH";
   g_strategies[STRAT_STOCH].magic = GetStrategyMagic(STRAT_STOCH);
   g_strategies[STRAT_STOCH].enabled = InpEnableStoch;
   g_strategies[STRAT_STOCH].lastBarTime = 0;
   g_strategies[STRAT_STOCH].lastDirection = 0;
   g_strategies[STRAT_STOCH].lastTradeTime = 0;
   g_strategies[STRAT_STOCH].lossStreak = 0;
   g_strategies[STRAT_STOCH].lossPauseUntil = 0;

   g_enabledStrategyCount = 0;
   for(int stratIdx = 0; stratIdx < STRAT_TOTAL; stratIdx++)
     {
      if(g_strategies[stratIdx].enabled)
         g_enabledStrategyCount++;
     }

   g_profileLabel = StringTrimLeft(StringTrimRight(InpProfileName));
   if(StringLen(g_profileLabel) == 0)
      g_profileLabel = "Default";

   g_runId = BuildRunIdentifier();

   string safeProfile = SanitiseProfileName(InpProfileName);
   g_resultLogFileName = "TradeLog_" + safeProfile + ".csv";
   g_parameterLogFileName = "TradeParams_" + safeProfile + "_" + g_runId + ".csv";

   UpdateDynamicPositionControls();

   LogInputParameters(safeProfile);

   bool configLoaded = LoadAtrBandConfig(safeProfile);
   if(configLoaded)
     {
      LogBandConfigurations();
      AppendBandConfigSnapshot();
     }
   else
     {
      if(InpUseAtrBandConfig)
         PrintFormat("ATR band config could not be applied. Using defaults. (file='%s')", g_bandConfigPath);
      else
         Print("ATR band config disabled via input parameter.");
     }

   EnsureResultLogHeader();
   LoadLoggedExitTickets();
   InitialiseTradeMetadata();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(Bars < 200)
      return;

   UpdateDynamicPositionControls();

   double atrValue = iATR(NULL, 0, InpATRPeriod, 1);

   ProcessStrategy(STRAT_MA, atrValue);
   ProcessStrategy(STRAT_RSI, atrValue);
   ProcessStrategy(STRAT_CCI, atrValue);
   ProcessStrategy(STRAT_MACD, atrValue);
   ProcessStrategy(STRAT_STOCH, atrValue);

   ManageOpenPositions(atrValue);

   CheckClosedOrders();
  }

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // No special cleanup required
  }
