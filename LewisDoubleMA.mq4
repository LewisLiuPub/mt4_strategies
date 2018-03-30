//+------------------------------------------------------------------+
//|                                                LewisDoubleMA.mq4 |
//|                                            Copyright 2016, Lewis |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Version 1.02
//|    1. Change Strategy:
//|       Only send 1 order on 1 Bar, BUT check close condition in 
//|       every tick.
//| Version 1.01
//|    1. add checkForClose strategy
//|    2. Add limitation for OrderSend, 
//|         send order if AccountMargin/Equity < 30%
//+------------------------------------------------------------------+

#property copyright "Copyright 2016, Lewis"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict

//--- input parameters
extern int      ShortMA=5;
extern int      LongMA=10;
extern double   BaseLots = 0.01;
extern ENUM_APPLIED_PRICE PriceType = PRICE_OPEN;
//extern ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT;

#define MAGICLEWIS 7799

//+-----------------------------+
//+ CROSSING TYPE DEFINITION    +
//+-----------------------------+
#define CROSSING_NONE         0
#define CROSSING_SHORTMA_UP   1
#define CROSSING_SHORTMA_DOWN 2
#define CROSSING_LONGMA_UP    4
#define CROSSING_LONGMA_DOWN  8
//#define CROSSING_CROSSED    128
#define CROSSING_GOLD        16
#define CROSSING_DEAD        32
//Uncrossed, shortMA is above longMA
#define CROSSING_UNCROSSED_UP    64
//Uncrossed, shortMA is below longMA
#define CROSSING_UNCROSSED_DOWN 128

//+-----------------------------+
//+ ORDER WEIGHT DEFINITION     +
//+-----------------------------+
//For Gold cross + W1 UP (shortMA > longMA)
#define ORDER_WEIGHT_1    (CROSSING_SHORTMA_UP | CROSSING_LONGMA_UP)
#define ORDER_WEIGHT_2    (CROSSING_SHORTMA_UP | CROSSING_LONGMA_DOWN)
#define ORDER_WEIGHT_3    (CROSSING_SHORTMA_DOWN | CROSSING_LONGMA_UP)
#define ORDER_WEIGHT_4    (CROSSING_SHORTMA_DOWN | CROSSING_LONGMA_DOWN)

//For Gold cross + W1 DOWN (shortMA < longMA)
#define LOT_WEIGHT_1      10
#define LOT_WEIGHT_2      7
#define LOT_WEIGHT_3      7
#define LOT_WEIGHT_4      5
#define LOT_WEIGHT_5      5
#define LOT_WEIGHT_6      2
#define LOT_WEIGHT_7      2
#define LOT_WEIGHT_8      1

//+-----------------------------+
//+ DIRECTION DEFINITION        +
//+-----------------------------+
#define DIRECTION_NONE 0
//ShortMA line is above LongMA line
#define DIRECTION_UP   CROSSING_UNCROSSED_UP
//ShortMA line is below LongMA line
#define DIRECTION_DOWN CROSSING_UNCROSSED_DOWN

#define DURATION_NOW      -1
#define DURATION_MONTH   (60*24*30)
#define DURATION_WEEK    (60*24*7)
//NOTE: change DURATION_DEFAULT value to choose the profit strategy
#define DURATION_DEFAULT  DURATION_NOW

int last_t = 0; //only one order in one bar.

