#ifndef BASKET_RECOVERY_SHARED_IDENTIFIERS_MQH
#define BASKET_RECOVERY_SHARED_IDENTIFIERS_MQH

class CBasketId
  {
private:
   string m_value;

public:
                     CBasketId(void) { m_value=""; }
                     CBasketId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
   void              Clear(void) { m_value=""; }

   bool              operator==(const CBasketId &other) const { return m_value==other.m_value; }
   bool              operator!=(const CBasketId &other) const { return m_value!=other.m_value; }
  };

class CCommandId
  {
private:
   string m_value;

public:
                     CCommandId(void) { m_value=""; }
                     CCommandId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
  };

class CSignalId
  {
private:
   string m_value;

public:
                     CSignalId(void) { m_value=""; }
                     CSignalId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
  };

class CRequestId
  {
private:
   string m_value;

public:
                     CRequestId(void) { m_value=""; }
                     CRequestId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
  };

class CEventId
  {
private:
   string m_value;

public:
                     CEventId(void) { m_value=""; }
                     CEventId(const string value) { m_value=value; }

   string            Value(void) const { return m_value; }
   bool              IsEmpty(void) const { return m_value==""; }
  };

#endif
