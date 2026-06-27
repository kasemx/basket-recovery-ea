#ifndef BRE_APP_QUOTE_SEQUENCE_GUARD_MQH
#define BRE_APP_QUOTE_SEQUENCE_GUARD_MQH

class CQuoteSequenceGuard
  {
public:
   static ulong      BuildSequence(const long tickTimeMsc,const long tickVolume)
     {
      return ((ulong)tickTimeMsc<<16)^((ulong)tickVolume & 0xFFFF);
     }

   bool              IsDuplicateSequence(const ulong lastSequence,const ulong currentSequence) const
     {
      if(lastSequence==0 || currentSequence==0)
         return false;
      return lastSequence==currentSequence;
     }
  };

#endif
