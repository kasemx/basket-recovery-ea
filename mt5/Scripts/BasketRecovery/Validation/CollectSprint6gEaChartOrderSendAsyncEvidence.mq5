#property script_show_inputs
#property description "Sprint 6G: collect EA chart OrderSendAsync validation evidence from logs."

input string InpBasketId              = "sprint6g-demo-btc-001";
input string InpExecutionRequestId    = "sprint6g-req-001";
input string InpTriggerToken          = "";
input string InpDuplicateTriggerToken = "";
input string InpLogFilePath           = "BasketRecovery/logs/basket_recovery.log";
input string InpExpertsJournalPath      = "";
input string InpExpertsJournalAbsolutePath = "";

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

int OpenTextFile(const string path)
  {
   int handle=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
   if(handle==INVALID_HANDLE && StringFind(path,":")<0)
     {
      handle=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
     }
   return handle;
  }

string ReadAllText(const string path)
  {
   int handle=OpenTextFile(path);
   if(handle==INVALID_HANDLE)
      return "";
   string content="";
   while(!FileIsEnding(handle))
     {
      if(content!="")
         content+="\n";
      content+=FileReadString(handle);
     }
   FileClose(handle);
   return content;
  }

void ScanContent(const string content,
                 bool &sawSubmissionAccepted,
                 bool &sawSubmissionRejected,
                 bool &sawOrderSendAsyncTrue,
                 bool &sawOrderSendAsyncFalse,
                 bool &sawOrdersendAsyncDiag,
                 bool &sawSubmittedStatus,
                 bool &sawRejectedStatus,
                 bool &sawDuplicateTriggerReject,
                 bool &sawOnTradeTransaction,
                 bool &sawCorrelationMatch,
                 bool &sawTransitionAck,
                 bool &sawBrokerBefore,
                 bool &sawBrokerAfter,
                 int &positionsBefore,
                 int &ordersBefore,
                 int &positionsAfter,
                 int &ordersAfter,
                 int &orderSendAsyncCallCount,
                 string &finalStatus,
                 string &correlationStrategy,
                 string &rejectionReason)
  {
   string lines[];
   int count=StringSplit(content,'\n',lines);
   for(int i=0;i<count;i++)
     {
      string line=lines[i];
      if(StringFind(line,"Manual demo submission accepted")>=0)
        {
         sawSubmissionAccepted=true;
         if(StringFind(line,"order_send_async=true")>=0)
            sawOrderSendAsyncTrue=true;
         if(StringFind(line,"order_send_async=false")>=0)
            sawOrderSendAsyncFalse=true;
         int statusPos=StringFind(line,"status=");
         if(statusPos>=0)
           {
            int endPos=StringFind(line," |",statusPos);
            if(endPos<0) endPos=StringLen(line);
            finalStatus=StringSubstr(line,statusPos+7,endPos-statusPos-7);
            if(finalStatus=="SUBMITTED")
               sawSubmittedStatus=true;
           }
        }
      if(StringFind(line,"Manual demo submission rejected")>=0)
        {
         sawSubmissionRejected=true;
         int reasonPos=StringFind(line,"reason=");
         if(reasonPos>=0)
           {
            int endPos=StringFind(line," |",reasonPos);
            if(endPos<0) endPos=StringLen(line);
            rejectionReason=StringSubstr(line,reasonPos+7,endPos-reasonPos-7);
           }
        }
      if(StringFind(line,"TRIGGER_TOKEN_CONSUMED")>=0)
         sawDuplicateTriggerReject=true;
      if(StringFind(line,"ordersend_async|")>=0)
        {
         sawOrdersendAsyncDiag=true;
         orderSendAsyncCallCount++;
         if(StringFind(line,"accepted=true")>=0)
            sawOrderSendAsyncTrue=true;
         if(StringFind(line,"accepted=false")>=0)
            sawOrderSendAsyncFalse=true;
        }
      if(StringFind(line,"status=REJECTED")>=0 && StringFind(line,"Manual demo submission accepted")<0)
         sawRejectedStatus=true;
      if(StringFind(line,"BRE OnTradeTransaction")>=0)
         sawOnTradeTransaction=true;
      if(StringFind(line,"correlation_match")>=0)
        {
         sawCorrelationMatch=true;
         int stratPos=StringFind(line,"strategy=");
         if(stratPos>=0)
           {
            int endPos=StringFind(line,"|",stratPos);
            if(endPos<0) endPos=StringLen(line);
            correlationStrategy=StringSubstr(line,stratPos+9,endPos-stratPos-9);
            StringReplace(correlationStrategy,"\"","");
            StringTrimRight(correlationStrategy);
            StringTrimLeft(correlationStrategy);
           }
        }
      if(StringFind(line,"transition_ok")>=0 && StringFind(line,"to=ACKNOWLEDGED")>=0)
         sawTransitionAck=true;
      if(StringFind(line,"broker_state_before")>=0)
        {
         sawBrokerBefore=true;
         int posPos=StringFind(line,"positions=");
         if(posPos>=0)
            positionsBefore=(int)StringToInteger(StringSubstr(line,posPos+10));
         int ordPos=StringFind(line,"orders=");
         if(ordPos>=0)
           {
            int endPos=StringFind(line," |",ordPos);
            if(endPos<0) endPos=StringLen(line);
            ordersBefore=(int)StringToInteger(StringSubstr(line,ordPos+7,endPos-ordPos-7));
           }
        }
      if(StringFind(line,"broker_state_after")>=0)
        {
         sawBrokerAfter=true;
         int posPos=StringFind(line,"positions=");
         if(posPos>=0)
            positionsAfter=(int)StringToInteger(StringSubstr(line,posPos+10));
         int ordPos=StringFind(line,"orders=");
         if(ordPos>=0)
           {
            int endPos=StringFind(line," |",ordPos);
            if(endPos<0) endPos=StringLen(line);
            ordersAfter=(int)StringToInteger(StringSubstr(line,ordPos+7,endPos-ordPos-7));
           }
        }
     }
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-6g-ea-chart-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
     {
      Print("Failed to open report");
      return;
     }

   string content=ReadAllText(InpLogFilePath);
   if(InpExpertsJournalPath!="")
      content+="\n"+ReadAllText(InpExpertsJournalPath);
   if(InpExpertsJournalAbsolutePath!="")
      content+="\n"+ReadAllText(InpExpertsJournalAbsolutePath);

   bool sawSubmissionAccepted=false;
   bool sawSubmissionRejected=false;
   bool sawOrderSendAsyncTrue=false;
   bool sawOrderSendAsyncFalse=false;
   bool sawOrdersendAsyncDiag=false;
   bool sawSubmittedStatus=false;
   bool sawRejectedStatus=false;
   bool sawDuplicateTriggerReject=false;
   bool sawOnTradeTransaction=false;
   bool sawCorrelationMatch=false;
   bool sawTransitionAck=false;
   bool sawBrokerBefore=false;
   bool sawBrokerAfter=false;
   int positionsBefore=0;
   int ordersBefore=0;
   int positionsAfter=0;
   int ordersAfter=0;
   int orderSendAsyncCallCount=0;
   string finalStatus="";
   string correlationStrategy="";
   string rejectionReason="";

   ScanContent(content,sawSubmissionAccepted,sawSubmissionRejected,sawOrderSendAsyncTrue,sawOrderSendAsyncFalse,
               sawOrdersendAsyncDiag,sawSubmittedStatus,sawRejectedStatus,sawDuplicateTriggerReject,
               sawOnTradeTransaction,sawCorrelationMatch,sawTransitionAck,sawBrokerBefore,sawBrokerAfter,
               positionsBefore,ordersBefore,positionsAfter,ordersAfter,orderSendAsyncCallCount,
               finalStatus,correlationStrategy,rejectionReason);

   int dealsTotal=(int)HistoryDealsTotal();
   int positionsTotal=PositionsTotal();
   int ordersTotal=OrdersTotal();

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"execution_request_id="+InpExecutionRequestId);
   WriteLine(reportHandle,"trigger_token="+InpTriggerToken);
   WriteLine(reportHandle,"duplicate_trigger_token="+InpDuplicateTriggerToken);
   WriteLine(reportHandle,"submission_accepted="+(sawSubmissionAccepted?"true":"false"));
   WriteLine(reportHandle,"submission_rejected="+(sawSubmissionRejected?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_true="+(sawOrderSendAsyncTrue?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_false="+(sawOrderSendAsyncFalse?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_call_count="+IntegerToString(orderSendAsyncCallCount));
   WriteLine(reportHandle,"ordersend_async_diag="+(sawOrdersendAsyncDiag?"true":"false"));
   WriteLine(reportHandle,"status_submitted="+(sawSubmittedStatus?"true":"false"));
   WriteLine(reportHandle,"status_rejected="+(sawRejectedStatus?"true":"false"));
   WriteLine(reportHandle,"immediate_status="+finalStatus);
   WriteLine(reportHandle,"on_trade_transaction="+(sawOnTradeTransaction?"true":"false"));
   WriteLine(reportHandle,"correlation_match="+(sawCorrelationMatch?"true":"false"));
   WriteLine(reportHandle,"correlation_strategy="+correlationStrategy);
   WriteLine(reportHandle,"transition_acknowledged="+(sawTransitionAck?"true":"false"));
   WriteLine(reportHandle,"duplicate_trigger_rejected="+(sawDuplicateTriggerReject?"true":"false"));
   WriteLine(reportHandle,"duplicate_rejection_reason="+rejectionReason);
   WriteLine(reportHandle,"broker_before_positions="+IntegerToString(positionsBefore));
   WriteLine(reportHandle,"broker_before_orders="+IntegerToString(ordersBefore));
   WriteLine(reportHandle,"broker_after_positions="+IntegerToString(positionsAfter));
   WriteLine(reportHandle,"broker_after_orders="+IntegerToString(ordersAfter));
   WriteLine(reportHandle,"terminal_positions="+IntegerToString(positionsTotal));
   WriteLine(reportHandle,"terminal_orders="+IntegerToString(ordersTotal));
   WriteLine(reportHandle,"terminal_deals_history="+IntegerToString(dealsTotal));

   bool passed=(orderSendAsyncCallCount==1) &&
               (sawSubmissionAccepted || sawOrderSendAsyncTrue || sawOrderSendAsyncFalse) &&
               sawDuplicateTriggerReject &&
               (!sawSubmittedStatus || sawOnTradeTransaction || sawTransitionAck || sawCorrelationMatch);

   WriteLine(reportHandle,"chart_validation_passed="+(passed?"true":"false"));
   FileClose(reportHandle);
  }
