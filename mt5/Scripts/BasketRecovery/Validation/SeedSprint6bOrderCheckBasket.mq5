#property script_show_inputs
#property description "Sprint 6B.1/6B.3: seed ACTIVE basket via production flow with CRC verification."

#include <BasketRecovery/Tests/StrategyProfileTestFixture.mqh>
#include <BasketRecovery/Application/Services/ExecutionDryRunTestBasketSeedService.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketPersistenceLoadDiagnostic.mqh>
#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Domain/Enums/BasketLifecycleState.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5Clock.mqh>
#include <BasketRecovery/Infrastructure/MT5/Mt5UniqueIdGenerator.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>

input string InpPreferredSymbol = "BTCUSD";
input string InpBasketId        = "sprint6b-demo-btc-001";

string ResolveTradingSymbol(const string preferred)
  {
   string candidates[];
   ArrayResize(candidates,4);
   candidates[0]=preferred;
   candidates[1]=preferred+"m";
   candidates[2]=preferred+".";
   candidates[3]=_Symbol;

   for(int i=0;i<ArraySize(candidates);i++)
     {
      if(candidates[i]=="")
         continue;
      if(SymbolSelect(candidates[i],true) && SymbolInfoDouble(candidates[i],SYMBOL_BID)>0.0)
         return candidates[i];
     }
   return preferred;
  }

void WriteLine(const int handle,const string line)
  {
   if(handle!=INVALID_HANDLE)
      FileWriteString(handle,line+"\r\n");
   Print(line);
  }

