#ifndef BASKET_RECOVERY_SHARED_REST_HTTP_RESPONSE_MQH
#define BASKET_RECOVERY_SHARED_REST_HTTP_RESPONSE_MQH

class CRestHttpResponse
  {
private:
   int    m_statusCode;
   string m_body;
   string m_errorMessage;

public:
                     CRestHttpResponse(void)
     {
      m_statusCode=0;
      m_body="";
      m_errorMessage="";
     }

   int               StatusCode(void) const { return m_statusCode; }
   string            Body(void) const { return m_body; }
   string            ErrorMessage(void) const { return m_errorMessage; }
   bool              IsSuccess(void) const { return m_statusCode>=200 && m_statusCode<300; }
   bool              IsNoContent(void) const { return m_statusCode==204; }

   void              SetStatusCode(const int value) { m_statusCode=value; }
   void              SetBody(const string value) { m_body=value; }
   void              SetErrorMessage(const string value) { m_errorMessage=value; }
  };

#endif
