#ifndef BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_BLOCK_READER_MQH
#define BASKET_RECOVERY_INFRASTRUCTURE_STRATEGY_PROFILE_JSON_BLOCK_READER_MQH

class CStrategyProfileJsonBlockReader
  {
public:
   static int        FindMatchingBrace(const string content,const int openIndex)
     {
      int depth=0;
      for(int i=openIndex;i<StringLen(content);i++)
        {
         ushort ch=StringGetCharacter(content,i);
         if(ch=='{')
            depth++;
         else if(ch=='}')
           {
            depth--;
            if(depth==0)
               return i;
           }
        }
      return -1;
     }

   static string     ExtractObjectAfterKey(const string content,const string key)
     {
      string pattern="\""+key+"\"";
      int keyIndex=StringFind(content,pattern);
      if(keyIndex<0)
         return "";
      int braceStart=StringFind(content,"{",keyIndex);
      if(braceStart<0)
         return "";
      int braceEnd=FindMatchingBrace(content,braceStart);
      if(braceEnd<0)
         return "";
      return StringSubstr(content,braceStart,braceEnd-braceStart+1);
     }

   static int        ExtractObjectArrayBlocks(const string content,const string key,string &blocks[])
     {
      string pattern="\""+key+"\"";
      int keyIndex=StringFind(content,pattern);
      if(keyIndex<0)
        {
         ArrayResize(blocks,0);
         return 0;
        }
      int arrayStart=StringFind(content,"[",keyIndex);
      int arrayEnd=StringFind(content,"]",arrayStart);
      if(arrayStart<0 || arrayEnd<0)
        {
         ArrayResize(blocks,0);
         return 0;
        }

      ArrayResize(blocks,0);
      int cursor=arrayStart+1;
      while(cursor<arrayEnd)
        {
         int objectStart=StringFind(content,"{",cursor);
         if(objectStart<0 || objectStart>=arrayEnd)
            break;
         int objectEnd=FindMatchingBrace(content,objectStart);
         if(objectEnd<0 || objectEnd>arrayEnd)
            break;
         int nextIndex=ArraySize(blocks);
         ArrayResize(blocks,nextIndex+1);
         blocks[nextIndex]=StringSubstr(content,objectStart,objectEnd-objectStart+1);
         cursor=objectEnd+1;
        }
      return ArraySize(blocks);
     }
  };

#endif
