#ifndef BASKET_RECOVERY_DOMAIN_RECOVERY_PROFILE_CONFIG_MQH
#define BASKET_RECOVERY_DOMAIN_RECOVERY_PROFILE_CONFIG_MQH

class CRecoveryProfileConfig
  {
private:
   string m_profileName;
   double m_recoveryStepPips;
   double m_recoveryLotSize;
   int    m_maxRecoverySteps;
   int    m_maxTotalPositions;
   int    m_initialPositionCount;
   double m_initialLotSize;

public:
                     CRecoveryProfileConfig(void)
     {
      m_profileName="default";
      m_recoveryStepPips=0.2;
      m_recoveryLotSize=0.01;
      m_maxRecoverySteps=50;
      m_maxTotalPositions=20;
      m_initialPositionCount=3;
      m_initialLotSize=0.01;
     }

   string            ProfileName(void) const { return m_profileName; }
   double            RecoveryStepPips(void) const { return m_recoveryStepPips; }
   double            RecoveryLotSize(void) const { return m_recoveryLotSize; }
   int               MaxRecoverySteps(void) const { return m_maxRecoverySteps; }
   int               MaxTotalPositions(void) const { return m_maxTotalPositions; }
   int               InitialPositionCount(void) const { return m_initialPositionCount; }
   double            InitialLotSize(void) const { return m_initialLotSize; }

   void              SetProfileName(const string value) { m_profileName=value; }
   void              SetRecoveryStepPips(const double value) { m_recoveryStepPips=value; }
   void              SetRecoveryLotSize(const double value) { m_recoveryLotSize=value; }
   void              SetMaxRecoverySteps(const int value) { m_maxRecoverySteps=value; }
   void              SetMaxTotalPositions(const int value) { m_maxTotalPositions=value; }
   void              SetInitialPositionCount(const int value) { m_initialPositionCount=value; }
   void              SetInitialLotSize(const double value) { m_initialLotSize=value; }
  };

#endif
