#ifndef BRE_APP_FAST_TRACK_AUDIT_FILE_SOURCE_MQH
#define BRE_APP_FAST_TRACK_AUDIT_FILE_SOURCE_MQH

#define BRE_FAST_TRACK_AUDIT_FILE_MAX_BYTES 8192

class CFastTrackAuditFileSource
  {
private:
   static bool       IsValidBasename(const string fileName)
     {
      string name=fileName;
      StringTrimLeft(name);
      StringTrimRight(name);
      if(name=="")
         return false;
      if(StringFind(name,"\\")>=0)
         return false;
      if(StringFind(name,"/")>=0)
         return false;
      if(StringFind(name,"..")>=0)
         return false;
      if(StringFind(name,":")>=0)
         return false;
      return true;
     }

   static bool       ReadTextFile(const string fileName,
                                    string &outContent,
                                    string &outReason,
                                    const string emptyReason)
     {
      outContent="";
      if(!IsValidBasename(fileName))
        {
         outReason="INVALID_FILE_NAME";
         return false;
        }

      int handle=FileOpen(fileName,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE)
        {
         outReason="FILE_NOT_FOUND";
         return false;
        }

      ulong fileSize=(ulong)FileSize(handle);
      if(fileSize>(ulong)BRE_FAST_TRACK_AUDIT_FILE_MAX_BYTES)
        {
         FileClose(handle);
         outReason="FILE_TOO_LARGE";
         return false;
        }

      string content="";
      while(!FileIsEnding(handle))
        {
         string line=FileReadString(handle);
         if(content!="")
            content+="\n";
         content+=line;
        }
      FileClose(handle);

      if(StringLen(content)>BRE_FAST_TRACK_AUDIT_FILE_MAX_BYTES)
        {
         outReason="FILE_TOO_LARGE";
         return false;
        }

      StringTrimLeft(content);
      StringTrimRight(content);
      if(content=="")
        {
         outReason=emptyReason;
         return false;
        }

      outContent=content;
      return true;
     }

public:
   static bool       TryRead(const bool enabled,
                               const string seed_file_name,
                               const string details_file_name,
                               string &out_seed_text,
                               string &out_details_text,
                               string &out_reason)
     {
      out_seed_text="";
      out_details_text="";
      out_reason="";

      if(!enabled)
        {
         out_reason="DISABLED";
         return false;
        }

      if(!IsValidBasename(seed_file_name) || !IsValidBasename(details_file_name))
        {
         out_reason="INVALID_FILE_NAME";
         return false;
        }

      if(!ReadTextFile(seed_file_name,out_seed_text,out_reason,"EMPTY_SEED"))
         return false;

      if(!ReadTextFile(details_file_name,out_details_text,out_reason,"EMPTY_DETAILS"))
        {
         out_seed_text="";
         return false;
        }

      return true;
     }

   static void       PrintReadAudit(const string seed_file_name,const string details_file_name)
     {
      Print("fast_track_audit_file_source=READ");
      Print("fast_track_audit_seed_file=",seed_file_name);
      Print("fast_track_audit_details_file=",details_file_name);
     }

   static void       PrintSkippedAudit(const string reason)
     {
      Print("fast_track_audit_file_source=SKIPPED");
      Print("fast_track_audit_file_reason=",reason);
     }
  };

#endif
