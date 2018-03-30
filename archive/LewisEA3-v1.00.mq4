//+------------------------------------------------------------------+
//|                                                LewisDoubleMA.mq4 |
//|                                            Copyright 2016, Lewis |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Version 1.00
//|
//+------------------------------------------------------------------+

#property copyright "Copyright 2016, Lewis"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//--- input parameters

#define MAGICLEWIS 7797


//+------------------------------------------------------------------+
//| Check for Open              
//|   
//+------------------------------------------------------------------+
void CheckForOpen()
{
   int ticket = -1;
   double gap = High[1] - Low[1];
   double lot = NormalizeDouble((double)AccountEquity()*0.01*50/10000/gap, 2);
   
   if (gap < 200.0 || lot <= 0.01) return;
   
   if(Open[1] > Close[1] ) { //if goes down, SELL
       ticket = OrderSend(Symbol(), OP_SELL, lot, Bid, 3, gap, gap, "LewisEA3", MAGICLEWIS,0, Red);
       if(ticket<0)
       {
           Print("OrderSend for SELL failed with error #",GetLastError());
           Print("Lots=", lot);
       }
   }
   
   if(Open[1] < Close[1]) { //if goes up, BUY
       ticket = OrderSend(Symbol(), OP_BUY, lot, Ask, 3, gap, gap, "LewisEA3", MAGICLEWIS,0, Green);
       if(ticket<0)
       {
           Print("OrderSend for SELL failed with error #",GetLastError());
           Print("Lots=", lot);
       }
   }
}

int start()
{
   //--- go trading only for first tiks of new bar
   if(Volume[0]>1) return(0);
   
   CheckForOpen();

   return(0);
}
