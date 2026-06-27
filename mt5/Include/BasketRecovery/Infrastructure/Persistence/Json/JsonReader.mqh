#ifndef BASKET_RECOVERY_INFRASTRUCTURE_JSON_READER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_JSON_READER_MQH

#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>

class CJsonReader
  {
private:
   string m_content;
   bool   m_recoveryMode;

   int FindKeyValueStart(const string key) const
     {
      string pattern="\""+key+"\"";
      int keyIndex=StringFind(m_content,pattern);
      if(keyIndex<0)
         return -1;
      int colonIndex=StringFind(m_content,":",keyIndex);
      if(colonIndex<0)
         return -1;
      return colonIndex+1;
     }

   string Trim(const string value) const
     {
      string trimmed=value;
      StringTrimLeft(trimmed);
      StringTrimRight(trimmed);
      if(StringLen(trimmed)>0 && StringGetCharacter(trimmed,0)=='"')
        {
         trimmed=StringSubstr(trimmed,1,StringLen(trimmed)-2);
        }
      return trimmed;
     }

public:
                     CJsonReader(void)
     {
      m_content="";
      m_recoveryMode=false;
     }

   void              SetRecoveryMode(const bool value) { m_recoveryMode=value; }

   CVoidResult       LoadFromFile(const string relativePath)
     {
      int handle=FileOpen(relativePath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE)
        {
         if(m_recoveryMode)
           {
            string backupPath=relativePath+".bak";
            handle=FileOpen(backupPath,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
            if(handle==INVALID_HANDLE)
               return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"JSON file and backup are missing");
           }
         else
            return CVoidResult::Fail(BRE_ERR_PERSIST_READ_FAILED,"JSON file is missing");
        }

      m_content="";
      while(!FileIsEnding(handle))
         m_content+=FileReadString(handle);
      FileClose(handle);
      return CVoidResult::Ok();
     }

   void              SetContent(const string content) { m_content=content; }
   string            Content(void) const { return m_content; }

   bool              HasKey(const string key) const { return FindKeyValueStart(key)>=0; }

   int               ReadInt(const string key,const int defaultValue=0) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
         return defaultValue;
      int end=StringFind(m_content,",",start);
      if(end<0)
         end=StringFind(m_content,"}",start);
      if(end<0)
         end=StringLen(m_content);
      string token=Trim(StringSubstr(m_content,start,end-start));
      return (int)StringToInteger(token);
     }

   long              ReadLong(const string key,const long defaultValue=0) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
         return defaultValue;
      int end=StringFind(m_content,",",start);
      if(end<0)
         end=StringFind(m_content,"}",start);
      if(end<0)
         end=StringLen(m_content);
      string token=Trim(StringSubstr(m_content,start,end-start));
      return (long)StringToInteger(token);
     }

   double            ReadDouble(const string key,const double defaultValue=0.0) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
         return defaultValue;
      int end=StringFind(m_content,",",start);
      if(end<0)
         end=StringFind(m_content,"}",start);
      if(end<0)
         end=StringLen(m_content);
      string token=Trim(StringSubstr(m_content,start,end-start));
      return StringToDouble(token);
     }

   bool              ReadBool(const string key,const bool defaultValue=false) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
         return defaultValue;
      int end=StringFind(m_content,",",start);
      if(end<0)
         end=StringFind(m_content,"}",start);
      if(end<0)
         end=StringLen(m_content);
      string token=Trim(StringSubstr(m_content,start,end-start));
      return token=="true";
     }

   string            ReadString(const string key,const string defaultValue="") const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
         return defaultValue;
      int quoteStart=StringFind(m_content,"\"",start);
      if(quoteStart<0)
         return defaultValue;
      int quoteEnd=StringFind(m_content,"\"",quoteStart+1);
      if(quoteEnd<0)
         return defaultValue;
      return StringSubstr(m_content,quoteStart+1,quoteEnd-quoteStart-1);
     }

   int               ReadSchemaVersion(void) const
     {
      return ReadInt("schema_version",0);
     }

   CVoidResult       ValidateSchemaVersion(const int supportedVersion) const
     {
      int version=ReadSchemaVersion();
      if(version<=0)
         return CVoidResult::Fail(BRE_ERR_PERSIST_CORRUPT,"Schema version is missing");
      if(version>supportedVersion)
         return CVoidResult::Fail(BRE_ERR_PERSIST_SCHEMA_UNSUPPORTED,"Schema version is newer than supported");
      return CVoidResult::Ok();
     }

   CVoidResult       ValidateCrc(const string payloadForCrc) const
     {
      string expectedHex=ReadString("crc32","");
      if(expectedHex=="")
         return CVoidResult::Fail(BRE_ERR_PERSIST_CORRUPT,"CRC field is missing");

      uint expectedCrc=0;
      if(!CCrc32::FromHex(expectedHex,expectedCrc))
         return CVoidResult::Fail(BRE_ERR_PERSIST_CORRUPT,"CRC field is invalid");

      uint actualCrc=CCrc32::Compute(payloadForCrc);
      if(actualCrc!=expectedCrc)
         return CVoidResult::Fail(BRE_ERR_PERSIST_CRC_MISMATCH,"CRC mismatch detected");

      return CVoidResult::Ok();
     }

   int               ReadStringArray(const string key,string &values[]) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      int arrayStart=StringFind(m_content,"[",start);
      int arrayEnd=StringFind(m_content,"]",arrayStart);
      if(arrayStart<0 || arrayEnd<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      string body=StringSubstr(m_content,arrayStart+1,arrayEnd-arrayStart-1);
      if(StringLen(body)==0)
        {
         ArrayResize(values,0);
         return 0;
        }

      string parts[];
      int count=StringSplit(body,',',parts);
      ArrayResize(values,count);
      for(int i=0;i<count;i++)
        {
         string item=parts[i];
         StringReplace(item,"\"","");
         StringTrimLeft(item);
         StringTrimRight(item);
         values[i]=item;
        }
      return count;
     }

   int               ReadLongArray(const string key,long &values[]) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      int arrayStart=StringFind(m_content,"[",start);
      int arrayEnd=StringFind(m_content,"]",arrayStart);
      if(arrayStart<0 || arrayEnd<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      string body=StringSubstr(m_content,arrayStart+1,arrayEnd-arrayStart-1);
      string parts[];
      int count=StringSplit(body,',',parts);
      ArrayResize(values,count);
      for(int i=0;i<count;i++)
        {
         StringTrimLeft(parts[i]);
         StringTrimRight(parts[i]);
         values[i]=(long)StringToInteger(parts[i]);
        }
      return count;
     }

   int               ReadDoubleArray(const string key,double &values[]) const
     {
      int start=FindKeyValueStart(key);
      if(start<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      int arrayStart=StringFind(m_content,"[",start);
      int arrayEnd=StringFind(m_content,"]",arrayStart);
      if(arrayStart<0 || arrayEnd<0)
        {
         ArrayResize(values,0);
         return 0;
        }

      string body=StringSubstr(m_content,arrayStart+1,arrayEnd-arrayStart-1);
      string parts[];
      int count=StringSplit(body,',',parts);
      ArrayResize(values,count);
      for(int i=0;i<count;i++)
        {
         StringTrimLeft(parts[i]);
         StringTrimRight(parts[i]);
         values[i]=StringToDouble(parts[i]);
        }
      return count;
     }
  };

#endif
