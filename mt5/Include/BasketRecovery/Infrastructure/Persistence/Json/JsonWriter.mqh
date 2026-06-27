#ifndef BASKET_RECOVERY_INFRASTRUCTURE_JSON_WRITER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_JSON_WRITER_MQH

#include <BasketRecovery/Shared/Utils/Crc32.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

enum ENUM_BRE_JSON_WRITE_MODE
  {
   BRE_JSON_WRITE_COMPACT=0,
   BRE_JSON_WRITE_PRETTY
  };

class CJsonWriter
  {
private:
   ENUM_BRE_JSON_WRITE_MODE m_mode;
   string                   m_indent;

   string            Escape(const string value) const
     {
      string escaped=value;
      StringReplace(escaped,"\\","\\\\");
      StringReplace(escaped,"\"","\\\"");
      StringReplace(escaped,"\n","\\n");
      StringReplace(escaped,"\r","\\r");
      return escaped;
     }

   string            NewLine(void) const
     {
      return m_mode==BRE_JSON_WRITE_PRETTY ? "\n" : "";
     }

   string            Indent(const int level) const
     {
      if(m_mode!=BRE_JSON_WRITE_PRETTY)
         return "";
      string spaces="";
      for(int i=0;i<level;i++)
         spaces+=m_indent;
      return spaces;
     }

   CVoidResult       WriteStringToHandle(const int handle,const string content) const
     {
      if(FileWriteString(handle,content)<=0)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to write JSON content");
      FileFlush(handle);
      return CVoidResult::Ok();
     }

   CVoidResult       CopyFileCommon(const string sourceRelativePath,const string targetRelativePath) const
     {
      int sourceHandle=FileOpen(sourceRelativePath,FILE_READ|FILE_BIN|FILE_COMMON);
      if(sourceHandle==INVALID_HANDLE)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to open source temp file");

      uchar buffer[];
      ulong fileSize=(ulong)FileSize(sourceHandle);
      if(fileSize==0)
        {
         FileClose(sourceHandle);
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Temp file is empty");
        }
      if(fileSize>(ulong)2147483647)
        {
         FileClose(sourceHandle);
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Temp file exceeds supported size");
        }

      int readSize=(int)fileSize;
      uint bytesRead=FileReadArray(sourceHandle,buffer,0,readSize);
      FileClose(sourceHandle);
      if(bytesRead<=0)
        return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Temp file is empty");

      int targetHandle=FileOpen(targetRelativePath,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(targetHandle==INVALID_HANDLE)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to open target file");

      FileWriteArray(targetHandle,buffer,0,(int)bytesRead);
      FileFlush(targetHandle);
      FileClose(targetHandle);
      return CVoidResult::Ok();
     }

public:
                     CJsonWriter(void)
     {
      m_mode=BRE_JSON_WRITE_COMPACT;
      m_indent="  ";
     }

   void              SetMode(const ENUM_BRE_JSON_WRITE_MODE mode) { m_mode=mode; }

   string            BuildEnvelope(const int schemaVersion,const string bodyFields) const
     {
      string payloadForCrc="\"schema_version\":"+IntegerToString(schemaVersion)+","+bodyFields;
      string crcHex=CCrc32::ToHex(CCrc32::Compute(payloadForCrc));

      string json="{";
      json+=NewLine();
      json+=Indent(1)+"\"schema_version\":"+IntegerToString(schemaVersion)+",";
      json+=NewLine();
      json+=Indent(1)+"\"crc32\":\""+crcHex+"\",";
      json+=NewLine();
      json+=Indent(1)+bodyFields;
      json+=NewLine()+"}";
      return json;
     }

   string            FieldString(const string key,const string value) const
     {
      return "\""+key+"\":\""+Escape(value)+"\"";
     }

   string            FieldInt(const string key,const long value) const
     {
      return "\""+key+"\":"+IntegerToString(value);
     }

   string            FieldDouble(const string key,const double value) const
     {
      return "\""+key+"\":"+DoubleToString(value,8);
     }

   string            FieldBool(const string key,const bool value) const
     {
      return "\""+key+"\":"+(value ? "true" : "false");
     }

   string            StringArrayField(const string key,const string &values[],const int count) const
     {
      string json="\""+key+"\":[";
      for(int i=0;i<count;i++)
        {
         if(i>0)
            json+=",";
         json+="\""+Escape(values[i])+"\"";
        }
      json+="]";
      return json;
     }

   string            LongArrayField(const string key,const long &values[],const int count) const
     {
      string json="\""+key+"\":[";
      for(int i=0;i<count;i++)
        {
         if(i>0)
            json+=",";
         json+=IntegerToString(values[i]);
        }
      json+="]";
      return json;
     }

   string            DoubleArrayField(const string key,const double &values[],const int count) const
     {
      string json="\""+key+"\":[";
      for(int i=0;i<count;i++)
        {
         if(i>0)
            json+=",";
         json+=DoubleToString(values[i],8);
        }
      json+="]";
      return json;
     }

   CVoidResult       EnsureDirectoryChain(const string relativePath) const
     {
      int lastSlash=-1;
      for(int i=StringLen(relativePath)-1;i>=0;i--)
        {
         if(StringGetCharacter(relativePath,i)=='/' || StringGetCharacter(relativePath,i)=='\\')
           {
            lastSlash=i;
            break;
           }
        }
      if(lastSlash<=0)
         return CVoidResult::Ok();

      string directory=StringSubstr(relativePath,0,lastSlash);
      string parts[];
      int count=StringSplit(directory,'/',parts);
      string current="";
      for(int i=0;i<count;i++)
        {
         if(parts[i]=="")
            continue;
         if(current=="")
            current=parts[i];
         else
            current=current+"/"+parts[i];
         if(!FolderCreate(current,FILE_COMMON))
           {
            int error=GetLastError();
            if(error!=5019 && error!=5020)
               return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to create persistence directory");
           }
        }
      return CVoidResult::Ok();
     }

   CVoidResult       WriteAtomic(const string relativePath,const string content)
     {
      CVoidResult directoryResult=EnsureDirectoryChain(relativePath);
      if(directoryResult.IsFail())
         return directoryResult;

      string tempPath=relativePath+".tmp";
      string backupPath=relativePath+".bak";

      int handle=FileOpen(tempPath,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(handle==INVALID_HANDLE)
         return CVoidResult::Fail(BRE_ERR_PERSIST_WRITE_FAILED,"Failed to open temp JSON file");

      CVoidResult writeResult=WriteStringToHandle(handle,content);
      FileClose(handle);
      if(writeResult.IsFail())
         return writeResult;

      if(FileIsExist(relativePath,FILE_COMMON))
        {
         FileDelete(backupPath,FILE_COMMON);
         FileCopy(relativePath,FILE_COMMON,backupPath,FILE_COMMON);
        }

      FileDelete(relativePath,FILE_COMMON);
      CVoidResult copyResult=CopyFileCommon(tempPath,relativePath);
      FileDelete(tempPath,FILE_COMMON);
      return copyResult;
     }
  };

#endif
