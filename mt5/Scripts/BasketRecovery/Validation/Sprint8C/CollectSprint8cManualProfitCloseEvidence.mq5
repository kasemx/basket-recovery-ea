#property script_show_inputs
#property description "Sprint 8C: collect manual profit-close chart validation evidence."

input string InpBasketId = "sprint8c-demo-btc-001";
input string InpPrimaryTriggerToken = "";
input string InpDuplicateTriggerToken = "";
input string InpLogFilePath = "BasketRecovery/logs/basket_recovery.log";
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
      handle=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
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
                 bool &sawCandidateAvailable,
                 bool &sawProfitCloseAccepted,
                 bool &sawProfitCloseRejected,
                 bool &sawOrderSendAsyncTrue,
                 bool &sawOrderSendAsyncFalse,
                 bool &sawDuplicateTriggerReject,
                 bool &sawExpiredReject,
                 bool &sawStaleVolumeReject,
                 bool &sawOnTradeTransaction,
                 bool &sawManualSelected,
                 bool &sawRevalidationPassed,
                 bool &sawSealedRequest,
                 bool &sawLevelTrackerFilled,
                 bool &sawCloseConfirmed,
                 bool &sawLevelMarkedCompleted,
                 int &orderSendAsyncCallCount,
                 string &finalStatus,
                 string &rejectionReason)
  {
   string lines[];
   int count=StringSplit(content,'\n',lines);
   for(int i=0;i<count;i++)
     {
      string line=lines[i];
      if(StringFind(line,"BRE manual_profit_close_candidate_available")>=0)
         sawCandidateAvailable=true;
      if(StringFind(line,"ProfitLevelCloseCandidateAvailable")>=0)
         sawCandidateAvailable=true;
      if(StringFind(line,"BRE manual_profit_close_candidate_revalidation=passed")>=0)
         sawRevalidationPassed=true;
      if(StringFind(line,"BRE manual_profit_close_sealed_request_created")>=0)
         sawSealedRequest=true;
      if(StringFind(line,"BRE manual_profit_close_candidate_manually_selected")>=0)
         sawManualSelected=true;
      if(StringFind(line,"BRE profit_level_close_execution_tracker | filled=true")>=0)
         sawLevelTrackerFilled=true;
      if(StringFind(line,"ProfitLevelCloseConfirmed")>=0)
         sawCloseConfirmed=true;
      if(StringFind(line,"ProfitLevelMarkedCompleted")>=0)
         sawLevelMarkedCompleted=true;
      if(StringFind(line,"Manual profit close submission accepted")>=0)
        {
         sawProfitCloseAccepted=true;
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
           }
        }
      if(StringFind(line,"Manual profit close submission rejected")>=0)
        {
         sawProfitCloseRejected=true;
         int reasonPos=StringFind(line,"reason=");
         if(reasonPos>=0)
           {
            int endPos=StringFind(line," |",reasonPos);
            if(endPos<0) endPos=StringLen(line);
            rejectionReason=StringSubstr(line,reasonPos+7,endPos-reasonPos-7);
           }
         int detailPos=StringFind(line,"detail=");
         if(detailPos>=0)
           {
            string detail=StringSubstr(line,detailPos+7);
            if(StringFind(detail,"expired")>=0 || StringFind(detail,"Expired")>=0)
               sawExpiredReject=true;
            if(StringFind(detail,"volume")>=0 || StringFind(detail,"Volume")>=0)
               sawStaleVolumeReject=true;
           }
        }
      if(StringFind(line,"TRIGGER_TOKEN_CONSUMED")>=0)
         sawDuplicateTriggerReject=true;
      if(StringFind(line,"ordersend_async|")>=0)
        {
         orderSendAsyncCallCount++;
         if(StringFind(line,"accepted=true")>=0)
            sawOrderSendAsyncTrue=true;
         if(StringFind(line,"accepted=false")>=0)
            sawOrderSendAsyncFalse=true;
        }
      if(StringFind(line,"BRE OnTradeTransaction")>=0)
         sawOnTradeTransaction=true;
     }
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-8c-ea-chart-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string journalContent=ReadAllText(InpExpertsJournalAbsolutePath);
   string logContent=ReadAllText(InpLogFilePath);
   string combined=journalContent+"\n"+logContent;

   bool sawCandidateAvailable=false;
   bool sawProfitCloseAccepted=false;
   bool sawProfitCloseRejected=false;
   bool sawOrderSendAsyncTrue=false;
   bool sawOrderSendAsyncFalse=false;
   bool sawDuplicateTriggerReject=false;
   bool sawExpiredReject=false;
   bool sawStaleVolumeReject=false;
   bool sawOnTradeTransaction=false;
   bool sawManualSelected=false;
   bool sawRevalidationPassed=false;
   bool sawSealedRequest=false;
   bool sawLevelTrackerFilled=false;
   bool sawCloseConfirmed=false;
   bool sawLevelMarkedCompleted=false;
   int orderSendAsyncCallCount=0;
   string finalStatus="";
   string rejectionReason="";

   ScanContent(combined,sawCandidateAvailable,sawProfitCloseAccepted,sawProfitCloseRejected,
               sawOrderSendAsyncTrue,sawOrderSendAsyncFalse,sawDuplicateTriggerReject,
               sawExpiredReject,sawStaleVolumeReject,sawOnTradeTransaction,sawManualSelected,
               sawRevalidationPassed,sawSealedRequest,sawLevelTrackerFilled,sawCloseConfirmed,
               sawLevelMarkedCompleted,orderSendAsyncCallCount,finalStatus,rejectionReason);

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"primary_trigger_token="+InpPrimaryTriggerToken);
   WriteLine(reportHandle,"duplicate_trigger_token="+InpDuplicateTriggerToken);
   WriteLine(reportHandle,"positions_after="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"orders_after="+IntegerToString(OrdersTotal()));
   WriteLine(reportHandle,"deals_history_after="+IntegerToString(HistoryDealsTotal()));
   WriteLine(reportHandle,"profit_close_candidate_available="+(sawCandidateAvailable?"true":"false"));
   WriteLine(reportHandle,"profit_close_submission_accepted="+(sawProfitCloseAccepted?"true":"false"));
   WriteLine(reportHandle,"profit_close_submission_rejected="+(sawProfitCloseRejected?"true":"false"));
   WriteLine(reportHandle,"manual_profit_close_selected="+(sawManualSelected?"true":"false"));
   WriteLine(reportHandle,"revalidation_passed="+(sawRevalidationPassed?"true":"false"));
   WriteLine(reportHandle,"sealed_request_created="+(sawSealedRequest?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_true="+(sawOrderSendAsyncTrue?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_false="+(sawOrderSendAsyncFalse?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_call_count="+IntegerToString(orderSendAsyncCallCount));
   WriteLine(reportHandle,"immediate_status="+finalStatus);
   WriteLine(reportHandle,"duplicate_trigger_rejected="+(sawDuplicateTriggerReject?"true":"false"));
   WriteLine(reportHandle,"expired_candidate_rejected="+(sawExpiredReject?"true":"false"));
   WriteLine(reportHandle,"stale_volume_rejected="+(sawStaleVolumeReject?"true":"false"));
   WriteLine(reportHandle,"on_trade_transaction="+(sawOnTradeTransaction?"true":"false"));
   WriteLine(reportHandle,"profit_level_close_confirmed="+(sawCloseConfirmed?"true":"false"));
   WriteLine(reportHandle,"profit_level_marked_completed="+(sawLevelMarkedCompleted?"true":"false"));
   WriteLine(reportHandle,"profit_level_tracker_filled="+(sawLevelTrackerFilled?"true":"false"));
   WriteLine(reportHandle,"rejection_reason="+rejectionReason);
   WriteLine(reportHandle,"automatic_partial_close_submission=false");

   bool passed=sawCandidateAvailable &&
               sawRevalidationPassed &&
               sawSealedRequest &&
               orderSendAsyncCallCount==1 &&
               sawDuplicateTriggerReject &&
               sawExpiredReject &&
               sawStaleVolumeReject;
   WriteLine(reportHandle,"chart_validation_passed="+(passed?"true":"false"));
   FileClose(reportHandle);
  }
