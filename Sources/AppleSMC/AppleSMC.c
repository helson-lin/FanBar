#include "AppleSMC.h"
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <string.h>

// AppleSMC's external-method ABI. It is intentionally isolated here because
// Apple does not publish a supported public API for fan target control.
typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_plimit;
    uint32_t gpu_plimit;
    uint32_t mem_plimit;
} SMCPLimitData;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    uint8_t data_attributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion version;
    uint16_t plimit_data_size;
    SMCPLimitData plimit_data;
    SMCKeyInfoData key_info;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

enum { kSMCGetKeyInfo = 9, kSMCReadBytes = 5, kSMCWriteBytes = 6, kSMCMethod = 2 };
static io_connect_t connection = IO_OBJECT_NULL;

static kern_return_t smc_call(SMCParamStruct *input, SMCParamStruct *output) {
    size_t output_size = sizeof(*output);
    return IOConnectCallStructMethod(connection, kSMCMethod, input, sizeof(*input), output, &output_size);
}

int fanbar_smc_open(void) {
    if (connection != IO_OBJECT_NULL) return KERN_SUCCESS;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return KERN_FAILURE;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result;
}

void fanbar_smc_close(void) {
    if (connection != IO_OBJECT_NULL) IOServiceClose(connection);
    connection = IO_OBJECT_NULL;
}

int fanbar_smc_read(uint32_t key, FanBarSMCValue *value) {
    if (connection == IO_OBJECT_NULL || value == NULL) return KERN_INVALID_ARGUMENT;
    SMCParamStruct input = {0}, output = {0};
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    kern_return_t result = smc_call(&input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return 0x10000 | output.result;

    input.key_info = output.key_info;
    input.data8 = kSMCReadBytes;
    result = smc_call(&input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return 0x10000 | output.result;
    value->data_type = input.key_info.data_type;
    value->data_size = input.key_info.data_size;
    memcpy(value->bytes, output.bytes, sizeof(value->bytes));
    return KERN_SUCCESS;
}

int fanbar_smc_write(uint32_t key, const FanBarSMCValue *value) {
    if (connection == IO_OBJECT_NULL || value == NULL || value->data_size > 32) return KERN_INVALID_ARGUMENT;
    SMCParamStruct input = {0}, output = {0};
    input.key = key;
    input.key_info.data_type = value->data_type;
    input.key_info.data_size = value->data_size;
    input.data8 = kSMCWriteBytes;
    memcpy(input.bytes, value->bytes, value->data_size);
    kern_return_t result = smc_call(&input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return 0x10000 | output.result;
    return KERN_SUCCESS;
}
