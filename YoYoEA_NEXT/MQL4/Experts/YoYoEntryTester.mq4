#property strict
#property version   "1.00"
#property description "Entry evaluation EA for MA, RSI, CCI, and MACD strategies."

//--- input parameters
input string InpProfileName     = "Default";
input double InpLots            = 0.10;
input int    InpStopLossPips    = 50;
input int    InpTakeProfitPips  = 50;
input int    InpSlippage        = 3;

input bool   InpEnableMA        = true;
input bool   InpEnableRSI       = true;
input bool   InpEnableCCI       = true;
input bool   InpEnableMACD      = true;

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

//--- strategy meta definitions
enum StrategyIndex
  {
   STRAT_MA = 0,
   STRAT_RSI,
   STRAT_CCI,
   STRAT_MACD,
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
  };

StrategyState g_strategies[STRAT_TOTAL];
string        g_logFileName;
string        g_profileLabel;

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
//| Utility: write entry info to CSV log                             |
//+------------------------------------------------------------------+
void LogEntry(const StrategyState &state,
              const int direction,
              const int ticket,
              const double price,
              const double atrValue,
              const double indicatorValue)
  {
   int handle = FileOpen(g_logFileName,
                         FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE,
                         ',');
   if(handle == INVALID_HANDLE)
     {
      Print("Failed to open log file ", g_logFileName, ". Error: ", GetLastError());
      return;
     }

   string directionText = (direction > 0 ? "BUY" : "SELL");
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle,
             TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
             Symbol(),
             g_profileLabel,
             state.name,
             directionText,
             IntegerToString(ticket),
             DoubleToString(price, Digits),
             DoubleToString(atrValue, 6),
             DoubleToString(indicatorValue, 6));
   FileClose(handle);
  }

//+------------------------------------------------------------------+
//| Utility: place trade with SL/TP                                  |
//+------------------------------------------------------------------+
bool ExecuteEntry(const StrategyState &state,
                  const int direction,
                  const double atrValue,
                  const double indicatorValue)
  {
   RefreshRates();

   int    cmd   = (direction > 0 ? OP_BUY : OP_SELL);
   double price = (cmd == OP_BUY ? Ask : Bid);
   double pip   = PipSize();

   double sl = 0.0;
   double tp = 0.0;

   if(InpStopLossPips > 0)
     {
      double dist = InpStopLossPips * pip;
      sl = (cmd == OP_BUY ? price - dist : price + dist);
      sl = NormalizeDouble(sl, Digits);
     }

   if(InpTakeProfitPips > 0)
     {
      double dist = InpTakeProfitPips * pip;
      tp = (cmd == OP_BUY ? price + dist : price - dist);
      tp = NormalizeDouble(tp, Digits);
     }

   string comment = state.comment;
   ResetLastError();
   int ticket = OrderSend(Symbol(),
                          cmd,
                          InpLots,
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
      return(false);
     }

   if(OrderSelect(ticket, SELECT_BY_TICKET))
     {
      LogEntry(state, direction, ticket, OrderOpenPrice(), atrValue, indicatorValue);
     }
   else
     {
      Print("OrderSelect failed for ticket ", ticket,
            ". Error: ", GetLastError());
     }

   return(true);
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
//| Process individual strategy                                      |
//+------------------------------------------------------------------+
void ProcessStrategy(StrategyIndex index, const double atrValue)
  {
   StrategyState state = g_strategies[index];
   if(!state.enabled)
      return;

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
     }

   if(direction == 0)
      return;

   datetime signalBarTime = Time[1];

   if(state.lastBarTime == signalBarTime && state.lastDirection == direction)
      return;

   if(HasOpenPosition(state))
      return;

   if(IsTradeContextBusy())
      return;

   if(!IsTradeAllowed(Symbol(), TimeCurrent()))
      return;

   if(ExecuteEntry(state, direction, atrValue, indicatorValue))
     {
      state.lastBarTime  = signalBarTime;
      state.lastDirection = direction;
      g_strategies[index] = state;
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
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

   g_strategies[STRAT_MA].name  = "MA_CROSS";
   g_strategies[STRAT_MA].comment = "MA";
   g_strategies[STRAT_MA].magic = 10101;
   g_strategies[STRAT_MA].enabled = InpEnableMA;
   g_strategies[STRAT_MA].lastBarTime = 0;
   g_strategies[STRAT_MA].lastDirection = 0;

   g_strategies[STRAT_RSI].name  = "RSI";
   g_strategies[STRAT_RSI].comment = "RSI";
   g_strategies[STRAT_RSI].magic = 10201;
   g_strategies[STRAT_RSI].enabled = InpEnableRSI;
   g_strategies[STRAT_RSI].lastBarTime = 0;
   g_strategies[STRAT_RSI].lastDirection = 0;

   g_strategies[STRAT_CCI].name  = "CCI";
   g_strategies[STRAT_CCI].comment = "CCI";
   g_strategies[STRAT_CCI].magic = 10301;
   g_strategies[STRAT_CCI].enabled = InpEnableCCI;
   g_strategies[STRAT_CCI].lastBarTime = 0;
   g_strategies[STRAT_CCI].lastDirection = 0;

   g_strategies[STRAT_MACD].name  = "MACD";
   g_strategies[STRAT_MACD].comment = "MACD";
   g_strategies[STRAT_MACD].magic = 10401;
   g_strategies[STRAT_MACD].enabled = InpEnableMACD;
   g_strategies[STRAT_MACD].lastBarTime = 0;
   g_strategies[STRAT_MACD].lastDirection = 0;

   g_profileLabel = StringTrimLeft(StringTrimRight(InpProfileName));
   if(StringLen(g_profileLabel) == 0)
      g_profileLabel = "Default";

   string safeProfile = SanitiseProfileName(InpProfileName);
   g_logFileName      = "EntryLog_" + safeProfile + ".csv";

   int handle = FileOpen(g_logFileName,
                         FILE_CSV | FILE_READ | FILE_WRITE | FILE_SHARE_READ | FILE_SHARE_WRITE,
                         ',');
   if(handle != INVALID_HANDLE)
     {
      if(FileSize(handle) == 0)
         FileWrite(handle,
                   "timestamp",
                   "symbol",
                   "profile",
                   "strategy",
                   "direction",
                   "ticket",
                   "price",
                   "atr",
                   "indicator");
      FileClose(handle);
     }
   else
     {
      Print("Failed to initialise log file ", g_logFileName,
            ". Error: ", GetLastError());
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(Bars < 200)
      return;

   double atrValue = iATR(NULL, 0, InpATRPeriod, 1);

   ProcessStrategy(STRAT_MA, atrValue);
   ProcessStrategy(STRAT_RSI, atrValue);
   ProcessStrategy(STRAT_CCI, atrValue);
   ProcessStrategy(STRAT_MACD, atrValue);
  }

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // No special cleanup required
  }