bool VerifyReopenOrFail(const int reportHandle,
                        const CBasketId &basketId,
                        const string expectedSymbol,
                        string &failureMessage)
  {
   CFileBasketRepository reopenedRepository(BRE_PERSISTENCE_BASKET_SUBDIR);
   CBasketPersistenceLoadDiagnostic inspect=
      CBasketPersistenceLoadDiagnostic::Inspect(BRE_PERSISTENCE_BASKET_SUBDIR,basketId,reopenedRepository);
   WriteLine(reportHandle,CBasketPersistenceLoadDiagnostic::FormatLogLine(inspect));
   WriteLine(reportHandle,"reopen_terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"reopen_common_data_path="+inspect.commonDataPath);
   WriteLine(reportHandle,"reopen_file="+inspect.fullResolvedFilePath);
   WriteLine(reportHandle,"reopen_stored_crc="+inspect.storedCrcHex);
   WriteLine(reportHandle,"reopen_computed_crc="+inspect.computedCrcHex);
   WriteLine(reportHandle,"reopen_validation_stage="+inspect.validationStage);

   if(!inspect.repositoryLoadOk)
     {
      failureMessage="Fresh repository reopen failed | code="+IntegerToString(inspect.repositoryErrorCode)+
                     " | message="+inspect.repositoryErrorMessage+
                     " | stage="+inspect.validationStage+
                     " | classification="+inspect.failureClassification;
      return false;
     }

   CResult<CBasketAggregate> loaded=reopenedRepository.Load(basketId);
   if(loaded.IsFail())
     {
      failureMessage=loaded.ErrorMessage();
      return false;
     }

   CBasketAggregate basket;
   loaded.TryGetValue(basket);
   if(basket.Id().Value()!=basketId.Value())
     {
      failureMessage="Reopened basket id mismatch";
      return false;
     }
   if(basket.LifecycleState()!=BRE_STATE_ACTIVE)
     {
      failureMessage="Reopened basket lifecycle is not ACTIVE";
      return false;
     }
   if(basket.Symbol()!=expectedSymbol)
     {
      failureMessage="Reopened basket symbol mismatch";
      return false;
     }
   if(!basket.HasStrategyProfile())
     {
      failureMessage="Reopened basket has no strategy snapshot";
      return false;
     }
   if(basket.StrategyProfileHash()=="")
     {
      failureMessage="Reopened basket strategy profile hash is empty";
      return false;
     }
   if(StringLen(basket.StrategyProfileHash())==0)
     {
      failureMessage="Reopened basket strategy profile hash length is zero";
      return false;
     }
   if(inspect.canonicalJsonLen<=0)
     {
      failureMessage="Reopened basket canonical strategy JSON is empty";
      return false;
     }
   if(inspect.profileHashLen<=0)
     {
      failureMessage="Reopened basket strategy profile hash length in persistence is zero";
      return false;
     }

   WriteLine(reportHandle,"reopen=OK basket_id="+basket.Id().Value()+
                         " lifecycle=ACTIVE symbol="+basket.Symbol()+
                         " version="+IntegerToString((int)basket.Version())+
                         " profile_hash="+basket.StrategyProfileHash()+
                         " strategy_id="+basket.StrategyId());
   WriteLine(reportHandle,"reopen_crc_match="+((inspect.storedCrcHex==inspect.computedCrcHex &&
                                                inspect.computedCrcHex!="")?"true":"false"));
   return true;
  }

void OnStart()
  {
   string symbol=ResolveTradingSymbol(InpPreferredSymbol);
   CBasketId basketId(InpBasketId);

   FolderCreate("BasketRecovery\\validation",FILE_COMMON);
   string reportRel="BasketRecovery\\validation\\sprint-6b-seed-result.txt";
   int reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(reportHandle==INVALID_HANDLE)
      reportHandle=FileOpen(reportRel,FILE_WRITE|FILE_TXT|FILE_ANSI);

   WriteLine(reportHandle,"=== Sprint 6B.3 Basket Seed ===");
   WriteLine(reportHandle,"timestamp="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   WriteLine(reportHandle,"seed_terminal_data_path="+TerminalInfoString(TERMINAL_DATA_PATH));
   WriteLine(reportHandle,"seed_common_data_path="+TerminalInfoString(TERMINAL_COMMONDATA_PATH));
   WriteLine(reportHandle,"persistence_store="+CExecutionDryRunTestBasketSeedService::PersistenceStoreLabel());
   WriteLine(reportHandle,"serializer="+CExecutionDryRunTestBasketSeedService::SerializerLabel());
   WriteLine(reportHandle,"use_case_flow="+CExecutionDryRunTestBasketSeedService::UseCaseFlowLabel());
   WriteLine(reportHandle,"final_persisted_file="+
             CBasketPersistenceLoadDiagnostic::BuildFullCommonFilePath(BRE_PERSISTENCE_BASKET_SUBDIR+"/"+
                                                                       basketId.Value()+".json"));

   CMt5Clock clock;
   CMt5UniqueIdGenerator idGenerator;
   CFileBasketRepository repository(BRE_PERSISTENCE_BASKET_SUBDIR);
   repository.Delete(basketId);
   CExecutionDryRunTestBasketSeedService seedService;
   if(!seedService.Initialize(&repository,&clock,&idGenerator,"default"))
     {
      WriteLine(reportHandle,"seed=FAILED message=Seed service initialization failed");
      if(reportHandle!=INVALID_HANDLE)
         FileClose(reportHandle);
      return;
     }

   string strategyJson=CStrategyProfileTestFixture::MinimalValidJson();
   CResult<CBasketAggregate> seedResult=seedService.SeedActiveBasket(basketId,symbol,BRE_DIRECTION_BUY,strategyJson);
   if(seedResult.IsFail())
     {
      WriteLine(reportHandle,"seed=FAILED error_code="+IntegerToString(seedResult.ErrorCode())+
                            " message="+seedResult.ErrorMessage());
      if(reportHandle!=INVALID_HANDLE)
         FileClose(reportHandle);
      return;
     }

   CBasketAggregate seeded;
   seedResult.TryGetValue(seeded);
   WriteLine(reportHandle,"seed=OK basket_id="+basketId.Value()+" symbol="+seeded.Symbol()+
                         " lifecycle=ACTIVE version="+IntegerToString((int)seeded.Version())+
                         " strategy_id="+seeded.StrategyId()+
                         " profile_hash="+seeded.StrategyProfileHash());

   CBasketSerializer serializer;
   string serialized=serializer.Serialize(seeded);
   CJsonReader reader;
   reader.SetContent(serialized);
   WriteLine(reportHandle,"post_save_stored_crc="+reader.ReadString("crc32",""));

   string reopenFailure="";
   if(!VerifyReopenOrFail(reportHandle,basketId,symbol,reopenFailure))
     {
      WriteLine(reportHandle,"seed_verification=FAILED message="+reopenFailure);
      if(reportHandle!=INVALID_HANDLE)
         FileClose(reportHandle);
      return;
     }

   WriteLine(reportHandle,"seed_verification=OK");
   WriteLine(reportHandle,"positions_before="+IntegerToString(PositionsTotal()));
   WriteLine(reportHandle,"orders_before="+IntegerToString(OrdersTotal()));

   if(reportHandle!=INVALID_HANDLE)
      FileClose(reportHandle);

   Print("Sprint 6B.3 basket seed complete | basket=",basketId.Value()," | symbol=",symbol);
  }
