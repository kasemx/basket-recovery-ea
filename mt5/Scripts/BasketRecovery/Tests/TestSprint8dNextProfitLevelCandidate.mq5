#property script_show_inputs

#include "../../../Include/BasketRecovery/Tests/TestAssert.mqh"
#include "../../../Include/BasketRecovery/Application/Strategy/ProfitLevelCloseCandidatePlanningService.mqh"

bool TryPlanNextLevelCandidate(const string basketId,
                               const ulong quoteSequence,
                               const string &levelIds[],
                               const bool &enabled[],
                               const bool &reached[],
                               const bool &completed[],
                               string &seenCandidateIds[],
                               int &seenCount,
                               string &plannedLevelOut,
                               string &candidateIdOut)
  {
   plannedLevelOut="";
   candidateIdOut="";
   string selectedLevel="";
   bool hasEligible=CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevel(levelIds,enabled,reached,completed,selectedLevel);
   if(!hasEligible)
      return false;

   string candidateId=CProfitLevelCloseCandidatePlanningService::BuildLevelScopedCandidateId(basketId,selectedLevel,quoteSequence);
   for(int i=0;i<seenCount;i++)
     {
      if(seenCandidateIds[i]==candidateId)
         return false; // explicit duplicate outcome: no new candidate
     }

   ArrayResize(seenCandidateIds,seenCount+1);
   seenCandidateIds[seenCount]=candidateId;
   seenCount++;
   plannedLevelOut=selectedLevel;
   candidateIdOut=candidateId;
   return true;
  }

void TestM1CompletedM2EligibleSelectsM2(void)
  {
   string levelIds[];
   bool enabled[];
   bool reached[];
   bool completed[];
   ArrayResize(levelIds,3);
   ArrayResize(enabled,3);
   ArrayResize(reached,3);
   ArrayResize(completed,3);
   levelIds[0]="M1";
   levelIds[1]="M2";
   levelIds[2]="M3";
   enabled[0]=true;
   enabled[1]=true;
   enabled[2]=true;
   reached[0]=true;
   reached[1]=true;
   reached[2]=false;
   completed[0]=true;
   completed[1]=false;
   completed[2]=false;

   string selected="";
   bool ok=CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevel(levelIds,enabled,reached,completed,selected);
   CTestAssert::True(ok,"must select one eligible level");
   CTestAssert::EqualString("M2",selected,"M1 completed + M2 eligible must select M2");

   string candidateId=CProfitLevelCloseCandidatePlanningService::BuildLevelScopedCandidateId("basket-8d","M2",42);
   CTestAssert::True(StringFind(candidateId,":level:M2:")>=0,"candidate id must contain :level:M2:");
  }

void TestCompletedLevelNeverSelectedAgain(void)
  {
   string levelIds[];
   bool enabled[];
   bool reached[];
   bool completed[];
   ArrayResize(levelIds,3);
   ArrayResize(enabled,3);
   ArrayResize(reached,3);
   ArrayResize(completed,3);
   levelIds[0]="M1";
   levelIds[1]="M2";
   levelIds[2]="M3";
   enabled[0]=true;
   enabled[1]=true;
   enabled[2]=true;
   reached[0]=true;
   reached[1]=true;
   reached[2]=true;
   completed[0]=true;
   completed[1]=false;
   completed[2]=false;

   string selected="";
   bool ok=CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevel(levelIds,enabled,reached,completed,selected);
   CTestAssert::True(ok,"must select next non-completed level");
   CTestAssert::True(selected!="M1","completed level must not be selected again");
  }

void TestSameLevelAndQuoteDoesNotCreateNewCandidate(void)
  {
   string levelIds[];
   bool enabled[];
   bool reached[];
   bool completed[];
   ArrayResize(levelIds,3);
   ArrayResize(enabled,3);
   ArrayResize(reached,3);
   ArrayResize(completed,3);
   levelIds[0]="M1";
   levelIds[1]="M2";
   levelIds[2]="M3";
   enabled[0]=true;
   enabled[1]=true;
   enabled[2]=true;
   reached[0]=true;
   reached[1]=true;
   reached[2]=false;
   completed[0]=true;
   completed[1]=false;
   completed[2]=false;

   string seenIds[];
   int seenCount=0;
   string firstLevel="";
   string firstCandidateId="";
   bool firstPlanned=TryPlanNextLevelCandidate("basket-8d",777,levelIds,enabled,reached,completed,seenIds,seenCount,firstLevel,firstCandidateId);
   CTestAssert::True(firstPlanned,"first planner pass must produce one M2 candidate");
   CTestAssert::EqualString("M2",firstLevel,"first candidate level must be M2");

   string secondLevel="";
   string secondCandidateId="";
   bool secondPlanned=TryPlanNextLevelCandidate("basket-8d",777,levelIds,enabled,reached,completed,seenIds,seenCount,secondLevel,secondCandidateId);
   CTestAssert::False(secondPlanned,"second planner pass with same basket+level+quote must not produce a new candidate");
   CTestAssert::EqualInt(1,seenCount,"duplicate planning must keep candidate count unchanged");
  }

void TestM1CompletedM2NotDueYieldsNoCandidateSelection(void)
  {
   string levelIds[];
   bool enabled[];
   bool reached[];
   bool completed[];
   ArrayResize(levelIds,3);
   ArrayResize(enabled,3);
   ArrayResize(reached,3);
   ArrayResize(completed,3);
   levelIds[0]="M1";
   levelIds[1]="M2";
   levelIds[2]="M3";
   enabled[0]=true;
   enabled[1]=true;
   enabled[2]=true;
   reached[0]=true;
   reached[1]=false; // M2 not due/not reached
   reached[2]=false;
   completed[0]=true;
   completed[1]=false;
   completed[2]=false;

   string selected="";
   bool ok=CProfitLevelCloseCandidatePlanningService::SelectFirstEligibleLevel(levelIds,enabled,reached,completed,selected);
   CTestAssert::False(ok,"M1 completed + M2 not due must yield no eligible level");
   CTestAssert::EqualString("",selected,"no level should be selected");
  }

void OnStart(void)
  {
   CTestAssert::Reset();
   TestM1CompletedM2EligibleSelectsM2();
   TestCompletedLevelNeverSelectedAgain();
   TestSameLevelAndQuoteDoesNotCreateNewCandidate();
   TestM1CompletedM2NotDueYieldsNoCandidateSelection();
   CTestAssert::Summary("TestSprint8dNextProfitLevelCandidate");
  }
