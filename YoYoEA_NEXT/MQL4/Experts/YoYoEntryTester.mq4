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
input bool   InpEnableStoch     = true;

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
  };

StrategyState g_strategies[STRAT_TOTAL];
string        g_logFileName;
string        g_profileLabel;
string        g_resultLogFileName;
int           g_exitLoggedTickets[];

#define RESULT_LOG_COLUMNS 16

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
//| Utility: find strategy index by magic number                     |
//+------------------------------------------------------------------+
int FindStrategyIndexByMagic(const int magic)
  {
   for(int i = 0; i < STRAT_TOTAL; i++)
     {
      if(g_strategies[i].magic == magic)
         return(i);
     }
   return(-1);
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
                "event",
                "symbol",
                "profile",
                "strategy",
                "direction",
                "ticket",
                "volume",
                "price",
                "atr",
                "indicator",
                "profit",
                "swap",
                "commission",
                "net",
                "pips");
      FileClose(handle);
      return(true);
     }

   if(FileSize(handle) == 0)
     {
      FileWrite(handle,
                "timestamp",
                "event",
                "symbol",
                "profile",
                "strategy",
                "direction",
                "ticket",
                "volume",
                "price",
                "atr",
                "indicator",
                "profit",
                "swap",
                "commission",
                "net",
                "pips");
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

   for(int i = 0; i < RESULT_LOG_COLUMNS && !FileIsEnding(handle); i++)
      FileReadString(handle);

   while(!FileIsEnding(handle))
     {
      string fields[RESULT_LOG_COLUMNS];
      bool   rowComplete = true;
      for(int col = 0; col < RESULT_LOG_COLUMNS; col++)
        {
         if(FileIsEnding(handle))
           {
            rowComplete = false;
            break;
           }
         fields[col] = FileReadString(handle);
        }

      if(!rowComplete)
         break;

      if(StringLen(fields[0]) == 0 && StringLen(fields[1]) == 0)
         continue;

      if(fields[1] == "EXIT")
        {
         int ticket = (int)StringToInteger(fields[6]);
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
                   const double atrValue,
                   const double indicatorValue,
                   const double profit,
                   const double swapValue,
                   const double commissionValue,
                   const double netProfit,
                   const double pipsValue,
                   const datetime eventTime)
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
   string atrText        = (atrValue == EMPTY_VALUE ? "" : DoubleToString(atrValue, 6));
   string indicatorText  = (indicatorValue == EMPTY_VALUE ? "" : DoubleToString(indicatorValue, 6));
   string profitText     = (profit == EMPTY_VALUE ? "" : DoubleToString(profit, 2));
   string swapText       = (swapValue == EMPTY_VALUE ? "" : DoubleToString(swapValue, 2));
   string commissionText = (commissionValue == EMPTY_VALUE ? "" : DoubleToString(commissionValue, 2));
   string netText        = (netProfit == EMPTY_VALUE ? "" : DoubleToString(netProfit, 2));
   string pipsText       = (pipsValue == EMPTY_VALUE ? "" : DoubleToString(pipsValue, 1));

   FileWrite(handle,
             TimeToString(eventTime, TIME_DATE | TIME_SECONDS),
             eventType,
             Symbol(),
             g_profileLabel,
             state.name,
             directionText,
             IntegerToString(ticket),
             DoubleToString(volume, 2),
             priceText,
             atrText,
             indicatorText,
             profitText,
             swapText,
             commissionText,
             netText,
             pipsText);

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
      LogTradeEvent(state,
                    "ENTRY",
                    direction,
                    ticket,
                    OrderLots(),
                    OrderOpenPrice(),
                    atrValue,
                    indicatorValue,
                    EMPTY_VALUE,
                    EMPTY_VALUE,
                    EMPTY_VALUE,
                    EMPTY_VALUE,
                    EMPTY_VALUE,
                    OrderOpenTime());
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
      case STRAT_STOCH:
         direction = EvaluateStochastic(indicatorValue);
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

      double volume     = OrderLots();
      double closePrice = OrderClosePrice();
      double atrValue   = iATR(NULL, 0, InpATRPeriod, 0);
      double profit     = OrderProfit();
      double swapValue  = OrderSwap();
      double commission = OrderCommission();
      double netProfit  = profit + swapValue + commission;

      double pipValue = EMPTY_VALUE;
      double pipSize  = PipSize();
      if(pipSize > 0)
        {
         double diff = OrderClosePrice() - OrderOpenPrice();
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
                    atrValue,
                    EMPTY_VALUE,
                    profit,
                    swapValue,
                    commission,
                    netProfit,
                    pipValue,
                    closeTime);

      MarkExitLogged(ticket);
      processedNew = true;
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

   g_strategies[STRAT_STOCH].name  = "STOCH";
   g_strategies[STRAT_STOCH].comment = "STOCH";
   g_strategies[STRAT_STOCH].magic = 10501;
   g_strategies[STRAT_STOCH].enabled = InpEnableStoch;
   g_strategies[STRAT_STOCH].lastBarTime = 0;
   g_strategies[STRAT_STOCH].lastDirection = 0;

   g_profileLabel = StringTrimLeft(StringTrimRight(InpProfileName));
   if(StringLen(g_profileLabel) == 0)
      g_profileLabel = "Default";

   string safeProfile = SanitiseProfileName(InpProfileName);
   g_logFileName      = "EntryLog_" + safeProfile + ".csv";
   g_resultLogFileName = "TradeLog_" + safeProfile + ".csv";

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

   EnsureResultLogHeader();
   LoadLoggedExitTickets();

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
   ProcessStrategy(STRAT_STOCH, atrValue);

   CheckClosedOrders();
  }

//+------------------------------------------------------------------+
//| Expert deinitialisation                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // No special cleanup required
  }
