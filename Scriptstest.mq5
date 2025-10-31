//+------------------------------------------------------------------+
//|                                                  ScalpingM1EA.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input double   LotSize = 0.05;           // Lot size
input int      TP_Pips = 100;             // Take Profit (pips)
input int      SL_Pips = 60;             // Stop Loss (pips)
input int      TolerancePips = 9;        // Tolerance from psychological level (pips)
input int      EMA_Fast_Period = 9;      // Fast EMA period
input int      EMA_Slow_Period = 21;     // Slow EMA period

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int emaFastHandle, emaSlowHandle;
double pipValue;
bool tradeOpened = false;
double currentPsychLevel = 0;
datetime currentBarTime = 0;
MqlRates currentRates[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize EMA handles
    emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast_Period, 0, MODE_EMA, PRICE_CLOSE);
    emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow_Period, 0, MODE_EMA, PRICE_CLOSE);
    
    // Calculate accurate pip value for XAUUSD
    pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 10; // Adjust for XAUUSD
    
    if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE)
    {
        Print("Error creating indicator handles");
        return(INIT_FAILED);
    }
    
    Print("EA initialized successfully - Pip Value: ", pipValue);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
    if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
}

//+------------------------------------------------------------------+
//| Get psychological level (multiple of 5)                          |
//+------------------------------------------------------------------+
double GetPsychologicalLevel(double price)
{
    int integerPart = (int)MathFloor(price);
    // Check if integer part is multiple of 5
    if(integerPart % 5 == 0)
        return (double)integerPart;
    return 0; // 0 means no valid psychological level
}

//+------------------------------------------------------------------+
//| Get accurate daily OHLC                                          |
//+------------------------------------------------------------------+
bool GetDailyOHLC(double &dailyOpen, double &dailyHigh, double &dailyLow, double &dailyClose)
{
    MqlRates dailyRates[];
    ArraySetAsSeries(dailyRates, true);
    
    // Get daily data - use 2 days to ensure we have current day
    if(CopyRates(_Symbol, PERIOD_D1, 0, 2, dailyRates) < 2)
        return false;
    
    // Use the most recent complete daily bar
    dailyOpen = dailyRates[1].open;
    dailyHigh = dailyRates[1].high;
    dailyLow = dailyRates[1].low;
    dailyClose = dailyRates[1].close;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if we can open new trade                                   |
//+------------------------------------------------------------------+
bool CanOpenTrade()
{
    // Check if there are no open positions for this symbol
    if(PositionSelect(_Symbol))
        return false;
    
    // Check if we already opened a trade in this EA instance
    if(tradeOpened)
        return false;
        
    // Check if this is a new bar (to avoid multiple entries on same bar)
    datetime newBarTime[1];
    if(CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, newBarTime) > 0)
    {
        if(newBarTime[0] == currentBarTime)
            return false; // Same bar, don't open new trade
        currentBarTime = newBarTime[0];
    }
        
    return true;
}

