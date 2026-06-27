#ifndef BRE_SHARED_EXECUTION_CORRELATION_ID_MQH
#define BRE_SHARED_EXECUTION_CORRELATION_ID_MQH

class CExecutionCorrelationId
  {
private:
   string m_value;

public:
                     CExecutionCorrelationId(void) { m_value=""; }
                     CExecutionCorrelationId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
   void              Clear(void) { m_value=""; }

   bool              operator==(const CExecutionCorrelationId &other) const { return m_value==other.m_value; }
   bool              operator!=(const CExecutionCorrelationId &other) const { return m_value!=other.m_value; }
  };

#endif
