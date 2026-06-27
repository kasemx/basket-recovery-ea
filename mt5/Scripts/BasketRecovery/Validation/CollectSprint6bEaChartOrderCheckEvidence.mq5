#property script_show_inputs
#property description "Sprint 6B.4: collect EA chart OrderCheck evidence from execution log and Experts journal."

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketPersistenceLoadDiagnostic.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>

input string InpBasketId        = "sprint6b-demo-btc-001";
input string InpLogFilePath     = "BasketRecovery/logs/basket_recovery.log";
input string InpTriggerToken    = "";
input string InpExpertsJournalPath = "";

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

int OpenTextFile(const string relativePath)
  {
   int flags=FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
   int handle=FileOpen(relativePath,flags);
   if(handle==INVALID_HANDLE)
     {
      flags|=FILE_COMMON;
      handle=FileOpen(relativePath,flags);
     }
   return handle;
  }

void ScanLine(const string line,
              bool &sawBasketLoadDiagnostic,
              bool &sawCrcOk,
              string &storedCrc,
              string &computedCrc,
              string &validationStage,
              bool &sawTranslationOk,
              bool &sawLocalValidationOk,
              bool &sawOrderCheckInvoked,
              bool &sawOrderCheckResult,
              bool &sawLocalRejected,
              bool &sawManualDryRun,
              bool &sawNoOrdersend,
              bool &sawAlgoTradingDisabled,
              bool &sawBrokerBefore,
              bool &sawBrokerAfter,
              int &positionsBefore,
              int &ordersBefore,
              int &positionsAfter,
              int &ordersAfter,
              string &orderCheckRetcode,
              string &orderCheckText,
              string &mappedStatus)
  {
   if(StringFind(line,"automated trading is disabled")>=0)
      sawAlgoTradingDisabled=true;

   if(StringFind(line,"BRE basket-load diagnostic")>=0)
     {
      sawBasketLoadDiagnostic=true;
      int storedPos=StringFind(line,"stored_crc=");
      if(storedPos>=0)
        {
         int endPos=StringFind(line,"|",storedPos);
         if(endPos<0)
            endPos=StringLen(line);
         storedCrc=StringSubstr(line,storedPos+11,endPos-storedPos-11);
        }
      int computedPos=StringFind(line,"computed_crc=");
      if(computedPos>=0)
        {
         int endPos=StringFind(line,"|",computedPos);
         if(endPos<0)
            endPos=StringLen(line);
         computedCrc=StringSubstr(line,computedPos+13,endPos-computedPos-13);
        }
      int stagePos=StringFind(line,"validation_stage=");
      if(stagePos>=0)
        {
         int endPos=StringFind(line,"|",stagePos);
         if(endPos<0)
            endPos=StringLen(line);
         validationStage=StringSubstr(line,stagePos+17,endPos-stagePos-17);
         if(validationStage=="ok")
            sawCrcOk=true;
        }
     }

   if(StringFind(line,"translation_ok")>=0)
      sawTranslationOk=true;
   if(StringFind(line,"local_validation_ok")>=0)
      sawLocalValidationOk=true;
   if(StringFind(line,"ordercheck_invoked")>=0 || StringFind(line,"order_check_invoked=true")>=0)
      sawOrderCheckInvoked=true;
   if(StringFind(line,"ordercheck_ok")>=0 || StringFind(line,"ordercheck_fail")>=0)
      sawOrderCheckResult=true;
   if(StringFind(line,"order_check_invoked=false")>=0)
      sawLocalRejected=true;
   if(StringFind(line,"no_ordersend=true")>=0)
      sawNoOrdersend=true;

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
         if(endPos<0)
            endPos=StringLen(line);
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
         if(endPos<0)
            endPos=StringLen(line);
         ordersAfter=(int)StringToInteger(StringSubstr(line,ordPos+7,endPos-ordPos-7));
        }
     }

   int retcodePos=StringFind(line,"retcode=");
   if(retcodePos>=0)
     {
      int endPos=StringFind(line,"|",retcodePos);
      if(endPos<0)
         endPos=StringLen(line);
      orderCheckRetcode=StringSubstr(line,retcodePos+8,endPos-retcodePos-8);
     }

   int textPos=StringFind(line,"text=");
   if(textPos>=0)
     {
      int endPos=StringFind(line,"|",textPos);
      if(endPos<0)
         endPos=StringLen(line);
      orderCheckText=StringSubstr(line,textPos+5,endPos-textPos-5);
     }

   if(StringFind(line,"Manual dry-run completed")>=0)
     {
      sawManualDryRun=true;
      int statusPos=StringFind(line,"status=");
      if(statusPos>=0)
        {
         int endPos=StringFind(line," |",statusPos);
         if(endPos<0)
            endPos=StringLen(line);
         mappedStatus=StringSubstr(line,statusPos+7,endPos-statusPos-7);
        }
     }
  }

