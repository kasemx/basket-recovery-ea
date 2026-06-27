#ifndef BRE_INF_BASKET_PERSISTENCE_LOAD_DIAGNOSTIC_MQH
#define BRE_INF_BASKET_PERSISTENCE_LOAD_DIAGNOSTIC_MQH

#include <BasketRecovery/Infrastructure/Persistence/FileBasketRepository.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketSerializer.mqh>
#include <BasketRecovery/Infrastructure/Persistence/BasketMigration.mqh>
#include <BasketRecovery/Infrastructure/Persistence/Json/JsonReader.mqh>
#include <BasketRecovery/Shared/Constants/PersistenceSchema.mqh>
#include <BasketRecovery/Shared/Constants/ErrorCodes.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>

class CBasketPersistenceLoadDiagnostic
  {
public:
   string            requestedBasketId;
   string            resolvedBasketId;
   string            terminalDataPath;
   string            commonDataPath;
   string            persistenceSubdir;
   string            relativeFilePath;
   string            fullResolvedFilePath;
   bool              fileExistsCommon;
   bool              fileExistsTerminalLocal;
   long              fileSizeBytes;
   string            storedCrcHex;
   string            computedCrcHex;
   int               schemaVersion;
   bool              strategySnapshotPresent;
   int               canonicalJsonLen;
   int               profileHashLen;
   string            validationStage;
   string            failureClassification;
   bool              repositoryLoadOk;
   int               repositoryErrorCode;
   string            repositoryErrorMessage;

                     CBasketPersistenceLoadDiagnostic(void)
     {
      requestedBasketId="";
      resolvedBasketId="";
      terminalDataPath="";
      commonDataPath="";
      persistenceSubdir=BRE_PERSISTENCE_BASKET_SUBDIR;
      relativeFilePath="";
      fullResolvedFilePath="";
      fileExistsCommon=false;
      fileExistsTerminalLocal=false;
      fileSizeBytes=0;
      storedCrcHex="";
      computedCrcHex="";
      schemaVersion=0;
      strategySnapshotPresent=false;
      canonicalJsonLen=0;
      profileHashLen=0;
      validationStage="not_started";
      failureClassification="none";
      repositoryLoadOk=false;
      repositoryErrorCode=0;
      repositoryErrorMessage="";
     }

   static string     NormalizePathSeparators(const string value)
     {
      string normalized=value;
      StringReplace(normalized,"/","\\");
      return normalized;
     }

   static string     BuildFullCommonFilePath(const string relativePath)
     {
      string commonRoot=TerminalInfoString(TERMINAL_COMMONDATA_PATH);
      string suffix=NormalizePathSeparators(relativePath);
      if(StringLen(commonRoot)>0 && StringGetCharacter(commonRoot,StringLen(commonRoot)-1)!='\\')
         commonRoot+="\\";
      return commonRoot+"Files\\"+suffix;
     }

   static long       ReadFileSizeBytes(const string relativePath,const bool useCommon)
     {
      int flags=FILE_READ|FILE_BIN;
      if(useCommon)
         flags|=FILE_COMMON;
      int handle=FileOpen(relativePath,flags);
      if(handle==INVALID_HANDLE)
         return -1;
      long size=(long)FileSize(handle);
      FileClose(handle);
      return size;
     }

   static string     ReadFileContentRaw(const string relativePath,const bool useCommon)
     {
      int flags=FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ;
      if(useCommon)
         flags|=FILE_COMMON;
      int handle=FileOpen(relativePath,flags);
      if(handle==INVALID_HANDLE)
         return "";
      string content="";
      while(!FileIsEnding(handle))
         content+=FileReadString(handle);
      FileClose(handle);
      return content;
     }

   static string     ClassifyFailure(const CBasketPersistenceLoadDiagnostic &report)
     {
      if(!report.fileExistsCommon && !report.fileExistsTerminalLocal)
         return "missing_file";
      if(!report.fileExistsCommon && report.fileExistsTerminalLocal)
         return "wrong_file_path";
      if(report.validationStage=="file_read_failed")
         return "missing_file";
      if(report.validationStage=="migration_failed")
         return "serializer_mismatch";
      if(report.validationStage=="schema_version_invalid" || report.validationStage=="schema_version_unsupported")
         return "serializer_mismatch";
      if(report.validationStage=="from_reader_failed")
         return "json_reader_parsing_mismatch";
      if(report.validationStage=="crc_mismatch")
        {
         if(report.strategySnapshotPresent && report.canonicalJsonLen==0 && report.profileHashLen==0)
            return "stale_file";
         return "json_reader_parsing_mismatch";
        }
      if(report.validationStage=="restore_failed")
         return "post_deserialization_canonicalization_mismatch";
      if(report.repositoryLoadOk)
         return "none";
      return "unknown";
     }

   static string     FormatLogLine(const CBasketPersistenceLoadDiagnostic &report)
     {
      return StringFormat("BRE basket-load diagnostic | requested_id=%s | resolved_id=%s | terminal_data_path=%s | persistence_subdir=%s | file=%s | file_exists=%s | file_size=%d | stored_crc=%s | computed_crc=%s | schema=%d | snapshot=%s | canonical_json_len=%d | hash_len=%d | validation_stage=%s | classification=%s | repository_load=%s | repository_error_code=%d",
                          report.requestedBasketId,
                          report.resolvedBasketId,
                          report.terminalDataPath,
                          report.persistenceSubdir,
                          report.fullResolvedFilePath,
                          report.fileExistsCommon?"true":"false",
                          (int)report.fileSizeBytes,
                          report.storedCrcHex,
                          report.computedCrcHex,
                          report.schemaVersion,
                          report.strategySnapshotPresent?"true":"false",
                          report.canonicalJsonLen,
                          report.profileHashLen,
                          report.validationStage,
                          report.failureClassification,
                          report.repositoryLoadOk?"ok":"failed",
                          report.repositoryErrorCode);
     }

   static CBasketPersistenceLoadDiagnostic Inspect(const string basketSubdir,
                                                   const CBasketId &requestedId,
                                                   const CFileBasketRepository &repository)
     {
      CBasketPersistenceLoadDiagnostic report;
      report.requestedBasketId=requestedId.Value();
      report.resolvedBasketId=requestedId.Value();
      report.persistenceSubdir=basketSubdir;
      report.terminalDataPath=TerminalInfoString(TERMINAL_DATA_PATH);
      report.commonDataPath=TerminalInfoString(TERMINAL_COMMONDATA_PATH);
      report.relativeFilePath=basketSubdir+"/"+requestedId.Value()+".json";
      report.fullResolvedFilePath=BuildFullCommonFilePath(report.relativeFilePath);

      report.fileExistsCommon=FileIsExist(report.relativeFilePath,FILE_COMMON);
      report.fileExistsTerminalLocal=FileIsExist(report.relativeFilePath,0);
      if(report.fileExistsCommon)
         report.fileSizeBytes=ReadFileSizeBytes(report.relativeFilePath,true);
      else if(report.fileExistsTerminalLocal)
         report.fileSizeBytes=ReadFileSizeBytes(report.relativeFilePath,false);

      if(!report.fileExistsCommon && !report.fileExistsTerminalLocal)
        {
         report.validationStage="file_missing";
         CResult<CBasketAggregate> loaded=repository.Load(requestedId);
         report.repositoryLoadOk=loaded.IsOk();
         report.repositoryErrorCode=loaded.ErrorCode();
         report.repositoryErrorMessage=loaded.ErrorMessage();
         report.failureClassification=ClassifyFailure(report);
         return report;
        }

      if(!report.fileExistsCommon && report.fileExistsTerminalLocal)
        {
         report.validationStage="wrong_file_path";
         CResult<CBasketAggregate> loaded=repository.Load(requestedId);
         report.repositoryLoadOk=loaded.IsOk();
         report.repositoryErrorCode=loaded.ErrorCode();
         report.repositoryErrorMessage=loaded.ErrorMessage();
         report.failureClassification=ClassifyFailure(report);
         return report;
        }

      string content=ReadFileContentRaw(report.relativeFilePath,true);
      if(content=="")
        {
         report.validationStage="file_read_failed";
         CResult<CBasketAggregate> loaded=repository.Load(requestedId);
         report.repositoryLoadOk=loaded.IsOk();
         report.repositoryErrorCode=loaded.ErrorCode();
         report.repositoryErrorMessage=loaded.ErrorMessage();
         report.failureClassification=ClassifyFailure(report);
         return report;
        }

      CJsonReader reader;
      reader.SetContent(content);
      report.storedCrcHex=reader.ReadString("crc32","");
      report.schemaVersion=reader.ReadSchemaVersion();
      report.strategySnapshotPresent=reader.ReadBool("has_strategy_snapshot",false);
      string canonicalJson=reader.ReadString("strategy_canonical_json","");
      string profileHash=reader.ReadString("strategy_profile_hash","");
      report.canonicalJsonLen=StringLen(canonicalJson);
      report.profileHashLen=StringLen(profileHash);

      CResult<string> migrated=CBasketMigration::MigrateToCurrent(content);
      if(migrated.IsFail())
        {
         report.validationStage="migration_failed";
         report.repositoryErrorCode=migrated.ErrorCode();
         report.repositoryErrorMessage=migrated.ErrorMessage();
         report.failureClassification=ClassifyFailure(report);
         CResult<CBasketAggregate> loaded=repository.Load(requestedId);
         report.repositoryLoadOk=loaded.IsOk();
         if(!report.repositoryLoadOk)
           {
            report.repositoryErrorCode=loaded.ErrorCode();
            report.repositoryErrorMessage=loaded.ErrorMessage();
           }
         return report;
        }

      string migratedContent;
      migrated.TryGetValue(migratedContent);

      CBasketSerializer serializer;
      CJsonReader migratedReader;
      migratedReader.SetContent(migratedContent);
      int schemaVersion=migratedReader.ReadSchemaVersion();
      if(schemaVersion<=0)
         report.validationStage="schema_version_invalid";
      else if(schemaVersion>BRE_PERSISTENCE_SCHEMA_VERSION)
         report.validationStage="schema_version_unsupported";
      else
        {
         CBasketPersistenceDto dto;
         if(!serializer.FromReader(migratedReader,dto,schemaVersion))
            report.validationStage="from_reader_failed";
         else
           {
            string payload=serializer.BuildCrcPayload(dto);
            report.computedCrcHex=CCrc32::ToHex(CCrc32::Compute(payload));
            CVoidResult crcResult=migratedReader.ValidateCrc(payload);
            if(crcResult.IsFail())
              {
               if(crcResult.ErrorCode()==BRE_ERR_PERSIST_CRC_MISMATCH)
                  report.validationStage="crc_mismatch";
               else
                  report.validationStage="crc_validation_error";
              }
            else
              {
               CBasketAggregate aggregate;
               if(!aggregate.RestoreFromDto(dto))
                  report.validationStage="restore_failed";
               else
                  report.validationStage="ok";
              }
           }
        }

      CResult<CBasketAggregate> loaded=repository.Load(requestedId);
      report.repositoryLoadOk=loaded.IsOk();
      report.repositoryErrorCode=loaded.ErrorCode();
      report.repositoryErrorMessage=loaded.ErrorMessage();
      if(!report.repositoryLoadOk && report.validationStage=="ok")
         report.validationStage="repository_load_failed";

      report.failureClassification=ClassifyFailure(report);
      return report;
     }
  };

#endif
