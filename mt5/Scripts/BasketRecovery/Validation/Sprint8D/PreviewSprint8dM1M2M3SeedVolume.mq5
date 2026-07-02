#property script_show_inputs
#property description "Sprint 8D: DRY_RUN guard for M1→M2→M3 XAUUSD seed volume chain. No orders, tokens, writes, or EA."

#include <BasketRecovery/Domain/Execution/ProfitCloseCandidateCloseVolumeCalculator.mqh>
#include <BasketRecovery/Domain/Market/SymbolTradingConstraints.mqh>

const double MINIMUM_CHAIN_SEED_VOLUME=0.06;

input string InpSymbol="XAUUSD";
input double InpRequestedSeedVolume=0.06;
input double InpM1ClosePercent=33.0;
input double InpM2ClosePercent=50.0;
input double InpM3ClosePercent=34.0;
input double InpMinLot=0.01;
input double InpLotStep=0.01;
input bool   InpDryRunOnly=true;

struct SSeedVolumeChainStep
  {
   double            closePercent;
   double            closeVolume;
   double            afterVolume;
   bool              promotionRequired;
   bool              valid;
   string            failureReason;
  };

void PrintLine(const string line)
  {
   Print(line);
  }

bool ClosePercentIsValid(const double closePercent)
  {
   return closePercent>0.0 && closePercent<=100.0;
  }

bool RequiresFullClosePromotion(const SProfitCloseVolumeCalculation &calc,
                                const double closePercent,
                                const CSymbolTradingConstraints &constraints)
  {
   if(calc.result!=BRE_PROFIT_CLOSE_VOLUME_RESULT_OK)
      return false;
   if(closePercent>=100.0)
      return false;

   const double epsilon=CProfitCloseCandidateCloseVolumeCalculator::VolumeComparisonEpsilon(constraints.VolumeStep());
   if(!CProfitCloseCandidateCloseVolumeCalculator::VolumeEquals(calc.remainderVolume,0.0,epsilon))
      return false;
   if(calc.closeVolume+epsilon<calc.sourceRemainingVolume)
      return false;

   double rawClose=calc.sourceRemainingVolume*closePercent/100.0;
   double partialClose=CProfitCloseCandidateCloseVolumeCalculator::NormalizeVolume(rawClose,constraints);
   double wouldBeRemainder=calc.sourceRemainingVolume-partialClose;
   if(wouldBeRemainder<0.0 && wouldBeRemainder>-epsilon)
      wouldBeRemainder=0.0;
   return CProfitCloseCandidateCloseVolumeCalculator::VolumeIsPositiveBelowMin(wouldBeRemainder,
                                                                               constraints.VolumeMin(),
                                                                               epsilon);
  }

bool EvaluateChainStep(const double remainingVolume,
                       const double closePercent,
                       const CSymbolTradingConstraints &constraints,
                       const string stepLabel,
                       SSeedVolumeChainStep &stepOut)
  {
   stepOut.closePercent=closePercent;
   stepOut.closeVolume=0.0;
   stepOut.afterVolume=remainingVolume;
   stepOut.promotionRequired=false;
   stepOut.valid=false;
   stepOut.failureReason="";

   SProfitCloseVolumeCalculation calc=
      CProfitCloseCandidateCloseVolumeCalculator::CalculateNextCloseVolume(remainingVolume,
                                                                           closePercent,
                                                                           constraints);
   stepOut.promotionRequired=RequiresFullClosePromotion(calc,closePercent,constraints);

   if(calc.result==BRE_PROFIT_CLOSE_VOLUME_RESULT_NO_VALID_CLOSE_VOLUME)
     {
      stepOut.failureReason=stepLabel+" calculator returned NO_VALID_CLOSE_VOLUME";
      return false;
     }
   if(stepOut.promotionRequired)
     {
      stepOut.failureReason=stepLabel+" requires "+CProfitCloseCandidateCloseVolumeCalculator::DustRemainderPolicyLabel();
      return false;
     }

   const double epsilon=CProfitCloseCandidateCloseVolumeCalculator::VolumeComparisonEpsilon(constraints.VolumeStep());
   stepOut.closeVolume=calc.closeVolume;
   stepOut.afterVolume=calc.remainderVolume;

   if(stepOut.closeVolume<=epsilon)
     {
      stepOut.failureReason=stepLabel+" close volume must be greater than zero";
      return false;
     }
   if(stepOut.afterVolume<=epsilon)
     {
      stepOut.failureReason=stepLabel+" remainder volume must be greater than zero";
      return false;
     }

   stepOut.valid=true;
   return true;
  }

