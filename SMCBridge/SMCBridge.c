#include "SMCBridge.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2

#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char key[5];
    uint32_t dataSize;
    char dataType[5];
    uint8_t bytes[32];
} SMCVal_t;

// Internal struct matching kernel expectations
typedef struct {
    uint32_t key;
    struct {
        uint32_t dataSize;
        uint32_t dataType;
        uint8_t dataAttributes;
    } keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

static uint32_t strtoul_b(const char *str, int size, int base) {
    uint32_t total = 0;
    for (int i = 0; i < size; i++) {
        if (base == 16) {
            total += (unsigned char)str[i] << (size - 1 - i) * 8;
        } else {
            total += (unsigned char)str[i] << (size - 1 - i) * 8;
        }
    }
    return total;
}

static void ultoa_b(uint32_t val, char *str, int size) {
    for (int i = 0; i < size; i++) {
        str[i] = (val >> ((size - 1 - i) * 8)) & 0xFF;
    }
}

static kern_return_t SMCCall(io_connect_t conn, uint32_t index, SMCParamStruct *inputStruct, SMCParamStruct *outputStruct) {
    size_t inputStructSize = sizeof(SMCParamStruct);
    size_t outputStructSize = sizeof(SMCParamStruct);
    
    return IOConnectCallStructMethod(conn, index, inputStruct, inputStructSize, outputStruct, &outputStructSize);
}

static kern_return_t SMCReadKey2(io_connect_t conn, const char *key, SMCVal_t *val) {
    kern_return_t result;
    SMCParamStruct inputStruct;
    SMCParamStruct outputStruct;
    
    memset(&inputStruct, 0, sizeof(SMCParamStruct));
    memset(&outputStruct, 0, sizeof(SMCParamStruct));
    memset(val, 0, sizeof(SMCVal_t));
    
    strncpy(val->key, key, 4);
    inputStruct.key = strtoul_b(key, 4, 16);
    inputStruct.data8 = SMC_CMD_READ_KEYINFO;
    
    result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStruct, &outputStruct);
    if (result != kIOReturnSuccess) {
        return result;
    }
    
    val->dataSize = outputStruct.keyInfo.dataSize;
    ultoa_b(outputStruct.keyInfo.dataType, val->dataType, 4);
    
    inputStruct.keyInfo.dataSize = val->dataSize;
    inputStruct.data8 = SMC_CMD_READ_BYTES;
    
    result = SMCCall(conn, KERNEL_INDEX_SMC, &inputStruct, &outputStruct);
    if (result != kIOReturnSuccess) {
        return result;
    }
    
    memcpy(val->bytes, outputStruct.bytes, sizeof(outputStruct.bytes));
    
    return kIOReturnSuccess;
}

static double convertValue(SMCVal_t *val) {
    if (val->dataSize == 0) {
        return 0.0;
    }
    
    // sp78 (fixed point)
    if (strcmp(val->dataType, "sp78") == 0 && val->dataSize == 2) {
        int16_t value = (val->bytes[0] << 8) | val->bytes[1];
        return value / 256.0;
    }
    
    // fpe2 (floating point e2)
    if (strcmp(val->dataType, "fpe2") == 0 && val->dataSize == 2) {
        uint16_t value = (val->bytes[0] << 8) | val->bytes[1];
        return value / 4.0;
    }
    
    // flt (32-bit float)
    if (strcmp(val->dataType, "flt ") == 0 && val->dataSize == 4) {
        uint32_t bits = (val->bytes[0] << 24) | (val->bytes[1] << 16) | (val->bytes[2] << 8) | val->bytes[3];
        float *fptr = (float *)&bits;
        return (double)*fptr;
    }
    
    // ui8/ui16/ui32 (unsigned integers)
    if (strcmp(val->dataType, "ui8 ") == 0) {
        return (double)val->bytes[0];
    }
    if (strcmp(val->dataType, "ui16") == 0 && val->dataSize == 2) {
        return (double)((val->bytes[0] << 8) | val->bytes[1]);
    }
    if (strcmp(val->dataType, "ui32") == 0 && val->dataSize == 4) {
        return (double)((val->bytes[0] << 24) | (val->bytes[1] << 16) | (val->bytes[2] << 8) | val->bytes[3]);
    }
    
    return 0.0;
}

kern_return_t SMCOpen(io_connect_t *conn) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return kIOReturnError;
    }
    
    kern_return_t result = IOServiceOpen(service, mach_task_self_, 0, conn);
    IOObjectRelease(service);
    
    return result;
}

kern_return_t SMCClose(io_connect_t conn) {
    return IOServiceClose(conn);
}

kern_return_t SMCReadKey(io_connect_t conn, const char *key, double *value) {
    SMCVal_t val;
    kern_return_t result = SMCReadKey2(conn, key, &val);
    
    if (result == kIOReturnSuccess) {
        *value = convertValue(&val);
    }
    
    return result;
}
