#ifndef BRE_DOMAIN_BROKER_EXECUTION_VOLUME_POLICY_MQH
#define BRE_DOMAIN_BROKER_EXECUTION_VOLUME_POLICY_MQH

class CBrokerExecutionVolumePolicy
  {
public:
   static double     NormalizeVolume(const double volume)
     {
      return NormalizeDouble(volume,8);
     }

   static bool       VolumesEquivalent(const double left,const double right)
     {
      if(left<=0.0 || right<=0.0)
         return false;
      return MathAbs(NormalizeVolume(left)-NormalizeVolume(right))<=0.0000001;
     }

   static string     VolumeMismatchReason(const double observed,const double expected)
     {
      if(observed<=0.0)
         return "observed_volume_zero_or_negative";
      if(expected<=0.0)
         return "expected_volume_zero_or_negative";
      double delta=MathAbs(NormalizeVolume(observed)-NormalizeVolume(expected));
      if(delta>0.0000001)
         return "normalized_volume_delta="+DoubleToString(delta,8);
      return "none";
     }
  };

#endif