void ScanTail(const int handle,
              bool &sawBasketLoadDiagnostic,
              bool &sawCrcOk,
              string &storedCrc,
              string &computedCrc,
              string &validationStage,
              bool &sawTranslationOk,
              bool &sawLocalValidationOk,
              bool &sawOrderCheckInvoked,
              bool &sawOrderCheckResult,
              bool &sawLocalRejected,
              bool &sawManualDryRun,
              bool &sawNoOrdersend,
              bool &sawAlgoTradingDisabled,
              bool &sawBrokerBefore,
              bool &sawBrokerAfter,
              int &positionsBefore,
              int &ordersBefore,
              int &positionsAfter,
              int &ordersAfter,
              string &orderCheckRetcode,
              string &orderCheckText,
              string &mappedStatus)
  {
   if(handle==INVALID_HANDLE)
      return;

   FileSeek(handle,0,SEEK_END);
   long fileSize=FileTell(handle);
   long tailStart=fileSize-65536;
   if(tailStart<0)
      tailStart=0;
   FileSeek(handle,(int)tailStart,SEEK_SET);

   while(!FileIsEnding(handle))
     {
      string line=FileReadString(handle);
      ScanLine(line,
               sawBasketLoadDiagnostic,
               sawCrcOk,
               storedCrc,
               computedCrc,
               validationStage,
               sawTranslationOk,
               sawLocalValidationOk,
               sawOrderCheckInvoked,
               sawOrderCheckResult,
               sawLocalRejected,
               sawManualDryRun,
               sawNoOrdersend,
               sawAlgoTradingDisabled,
               sawBrokerBefore,
               sawBrokerAfter,
               positionsBefore,
               ordersBefore,
               positionsAfter,
               ordersAfter,
               orderCheckRetcode,
               orderCheckText,
               mappedStatus);
     }
   FileClose(handle);
  }

