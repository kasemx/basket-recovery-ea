#ifndef BASKET_RECOVERY_APPLICATION_IASYNC_LOG_WRITER_MQH
#define BASKET_RECOVERY_APPLICATION_IASYNC_LOG_WRITER_MQH

#include <BasketRecovery/Application/Ports/ILogBuffer.mqh>

class IAsyncLogWriter
  {
public:
   virtual          ~IAsyncLogWriter(void) {}
   virtual bool      Initialize(const string filePath)=0;
   virtual bool      Submit(const string line)=0;
   virtual void      FlushPending(void)=0;
   virtual ILogBuffer* Buffer(void)=0;
  };

#endif
