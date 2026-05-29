#include "CellCapSMCBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum {
    kCellCapSMCSelector = 2,
    kCellCapSMCReadBytes = 5,
    kCellCapSMCWriteBytes = 6,
    kCellCapSMCReadKeyInfo = 9,
};

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    uint16_t release;
} CellCapSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPowerLimit;
    uint32_t gpuPowerLimit;
    uint32_t memoryPowerLimit;
} CellCapSMCPowerLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char attributes;
} CellCapSMCKeyInfo;

typedef unsigned char CellCapSMCBytes[32];

typedef struct {
    uint32_t key;
    CellCapSMCVersion version;
    CellCapSMCPowerLimit powerLimit;
    CellCapSMCKeyInfo keyInfo;
    char result;
    char status;
    char command;
    uint32_t data32;
    CellCapSMCBytes bytes;
} CellCapSMCCommandBuffer;

typedef struct {
    char key[5];
    uint32_t dataSize;
    char dataType[5];
    CellCapSMCBytes bytes;
} CellCapSMCValue;

static void cellcap_set_error(char *buffer, int length, const char *message) {
    if (buffer == NULL || length <= 0) {
        return;
    }

    if (message == NULL) {
        buffer[0] = '\0';
        return;
    }

    snprintf(buffer, (size_t)length, "%s", message);
}

static uint32_t cellcap_fourcc(const char *key) {
    return
        ((uint32_t)(unsigned char)key[0] << 24) |
        ((uint32_t)(unsigned char)key[1] << 16) |
        ((uint32_t)(unsigned char)key[2] << 8) |
        (uint32_t)(unsigned char)key[3];
}

static void cellcap_fourcc_to_string(uint32_t value, char out[5]) {
    out[0] = (char)((value >> 24) & 0xff);
    out[1] = (char)((value >> 16) & 0xff);
    out[2] = (char)((value >> 8) & 0xff);
    out[3] = (char)(value & 0xff);
    out[4] = '\0';
}

static kern_return_t cellcap_smc_call(
    io_connect_t connection,
    CellCapSMCCommandBuffer *input,
    CellCapSMCCommandBuffer *output
) {
    size_t inputSize = sizeof(CellCapSMCCommandBuffer);
    size_t outputSize = sizeof(CellCapSMCCommandBuffer);

    return IOConnectCallStructMethod(
        connection,
        kCellCapSMCSelector,
        input,
        inputSize,
        output,
        &outputSize
    );
}

static bool cellcap_open_connection(
    io_connect_t *connection,
    char *errorMessage,
    int errorMessageLength,
    int32_t *kernelResult
) {
    mach_port_t mainPort = MACH_PORT_NULL;
    io_iterator_t iterator = IO_OBJECT_NULL;
    io_object_t device = IO_OBJECT_NULL;

    kern_return_t result = IOMainPort(MACH_PORT_NULL, &mainPort);
    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        cellcap_set_error(errorMessage, errorMessageLength, "IOMainPort 호출에 실패했습니다.");
        return false;
    }

    CFMutableDictionaryRef matching = IOServiceMatching("AppleSMC");
    if (matching == NULL) {
        cellcap_set_error(errorMessage, errorMessageLength, "AppleSMC 매칭 딕셔너리를 만들지 못했습니다.");
        return false;
    }

    result = IOServiceGetMatchingServices(mainPort, matching, &iterator);
    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        cellcap_set_error(errorMessage, errorMessageLength, "AppleSMC 서비스 검색에 실패했습니다.");
        return false;
    }

    device = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    iterator = IO_OBJECT_NULL;

    if (device == IO_OBJECT_NULL) {
        cellcap_set_error(errorMessage, errorMessageLength, "AppleSMC 서비스를 찾지 못했습니다.");
        return false;
    }

    result = IOServiceOpen(device, mach_task_self(), 0, connection);
    IOObjectRelease(device);

    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        cellcap_set_error(errorMessage, errorMessageLength, "AppleSMC 연결을 열지 못했습니다.");
        return false;
    }

    return true;
}

// 공유 AppleSMC 연결과 key-info 캐시.
// helper는 단일 root 데몬이고 상위 actor가 호출을 직렬화하지만, 전역 상태를
// 보호하기 위해 mutex로 한 번 더 감싼다. keyInfo(dataSize/dataType)는 기기에서
// 사실상 불변이므로 연결 수명 동안 캐시하고, 연결을 새로 열 때만 비운다.
typedef struct {
    uint32_t key;
    CellCapSMCKeyInfo info;
} CellCapKeyInfoCacheEntry;

#define CELLCAP_KEYINFO_CACHE_CAPACITY 16

