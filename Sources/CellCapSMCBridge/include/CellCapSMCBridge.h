#ifndef CELLCAP_SMC_BRIDGE_H
#define CELLCAP_SMC_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool serviceAvailable;
    bool legacyChargingKeysAvailable;
    bool tahoeChargingKeyAvailable;
    bool adapterKeyAvailable;
    bool batteryChargeKeyAvailable;
    bool acPowerKeyAvailable;
    bool chargingEnabledKnown;
    bool chargingEnabled;
    bool adapterEnabledKnown;
    bool adapterEnabled;
    bool externalPowerKnown;
    bool externalPowerConnected;
    int32_t batteryChargePercent;
    int32_t kernelResult;
} CellCapSMCStatus;

bool cellcap_smc_read_status(
    CellCapSMCStatus *status,
    char *errorMessage,
    int errorMessageLength
);

bool cellcap_smc_set_charging_enabled(
    bool enabled,
    char *errorMessage,
    int errorMessageLength
);

#endif
