#ifndef BASKET_RECOVERY_SHARED_RESULT_VALUE_TRANSFER_MQH
#define BASKET_RECOVERY_SHARED_RESULT_VALUE_TRANSFER_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Application/DTOs/EventHandlingResult.mqh>
#include <BasketRecovery/Application/DTOs/CommandExecutionResult.mqh>

CResult<CEventHandlingResult> BreResultOkAdopting(CEventHandlingResult &source)
  {
   CResult<CEventHandlingResult> result=CResult<CEventHandlingResult>::EmptyOk();
   source.TransferCommandsTo(result.m_value);
   return result;
  }

CResult<CCommandExecutionResult> BreResultOkAdopting(CCommandExecutionResult &source)
  {
   CResult<CCommandExecutionResult> result=CResult<CCommandExecutionResult>::EmptyOk();
   source.TransferEventsTo(result.m_value);
   return result;
  }

bool BreResultTryAdoptValue(CResult<CEventHandlingResult> &result,CEventHandlingResult &outValue)
  {
   if(!result.HasValue())
      return false;
   result.m_value.TransferCommandsTo(outValue);
   return true;
  }

bool BreResultTryAdoptValue(CResult<CCommandExecutionResult> &result,CCommandExecutionResult &outValue)
  {
   if(!result.HasValue())
      return false;
   result.m_value.TransferEventsTo(outValue);
   return true;
  }

#endif