static pthread_mutex_t g_smc_lock = PTHREAD_MUTEX_INITIALIZER;
static io_connect_t g_smc_connection = IO_OBJECT_NULL;
static CellCapKeyInfoCacheEntry g_keyinfo_cache[CELLCAP_KEYINFO_CACHE_CAPACITY];
static int g_keyinfo_cache_count = 0;

static void cellcap_keyinfo_cache_clear(void) {
    g_keyinfo_cache_count = 0;
}

static bool cellcap_keyinfo_cache_lookup(uint32_t key, CellCapSMCKeyInfo *out) {
    for (int index = 0; index < g_keyinfo_cache_count; index += 1) {
        if (g_keyinfo_cache[index].key == key) {
            *out = g_keyinfo_cache[index].info;
            return true;
        }
    }
    return false;
}

static void cellcap_keyinfo_cache_store(uint32_t key, CellCapSMCKeyInfo info) {
    for (int index = 0; index < g_keyinfo_cache_count; index += 1) {
        if (g_keyinfo_cache[index].key == key) {
            g_keyinfo_cache[index].info = info;
            return;
        }
    }
    if (g_keyinfo_cache_count < CELLCAP_KEYINFO_CACHE_CAPACITY) {
        g_keyinfo_cache[g_keyinfo_cache_count].key = key;
        g_keyinfo_cache[g_keyinfo_cache_count].info = info;
        g_keyinfo_cache_count += 1;
    }
}

static void cellcap_connection_invalidate_locked(void) {
    if (g_smc_connection != IO_OBJECT_NULL) {
        IOServiceClose(g_smc_connection);
        g_smc_connection = IO_OBJECT_NULL;
    }
    cellcap_keyinfo_cache_clear();
}

// 공유 연결을 돌려준다. 처음 호출이거나 직전에 무효화되었으면 새로 열고,
// 새로 열 때는 stale 메타데이터 재사용을 막기 위해 key-info 캐시를 비운다.
static bool cellcap_connection_acquire_locked(
    io_connect_t *connection,
    char *errorMessage,
    int errorMessageLength,
    int32_t *kernelResult
) {
    if (g_smc_connection != IO_OBJECT_NULL) {
        *connection = g_smc_connection;
        return true;
    }

    io_connect_t opened = IO_OBJECT_NULL;
    if (!cellcap_open_connection(&opened, errorMessage, errorMessageLength, kernelResult)) {
        return false;
    }

    g_smc_connection = opened;
    cellcap_keyinfo_cache_clear();
    *connection = opened;
    return true;
}

static bool cellcap_read_key_info(
    io_connect_t connection,
    const char *key,
    CellCapSMCKeyInfo *keyInfo,
    int32_t *kernelResult,
    char *errorMessage,
    int errorMessageLength
) {
    uint32_t fourcc = cellcap_fourcc(key);
    if (cellcap_keyinfo_cache_lookup(fourcc, keyInfo)) {
        return true;
    }

    CellCapSMCCommandBuffer input;
    CellCapSMCCommandBuffer output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = fourcc;
    input.command = kCellCapSMCReadKeyInfo;

    kern_return_t result = cellcap_smc_call(connection, &input, &output);
    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        char message[128];
        snprintf(message, sizeof(message), "SMC 키 정보 읽기에 실패했습니다: %s", key);
        cellcap_set_error(errorMessage, errorMessageLength, message);
        return false;
    }

    *keyInfo = output.keyInfo;
    cellcap_keyinfo_cache_store(fourcc, output.keyInfo);
    return true;
}

static bool cellcap_read_key(
    io_connect_t connection,
    const char *key,
    CellCapSMCValue *value,
    int32_t *kernelResult,
    char *errorMessage,
    int errorMessageLength
) {
    CellCapSMCCommandBuffer input;
    CellCapSMCCommandBuffer output;
    CellCapSMCKeyInfo keyInfo;

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    memset(value, 0, sizeof(*value));

    if (!cellcap_read_key_info(connection, key, &keyInfo, kernelResult, errorMessage, errorMessageLength)) {
        return false;
    }

    input.key = cellcap_fourcc(key);
    input.keyInfo.dataSize = keyInfo.dataSize;
    input.command = kCellCapSMCReadBytes;

    kern_return_t result = cellcap_smc_call(connection, &input, &output);
    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        char message[128];
        snprintf(message, sizeof(message), "SMC 키 읽기에 실패했습니다: %s", key);
        cellcap_set_error(errorMessage, errorMessageLength, message);
        return false;
    }

    memcpy(value->bytes, output.bytes, sizeof(output.bytes));
    value->dataSize = keyInfo.dataSize;
    memcpy(value->key, key, 4);
    value->key[4] = '\0';
    cellcap_fourcc_to_string(keyInfo.dataType, value->dataType);
    return true;
}

