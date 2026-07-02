#property script_show_inputs

#include <BasketRecovery/Tests/TestAssert.mqh>
#include <BasketRecovery/Domain/Execution/ProfitCloseAuthorizationBinding.mqh>
#include <BasketRecovery/Domain/Execution/ExecutionAuthorizationToken.mqh>

const string TEST_BASKET_ID="basket-8d7-auth-binding";
const string M2_CANDIDATE_ID="profit-level-close:basket-8d7-auth-binding:level:M2:q:901";
const string M2_EXECUTION_REQUEST_ID="profit-close-manual:8d7-m2";
const ulong TEST_TICKET=1517000001;
const double M2_CLOSE_VOLUME=0.05;

const string M3_CANDIDATE_ID="profit-level-close:basket-8d7-auth-binding:level:M3:q:902";
const string M3_EXECUTION_REQUEST_ID="profit-close-manual:8d7-m3";
const double M3_CLOSE_VOLUME=0.03;

const datetime TEST_EXPIRY_UTC=4000;

string IssueBindingToken(const string basketId,
                         const string candidateId,
                         const string executionRequestId,
                         const ulong ticket,
                         const double closeVolume,
                         const datetime expiryUtc)
  {
   string fingerprint=CProfitCloseAuthorizationBinding::ComputeBindingHash(basketId,
                                                                           candidateId,
                                                                           executionRequestId,
                                                                           ticket,
                                                                           closeVolume);
   return CExecutionAuthorizationToken::IssuePlaintextToken(fingerprint,expiryUtc);
  }

bool ValidateBindingToken(const string token,
                          const string basketId,
                          const string candidateId,
                          const string executionRequestId,
                          const ulong ticket,
                          const double closeVolume,
                          string &failureFieldOut)
  {
   failureFieldOut="";
   string fingerprint="";
   datetime expiryUtc=0;
   if(!CExecutionAuthorizationToken::TryParsePlaintextToken(token,fingerprint,expiryUtc))
     {
      failureFieldOut="token_parse";
      return false;
     }
   return CProfitCloseAuthorizationBinding::ValidateTokenFingerprint(fingerprint,
                                                                     basketId,
                                                                     candidateId,
                                                                     executionRequestId,
                                                                     ticket,
                                                                     closeVolume,
                                                                     failureFieldOut);
  }

void AssertBindingRejected(const string token,
                           const string basketId,
                           const string candidateId,
                           const string executionRequestId,
                           const ulong ticket,
                           const double closeVolume,
                           const string &message)
  {
   string failureField="";
   CTestAssert::False(ValidateBindingToken(token,basketId,candidateId,executionRequestId,ticket,closeVolume,failureField),
                      message);
   string failureMsg=message+" must fail with binding_hash";
   CTestAssert::EqualString("binding_hash",failureField,failureMsg);
  }

void TestM2ExactTupleValidates(void)
  {
   string m2Token=IssueBindingToken(TEST_BASKET_ID,
                                    M2_CANDIDATE_ID,
                                    M2_EXECUTION_REQUEST_ID,
                                    TEST_TICKET,
                                    M2_CLOSE_VOLUME,
                                    TEST_EXPIRY_UTC);
   string failureField="";
   CTestAssert::True(ValidateBindingToken(m2Token,
                                          TEST_BASKET_ID,
                                          M2_CANDIDATE_ID,
                                          M2_EXECUTION_REQUEST_ID,
                                          TEST_TICKET,
                                          M2_CLOSE_VOLUME,
                                          failureField),
                     "M2 exact tuple must validate");
   CTestAssert::EqualString("",failureField,"M2 exact tuple must not set failure field");
  }

void TestM2VsM3ChangesBinding(void)
  {
   string m2Hash=CProfitCloseAuthorizationBinding::ComputeBindingHash(TEST_BASKET_ID,
                                                                     M2_CANDIDATE_ID,
                                                                     M2_EXECUTION_REQUEST_ID,
                                                                     TEST_TICKET,
                                                                     M2_CLOSE_VOLUME);
   string m3Hash=CProfitCloseAuthorizationBinding::ComputeBindingHash(TEST_BASKET_ID,
                                                                     M3_CANDIDATE_ID,
                                                                     M3_EXECUTION_REQUEST_ID,
                                                                     TEST_TICKET,
                                                                     M3_CLOSE_VOLUME);
   CTestAssert::True(m2Hash!=m3Hash,"M2 and M3 candidate tuples must produce different binding hashes");

   string m2Token=IssueBindingToken(TEST_BASKET_ID,
                                    M2_CANDIDATE_ID,
                                    M2_EXECUTION_REQUEST_ID,
                                    TEST_TICKET,
                                    M2_CLOSE_VOLUME,
                                    TEST_EXPIRY_UTC);
   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         M3_CANDIDATE_ID,
                         M3_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         M3_CLOSE_VOLUME,
                         "M2 token must not authorize M3 tuple");
  }

