#ifndef BASKET_RECOVERY_APPLICATION_ILOG_BUFFER_MQH
#define BASKET_RECOVERY_APPLICATION_ILOG_BUFFER_MQH

class ILogBuffer
  {
public:
   virtual          ~ILogBuffer(void) {}
   virtual bool      Enqueue(const string &line)=0;
   virtual int       Count(void) const=0;
   virtual bool      TryDequeue(string &line)=0;
   virtual void      Clear(void)=0;
  };

#endif