static bool cellcap_write_key(
    io_connect_t connection,
    const char *key,
    const unsigned char *bytes,
    uint32_t length,
    int32_t *kernelResult,
    char *errorMessage,
    int errorMessageLength
) {
    CellCapSMCCommandBuffer input;
    CellCapSMCCommandBuffer output;
    CellCapSMCKeyInfo keyInfo;

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    if (!cellcap_read_key_info(connection, key, &keyInfo, kernelResult, errorMessage, errorMessageLength)) {
        return false;
    }

    if (keyInfo.dataSize != length) {
        char message[128];
        snprintf(
            message,
            sizeof(message),
            "SMC 키 길이가 맞지 않습니다: %s (expected=%u, actual=%u)",
            key,
            keyInfo.dataSize,
            length
        );
        cellcap_set_error(errorMessage, errorMessageLength, message);
        return false;
    }

    input.key = cellcap_fourcc(key);
    input.keyInfo.dataSize = length;
    input.command = kCellCapSMCWriteBytes;
    memcpy(input.bytes, bytes, length);

    kern_return_t result = cellcap_smc_call(connection, &input, &output);
    if (kernelResult != NULL) {
        *kernelResult = result;
    }
    if (result != KERN_SUCCESS) {
        char message[128];
        snprintf(message, sizeof(message), "SMC 키 쓰기에 실패했습니다: %s", key);
        cellcap_set_error(errorMessage, errorMessageLength, message);
        return false;
    }

    return true;
}

static bool cellcap_try_read_key(io_connect_t connection, const char *key, CellCapSMCValue *value, int32_t *kernelResult) {
    char ignored[1] = {0};
    return cellcap_read_key(connection, key, value, kernelResult, ignored, 0);
}

static bool cellcap_is_zero_bytes(const unsigned char *bytes, uint32_t length) {
    for (uint32_t index = 0; index < length; index += 1) {
        if (bytes[index] != 0x00) {
            return false;
        }
    }
    return true;
}

