#ifndef BASKET_RECOVERY_SHARED_RESULT_MQH
#define BASKET_RECOVERY_SHARED_RESULT_MQH

#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

template<typename T>
class CResult
  {
public:
   bool   m_success;
   T      m_value;
   int    m_errorCode;
   string m_errorMessage;
   bool   m_hasValue;

                     CResult(void)
     {
      m_success=false;
      m_errorCode=BRE_ERR_NONE;
      m_errorMessage="";
      m_hasValue=false;
     }

                     CResult(const CResult &other)
     {
      m_success=other.m_success;
      m_value=other.m_value;
      m_errorCode=other.m_errorCode;
      m_errorMessage=other.m_errorMessage;
      m_hasValue=other.m_hasValue;
     }

   static CResult    Ok(const T &value)
     {
      CResult<T> result;
      result.m_success=true;
      result.m_hasValue=true;
      result.m_value=value;
      return result;
     }

   static CResult    EmptyOk(void)
     {
      CResult<T> result;
      result.m_success=true;
      result.m_hasValue=true;
      return result;
     }

   static CResult    Fail(const int errorCode,const string message)
     {
      CResult<T> result;
      result.m_success=false;
      result.m_errorCode=errorCode;
      result.m_errorMessage=message;
      return result;
     }

   bool              IsOk(void) const { return m_success; }
   bool              IsFail(void) const { return !m_success; }
   int               ErrorCode(void) const { return m_errorCode; }
   string            ErrorMessage(void) const { return m_errorMessage; }
   bool              HasValue(void) const { return m_hasValue && m_success; }

   bool              TryGetValue(T &outValue) const
     {
      if(!HasValue())
         return false;
      outValue=m_value;
      return true;
     }
  };

class CVoidResult
  {
private:
   bool   m_success;
   int    m_errorCode;
   string m_errorMessage;

public:
                     CVoidResult(void)
     {
      m_success=false;
      m_errorCode=BRE_ERR_NONE;
      m_errorMessage="";
     }

   static CVoidResult Ok(void)
     {
      CVoidResult result;
      result.m_success=true;
      return result;
     }

   static CVoidResult Fail(const int errorCode,const string message)
     {
      CVoidResult result;
      result.m_success=false;
      result.m_errorCode=errorCode;
      result.m_errorMessage=message;
      return result;
     }

   bool              IsOk(void) const { return m_success; }
   bool              IsFail(void) const { return !m_success; }
   int               ErrorCode(void) const { return m_errorCode; }
   string            ErrorMessage(void) const { return m_errorMessage; }
  };

#endif
