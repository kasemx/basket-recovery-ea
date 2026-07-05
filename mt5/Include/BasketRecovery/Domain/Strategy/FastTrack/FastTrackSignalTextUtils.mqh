#ifndef BRE_DOMAIN_FAST_TRACK_SIGNAL_TEXT_UTILS_MQH
#define BRE_DOMAIN_FAST_TRACK_SIGNAL_TEXT_UTILS_MQH

#include <BasketRecovery/Domain/Enums/TradeDirection.mqh>

class CFastTrackSignalTextUtils
  {
public:
   static string     Trim(const string value)
     {
      string text=value;
      StringTrimLeft(text);
      StringTrimRight(text);
      return text;
     }

   static string     NormalizeLineEndings(const string message)
     {
      string text=message;
      StringReplace(text,"\r\n","\n");
      StringReplace(text,"\r","\n");
      return text;
     }

   static int        SplitLines(const string message,string &linesOut[])
     {
      string text=NormalizeLineEndings(message);
      ArrayResize(linesOut,0);
      int lineCount=0;
      int start=0;
      int length=StringLen(text);
      for(int index=0; index<=length; index++)
        {
         bool atEnd=(index==length);
         ushort character=atEnd ? (ushort)'\n' : (ushort)StringGetCharacter(text,index);
         if(character=='\n')
           {
            string line=Trim(StringSubstr(text,start,index-start));
            ArrayResize(linesOut,lineCount+1);
            linesOut[lineCount]=line;
            lineCount++;
            start=index+1;
           }
        }
      return lineCount;
     }

   static int        FindNowMarkerPosition(const string lowerText)
     {
      int spacedPos=StringFind(lowerText," now ");
      if(spacedPos>=0)
         return spacedPos;

      int compactPos=StringFind(lowerText," now");
      if(compactPos<0)
         return -1;

      int afterNow=compactPos+4;
      if(afterNow>=StringLen(lowerText))
         return compactPos;

      ushort nextCharacter=(ushort)StringGetCharacter(lowerText,afterNow);
      if(nextCharacter==' ' || (nextCharacter>='0' && nextCharacter<='9'))
         return compactPos;

      return -1;
     }

   static bool       TryParseRangePair(const string rangeText,double &rangeLowOut,double &rangeHighOut,string &failureDetail)
     {
      string normalized=Trim(rangeText);
      int newlinePos=StringFind(normalized,"\n");
      if(newlinePos>=0)
         normalized=Trim(StringSubstr(normalized,0,newlinePos));

      int dashPos=StringFind(normalized,"-");
      if(dashPos<=0)
        {
         failureDetail="Entry range must contain '-' between low and high";
         return false;
        }

      string lowToken=Trim(StringSubstr(normalized,0,dashPos));
      string highToken=Trim(StringSubstr(normalized,dashPos+1));
      if(!TryParseDoubleToken(lowToken,rangeLowOut) || !TryParseDoubleToken(highToken,rangeHighOut))
        {
         failureDetail="Entry range values are invalid";
         return false;
        }

      if(rangeLowOut<=0.0 || rangeHighOut<=0.0 || rangeLowOut>=rangeHighOut)
        {
         failureDetail="Entry range low must be less than high";
         return false;
        }

      return true;
     }

   static bool       TryParseDoubleToken(const string token,double &valueOut)
     {
      string trimmed=Trim(token);
      if(trimmed=="")
         return false;
      valueOut=StringToDouble(trimmed);
      if(valueOut==0.0 && trimmed!="0" && trimmed!="0.0")
         return false;
      return true;
     }

   static bool       TryResolveSymbolAlias(const string alias,string &symbolOut)
     {
      string normalized=Trim(alias);
      StringToLower(normalized);
      if(normalized=="gold")
        {
         symbolOut="XAUUSD";
         return true;
        }
      return false;
     }

   static bool       TryResolveDirectionToken(const string token,ENUM_BRE_TRADE_DIRECTION &directionOut)
     {
      string normalized=Trim(token);
      StringToLower(normalized);
      if(normalized=="buy")
        {
         directionOut=BRE_DIRECTION_BUY;
         return true;
        }
      if(normalized=="sell")
        {
         directionOut=BRE_DIRECTION_SELL;
         return true;
        }
      return false;
     }
  };

#endif