bool cellcap_smc_read_status(
    CellCapSMCStatus *status,
    char *errorMessage,
    int errorMessageLength
) {
    if (status == NULL) {
        cellcap_set_error(errorMessage, errorMessageLength, "상태 버퍼가 비어 있습니다.");
        return false;
    }

    pthread_mutex_lock(&g_smc_lock);

    // 공유 연결을 재사용하되, 재사용한 연결이 키를 하나도 읽지 못하면(sleep/wake나
    // SMC 리셋으로 핸들이 죽은 경우) 한 번만 새 연결로 재시도한다.
    for (int attempt = 0; attempt < 2; attempt += 1) {
        memset(status, 0, sizeof(*status));
        status->batteryChargePercent = -1;

        bool freshlyOpened = (g_smc_connection == IO_OBJECT_NULL);
        io_connect_t connection = IO_OBJECT_NULL;
        if (!cellcap_connection_acquire_locked(&connection, errorMessage, errorMessageLength, &status->kernelResult)) {
            pthread_mutex_unlock(&g_smc_lock);
            return false;
        }

        status->serviceAvailable = true;

        CellCapSMCValue value;
        CellCapSMCValue legacyChargeValue;
        bool anyKeySucceeded = false;

        bool hasCH0B = cellcap_try_read_key(connection, "CH0B", &legacyChargeValue, &status->kernelResult);
        bool hasCH0C = cellcap_try_read_key(connection, "CH0C", &value, &status->kernelResult);
        status->legacyChargingKeysAvailable = hasCH0B && hasCH0C;
        anyKeySucceeded = anyKeySucceeded || hasCH0B || hasCH0C;

        if (cellcap_try_read_key(connection, "CHTE", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->tahoeChargingKeyAvailable = true;
            status->chargingEnabledKnown = value.dataSize == 4;
            status->chargingEnabled = status->chargingEnabledKnown && cellcap_is_zero_bytes(value.bytes, 4);
        } else if (status->legacyChargingKeysAvailable) {
            // 위에서 이미 읽은 CH0B 바이트를 재사용해 같은 키를 두 번 읽지 않는다.
            status->chargingEnabledKnown = legacyChargeValue.dataSize >= 1;
            status->chargingEnabled = status->chargingEnabledKnown && legacyChargeValue.bytes[0] == 0x00;
        }

        if (cellcap_try_read_key(connection, "CH0I", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->adapterKeyAvailable = true;
            status->adapterEnabledKnown = value.dataSize >= 1;
            status->adapterEnabled = status->adapterEnabledKnown && value.bytes[0] == 0x00;
        } else if (cellcap_try_read_key(connection, "CH0J", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->adapterKeyAvailable = true;
            status->adapterEnabledKnown = value.dataSize >= 1;
            status->adapterEnabled = status->adapterEnabledKnown && value.bytes[0] == 0x00;
        } else if (cellcap_try_read_key(connection, "CHIE", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->adapterKeyAvailable = true;
            status->adapterEnabledKnown = value.dataSize >= 1;
            status->adapterEnabled = status->adapterEnabledKnown && value.bytes[0] == 0x00;
        }

        if (cellcap_try_read_key(connection, "AC-W", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->acPowerKeyAvailable = true;
            status->externalPowerKnown = value.dataSize >= 1;
            status->externalPowerConnected = status->externalPowerKnown && ((int8_t)value.bytes[0] > 0);
        }

        if (cellcap_try_read_key(connection, "BUIC", &value, &status->kernelResult)) {
            anyKeySucceeded = true;
            status->batteryChargeKeyAvailable = true;
            if (value.dataSize >= 1) {
                status->batteryChargePercent = (int32_t)value.bytes[0];
            }
        }

        if (!freshlyOpened && !anyKeySucceeded) {
            cellcap_connection_invalidate_locked();
            continue;
        }

        cellcap_set_error(errorMessage, errorMessageLength, NULL);
        pthread_mutex_unlock(&g_smc_lock);
        return true;
    }

    pthread_mutex_unlock(&g_smc_lock);
    return false;
}

bool cellcap_smc_set_charging_enabled(
    bool enabled,
    char *errorMessage,
    int errorMessageLength
) {
    pthread_mutex_lock(&g_smc_lock);

    // 공유 연결을 재사용하되, 재사용한 연결의 모든 쓰기가 실패하면(핸들이 죽었을 수
    // 있음) 한 번만 새 연결로 재시도한 뒤 실패를 보고한다.
    for (int attempt = 0; attempt < 2; attempt += 1) {
        bool freshlyOpened = (g_smc_connection == IO_OBJECT_NULL);
        io_connect_t connection = IO_OBJECT_NULL;
        int32_t kernelResult = 0;
        if (!cellcap_connection_acquire_locked(&connection, errorMessage, errorMessageLength, &kernelResult)) {
            pthread_mutex_unlock(&g_smc_lock);
            return false;
        }

        bool success = false;
        if (enabled) {
            const unsigned char legacyValue[1] = {0x00};
            const unsigned char tahoeValue[4] = {0x00, 0x00, 0x00, 0x00};

            if (cellcap_write_key(connection, "CHTE", tahoeValue, 4, &kernelResult, errorMessage, errorMessageLength)) {
                success = true;
            } else {
                char ignored[1] = {0};
                bool first = cellcap_write_key(connection, "CH0B", legacyValue, 1, &kernelResult, ignored, 0);
                bool second = cellcap_write_key(connection, "CH0C", legacyValue, 1, &kernelResult, ignored, 0);
                if (first && second) {
                    success = true;
                    cellcap_set_error(errorMessage, errorMessageLength, NULL);
                } else {
                    cellcap_set_error(errorMessage, errorMessageLength, "충전 활성화 SMC 키를 찾지 못했습니다.");
                }
            }
        } else {
            const unsigned char legacyValue[1] = {0x02};
            const unsigned char tahoeValue[4] = {0x01, 0x00, 0x00, 0x00};

            if (cellcap_write_key(connection, "CHTE", tahoeValue, 4, &kernelResult, errorMessage, errorMessageLength)) {
                success = true;
            } else {
                char ignored[1] = {0};
                bool first = cellcap_write_key(connection, "CH0B", legacyValue, 1, &kernelResult, ignored, 0);
                bool second = cellcap_write_key(connection, "CH0C", legacyValue, 1, &kernelResult, ignored, 0);
                if (first && second) {
                    success = true;
                    cellcap_set_error(errorMessage, errorMessageLength, NULL);
                } else {
                    cellcap_set_error(errorMessage, errorMessageLength, "충전 비활성화 SMC 키를 찾지 못했습니다.");
                }
            }
        }

        if (success) {
            pthread_mutex_unlock(&g_smc_lock);
            return true;
        }

        if (!freshlyOpened) {
            cellcap_connection_invalidate_locked();
            continue;
        }

        pthread_mutex_unlock(&g_smc_lock);
        return false;
    }

    pthread_mutex_unlock(&g_smc_lock);
    return false;
}
