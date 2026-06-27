#ifndef BASKET_RECOVERY_TESTS_PERSISTENCE_TEST_PATHS_MQH
#define BASKET_RECOVERY_TESTS_PERSISTENCE_TEST_PATHS_MQH

#define BRE_TEST_PERSISTENCE_BASKET_SUBDIR       "BasketRecovery/persistence/test/baskets"
#define BRE_TEST_PERSISTENCE_COMMANDS_FILE       "BasketRecovery/persistence/test/commands/pending.json"
#define BRE_TEST_PERSISTENCE_IDEMPOTENCY_FILE    "BasketRecovery/persistence/test/idempotency/processed.json"

class CPersistenceTestPaths
  {
public:
   static void       Cleanup(void)
     {
      string searchPath=BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/*.json";
      string fileName;
      long handle=FileFindFirst(searchPath,fileName,FILE_COMMON);
      if(handle!=INVALID_HANDLE)
        {
         do
           {
            string baseName=StringSubstr(fileName,0,StringFind(fileName,".json"));
            FileDelete(BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/"+fileName,FILE_COMMON);
            FileDelete(BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/"+baseName+".json.bak",FILE_COMMON);
            FileDelete(BRE_TEST_PERSISTENCE_BASKET_SUBDIR+"/"+baseName+".json.tmp",FILE_COMMON);
           }
         while(FileFindNext(handle,fileName));
         FileFindClose(handle);
        }

      FileDelete(BRE_TEST_PERSISTENCE_COMMANDS_FILE,FILE_COMMON);
      FileDelete(BRE_TEST_PERSISTENCE_COMMANDS_FILE+".bak",FILE_COMMON);
      FileDelete(BRE_TEST_PERSISTENCE_COMMANDS_FILE+".tmp",FILE_COMMON);
      FileDelete(BRE_TEST_PERSISTENCE_IDEMPOTENCY_FILE,FILE_COMMON);
      FileDelete(BRE_TEST_PERSISTENCE_IDEMPOTENCY_FILE+".bak",FILE_COMMON);
      FileDelete(BRE_TEST_PERSISTENCE_IDEMPOTENCY_FILE+".tmp",FILE_COMMON);
     }
  };

#endif
