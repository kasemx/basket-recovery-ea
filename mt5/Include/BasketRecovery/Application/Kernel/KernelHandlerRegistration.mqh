#ifndef BASKET_RECOVERY_APPLICATION_KERNEL_HANDLER_REGISTRATION_MQH
#define BASKET_RECOVERY_APPLICATION_KERNEL_HANDLER_REGISTRATION_MQH

#include <BasketRecovery/Application/Kernel/CommandDispatcher.mqh>
#include <BasketRecovery/Application/Kernel/EventDispatcher.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CreateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/ActivateBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/CloseBasketCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/EvaluateStrategyCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/StrategyExecutionStubHandlers.mqh>
#include <BasketRecovery/Application/Handlers/Commands/DisableRecoveryCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Commands/MarkProfitLevelCompletedCommandHandler.mqh>
#include <BasketRecovery/Application/Handlers/Events/StrategyRuntimeEventHandlers.mqh>
#include <BasketRecovery/Application/Handlers/Events/StrategyRuntimeEventHandlersPart2.mqh>

class CKernelHandlerRegistration
  {
public:
   static void       RegisterCommandHandlers(CCommandDispatcher &dispatcher,
                                             CCreateBasketCommandHandler *createHandler,
                                             CActivateBasketCommandHandler *activateHandler,
                                             CCloseBasketCommandHandler *closeHandler,
                                             CEvaluateStrategyCommandHandler *evaluateHandler,
                                             COpenRecoveryPositionCommandHandler *openRecoveryHandler,
                                             CClosePositionsCommandHandler *closePositionsHandler,
                                             CMoveBasketStopLossCommandHandler *moveStopHandler,
                                             CReduceBasketRiskCommandHandler *reduceRiskHandler,
                                             CDisableRecoveryCommandHandler *disableRecoveryHandler,
                                             CMarkProfitLevelCompletedCommandHandler *markProfitHandler)
     {
      if(createHandler!=NULL) dispatcher.RegisterHandler(createHandler,10);
      if(activateHandler!=NULL) dispatcher.RegisterHandler(activateHandler,20);
      if(closeHandler!=NULL) dispatcher.RegisterHandler(closeHandler,30);
      if(evaluateHandler!=NULL) dispatcher.RegisterHandler(evaluateHandler,40);
      if(openRecoveryHandler!=NULL) dispatcher.RegisterHandler(openRecoveryHandler,50);
      if(closePositionsHandler!=NULL) dispatcher.RegisterHandler(closePositionsHandler,50);
      if(moveStopHandler!=NULL) dispatcher.RegisterHandler(moveStopHandler,50);
      if(reduceRiskHandler!=NULL) dispatcher.RegisterHandler(reduceRiskHandler,50);
      if(disableRecoveryHandler!=NULL) dispatcher.RegisterHandler(disableRecoveryHandler,60);
      if(markProfitHandler!=NULL) dispatcher.RegisterHandler(markProfitHandler,60);
     }

   static void       RegisterStrategyEventHandlers(CEventDispatcher &dispatcher,
                                                   CProfitLevelReachedEventHandler *profitReachedHandler,
                                                   CProfitLevelCloseRequestedEventHandler *closeRequestedHandler,
                                                   CProfitLevelCloseCompletedEventHandler *closeCompletedHandler,
                                                   CBreakEvenActivatedEventHandler *breakEvenHandler,
                                                   CRecoveryDisabledEventHandler *recoveryDisabledHandler,
                                                   CRiskReductionRequestedEventHandler *riskReductionHandler,
                                                   CBasketLockedEventHandler *lockedHandler,
                                                   CStrategyProfileBoundEventHandler *profileBoundHandler)
     {
      if(profitReachedHandler!=NULL) dispatcher.RegisterHandler(profitReachedHandler);
      if(closeRequestedHandler!=NULL) dispatcher.RegisterHandler(closeRequestedHandler);
      if(closeCompletedHandler!=NULL) dispatcher.RegisterHandler(closeCompletedHandler);
      if(breakEvenHandler!=NULL) dispatcher.RegisterHandler(breakEvenHandler);
      if(recoveryDisabledHandler!=NULL) dispatcher.RegisterHandler(recoveryDisabledHandler);
      if(riskReductionHandler!=NULL) dispatcher.RegisterHandler(riskReductionHandler);
      if(lockedHandler!=NULL) dispatcher.RegisterHandler(lockedHandler);
      if(profileBoundHandler!=NULL) dispatcher.RegisterHandler(profileBoundHandler);
     }
  };

#endif
