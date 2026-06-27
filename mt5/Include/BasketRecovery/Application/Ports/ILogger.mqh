#ifndef BASKET_RECOVERY_APPLICATION_ILOGGER_MQH
#define BASKET_RECOVERY_APPLICATION_ILOGGER_MQH

class ILogger
  {
public:
   virtual          ~ILogger(void) {}
   virtual void     Trace(const string category,const string eventName,const string basketId,const string details)=0;
   virtual void     Debug(const string category,const string eventName,const string basketId,const string details)=0;
   virtual void     Info(const string category,const string eventName,const string basketId,const string details)=0;
   virtual void     Warn(const string category,const string eventName,const string basketId,const string details,const int errorCode)=0;
   virtual void     Error(const string category,const string eventName,const string basketId,const string details,const int errorCode)=0;
   virtual void     Critical(const string category,const string eventName,const string basketId,const string details,const int errorCode)=0;
   virtual void     Flush(void)=0;
  };

#endif
