#ifndef BASKET_RECOVERY_APPLICATION_IREST_HTTP_CLIENT_MQH
#define BASKET_RECOVERY_APPLICATION_IREST_HTTP_CLIENT_MQH

#include <BasketRecovery/Shared/Types/Result.mqh>
#include <BasketRecovery/Shared/DTOs/RestHttpResponse.mqh>

class IRestHttpClient
  {
public:
   virtual          ~IRestHttpClient(void) {}
   virtual CResult<CRestHttpResponse> Get(const string &url,const string &headers)=0;
   virtual CResult<CRestHttpResponse> Post(const string &url,const string &headers,const string &body)=0;
  };

#endif
