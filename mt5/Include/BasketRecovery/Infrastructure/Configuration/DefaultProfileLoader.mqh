#ifndef BASKET_RECOVERY_INFRASTRUCTURE_DEFAULT_PROFILE_LOADER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_DEFAULT_PROFILE_LOADER_MQH

#include <BasketRecovery/Application/Ports/IConfigurationProfileLoader.mqh>
#include <BasketRecovery/Application/Ports/IClock.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CDefaultProfileLoader : public IConfigurationProfileLoader
  {
private:
   IClock *m_clock;

   CProfileBundle BuildDefaultProfile(const string profileName) const
     {
      CProfileBundle bundle;
      bundle.SetProfileName(profileName);

      CRiskProfileConfig risk;
      risk.SetProfileName(profileName);
      bundle.SetRisk(risk);

      CRecoveryProfileConfig recovery;
      recovery.SetProfileName(profileName);
      bundle.SetRecovery(recovery);

      CTakeProfitProfileConfig takeProfit;
      takeProfit.SetProfileName(profileName);
      bundle.SetTakeProfit(takeProfit);

      CBreakEvenProfileConfig breakEven;
      breakEven.SetProfileName(profileName);
      bundle.SetBreakEven(breakEven);

      CExecutionProfileConfig execution;
      execution.SetProfileName(profileName);
      bundle.SetExecution(execution);

      if(m_clock!=NULL)
         bundle.SetBoundAt(CUtcTime(m_clock.Now()));
      else
         bundle.SetBoundAt(CUtcTime(0));

      return bundle;
     }

public:
                     CDefaultProfileLoader(IClock *clock)
     {
      m_clock=clock;
     }

   virtual          ~CDefaultProfileLoader(void) {}

   virtual CResult<CProfileBundle> LoadProfile(const string profileName)
     {
      if(profileName=="")
         return CResult<CProfileBundle>::Fail(BRE_ERR_PROFILE_LOAD_FAILED,"Profile name is empty");

      CProfileBundle bundle=BuildDefaultProfile(profileName);
      CVoidResult validation=Validate(bundle);
      if(validation.IsFail())
         return CResult<CProfileBundle>::Fail(validation.ErrorCode(),validation.ErrorMessage());

      return CResult<CProfileBundle>::Ok(bundle);
     }

   virtual CResult<CProfileBundle> ResolveForSymbol(const string symbol)
     {
      string profileName="default";
      if(symbol=="")
         profileName="default";
      return LoadProfile(profileName);
     }

   virtual CVoidResult Validate(const CProfileBundle &profileBundle)
     {
      if(profileBundle.ProfileName()=="")
         return CVoidResult::Fail(BRE_ERR_CONFIG_INVALID,"Profile name is empty");

      if(profileBundle.Risk().MaxRiskPct()<profileBundle.Risk().TargetRiskPct())
         return CVoidResult::Fail(BRE_ERR_CONFIG_INVALID,"Max risk must be greater than or equal to target risk");

      if(profileBundle.Recovery().InitialPositionCount()<=0)
         return CVoidResult::Fail(BRE_ERR_CONFIG_INVALID,"Initial position count must be positive");

      if(profileBundle.TakeProfit().Tp1RealizeFraction()>=profileBundle.TakeProfit().Tp2RealizeFraction())
         return CVoidResult::Fail(BRE_ERR_CONFIG_INVALID,"TP1 fraction must be less than TP2 fraction");

      return CVoidResult::Ok();
     }
  };

#endif