void TestEveryCriticalFieldIsBound(void)
  {
   string m2Token=IssueBindingToken(TEST_BASKET_ID,
                                    M2_CANDIDATE_ID,
                                    M2_EXECUTION_REQUEST_ID,
                                    TEST_TICKET,
                                    M2_CLOSE_VOLUME,
                                    TEST_EXPIRY_UTC);

   AssertBindingRejected(m2Token,
                         "basket-8d7-auth-binding-changed",
                         M2_CANDIDATE_ID,
                         M2_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         M2_CLOSE_VOLUME,
                         "basketId substitution must be rejected");

   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         "profit-level-close:basket-8d7-auth-binding:level:M2:q:999",
                         M2_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         M2_CLOSE_VOLUME,
                         "candidateId substitution must be rejected");

   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         M2_CANDIDATE_ID,
                         "profit-close-manual:8d7-m2-changed",
                         TEST_TICKET,
                         M2_CLOSE_VOLUME,
                         "executionRequestId substitution must be rejected");

   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         M2_CANDIDATE_ID,
                         M2_EXECUTION_REQUEST_ID,
                         1517000002,
                         M2_CLOSE_VOLUME,
                         "ticket substitution must be rejected");

   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         M2_CANDIDATE_ID,
                         M2_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         0.04,
                         "closeVolume one lot-step substitution must be rejected");
  }

void TestCloseVolumeNormalizationContract(void)
  {
   string hashFive=CProfitCloseAuthorizationBinding::ComputeBindingHash(TEST_BASKET_ID,
                                                                        M2_CANDIDATE_ID,
                                                                        M2_EXECUTION_REQUEST_ID,
                                                                        TEST_TICKET,
                                                                        0.05);
   string hashEight=CProfitCloseAuthorizationBinding::ComputeBindingHash(TEST_BASKET_ID,
                                                                         M2_CANDIDATE_ID,
                                                                         M2_EXECUTION_REQUEST_ID,
                                                                         TEST_TICKET,
                                                                         0.05000000);
   CTestAssert::EqualString(hashFive,hashEight,"0.05 and 0.05000000 must canonicalize to same binding hash");

   string canonicalFive=CProfitCloseAuthorizationBinding::BuildCanonicalPayload(TEST_BASKET_ID,
                                                                                M2_CANDIDATE_ID,
                                                                                M2_EXECUTION_REQUEST_ID,
                                                                                TEST_TICKET,
                                                                                0.05);
   string canonicalEight=CProfitCloseAuthorizationBinding::BuildCanonicalPayload(TEST_BASKET_ID,
                                                                               M2_CANDIDATE_ID,
                                                                               M2_EXECUTION_REQUEST_ID,
                                                                               TEST_TICKET,
                                                                               0.05000000);
   CTestAssert::EqualString(canonicalFive,canonicalEight,"0.05 and 0.05000000 must share canonical payload");

   string formattedFive=CProfitCloseAuthorizationBinding::FormatCloseVolume(0.05);
   string formattedEight=CProfitCloseAuthorizationBinding::FormatCloseVolume(0.05000000);
   CTestAssert::EqualString(formattedFive,formattedEight,"FormatCloseVolume must normalize trailing zeros");

   string hashStep=CProfitCloseAuthorizationBinding::ComputeBindingHash(TEST_BASKET_ID,
                                                                      M2_CANDIDATE_ID,
                                                                      M2_EXECUTION_REQUEST_ID,
                                                                      TEST_TICKET,
                                                                      0.05000001);
   CTestAssert::True(hashFive!=hashStep,"0.05 and 0.05000001 must produce different binding hashes");

   string m2Token=IssueBindingToken(TEST_BASKET_ID,
                                    M2_CANDIDATE_ID,
                                    M2_EXECUTION_REQUEST_ID,
                                    TEST_TICKET,
                                    0.05,
                                    TEST_EXPIRY_UTC);
   string failureField="";
   CTestAssert::True(ValidateBindingToken(m2Token,
                                          TEST_BASKET_ID,
                                          M2_CANDIDATE_ID,
                                          M2_EXECUTION_REQUEST_ID,
                                          TEST_TICKET,
                                          0.05000000,
                                          failureField),
                     "M2 token must validate normalized equivalent volume 0.05000000");
   AssertBindingRejected(m2Token,
                         TEST_BASKET_ID,
                         M2_CANDIDATE_ID,
                         M2_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         0.05000001,
                         "non-step volume 0.05000001 must be rejected against 0.05 binding");
  }

void TestM3ExactTupleValidatesIndependently(void)
  {
   string m3Token=IssueBindingToken(TEST_BASKET_ID,
                                    M3_CANDIDATE_ID,
                                    M3_EXECUTION_REQUEST_ID,
                                    TEST_TICKET,
                                    M3_CLOSE_VOLUME,
                                    TEST_EXPIRY_UTC);
   string failureField="";
   CTestAssert::True(ValidateBindingToken(m3Token,
                                          TEST_BASKET_ID,
                                          M3_CANDIDATE_ID,
                                          M3_EXECUTION_REQUEST_ID,
                                          TEST_TICKET,
                                          M3_CLOSE_VOLUME,
                                          failureField),
                     "M3 exact tuple must validate");
   CTestAssert::EqualString("",failureField,"M3 exact tuple must not set failure field");

   AssertBindingRejected(m3Token,
                         TEST_BASKET_ID,
                         M2_CANDIDATE_ID,
                         M2_EXECUTION_REQUEST_ID,
                         TEST_TICKET,
                         M2_CLOSE_VOLUME,
                         "M3 token must not authorize M2 tuple");
  }

void OnStart(void)
  {
   TestM2ExactTupleValidates();
   TestM2VsM3ChangesBinding();
   TestEveryCriticalFieldIsBound();
   TestCloseVolumeNormalizationContract();
   TestM3ExactTupleValidatesIndependently();
   CTestAssert::Summary("TestSprint8dProfitCloseAuthorizationBinding");
   if(!CTestAssert::AllPassed())
      return;
   Print("TestSprint8dProfitCloseAuthorizationBinding: ALL PASSED");
  }
