#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_WEB_REQUEST_CLIENT_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_WEB_REQUEST_CLIENT_MQH

#include <BasketRecovery/Application/Ports/IRestHttpClient.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CRestWebRequestClient : public IRestHttpClient
  {
private:
   int               m_timeoutMs;

   CResult<CRestHttpResponse> Execute(const string method,
                                      const string url,
                                      const string headers,
                                      const string body) const
     {
      char requestData[];
      char responseData[];
      string responseHeaders;
      StringToCharArray(body,requestData,0,WHOLE_ARRAY,CP_UTF8);

      ResetLastError();
      int statusCode=WebRequest(method,
                                url,
                                headers,
                                m_timeoutMs,
                                requestData,
                                responseData,
                                responseHeaders);

      if(statusCode==-1)
        {
         int error=GetLastError();
         CRestHttpResponse response;
         response.SetStatusCode(-1);
         response.SetErrorMessage(StringFormat("WebRequest failed | error=%d",error));
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,response.ErrorMessage());
        }

      CRestHttpResponse response;
      response.SetStatusCode(statusCode);
      response.SetBody(CharArrayToString(responseData,0,WHOLE_ARRAY,CP_UTF8));
      return CResult<CRestHttpResponse>::Ok(response);
     }

public:
                     CRestWebRequestClient(const int timeoutMs=5000)
     {
      m_timeoutMs=timeoutMs;
     }

   void              SetTimeoutMs(const int value) { m_timeoutMs=value; }

   virtual CResult<CRestHttpResponse> Get(const string &url,const string &headers)
     {
      return Execute("GET",url,headers,"");
     }

   virtual CResult<CRestHttpResponse> Post(const string &url,const string &headers,const string &body)
     {
      return Execute("POST",url,headers,body);
     }
  };

#endif
