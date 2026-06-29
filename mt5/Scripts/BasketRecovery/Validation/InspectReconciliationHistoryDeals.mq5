#property script_show_inputs
#property description "Read-only diagnostic: list history deals for reconciliation debug."

input long InpMagic = 0;
input string InpToken = "BRE|";

void OnStart(void)
  {
   HistorySelect(0,TimeCurrent());
   int total=(int)HistoryDealsTotal();
   Print("history_deals_total=",total);
   for(int i=total-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || !HistoryDealSelect(ticket))
         continue;
      long magic=HistoryDealGetInteger(ticket,DEAL_MAGIC);
      if(InpMagic>0 && magic!=InpMagic)
         continue;
      string comment=HistoryDealGetString(ticket,DEAL_COMMENT);
      if(InpToken!="" && StringFind(comment,InpToken)<0)
         continue;
      Print("deal_ticket=",ticket,
            " | symbol=",HistoryDealGetString(ticket,DEAL_SYMBOL),
            " | magic=",magic,
            " | volume=",DoubleToString(HistoryDealGetDouble(ticket,DEAL_VOLUME),8),
            " | time=",IntegerToString((long)HistoryDealGetInteger(ticket,DEAL_TIME)),
            " | comment=",comment);
     }
  }