int FindLongerTimeframe(int timeframe)
{
    //timeframes group supported by this code
    int timeframes[] = {0, 1, 5, 15, 30, 60, 240, 1440, 10080, 43200};
    int i = 0;
    
    if(timeframe == 0) timeframe = Period();
    
    for(;i<10;i++){
        if(timeframes[i] == timeframe) break;
    }
    i++;
    
    return(timeframes[i]);
}
//+------------------------------------------------------------------+
//+ Check Cross Status in D1 chart.
//+
//+ Return Value
//+    CROSSING_NONE: Crossing is not happened
//+    CROSSING_GOLD: The short MA period crossed UP the long MA line.
//+    CROSSING_DEAD: The short MA period crossed DOWN the long MA line.
int CheckCross(int timeframe)
{
    double s, l, last_s, last_l; //MA data
    int ret = 0; //return value
    
    s = iMA(NULL, timeframe, ShortMA, 0, MODE_SMA, PriceType, 0);
    l = iMA(NULL, timeframe, LongMA, 0, MODE_SMA, PriceType, 0);
    last_s = iMA(NULL, timeframe, ShortMA, 0, MODE_SMA, PriceType, 1);
    last_l = iMA(NULL, timeframe, LongMA, 0, MODE_SMA, PriceType, 1);

    if ( s >= last_s ) ret |= CROSSING_SHORTMA_UP;
    else ret |= CROSSING_SHORTMA_DOWN;
    if ( l >= last_l ) ret |= CROSSING_LONGMA_UP;
    else ret |= CROSSING_LONGMA_DOWN;
    
    if(last_s < last_l && s >= l) ret |= CROSSING_GOLD;
    if(last_s > last_l && s <= l) ret |= CROSSING_DEAD;
    
    if(last_s > last_l && s > l) ret |= CROSSING_UNCROSSED_UP;
    if(last_s < last_l && s < l) ret |= CROSSING_UNCROSSED_DOWN;
    
    //Print("timeframe=",timeframe, ", curS=",s,", lastS=", last_s, ", curL=",l,", lastL=",last_l, "==>RETURN:", ret);
    
    
    return(ret);
}

//+------------------------------------------------------------------+
//| Calculate open positions                                         |
//+------------------------------------------------------------------+
int CalculateCurrentOrders(string symbol)
{
   int buys=0,sells=0;

   for(int i=0;i<OrdersTotal();i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) break;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==MAGICLEWIS)
        {
         if(OrderType()==OP_BUY)  buys++;
         if(OrderType()==OP_SELL) sells++;
        }
     }
     
   //--- return orders volume
   if(buys>0) return(buys);
   else       return(-sells);
}


//+------------------------------------------------------------------+
//| Calculate total profit for buy orders or sell orders             |
//+------------------------------------------------------------------+
double CalculateTotalProfit(int otype, int duration=DURATION_DEFAULT)
{
    double total = 0.0;
    for (int i=0;i<OrdersTotal(); i++){
        if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
        if(OrderMagicNumber()!=MAGICLEWIS || OrderSymbol()!=Symbol()) continue;
        if(OrderType()== otype && (duration == DURATION_NOW || ((OrderOpenTime() - Time[0])/60 > duration))){
            total += OrderProfit();
        }
    }
    
    return(total);
}

//+------------------------------------------------------------------+
//| Check for Close based on OP_TYPE (OP_BUY or OP_SELL)             
//|   
//+------------------------------------------------------------------+
void CheckForClose(int otype, int duration=DURATION_DEFAULT)
{
    if (CalculateTotalProfit(otype, duration)<= 0) return;
    
    for (int i=0;i<OrdersTotal(); i++){
        if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
        if(OrderMagicNumber()!=MAGICLEWIS || OrderSymbol()!=Symbol()) continue;
        if(OrderType()== otype && (duration == DURATION_NOW || ((OrderOpenTime() - Time[0])/60 > duration))){
            if (otype == OP_BUY){
                 if(!OrderClose(OrderTicket(),OrderLots(),Bid,3,Blue))
                        Print("OrderClose error ",GetLastError());
            }
            if (otype == OP_SELL){
                if(!OrderClose(OrderTicket(),OrderLots(),Ask,3,Violet))
                        Print("OrderClose error ",GetLastError());
            }
        }
    }
    
}