bool RunSeedVolumePreflight(const CSymbolTradingConstraints &constraints,
                            SSeedVolumeChainStep &m1Out,
                            SSeedVolumeChainStep &m2Out,
                            SSeedVolumeChainStep &m3Out,
                            bool &promotionRequiredOut,
                            string &failureReasonOut)
  {
   failureReasonOut="";
   promotionRequiredOut=false;
   m1Out.closePercent=InpM1ClosePercent;
   m2Out.closePercent=InpM2ClosePercent;
   m3Out.closePercent=InpM3ClosePercent;

   if(!InpDryRunOnly)
     {
      failureReasonOut="InpDryRunOnly must remain true; this script has no submit mode";
      return false;
     }
   if(InpSymbol!="XAUUSD")
     {
      failureReasonOut="Symbol must be XAUUSD";
      return false;
     }
   if(InpRequestedSeedVolume<MINIMUM_CHAIN_SEED_VOLUME)
     {
      failureReasonOut="Requested seed volume must be at least 0.06 for M1→M2→M3 chain";
      return false;
     }
   if(InpMinLot<=0.0)
     {
      failureReasonOut="Min lot must be greater than zero";
      return false;
     }
   if(InpLotStep<=0.0)
     {
      failureReasonOut="Lot step must be greater than zero";
      return false;
     }
   if(!ClosePercentIsValid(InpM1ClosePercent))
     {
      failureReasonOut="M1 close percent must be greater than zero and at most 100";
      return false;
     }
   if(!ClosePercentIsValid(InpM2ClosePercent))
     {
      failureReasonOut="M2 close percent must be greater than zero and at most 100";
      return false;
     }
   if(!ClosePercentIsValid(InpM3ClosePercent))
     {
      failureReasonOut="M3 close percent must be greater than zero and at most 100";
      return false;
     }

   if(!EvaluateChainStep(InpRequestedSeedVolume,InpM1ClosePercent,constraints,"M1",m1Out))
     {
      failureReasonOut=m1Out.failureReason;
      promotionRequiredOut=m1Out.promotionRequired;
      return false;
     }
   promotionRequiredOut=m1Out.promotionRequired;

   if(!EvaluateChainStep(m1Out.afterVolume,InpM2ClosePercent,constraints,"M2",m2Out))
     {
      failureReasonOut=m2Out.failureReason;
      promotionRequiredOut=(promotionRequiredOut || m2Out.promotionRequired);
      return false;
     }
   promotionRequiredOut=(promotionRequiredOut || m2Out.promotionRequired);

   if(!EvaluateChainStep(m2Out.afterVolume,InpM3ClosePercent,constraints,"M3",m3Out))
     {
      failureReasonOut=m3Out.failureReason;
      promotionRequiredOut=(promotionRequiredOut || m3Out.promotionRequired);
      return false;
     }
   promotionRequiredOut=(promotionRequiredOut || m3Out.promotionRequired);

   return true;
  }

void PrintSeedVolumeSummary(const bool preflightOk,
                            const string failureReason,
                            const bool promotionRequired,
                            const SSeedVolumeChainStep &m1,
                            const SSeedVolumeChainStep &m2,
                            const SSeedVolumeChainStep &m3)
  {
   PrintLine("sprint8d_seed_volume_mode=DRY_RUN");
   PrintLine("symbol="+InpSymbol);
   PrintLine("seed_volume="+DoubleToString(InpRequestedSeedVolume,8));
   PrintLine("m1_close_percent="+DoubleToString(m1.closePercent,8));
   PrintLine("m1_close_volume="+DoubleToString(m1.closeVolume,8));
   PrintLine("after_m1_volume="+DoubleToString(m1.afterVolume,8));
   PrintLine("m2_close_percent="+DoubleToString(m2.closePercent,8));
   PrintLine("m2_close_volume="+DoubleToString(m2.closeVolume,8));
   PrintLine("after_m2_volume="+DoubleToString(m2.afterVolume,8));
   PrintLine("m3_close_percent="+DoubleToString(m3.closePercent,8));
   PrintLine("m3_close_volume="+DoubleToString(m3.closeVolume,8));
   PrintLine("after_m3_volume="+DoubleToString(m3.afterVolume,8));
   PrintLine("min_lot="+DoubleToString(InpMinLot,8));
   PrintLine("lot_step="+DoubleToString(InpLotStep,8));
   PrintLine("full_close_promotion_required="+(promotionRequired?"true":"false"));
   PrintLine("seed_volume_preflight_result="+(preflightOk?"PASS":"FAIL"));
   PrintLine("seed_volume_preflight_reason="+failureReason);
   if(preflightOk)
      PrintLine("next_safe_step=REVIEW_AND_APPROVE_CONTROLLED_0_06_DEMO_SEED");
   else
      PrintLine("next_safe_step=DO_NOT_PREPARE_OR_SUBMIT_SEED");
  }

void OnStart(void)
  {
   CSymbolTradingConstraints constraints=CSymbolTradingConstraints::Create(0,0,InpMinLot,InpRequestedSeedVolume,InpLotStep);

   SSeedVolumeChainStep m1;
   SSeedVolumeChainStep m2;
   SSeedVolumeChainStep m3;
   bool promotionRequired=false;
   string failureReason="";
   bool preflightOk=RunSeedVolumePreflight(constraints,m1,m2,m3,promotionRequired,failureReason);
   PrintSeedVolumeSummary(preflightOk,failureReason,promotionRequired,m1,m2,m3);
  }
