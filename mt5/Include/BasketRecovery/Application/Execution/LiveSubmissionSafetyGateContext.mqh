#ifndef BRE_APP_LIVE_SUBMISSION_SAFETY_GATE_CONTEXT_MQH
#define BRE_APP_LIVE_SUBMISSION_SAFETY_GATE_CONTEXT_MQH

#include <BasketRecovery/Application/Configuration/DemoExecutionAuthorizationConfig.mqh>
#include <BasketRecovery/Domain/Aggregates/BasketAggregate.mqh>
#include <BasketRecovery/Domain/Execution/PendingExecutionEntry.mqh>
#include <BasketRecovery/Domain/Execution/BrokerSubmissionEnvelope.mqh>
#include <BasketRecovery/Domain/Execution/AccountExecutionEligibilitySnapshot.mqh>
#include <BasketRecovery/Domain/Market/MarketQuote.mqh>
#include <BasketRecovery/Application/Configuration/MarketSafetyConfig.mqh>

class CLiveSubmissionSafetyGateContext
  {
private:
   CDemoExecutionAuthorizationConfig       m_config;
   CPendingExecutionEntry                  m_entry;
   CBrokerSubmissionEnvelope               m_envelope;
   CBasketAggregate                        m_basket;
   CMarketQuote                            m_quote;
   CAccountExecutionEligibilitySnapshot    m_eligibility;
   CMarketSafetyConfig                     m_marketSafety;
   datetime                                m_nowUtc;

public:
   CDemoExecutionAuthorizationConfig      Config(void) const { return m_config; }
   void                                   SetConfig(const CDemoExecutionAuthorizationConfig &value) { m_config=value; }
   CPendingExecutionEntry                 Entry(void) const { return m_entry; }
   void                                   SetEntry(const CPendingExecutionEntry &value) { m_entry=value; }
   CBrokerSubmissionEnvelope              Envelope(void) const { return m_envelope; }
   void                                   SetEnvelope(const CBrokerSubmissionEnvelope &value) { m_envelope=value; }
   CBasketAggregate                       Basket(void) const { return m_basket; }
   void                                   SetBasket(const CBasketAggregate &value) { m_basket=value; }
   CMarketQuote                           Quote(void) const { return m_quote; }
   void                                   SetQuote(const CMarketQuote &value) { m_quote=value; }
   CAccountExecutionEligibilitySnapshot   Eligibility(void) const { return m_eligibility; }
   void                                   SetEligibility(const CAccountExecutionEligibilitySnapshot &value) { m_eligibility=value; }
   CMarketSafetyConfig                    MarketSafety(void) const { return m_marketSafety; }
   void                                   SetMarketSafety(const CMarketSafetyConfig &value) { m_marketSafety=value; }
   datetime                               NowUtc(void) const { return m_nowUtc; }
   void                                   SetNowUtc(const datetime value) { m_nowUtc=value; }
  };

#endif