int start()
{
    double shortma, longma;
    int isCrossed = CROSSING_NONE;
    int crossShort = CheckCross(0);
    int crossLong = CheckCross(FindLongerTimeframe(0));
    int buy = 0;
    int lotRatio = 0;
    int ticket;
    
    if( Bars < 100 ){
        Print("bar number is less than 100, do nothing!");
        return(0);
    }
    
    //Print("timeframe:", PERIOD_CURRENT);
    //Print("CrossShort=", crossShort);
    //Print("crossLong=", crossLong);
    //if gold cross occurs in D1 chart
    if(crossShort & CROSSING_GOLD){ //GOLD cross
        buy=1;
        //Check cross status in W1 chart: if short MA line is above long MA line
        if(crossLong & CROSSING_UNCROSSED_UP){
            if((crossShort & ORDER_WEIGHT_1) == ORDER_WEIGHT_1) lotRatio = LOT_WEIGHT_1;
            if((crossShort & ORDER_WEIGHT_2) == ORDER_WEIGHT_2) lotRatio = LOT_WEIGHT_2;
            if((crossShort & ORDER_WEIGHT_3) == ORDER_WEIGHT_3) lotRatio = LOT_WEIGHT_3;
            if((crossShort & ORDER_WEIGHT_4) == ORDER_WEIGHT_4) lotRatio = LOT_WEIGHT_4;
        }else{ //if(crossW1 & CROSSING_UNCROSSED_UP)
            if((crossShort & ORDER_WEIGHT_1) == ORDER_WEIGHT_1) lotRatio = LOT_WEIGHT_5;
            if((crossShort & ORDER_WEIGHT_2) == ORDER_WEIGHT_2) lotRatio = LOT_WEIGHT_6;
            if((crossShort & ORDER_WEIGHT_3) == ORDER_WEIGHT_3) lotRatio = LOT_WEIGHT_7;
            if((crossShort & ORDER_WEIGHT_4) == ORDER_WEIGHT_4) lotRatio = LOT_WEIGHT_8;
        }
    } 
    
    if(crossShort & CROSSING_DEAD){ //DEAD cross 
        buy=-1;
        //Check cross status in W1 chart: if short MA line is above long MA line
        if(crossLong & CROSSING_UNCROSSED_UP){
            if((crossShort & ORDER_WEIGHT_1) == ORDER_WEIGHT_1) lotRatio = LOT_WEIGHT_8;
            if((crossShort & ORDER_WEIGHT_2) == ORDER_WEIGHT_2) lotRatio = LOT_WEIGHT_7;
            if((crossShort & ORDER_WEIGHT_3) == ORDER_WEIGHT_3) lotRatio = LOT_WEIGHT_6;
            if((crossShort & ORDER_WEIGHT_4) == ORDER_WEIGHT_4) lotRatio = LOT_WEIGHT_5;
        }else{ //if(crossW1 & CROSSING_UNCROSSED_UP)
            if((crossShort & ORDER_WEIGHT_1) == ORDER_WEIGHT_1) lotRatio = LOT_WEIGHT_4;
            if((crossShort & ORDER_WEIGHT_2) == ORDER_WEIGHT_2) lotRatio = LOT_WEIGHT_3;
            if((crossShort & ORDER_WEIGHT_3) == ORDER_WEIGHT_3) lotRatio = LOT_WEIGHT_2;
            if((crossShort & ORDER_WEIGHT_4) == ORDER_WEIGHT_4) lotRatio = LOT_WEIGHT_1;
        }
    }
    
    //ajudging Lot with the ratio of Account Equity. 
    double lot= NormalizeDouble(BaseLots*lotRatio*AccountEquity()/10000, 2);
    
    double margin_ratio = (double)AccountMargin()/AccountEquity();
    
    if (buy > 0) { //BUY
        if (lot >= 0.01 && margin_ratio < 0.3 && Volume[0] < 1){
            ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, 3, 0, 0, "autobuy DoubleMA", MAGICLEWIS,0, Green);
            if(ticket<0)
            {
                Print("OrderSend for BUY failed with error #",GetLastError());
                Print("lotRatio=", lotRatio, ",Lots=", lot);
            }
            else{
               //Print("OrderSend for BUY placed successfully");
               last_t = Time[0];
            }
        }
            
        //CLOSE SELL Orders
        CheckForClose(OP_SELL);
    }
    if (buy < 0) { //SELL
        if (lot >= 0.01 && margin_ratio < 0.3 && Volume[0] < 1){
           ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, 3, 0, 0, "autobuy DoubleMA", MAGICLEWIS,0, Red);
           if(ticket<0)
           {
               Print("OrderSend for SELL failed with error #",GetLastError());
               Print("lotRatio=", lotRatio, ",Lots=", lot);
           }
           else{
               //Print("OrderSend for SELL placed successfully");
               last_t = Time[0];
           }
        } 
        //CLOSE BUY Orders
        CheckForClose(OP_BUY);
    }
    
    return(0);
}