void OnStart()
  {
   FolderCreate("BasketRecovery\\validation",FILE_COMMON);
   string reportRel="BasketRecovery\\validation\\sprint-6b-ea-chart-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI);

   bool sawBasketLoadDiagnostic=false;
   bool sawCrcOk=false;
   string storedCrc="";
   string computedCrc="";
   string validationStage="";
   bool sawTranslationOk=false;
   bool sawLocalValidationOk=false;
   bool sawOrderCheckInvoked=false;
   bool sawOrderCheckResult=false;
   bool sawLocalRejected=false;
   bool sawManualDryRun=false;
   bool sawNoOrdersend=false;
   bool sawAlgoTradingDisabled=false;
   bool sawBrokerBefore=false;
   bool sawBrokerAfter=false;
   int positionsBefore=-1;
   int ordersBefore=-1;
   int positionsAfter=-1;
   int ordersAfter=-1;
   string orderCheckRetcode="0";
   string orderCheckText="";
   string mappedStatus="";

   WriteLine(reportHandle,"=== Sprint 6B.4 EA Chart OrderCheck Evidence ===");
   WriteLine(reportHandle,"timestamp="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   WriteLine(reportHandle,"basket_id="+InpBasketId);
   WriteLine(reportHandle,"trigger_token="+InpTriggerToken);
   WriteLine(reportHandle,"terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"common_data_path="+TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   WriteLine(reportHandle,"persistence_file="+CBasketPersistenceLoadDiagnostic::BuildFullCommonFilePath(
                            BRE_PERSISTENCE_BASKET_SUBDIR+"/"+InpBasketId+".json"));
   WriteLine(reportHandle,"account_trade_expert="+(AccountInfoInteger(ACCOUNT_TRADE_EXPERT)?"true":"false"));
   WriteLine(reportHandle,"terminal_trade_allowed="+(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)?"true":"false"));

   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CBasketPersistenceLoadDiagnostic inspect=
      CBasketPersistenceLoadDiagnostic::Inspect(BRE_PERSISTENCE_BASKET_SUBDIR,CBasketId(InpBasketId),repository);
   WriteLine(reportHandle,CBasketPersistenceLoadDiagnostic::FormatLogLine(inspect));

   int logHandle=OpenTextFile(InpLogFilePath);
   if(logHandle==INVALID_HANDLE)
      WriteLine(reportHandle,"execution_log=MISSING path="+InpLogFilePath);
   else
     {
      WriteLine(reportHandle,"--- execution_log_tail ---");
      ScanTail(logHandle,
               sawBasketLoadDiagnostic,
               sawCrcOk,
               storedCrc,
               computedCrc,
               validationStage,
               sawTranslationOk,
               sawLocalValidationOk,
               sawOrderCheckInvoked,
               sawOrderCheckResult,
               sawLocalRejected,
               sawManualDryRun,
               sawNoOrdersend,
               sawAlgoTradingDisabled,
               sawBrokerBefore,
               sawBrokerAfter,
               positionsBefore,
               ordersBefore,
               positionsAfter,
               ordersAfter,
               orderCheckRetcode,
               orderCheckText,
               mappedStatus);
     }

   if(InpExpertsJournalPath!="")
     {
      int journalHandle=FileOpen(InpExpertsJournalPath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(journalHandle==INVALID_HANDLE)
         WriteLine(reportHandle,"experts_journal=MISSING path="+InpExpertsJournalPath);
      else
        {
         WriteLine(reportHandle,"--- experts_journal_tail ---");
         ScanTail(journalHandle,
                  sawBasketLoadDiagnostic,
                  sawCrcOk,
                  storedCrc,
                  computedCrc,
                  validationStage,
                  sawTranslationOk,
                  sawLocalValidationOk,
                  sawOrderCheckInvoked,
                  sawOrderCheckResult,
                  sawLocalRejected,
                  sawManualDryRun,
                  sawNoOrdersend,
                  sawAlgoTradingDisabled,
                  sawBrokerBefore,
                  sawBrokerAfter,
                  positionsBefore,
                  ordersBefore,
                  positionsAfter,
                  ordersAfter,
                  orderCheckRetcode,
                  orderCheckText,
                  mappedStatus);
        }
     }

   bool brokerUnchanged=(sawBrokerBefore && sawBrokerAfter &&
                         positionsBefore==positionsAfter &&
                         ordersBefore==ordersAfter);
   bool realOrderCheckProof=(sawOrderCheckInvoked &&
                             sawOrderCheckResult &&
                             !sawLocalRejected);
   bool chartValidationPassed=(inspect.validationStage=="ok" &&
                               inspect.repositoryLoadOk &&
                               sawTranslationOk &&
                               sawLocalValidationOk &&
                               realOrderCheckProof &&
                               sawManualDryRun &&
                               sawNoOrdersend &&
                               !sawAlgoTradingDisabled &&
                               brokerUnchanged);

   WriteLine(reportHandle,"basket_load_diagnostic_logged="+(sawBasketLoadDiagnostic?"true":"false"));
   WriteLine(reportHandle,"crc_validation_stage="+validationStage);
   WriteLine(reportHandle,"stored_crc="+storedCrc);
   WriteLine(reportHandle,"computed_crc="+computedCrc);
   WriteLine(reportHandle,"translation_ok="+(sawTranslationOk?"true":"false"));
   WriteLine(reportHandle,"local_validation_ok="+(sawLocalValidationOk?"true":"false"));
   WriteLine(reportHandle,"order_check_invoked="+(sawOrderCheckInvoked?"true":"false"));
   WriteLine(reportHandle,"ordercheck_result_logged="+(sawOrderCheckResult?"true":"false"));
   WriteLine(reportHandle,"local_rejection_logged="+(sawLocalRejected?"true":"false"));
   WriteLine(reportHandle,"manual_route_completed="+(sawManualDryRun?"true":"false"));
   WriteLine(reportHandle,"ordercheck_retcode="+orderCheckRetcode);
   WriteLine(reportHandle,"ordercheck_text="+orderCheckText);
   WriteLine(reportHandle,"mapped_status="+mappedStatus);
   WriteLine(reportHandle,"algo_trading_disabled_detected="+(sawAlgoTradingDisabled?"true":"false"));
   WriteLine(reportHandle,"broker_state_before positions="+IntegerToString(positionsBefore)+
                         " orders="+IntegerToString(ordersBefore));
   WriteLine(reportHandle,"broker_state_after positions="+IntegerToString(positionsAfter)+
                         " orders="+IntegerToString(ordersAfter));
   WriteLine(reportHandle,"broker_mutation="+(brokerUnchanged?"NONE":"CHANGED"));
   WriteLine(reportHandle,"ordersend_path=NOT_USED");
   WriteLine(reportHandle,"ordercheck_reached="+(realOrderCheckProof?"true":"false"));
   WriteLine(reportHandle,"chart_validation_passed="+(chartValidationPassed?"true":"false"));

   if(reportHandle!=INVALID_HANDLE)
      FileClose(reportHandle);

   Print("Sprint 6B.4 EA chart evidence collection complete | chart_validation_passed=",
         chartValidationPassed?"true":"false");
  }
