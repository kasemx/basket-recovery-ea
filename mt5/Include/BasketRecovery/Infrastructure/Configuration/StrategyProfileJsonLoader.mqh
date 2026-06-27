#ifndef BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_LOADER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_LOADER_MQH

#include <BasketRecovery/Infrastructure/Configuration/StrategyProfileJsonParser.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Shared/Constants/StrategySchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CStrategyProfileJsonLoader
  {
private:
   IClock *m_clock;

   string            BuildRelativePath(const string strategyId) const
     {
      return BRE_STRATEGY_FILES_SUBDIR+strategyId+".strategy.json";
     }

   CResult<string>   ReadFileContent(const string relativePath) const
     {
      int handle=FileOpen(relativePath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE)
         return CResult<string>::Fail(BRE_ERR_STRATEGY_LOAD_FAILED,"Strategy profile file is missing: "+relativePath);

      string content="";
      while(!FileIsEnding(handle))
         content+=FileReadString(handle);
      FileClose(handle);
      return CResult<string>::Ok(content);
     }

   CUtcTime          ResolveBoundAt(void) const
     {
      if(m_clock!=NULL)
         return CUtcTime(m_clock.Now());
      return CUtcTime(0);
     }

public:
                     CStrategyProfileJsonLoader(IClock *clock=NULL)
     {
      m_clock=clock;
     }

   CResult<CStrategyProfile> LoadFromStrategyId(const string strategyId)
     {
      if(strategyId=="")
         return CResult<CStrategyProfile>::Fail(BRE_ERR_STRATEGY_LOAD_FAILED,"Strategy id is empty");
      return LoadFromRelativePath(BuildRelativePath(strategyId));
     }

   CResult<CStrategyProfile> LoadFromRelativePath(const string relativePath)
     {
      CResult<string> contentResult=ReadFileContent(relativePath);
      if(contentResult.IsFail())
         return CResult<CStrategyProfile>::Fail(contentResult.ErrorCode(),contentResult.ErrorMessage());
      string content;
      contentResult.TryGetValue(content);
      return LoadFromJsonContent(content);
     }

   CResult<CStrategyProfile> LoadFromJsonContent(const string content)
     {
      CStrategyProfileJsonParser parser;
      return parser.Parse(content,ResolveBoundAt());
     }
  };

#endif
