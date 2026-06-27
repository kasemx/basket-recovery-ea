#ifndef BASKET_RECOVERY_SHARED_PERSISTENCE_SCHEMA_MQH
#define BASKET_RECOVERY_SHARED_PERSISTENCE_SCHEMA_MQH

#define BRE_PERSISTENCE_SCHEMA_VERSION          1
#define BRE_PERSISTENCE_BASKET_SUBDIR           "BasketRecovery/persistence/baskets"
#define BRE_PERSISTENCE_COMMAND_SUBDIR          "BasketRecovery/persistence/commands"
#define BRE_PERSISTENCE_IDEMPOTENCY_SUBDIR      "BasketRecovery/persistence/idempotency"
#define BRE_PERSISTENCE_PENDING_COMMANDS_FILE   "BasketRecovery/persistence/commands/pending.json"
#define BRE_PERSISTENCE_IDEMPOTENCY_FILE        "BasketRecovery/persistence/idempotency/processed.json"

#endif
