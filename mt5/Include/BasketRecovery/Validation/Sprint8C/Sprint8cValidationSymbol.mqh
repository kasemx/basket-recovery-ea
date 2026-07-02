#ifndef BRE_SPRINT8C_VALIDATION_SYMBOL_MQH
#define BRE_SPRINT8C_VALIDATION_SYMBOL_MQH

// Validation-only symbol resolution for Sprint 8C tooling. Do not include from production paths.

string Sprint8cValidationSymbolTradeModeLabel(const long tradeMode)
  {
   if(tradeMode==SYMBOL_TRADE_MODE_DISABLED)
      return "DISABLED";
   if(tradeMode==SYMBOL_TRADE_MODE_LONGONLY)
      return "LONGONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_SHORTONLY)
      return "SHORTONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY)
      return "CLOSEONLY";
   if(tradeMode==SYMBOL_TRADE_MODE_FULL)
      return "FULL";
   return "UNKNOWN";
  }

bool Sprint8cValidationSymbolIsQuotable(const string symbol)
  {
   if(symbol=="")
      return false;
   return SymbolSelect(symbol,true) && SymbolInfoDouble(symbol,SYMBOL_BID)>0.0;
  }

string Sprint8cResolveValidationTradingSymbol(const string preferred,const bool allowChartSymbolFallback=false)
  {
   string candidates[];
   int count=4;
   if(allowChartSymbolFallback)
      count=5;
   ArrayResize(candidates,count);
   candidates[0]=preferred;
   candidates[1]=preferred+"m";
   candidates[2]=preferred+".";
   candidates[3]=preferred+"+";
   if(allowChartSymbolFallback)
      candidates[4]=_Symbol;

   for(int i=0;i<count;i++)
     {
      if(candidates[i]=="")
         continue;
      if(Sprint8cValidationSymbolIsQuotable(candidates[i]))
         return candidates[i];
     }
   return preferred;
  }

double Sprint8cNormalizeValidationVolume(const string symbol,const double volume)
  {
   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0)
      minVolume=0.01;
   if(step<=0.0)
      step=minVolume;
   double normalized=MathMax(volume,minVolume);
   normalized=MathFloor(normalized/step+0.0000001)*step;
   return normalized;
  }

bool Sprint8cAssessPartialCloseVolumePlan(const string symbol,
                                          double &seedVolumeOut,
                                          double &partialCloseVolumeOut)
  {
   seedVolumeOut=0.0;
   partialCloseVolumeOut=0.0;
   if(!Sprint8cValidationSymbolIsQuotable(symbol))
      return false;

   double minVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double volumeStep=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(minVolume<=0.0)
      minVolume=0.01;
   if(volumeStep<=0.0)
      volumeStep=minVolume;

   seedVolumeOut=Sprint8cNormalizeValidationVolume(symbol,minVolume*2.0);
   partialCloseVolumeOut=Sprint8cNormalizeValidationVolume(symbol,seedVolumeOut*0.5);
   return (partialCloseVolumeOut>0.0 && partialCloseVolumeOut<seedVolumeOut);
  }

#endif
