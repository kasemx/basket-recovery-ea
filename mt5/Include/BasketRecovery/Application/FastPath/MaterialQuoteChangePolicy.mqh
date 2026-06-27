#ifndef BRE_APP_MATERIAL_QUOTE_CHANGE_POLICY_MQH
#define BRE_APP_MATERIAL_QUOTE_CHANGE_POLICY_MQH

class CMaterialQuoteChangePolicy
  {
public:
   bool              HasMaterialChange(const double lastBid,
                                       const double lastAsk,
                                       const double bid,
                                       const double ask,
                                       const double point,
                                       const int thresholdPoints) const
     {
      if(lastBid<=0.0 || lastAsk<=0.0)
         return true;

      if(point<=0.0)
         return (MathAbs(bid-lastBid)>0.0 || MathAbs(ask-lastAsk)>0.0);

      double threshold=point*(double)MathMax(thresholdPoints,1);
      return MathAbs(bid-lastBid)>=threshold || MathAbs(ask-lastAsk)>=threshold;
     }
  };

#endif
