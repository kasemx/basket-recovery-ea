#ifndef BRE_DOMAIN_EXECUTION_AUTHORIZATION_TOKEN_MQH
#define BRE_DOMAIN_EXECUTION_AUTHORIZATION_TOKEN_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Domain/Execution/TradeExecutionIntentType.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CExecutionAuthorizationToken
  {
private:
   string                        m_plaintextToken;
   string                        m_tokenHash;
   string                        m_bindingFingerprint;
   datetime                      m_expiryUtc;

public:
                     CExecutionAuthorizationToken(void)
     {
      m_expiryUtc=0;
     }

   string            PlaintextToken(void) const { return m_plaintextToken; }
   string            TokenHash(void) const { return m_tokenHash; }
   string            BindingFingerprint(void) const { return m_bindingFingerprint; }
   datetime          ExpiryUtc(void) const { return m_expiryUtc; }

   void              SetPlaintextToken(const string value) { m_plaintextToken=value; }
   void              SetTokenHash(const string value) { m_tokenHash=value; }
   void              SetBindingFingerprint(const string value) { m_bindingFingerprint=value; }
   void              SetExpiryUtc(const datetime value) { m_expiryUtc=value; }

   bool              IsExpired(const datetime nowUtc) const
     {
      return m_expiryUtc>0 && nowUtc>=m_expiryUtc;
     }

   static string     ComputeBindingFingerprint(const string executionRequestId,
                                               const CBasketId &basketId,
                                               const string symbol,
                                               const ENUM_BRE_TRADE_EXECUTION_INTENT intentType,
                                               const double requestedVolume,
                                               const int expectedBasketVersion,
                                               const string strategyProfileHash)
     {
      string canonical=StringFormat("%s|%s|%s|%d|%.8f|%d|%s",
                                    executionRequestId,
                                    basketId.Value(),
                                    symbol,
                                    (int)intentType,
                                    requestedVolume,
                                    expectedBasketVersion,
                                    strategyProfileHash);
      return StringSubstr(CCrc32::ToHex(CCrc32::Compute(canonical)),0,8);
     }

   static string     ComputeTokenHash(const string plaintextToken)
     {
      return CCrc32::ToHex(CCrc32::Compute(plaintextToken));
     }

   static string     IssuePlaintextToken(const string bindingFingerprint,const datetime expiryUtc)
     {
      return StringFormat("BRE-DEMO-%s-%I64d",bindingFingerprint,(long)expiryUtc);
     }

   static bool       TryParsePlaintextToken(const string plaintextToken,
                                            string &bindingFingerprintOut,
                                            datetime &expiryUtcOut)
     {
      bindingFingerprintOut="";
      expiryUtcOut=0;
      if(StringFind(plaintextToken,"BRE-DEMO-")!=0)
         return false;
      string remainder=StringSubstr(plaintextToken,9);
      int sep=StringFind(remainder,"-");
      if(sep<0)
         return false;
      bindingFingerprintOut=StringSubstr(remainder,0,sep);
      expiryUtcOut=(datetime)StringToInteger(StringSubstr(remainder,sep+1));
      return bindingFingerprintOut!="" && expiryUtcOut>0;
     }
  };

#endif
