#ifndef BASKET_RECOVERY_INFRASTRUCTURE_FILE_LOGGER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_FILE_LOGGER_MQH

#include <BasketRecovery/Application/Ports/ILogger.mqh>
#include <BasketRecovery/Application/Ports/IAsyncLogWriter.mqh>

// Sprint 0.1: synchronous implementation. IAsyncLogWriter + ILogBuffer are defined for
// future async buffering; CFileLogger remains the active ILogger adapter until Sprint 15.

class CFileLogger : public ILogger
  {
private:
   string m_filePath;
   int    m_minLevel;
   bool   m_initialized;

   string LevelToString(const int level) const
     {
      switch(level)
        {
         case 0: return "TRACE";
         case 1: return "DEBUG";
         case 2: return "INFO";
         case 3: return "WARN";
         case 4: return "ERROR";
         case 5: return "CRITICAL";
         default: return "INFO";
        }
     }

   void WriteLine(const int level,const string category,const string eventName,
                  const string basketId,const string details,const int errorCode)
     {
      if(level<m_minLevel)
         return;

      string line=StringFormat("{\"ts\":\"%s\",\"level\":\"%s\",\"category\":\"%s\",\"event\":\"%s\",\"basket_id\":\"%s\",\"error_code\":%d,\"details\":\"%s\"}",
                               TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                               LevelToString(level),
                               category,
                               eventName,
                               basketId,
                               errorCode,
                               details);

      int handle=FileOpen(m_filePath,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE)
         handle=FileOpen(m_filePath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ);

      if(handle!=INVALID_HANDLE)
        {
         FileSeek(handle,0,SEEK_END);
         FileWriteString(handle,line+"\n");
         FileClose(handle);
        }
     }

public:
                     CFileLogger(void)
     {
      m_filePath="BasketRecovery/logs/basket_recovery.log";
      m_minLevel=2;
      m_initialized=false;
     }

   virtual          ~CFileLogger(void) {}

   bool              Initialize(const string filePath,const int minLevel)
     {
      m_filePath=filePath;
      m_minLevel=minLevel;
      m_initialized=true;
      return true;
     }

   bool              IsInitialized(void) const { return m_initialized; }

   virtual void     Trace(const string category,const string eventName,const string basketId,const string details)
     {
      WriteLine(0,category,eventName,basketId,details,0);
     }

   virtual void     Debug(const string category,const string eventName,const string basketId,const string details)
     {
      WriteLine(1,category,eventName,basketId,details,0);
     }

   virtual void     Info(const string category,const string eventName,const string basketId,const string details)
     {
      WriteLine(2,category,eventName,basketId,details,0);
     }

   virtual void     Warn(const string category,const string eventName,const string basketId,const string details,const int errorCode)
     {
      WriteLine(3,category,eventName,basketId,details,errorCode);
     }

   virtual void     Error(const string category,const string eventName,const string basketId,const string details,const int errorCode)
     {
      WriteLine(4,category,eventName,basketId,details,errorCode);
     }

   virtual void     Critical(const string category,const string eventName,const string basketId,const string details,const int errorCode)
     {
      WriteLine(5,category,eventName,basketId,details,errorCode);
     }

   virtual void     Flush(void)
     {
     }
  };

#endif
