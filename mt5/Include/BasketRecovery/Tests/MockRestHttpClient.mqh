#ifndef BASKET_RECOVERY_TESTS_MOCK_REST_HTTP_CLIENT_MQH
#define BASKET_RECOVERY_TESTS_MOCK_REST_HTTP_CLIENT_MQH

#include <BasketRecovery/Application/Ports/IRestHttpClient.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CMockRestHttpClient : public IRestHttpClient
  {
private:
   string m_nextGetBody;
   int    m_nextGetStatus;
   string m_nextPostBody;
   int    m_nextPostStatus;
   bool   m_failNextGet;
   bool   m_failNextPost;
   int    m_getCallCount;
   int    m_postCallCount;
   string m_lastGetUrl;
   string m_lastPostUrl;
   string m_lastPostBody;

public:
                     CMockRestHttpClient(void)
     {
      m_nextGetBody="";
      m_nextGetStatus=200;
      m_nextPostBody="{\"acknowledged\":true}";
      m_nextPostStatus=200;
      m_failNextGet=false;
      m_failNextPost=false;
      m_getCallCount=0;
      m_postCallCount=0;
      m_lastGetUrl="";
      m_lastPostUrl="";
      m_lastPostBody="";
     }

   void              SetNextGetResponse(const string body,const int statusCode=200)
     {
      m_nextGetBody=body;
      m_nextGetStatus=statusCode;
      m_failNextGet=false;
     }

   void              SetNextPostResponse(const string body,const int statusCode=200)
     {
      m_nextPostBody=body;
      m_nextPostStatus=statusCode;
      m_failNextPost=false;
     }

   void              FailNextGet(void) { m_failNextGet=true; }
   void              FailNextPost(void) { m_failNextPost=true; }

   int               GetCallCount(void) const { return m_getCallCount; }
   int               PostCallCount(void) const { return m_postCallCount; }
   string            LastGetUrl(void) const { return m_lastGetUrl; }
   string            LastPostUrl(void) const { return m_lastPostUrl; }
   string            LastPostBody(void) const { return m_lastPostBody; }

   virtual CResult<CRestHttpResponse> Get(const string &url,const string &headers)
     {
      m_getCallCount++;
      m_lastGetUrl=url;
      if(m_failNextGet)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_NETWORK_ERROR,"Mock GET failed");

      CRestHttpResponse response;
      response.SetStatusCode(m_nextGetStatus);
      response.SetBody(m_nextGetBody);
      return CResult<CRestHttpResponse>::Ok(response);
     }

   virtual CResult<CRestHttpResponse> Post(const string &url,const string &headers,const string &body)
     {
      m_postCallCount++;
      m_lastPostUrl=url;
      m_lastPostBody=body;
      if(m_failNextPost)
         return CResult<CRestHttpResponse>::Fail(BRE_ERR_REST_ACK_FAILED,"Mock POST failed");

      CRestHttpResponse response;
      response.SetStatusCode(m_nextPostStatus);
      response.SetBody(m_nextPostBody);
      return CResult<CRestHttpResponse>::Ok(response);
     }
  };

#endif
