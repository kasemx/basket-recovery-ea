#ifndef BRE_DOMAIN_PROFIT_CLOSE_AUTHORIZATION_BINDING_MQH
#define BRE_DOMAIN_PROFIT_CLOSE_AUTHORIZATION_BINDING_MQH

#include <BasketRecovery/Shared/Types/Identifiers.mqh>
#include <BasketRecovery/Shared/Utils/Crc32.mqh>
#include <BasketRecovery/Domain/Execution/ValueObjects/ManualProfitCloseCandidateEntry.mqh>

#define BRE_PROFIT_CLOSE_AUTH_BINDING_VERSION "S8C_AUTH_BINDING_V2"
#define BRE_PROFIT_CLOSE_AUTH_BINDING_BUILD_MARKER "S8C_AUTH_BINDING_V2"

class CProfitCloseAuthorizationBinding
  {
public:
   static string     BuildMarker(void) { return BRE_PROFIT_CLOSE_AUTH_BINDING_BUILD_MARKER; }
   static string     BindingVersion(void) { return BRE_PROFIT_CLOSE_AUTH_BINDING_VERSION; }
   static string     SerializerClassName(void) { return "CProfitCloseAuthorizationBinding"; }

   static bool       IsProfitCloseExecutionRequestId(const string executionRequestId)
     {
      return StringFind(executionRequestId,"profit-close-manual:")==0;
     }

   static double     NormalizeCloseVolume(const double closeVolume)
     {
      return StringToDouble(DoubleToString(closeVolume,8));
     }

   static string     FormatCloseVolume(const double closeVolume)
     {
      return DoubleToString(NormalizeCloseVolume(closeVolume),8);
     }

   static string     BuildCanonicalPayload(const string basketId,
                                           const string candidateId,
                                           const string executionRequestId,
                                           const ulong ticket,
                                           const double closeVolume)
     {
      return StringFormat("%s|%s|%s|%s|%I64u|%s",
                          BRE_PROFIT_CLOSE_AUTH_BINDING_VERSION,
                          basketId,
                          candidateId,
                          executionRequestId,
                          (long)ticket,
                          FormatCloseVolume(closeVolume));
     }

   static string     BuildLegacyV1CanonicalPayload(const string basketId,
                                                   const string candidateId,
                                                   const string executionRequestId,
                                                   const ulong ticket,
                                                   const double closeVolume)
     {
      return StringFormat("%s|%s|%s|%I64u|%s",
                          basketId,
                          candidateId,
                          executionRequestId,
                          (long)ticket,
                          FormatCloseVolume(closeVolume));
     }

   static string     ComputeBindingHash(const string basketId,
                                        const string candidateId,
                                        const string executionRequestId,
                                        const ulong ticket,
                                        const double closeVolume)
     {
      string canonical=BuildCanonicalPayload(basketId,candidateId,executionRequestId,ticket,closeVolume);
      return StringSubstr(CCrc32::ToHex(CCrc32::Compute(canonical)),0,8);
     }

   static string     ComputeLegacyV1BindingHash(const string basketId,
                                                const string candidateId,
                                                const string executionRequestId,
                                                const ulong ticket,
                                                const double closeVolume)
     {
      string canonical=BuildLegacyV1CanonicalPayload(basketId,candidateId,executionRequestId,ticket,closeVolume);
      return StringSubstr(CCrc32::ToHex(CCrc32::Compute(canonical)),0,8);
     }

   static string     ComputeBindingHashFromEntry(const CManualProfitCloseCandidateEntry &entry)
     {
      return ComputeBindingHash(entry.BasketId().Value(),
                              entry.CandidateId(),
                              entry.ExecutionRequestId(),
                              entry.PositionTicket(),
                              entry.ProposedCloseVolume());
     }

   static bool       ValidateTokenFingerprint(const string tokenFingerprint,
                                              const string basketId,
                                              const string candidateId,
                                              const string executionRequestId,
                                              const ulong ticket,
                                              const double closeVolume,
                                              string &failureFieldOut)
     {
      failureFieldOut="";
      string v2Hash=ComputeBindingHash(basketId,candidateId,executionRequestId,ticket,closeVolume);
      if(tokenFingerprint==v2Hash)
         return true;
      if(tokenFingerprint==ComputeLegacyV1BindingHash(basketId,candidateId,executionRequestId,ticket,closeVolume))
        {
         failureFieldOut="legacy_auth_binding_version";
         return false;
        }
      failureFieldOut="binding_hash";
      return false;
     }

   static bool       ValidateTokenFingerprintFromEntry(const string tokenFingerprint,
                                                       const CManualProfitCloseCandidateEntry &entry,
                                                       string &failureFieldOut)
     {
      return ValidateTokenFingerprint(tokenFingerprint,
                                      entry.BasketId().Value(),
                                      entry.CandidateId(),
                                      entry.ExecutionRequestId(),
                                      entry.PositionTicket(),
                                      entry.ProposedCloseVolume(),
                                      failureFieldOut);
     }

   static void       PrintIssueBindingDiagnostics(const string runtimeBuildMarker,
                                                  const string basketId,
                                                  const string candidateId,
                                                  const string executionRequestId,
                                                  const ulong ticket,
                                                  const double closeVolume)
     {
      string canonical=BuildCanonicalPayload(basketId,candidateId,executionRequestId,ticket,closeVolume);
      string bindingHash=ComputeBindingHash(basketId,candidateId,executionRequestId,ticket,closeVolume);
      Print("auth_issue_runtime_build_marker=",runtimeBuildMarker);
      Print("auth_issue_binding_serializer_class=",SerializerClassName());
      Print("auth_issue_canonical_binding_string=",canonical);
      Print("auth_issue_binding_hash=",bindingHash);
      Print("auth_binding_build_marker=",BuildMarker());
     }

   static string     MaskToken(const string plaintextToken)
     {
      if(plaintextToken=="")
         return "";
      if(StringLen(plaintextToken)<=16)
         return StringSubstr(plaintextToken,0,8)+"...";
      return StringSubstr(plaintextToken,0,12)+"..."+StringSubstr(plaintextToken,StringLen(plaintextToken)-4);
     }

   static string     DetectBindingFailureField(const string basketIdExpected,
                                               const string basketIdActual,
                                               const string candidateIdExpected,
                                               const string candidateIdActual,
                                               const string executionRequestIdExpected,
                                               const string executionRequestIdActual,
                                               const ulong ticketExpected,
                                               const ulong ticketActual,
                                               const double closeVolumeExpected,
                                               const double closeVolumeActual)
     {
      if(basketIdExpected!=basketIdActual)
         return "basket_id";
      if(candidateIdExpected!=candidateIdActual)
         return "candidate_id";
      if(executionRequestIdExpected!=executionRequestIdActual)
         return "execution_request_id";
      if(ticketExpected!=ticketActual)
         return "ticket";
      if(FormatCloseVolume(closeVolumeExpected)!=FormatCloseVolume(closeVolumeActual))
         return "close_volume";
      return "";
     }
  };

#endif
