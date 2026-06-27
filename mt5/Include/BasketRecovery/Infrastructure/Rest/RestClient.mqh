#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_CLIENT_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_CLIENT_MQH

#include <BasketRecovery/Application/Ports/IRestHttpClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/ExponentialBackoff.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCircuitBreaker.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CRestClient
  {
private:
   IRestHttpClient    *m_httpClient;
   CRestCircuitBreaker m_circuitBreaker;
   CExponentialBackoff m_getBackoff;
   CExponentialBackoff m_postBackoff;
   bool                m_authFailed;
   bool                m_ownsHttpClient;

   bool              ShouldRetryStatus(const int statusCode) const
     {
      if(statusCode==429)
         return true;
      if(statusCode>=500 && statusCode<600)
         return true;
      if(statusCode==-1)
         return true;
      return false;
     }

public:
                     CRestClient(IRestHttpClient *httpClient,const bool takeOwnership=false)
     {
      m_httpClient=httpClient;
      m_authFailed=false;
      m_ownsHttpClient=takeOwnership;
      m_getBackoff.UseDefaultGetDelays();
      m_postBackoff.UseDefaultPostDelays();
     }

                    ~CRestClient(void)
     {
      if(m_ownsHttpClient && m_httpClient!=NULL)
        {
         delete m_httpClient;
         m_httpClient=NULL;
        }
     }

   bool              AuthFailed(void) const { return m_authFailed; }
   bool              IsCircuitOpen(void) const { return m_circuitBreaker.IsOpen(); }
   CRestCircuitBreaker& CircuitBreaker(void) { return m_circuitBreaker; }

   CResult<CRestHttpResponse> GetWithRetry(const string &url,const string &headers)
     {
      if(m_authFailed)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_AUTH_FAILED,"REST auth previously failed");

      if(!m_circuitBreaker.AllowRequest())
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_CIRCUIT_OPEN,"REST circuit breaker is open");

      if(m_httpClient==NULL)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"HTTP client is not configured");

      for(int attempt=0;attempt<m_getBackoff.MaxAttempts();attempt++)
        {
         CResult<CRestHttpResponse> responseResult=m_httpClient.Get(url,headers);
         if(responseResult.IsFail())
           {
            m_circuitBreaker.RecordFailure();
            if(attempt<m_getBackoff.MaxAttempts()-1)
              {
               m_getBackoff.WaitBeforeRetry(attempt);
               continue;
              }
            return responseResult;
           }

         CRestHttpResponse response;
         if(!responseResult.TryGetValue(response))
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"GET response is empty");

         if(response.StatusCode()==401)
           {
            m_authFailed=true;
            m_circuitBreaker.RecordFailure();
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_AUTH_FAILED,"REST auth failed");
           }

         if(response.IsSuccess() || response.IsNoContent())
           {
            m_circuitBreaker.RecordSuccess();
            return CResult<CRestHttpResponse>::Ok(response);
           }

         if(!ShouldRetryStatus(response.StatusCode()))
           {
            m_circuitBreaker.RecordFailure();
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,
                                                    StringFormat("GET failed | status=%d",response.StatusCode()));
           }

         m_circuitBreaker.RecordFailure();
         if(attempt<m_getBackoff.MaxAttempts()-1)
            m_getBackoff.WaitBeforeRetry(attempt);
        }

      return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"GET retries exhausted");
     }

   CResult<CRestHttpResponse> PostWithRetry(const string &url,const string &headers,const string &body)
     {
      if(m_authFailed)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_AUTH_FAILED,"REST auth previously failed");

      if(!m_circuitBreaker.AllowRequest())
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_CIRCUIT_OPEN,"REST circuit breaker is open");

      if(m_httpClient==NULL)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"HTTP client is not configured");

      for(int attempt=0;attempt<m_postBackoff.MaxAttempts();attempt++)
        {
         CResult<CRestHttpResponse> responseResult=m_httpClient.Post(url,headers,body);
         if(responseResult.IsFail())
           {
            m_circuitBreaker.RecordFailure();
            if(attempt<m_postBackoff.MaxAttempts()-1)
              {
               m_postBackoff.WaitBeforeRetry(attempt);
               continue;
              }
            return responseResult;
           }

         CRestHttpResponse response;
         if(!responseResult.TryGetValue(response))
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"POST response is empty");

         if(response.StatusCode()==401)
           {
            m_authFailed=true;
            m_circuitBreaker.RecordFailure();
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_AUTH_FAILED,"REST auth failed");
           }

         if(response.IsSuccess() || response.StatusCode()==409)
           {
            m_circuitBreaker.RecordSuccess();
            return CResult<CRestHttpResponse>::Ok(response);
           }

         if(!ShouldRetryStatus(response.StatusCode()))
           {
            m_circuitBreaker.RecordFailure();
            return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_ACK_FAILED,
                                                    StringFormat("POST failed | status=%d",response.StatusCode()));
           }

         m_circuitBreaker.RecordFailure();
         if(attempt<m_postBackoff.MaxAttempts()-1)
            m_postBackoff.WaitBeforeRetry(attempt);
        }

      return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_ACK_FAILED,"POST retries exhausted");
     }
  };

#endif
