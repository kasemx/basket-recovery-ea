#ifndef BASKET_RECOVERY_INFRASTRUCTURE_REST_COMMAND_SOURCE_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_REST_COMMAND_SOURCE_MQH

#include <BasketRecovery/Application/Ports/ICommandSource.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClient.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestClientConfig.mqh>
#include <BasketRecovery/Infrastructure/Rest/RestCommandJsonParser.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CRestCommandSource : public ICommandSource
  {
private:
   CRestClientConfig      m_config;
   CRestClient           *m_restClient;
   CRestCommandJsonParser m_parser;
   string                 m_cursor;
   int                    m_lastRejectedCount;
   bool                   m_ownsRestClient;

   string            BuildHeaders(void) const
     {
      string headers="Accept: application/json\r\n";
      if(m_config.ApiKey()!="")
         headers+="X-API-Key: "+m_config.ApiKey()+"\r\n";
      return headers;
     }

   string            BuildPendingUrl(void) const
     {
      string url=m_config.BaseUrl();
      if(StringFind(url,"/api/v1/commands/pending")<0)
        {
         if(StringGetCharacter(url,StringLen(url)-1)!='/')
            url+="/";
         url+="api/v1/commands/pending";
        }
      url+="?account_id="+IntegerToString(m_config.AccountId());
      if(m_cursor!="")
         url+="&since="+m_cursor;
      return url;
     }

   string            BuildAckUrl(const CCommandId &commandId) const
     {
      string url=m_config.BaseUrl();
      if(StringGetCharacter(url,StringLen(url)-1)!='/')
         url+="/";
      return url+"api/v1/commands/"+commandId.Value()+"/ack";
     }

   string            BuildAckBody(void) const
     {
      return "{"
             +"\"account_id\":\""+IntegerToString(m_config.AccountId())+"\","
             +"\"processed_at\":\""+TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS)+"\","
             +"\"mt5_instance_id\":\""+m_config.Mt5InstanceId()+"\""
             +"}";
     }

public:
                     CRestCommandSource(CRestClient *restClient,const CRestClientConfig &config,const bool takeOwnership=false)
     {
      m_restClient=restClient;
      m_config=config;
      m_cursor="";
      m_lastRejectedCount=0;
      m_ownsRestClient=takeOwnership;
     }

                    ~CRestCommandSource(void)
     {
      if(m_ownsRestClient && m_restClient!=NULL)
        {
         delete m_restClient;
         m_restClient=NULL;
        }
     }

   int               LastRejectedCount(void) const { return m_lastRejectedCount; }
   string            Cursor(void) const { return m_cursor; }

   virtual int       LastValidationRejectedCount(void) const { return m_lastRejectedCount; }

   virtual bool      IsAvailable(void) const
     {
      if(!m_config.IsEnabled())
         return false;
      if(m_restClient==NULL)
         return false;
      if(m_restClient.AuthFailed())
         return false;
      return !m_restClient.IsCircuitOpen();
     }

   virtual CResult<int> FetchPending(ICommand * &commands[])
     {
      ArrayResize(commands,0);
      m_lastRejectedCount=0;

      if(!m_config.IsEnabled())
         return CResult<int>::Fail(BRE_ERR_REST_DISABLED,"REST command source is disabled");

      if(m_restClient==NULL)
         return CResult<int>::Fail(BRE_ERR_REST_NETWORK_ERROR,"REST client is not configured");

      string pendingUrl=BuildPendingUrl();
      string headers=BuildHeaders();
      CResult<CRestHttpResponse> responseResult=m_restClient.GetWithRetry(pendingUrl,headers);
      if(responseResult.IsFail())
         return CResult<int>::Fail(responseResult.ErrorCode(),responseResult.ErrorMessage());

      CRestHttpResponse response;
      if(!responseResult.TryGetValue(response))
         return CResult<int>::Fail(BRE_ERR_REST_NETWORK_ERROR,"Pending GET response is empty");

      if(response.IsNoContent())
         return CResult<int>::Ok(0);

      if(!response.IsSuccess())
         return CResult<int>::Fail(BRE_ERR_REST_NETWORK_ERROR,
                                   StringFormat("Pending GET failed | status=%d",response.StatusCode()));

      string rejectedError="";
      CResult<int> parseResult=m_parser.ParsePendingResponse(response.Body(),commands,m_lastRejectedCount,m_cursor);
      if(parseResult.IsFail())
         return parseResult;

      int count=0;
      if(!parseResult.TryGetValue(count))
         count=0;
      return CResult<int>::Ok(count);
     }

   virtual CVoidResult Acknowledge(const CCommandId &commandId)
     {
      if(commandId.IsEmpty())
         return CVoidResult::Fail(BRE_ERR_COMMAND_INVALID,"Ack command id is empty");

      if(m_restClient==NULL)
         return CVoidResult::Fail(BRE_ERR_REST_NETWORK_ERROR,"REST client is not configured");

      string ackUrl=BuildAckUrl(commandId);
      string ackHeaders=BuildHeaders()+"Content-Type: application/json\r\n";
      string ackBody=BuildAckBody();
      CResult<CRestHttpResponse> responseResult=m_restClient.PostWithRetry(ackUrl,ackHeaders,ackBody);

      if(responseResult.IsFail())
         return CVoidResult::Fail(responseResult.ErrorCode(),responseResult.ErrorMessage());

      return CVoidResult::Ok();
     }
  };

#endif