//+------------------------------------------------------------------+
//| Open buy order                                                   |
//+------------------------------------------------------------------+
bool OpenBuyOrder(double entryPrice, double sl, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_BUY;
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    
    if(OrderSend(request, result))
    {
        Print("BUY order opened. Ticket: ", result.order, 
              " Entry: ", entryPrice, 
              " SL: ", sl, 
              " TP: ", tp);
        tradeOpened = true;
        return true;
    }
    else
    {
        Print("Error opening BUY order: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Open sell order                                                  |
//+------------------------------------------------------------------+
bool OpenSellOrder(double entryPrice, double sl, double tp)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    ZeroMemory(result);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = LotSize;
    request.type = ORDER_TYPE_SELL;
    request.price = entryPrice;
    request.sl = sl;
    request.tp = tp;
    request.deviation = 10;
    request.magic = 12345;
    
    if(OrderSend(request, result))
    {
        Print("SELL order opened. Ticket: ", result.order,
              " Entry: ", entryPrice,
              " SL: ", sl,
              " TP: ", tp);
        tradeOpened = true;
        return true;
    }
    else
    {
        Print("Error opening SELL order: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Check if position exists                                         |
//+------------------------------------------------------------------+
bool PositionExists()
{
    return PositionSelect(_Symbol);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Get current bar data
    if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 1, currentRates) < 1)
        return;
        
    double currentClose = currentRates[0].close;
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Get daily OHLC
    double dailyOpen, dailyHigh, dailyLow, dailyClose;
    if(!GetDailyOHLC(dailyOpen, dailyHigh, dailyLow, dailyClose))
    {
        Print("Error getting daily data");
        return;
    }
    
    // Get EMA values
    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    
    if(CopyBuffer(emaFastHandle, 0, 0, 2, emaFast) <= 0 ||
       CopyBuffer(emaSlowHandle, 0, 0, 2, emaSlow) <= 0)
    {
        Print("Error getting EMA data");
        return;
    }
    
    // Get psychological level based on current close
    currentPsychLevel = GetPsychologicalLevel(currentClose);
    
    // Check if we can open new trade
    if(!CanOpenTrade())
    {
        // Reset tradeOpened flag if position was closed
        if(tradeOpened && !PositionExists())
        {
            tradeOpened = false;
            Print("Position closed, ready for new trade");
        }
        return;
    }
    
    // Determine trend using current EMA values
    bool trendBullish = emaFast[0] > emaSlow[0];
    bool trendBearish = emaFast[0] < emaSlow[0];
    
    // Check daily levels conditions (SAMA PERSIS dengan TradingView)
    bool aboveLevel2 = currentClose > dailyOpen && currentClose < dailyHigh;
    bool aboveLevel1 = currentClose > dailyHigh;
    bool belowLevel3 = currentClose < dailyOpen && currentClose > dailyLow;
    bool belowLevel4 = currentClose < dailyLow;
    
    // Debug information
    Print(StringFormat("Close: %.2f, Daily O: %.2f H: %.2f L: %.2f C: %.2f", 
          currentClose, dailyOpen, dailyHigh, dailyLow, dailyClose));
    Print(StringFormat("Levels - A1: %d, A2: %d, B3: %d, B4: %d", 
          aboveLevel1, aboveLevel2, belowLevel3, belowLevel4));
    Print(StringFormat("Trend - Bullish: %d, Bearish: %d", trendBullish, trendBearish));
    Print(StringFormat("Psych Level: %.2f", currentPsychLevel));
    
    // Check if price is near psychological level
    bool nearPsychLevel = false;
    if(currentPsychLevel > 0)
    {
        double tolerance = TolerancePips * pipValue;
        nearPsychLevel = MathAbs(currentClose - currentPsychLevel) <= tolerance;
        Print(StringFormat("Near Psych: %d, Distance: %.4f, Tolerance: %.4f", 
              nearPsychLevel, MathAbs(currentClose - currentPsychLevel), tolerance));
    }
    
    // Check entry conditions (SAMA PERSIS dengan TradingView)
    bool buyCondition = trendBullish && (aboveLevel1 || aboveLevel2) && nearPsychLevel;
    bool sellCondition = trendBearish && (belowLevel3 || belowLevel4) && nearPsychLevel;
    
    Print(StringFormat("BUY Condition: %d, SELL Condition: %d", buyCondition, sellCondition));
    
    // Open trades if conditions are met
    if(buyCondition)
    {
        double entryPrice = currentAsk;
        double tpPrice = entryPrice + (TP_Pips * pipValue);
        double slPrice = entryPrice - (SL_Pips * pipValue);
        
        Print(StringFormat("BUY Signal - Entry: %.2f, TP: %.2f, SL: %.2f", 
              entryPrice, tpPrice, slPrice));
              
        if(OpenBuyOrder(entryPrice, slPrice, tpPrice))
        {
            Print("BUY order executed at psychological level: ", currentPsychLevel);
        }
    }
    else if(sellCondition)
    {
        double entryPrice = currentBid;
        double tpPrice = entryPrice - (TP_Pips * pipValue);
        double slPrice = entryPrice + (SL_Pips * pipValue);
        
        Print(StringFormat("SELL Signal - Entry: %.2f, TP: %.2f, SL: %.2f", 
              entryPrice, tpPrice, slPrice));
              
        if(OpenSellOrder(entryPrice, slPrice, tpPrice))
        {
            Print("SELL order executed at psychological level: ", currentPsychLevel);
        }
    }
}

//+------------------------------------------------------------------+