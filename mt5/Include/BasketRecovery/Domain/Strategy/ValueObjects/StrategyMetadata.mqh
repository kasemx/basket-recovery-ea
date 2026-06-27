#ifndef BASKET_RECOVERY_DOMAIN_STRATEGY_STRATEGY_METADATA_MQH
#define BASKET_RECOVERY_DOMAIN_STRATEGY_STRATEGY_METADATA_MQH

class CStrategyMetadata
  {
private:
   string m_strategyName;
   string m_description;
   string m_author;

public:
                     CStrategyMetadata(void) {}

                     CStrategyMetadata(const CStrategyMetadata &other)
     {
      m_strategyName=other.m_strategyName;
      m_description=other.m_description;
      m_author=other.m_author;
     }

   string            StrategyName(void) const { return m_strategyName; }
   string            Description(void) const { return m_description; }
   string            Author(void) const { return m_author; }

   static CStrategyMetadata Create(const string strategyName,
                                   const string description="",
                                   const string author="")
     {
      CStrategyMetadata metadata;
      metadata.m_strategyName=strategyName;
      metadata.m_description=description;
      metadata.m_author=author;
      return metadata;
     }
  };

#endif
