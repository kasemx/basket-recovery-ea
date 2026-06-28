#property script_show_inputs
#property description "Sprint 7D: collect manual recovery chart validation evidence."

input string InpBasketId = "sprint7d-demo-btc-001";
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
                 bool &sawRecoveryAccepted,
                 bool &sawRecoveryRejected,
                 bool &sawOrderSendAsyncTrue,
                 bool &sawOrderSendAsyncFalse,
                 bool &sawDuplicateTriggerReject,
                 bool &sawExpiredReject,
                 bool &sawPendingReject,
                 bool &sawOnTradeTransaction,
                 bool &sawManualRecoverySelected,
                 bool &sawRevalidationPassed,
                 bool &sawSealedRequest,
                 bool &sawStepTrackerFilled,
                 int &orderSendAsyncCallCount,
                 string &finalStatus,
                 string &rejectionReason,
                 string &correlationStrategy)
  {
   string lines[];
   int count=StringSplit(content,'\n',lines);
   for(int i=0;i<count;i++)
     {
      string line=lines[i];
      if(StringFind(line,"BRE manual_recovery_candidate_available")>=0)
         sawCandidateAvailable=true;
      if(StringFind(line,"BRE manual_recovery_candidate_revalidation=passed")>=0)
         sawRevalidationPassed=true;
      if(StringFind(line,"BRE manual_recovery_sealed_request_created")>=0)
         sawSealedRequest=true;
      if(StringFind(line,"BRE manual_recovery_candidate_manually_selected")>=0)
         sawManualRecoverySelected=true;
      if(StringFind(line,"BRE recovery_step_execution_tracker | filled=true")>=0)
         sawStepTrackerFilled=true;
      if(StringFind(line,"Manual recovery submission accepted")>=0)
        {
         sawRecoveryAccepted=true;
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
      if(StringFind(line,"Manual recovery submission rejected")>=0)
        {
         sawRecoveryRejected=true;
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
            if(StringFind(detail,"pending execution")>=0 || StringFind(detail,"Unresolved pending")>=0)
               sawPendingReject=true;
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
      if(StringFind(line,"correlation_match")>=0 || StringFind(line,"strategy=")>=0)
        {
         int stratPos=StringFind(line,"strategy=");
         if(stratPos>=0)
           {
            int endPos=StringFind(line," |",stratPos);
            if(endPos<0) endPos=StringLen(line);
            correlationStrategy=StringSubstr(line,stratPos+8,endPos-stratPos-8);
           }
        }
     }
  }

void OnStart(void)
  {
   string reportRel="BasketRecovery/validation/sprint-7d-ea-chart-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      return;

   string journalContent=ReadAllText(InpExpertsJournalAbsolutePath);
   string logContent=ReadAllText(InpLogFilePath);
   string combined=journalContent+"\n"+logContent;

   bool sawCandidateAvailable=false;
   bool sawRecoveryAccepted=false;
   bool sawRecoveryRejected=false;
   bool sawOrderSendAsyncTrue=false;
   bool sawOrderSendAsyncFalse=false;
   bool sawDuplicateTriggerReject=false;
   bool sawExpiredReject=false;
   bool sawPendingReject=false;
   bool sawOnTradeTransaction=false;
   bool sawManualRecoverySelected=false;
   bool sawRevalidationPassed=false;
   bool sawSealedRequest=false;
   bool sawStepTrackerFilled=false;
   int orderSendAsyncCallCount=0;
   string finalStatus="";
   string rejectionReason="";
   string correlationStrategy="";

   ScanContent(combined,sawCandidateAvailable,sawRecoveryAccepted,sawRecoveryRejected,
               sawOrderSendAsyncTrue,sawOrderSendAsyncFalse,sawDuplicateTriggerReject,
               sawExpiredReject,sawPendingReject,sawOnTradeTransaction,sawManualRecoverySelected,
               sawRevalidationPassed,sawSealedRequest,sawStepTrackerFilled,orderSendAsyncCallCount,
               finalStatus,rejectionReason,correlationStrategy);

   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"primary_trigger_token="+InpPrimaryTriggerToken);
   WriteLine(reportHandle,"duplicate_trigger_token="+InpDuplicateTriggerToken);
   WriteLine(reportHandle,"positions_after="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"orders_after="+IntegerToString(OrdersTotal()));
   WriteLine(reportHandle,"deals_history_after="+IntegerToString(HistoryDealsTotal()));
   WriteLine(reportHandle,"recovery_candidate_available="+(sawCandidateAvailable?"true":"false"));
   WriteLine(reportHandle,"recovery_submission_accepted="+(sawRecoveryAccepted?"true":"false"));
   WriteLine(reportHandle,"recovery_submission_rejected="+(sawRecoveryRejected?"true":"false"));
   WriteLine(reportHandle,"manual_recovery_selected="+(sawManualRecoverySelected?"true":"false"));
   WriteLine(reportHandle,"revalidation_passed="+(sawRevalidationPassed?"true":"false"));
   WriteLine(reportHandle,"sealed_request_created="+(sawSealedRequest?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_true="+(sawOrderSendAsyncTrue?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_false="+(sawOrderSendAsyncFalse?"true":"false"));
   WriteLine(reportHandle,"ordersend_async_call_count="+IntegerToString(orderSendAsyncCallCount));
   WriteLine(reportHandle,"immediate_status="+finalStatus);
   WriteLine(reportHandle,"duplicate_trigger_rejected="+(sawDuplicateTriggerReject?"true":"false"));
   WriteLine(reportHandle,"expired_candidate_rejected="+(sawExpiredReject?"true":"false"));
   WriteLine(reportHandle,"pending_execution_rejected="+(sawPendingReject?"true":"false"));
   WriteLine(reportHandle,"on_trade_transaction="+(sawOnTradeTransaction?"true":"false"));
   WriteLine(reportHandle,"correlation_strategy="+correlationStrategy);
   WriteLine(reportHandle,"recovery_step_tracker_filled="+(sawStepTrackerFilled?"true":"false"));
   WriteLine(reportHandle,"rejection_reason="+rejectionReason);
   WriteLine(reportHandle,"automatic_recovery_submission=false");

   bool passed=sawCandidateAvailable &&
               sawRevalidationPassed &&
               sawSealedRequest &&
               orderSendAsyncCallCount==1 &&
               sawDuplicateTriggerReject &&
               sawExpiredReject &&
               sawPendingReject;
   WriteLine(reportHandle,"chart_validation_passed="+(passed?"true":"false"));
   FileClose(reportHandle);
  }
