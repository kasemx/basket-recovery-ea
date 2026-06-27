#ifndef BRE_INF_IN_MEMORY_MARKET_DATA_PROVIDER_MQH
#define BRE_INF_IN_MEMORY_MARKET_DATA_PROVIDER_MQH

#include <BasketRecovery/Application/Ports/IMarketDataProvider.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CInMemoryMarketDataProvider : public IMarketDataProvider
  {
private:
   CMarketQuote           m_quote;
   CAccountContextSnapshot m_account;
   bool                   m_hasQuote;
   bool                   m_hasAccount;

public:
                     CInMemoryMarketDataProvider(void)
     {
      m_hasQuote=false;
      m_hasAccount=false;
     }

   void              SetQuote(const CMarketQuote &quote)
     {
      m_quote=quote;
      m_hasQuote=(quote.Symbol()!="" && quote.Bid()>0.0 && quote.Ask()>0.0);
     }

   void              SetAccount(const CAccountContextSnapshot &account)
     {
      m_account=account;
      m_hasAccount=true;
     }

   virtual CResult<CMarketQuote> TryGetQuote(const string symbol) const
     {
      if(!m_hasQuote || m_quote.Symbol()!=symbol)
         return CResult<CMarketQuote>::Fail(BRE_ERR_SYMBOL_UNAVAILABLE,"Quote not configured");
      return CResult<CMarketQuote>::Ok(m_quote);
     }

   virtual CResult<CMarketContextSnapshot> TryGetMarketSnapshot(const string symbol) const
     {
      CResult<CMarketQuote> quoteResult=TryGetQuote(symbol);
      if(quoteResult.IsFail())
         return CResult<CMarketContextSnapshot>::Fail(quoteResult.ErrorCode(),quoteResult.ErrorMessage());

      CMarketQuote quote;
      quoteResult.TryGetValue(quote);
      return CResult<CMarketContextSnapshot>::Ok(CMarketContextSnapshot::Create(quote));
     }

   virtual CResult<CAccountContextSnapshot> TryGetAccountSnapshot(void) const
     {
      if(!m_hasAccount)
         return CResult<CAccountContextSnapshot>::Fail(BRE_ERR_ACCOUNT_TRADE_DISABLED,"Account snapshot not configured");
      return CResult<CAccountContextSnapshot>::Ok(m_account);
     }

   virtual void      RefreshCachedQuotes(const string &symbols[],const int symbolCount)
     {
     }
  };

#endif
