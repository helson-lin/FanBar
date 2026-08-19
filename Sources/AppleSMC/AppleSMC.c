#include "AppleSMC.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <string.h>

#if defined(__arm64__)
// Apple ships these HID event symbols in IOKit but does not expose all of
// their declarations in the macOS SDK. Keep the private boundary in C so the
// Swift telemetry layer remains architecture-agnostic.
typedef struct __IOHIDEvent *IOHIDEventRef;
#define FANBAR_HID_EVENT_TYPE_TEMPERATURE 15
#define FANBAR_HID_EVENT_FIELD_BASE(type) ((type) << 16)

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(
    IOHIDEventSystemClientRef client,
    CFDictionaryRef matching
);
IOHIDEventRef IOHIDServiceClientCopyEvent(
    IOHIDServiceClientRef service,
    int64_t type,
    int32_t options,
    int64_t timeout
);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
#endif

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
    mach_port_t master_port = MACH_PORT_NULL;
    if (__builtin_available(macOS 12.0, *)) {
        master_port = kIOMainPortDefault;
    } else {
        master_port = kIOMasterPortDefault;
    }
    io_service_t service = IOServiceGetMatchingService(master_port, IOServiceMatching("AppleSMC"));
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

int fanbar_embedded_nvme_temperature(double *temperature) {
    if (temperature == NULL) return KERN_INVALID_ARGUMENT;

#if !defined(__arm64__)
    // Intel Macs use the SMC and NVMe SMART paths; this HID sensor family is
    // specific to Apple Silicon's embedded storage controller.
    return KERN_FAILURE;
#else
    int32_t usage_page = 0xff00;
    int32_t usage = 0x0005;
    CFNumberRef usage_page_number = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &usage_page
    );
    CFNumberRef usage_number = CFNumberCreate(
        kCFAllocatorDefault,
        kCFNumberSInt32Type,
        &usage
    );
    if (usage_page_number == NULL || usage_number == NULL) {
        if (usage_page_number != NULL) CFRelease(usage_page_number);
        if (usage_number != NULL) CFRelease(usage_number);
        return KERN_RESOURCE_SHORTAGE;
    }

    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[] = { usage_page_number, usage_number };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(usage_page_number);
    CFRelease(usage_number);
    if (matching == NULL) return KERN_RESOURCE_SHORTAGE;

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        CFRelease(matching);
        return KERN_FAILURE;
    }
    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return KERN_FAILURE;
    }

    double total = 0.0;
    CFIndex count = 0;
    CFIndex service_count = CFArrayGetCount(services);
    for (CFIndex index = 0; index < service_count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)
            CFArrayGetValueAtIndex(services, index);
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        bool is_nand_sensor = product != NULL
            && CFGetTypeID(product) == CFStringGetTypeID()
            && CFStringHasPrefix((CFStringRef)product, CFSTR("NAND CH"));
        if (product != NULL) CFRelease(product);
        if (!is_nand_sensor) continue;

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(
            service,
            FANBAR_HID_EVENT_TYPE_TEMPERATURE,
            0,
            0
        );
        if (event == NULL) continue;
        double celsius = IOHIDEventGetFloatValue(
            event,
            FANBAR_HID_EVENT_FIELD_BASE(FANBAR_HID_EVENT_TYPE_TEMPERATURE)
        );
        CFRelease(event);
        if (celsius >= 10.0 && celsius <= 120.0) {
            total += celsius;
            count++;
        }
    }

    CFRelease(services);
    CFRelease(client);
    if (count == 0) return KERN_FAILURE;
    *temperature = total / (double)count;
    return KERN_SUCCESS;
#endif
}

int fanbar_nvme_temperature(double *temperature) {
    if (temperature == NULL) return KERN_INVALID_ARGUMENT;

    mach_port_t master_port = MACH_PORT_NULL;
    if (__builtin_available(macOS 12.0, *)) {
        master_port = kIOMainPortDefault;
    } else {
        master_port = kIOMasterPortDefault;
    }

    // Match the storage service that advertises the public SMART capability
    // instead of depending on the controller class used by each Mac family.
    CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDevice");
    if (matching == NULL) return KERN_FAILURE;
    CFDictionarySetValue(
        matching,
        CFSTR(kIOPropertyNVMeSMARTCapableKey),
        kCFBooleanTrue
    );

    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(master_port, matching, &iterator);
    if (result != KERN_SUCCESS) return result;

    result = KERN_FAILURE;
    io_service_t service = IO_OBJECT_NULL;
    // External NVMe devices can coexist with the internal disk. Try every
    // SMART-capable service and keep the first valid temperature.
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score = 0;
        result = IOCreatePlugInInterfaceForService(
            service,
            kIONVMeSMARTUserClientTypeID,
            kIOCFPlugInInterfaceID,
            &plugin,
            &score
        );
        if (result == KERN_SUCCESS && plugin != NULL) {
            IONVMeSMARTInterface **interface = NULL;
            HRESULT query_result = (*plugin)->QueryInterface(
                (void *)plugin,
                CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
                (LPVOID *)&interface
            );
            if (query_result == S_OK && interface != NULL) {
                NVMeSMARTData smart = {0};
                result = (*interface)->SMARTReadData(interface, &smart);
                if (result == KERN_SUCCESS) {
                    double celsius = (double)smart.TEMPERATURE - 273.15;
                    if (celsius >= 10.0 && celsius <= 120.0) {
                        *temperature = celsius;
                        result = KERN_SUCCESS;
                    } else {
                        result = KERN_FAILURE;
                    }
                }
                (*interface)->Release(interface);
            } else {
                result = KERN_FAILURE;
            }
            (*plugin)->Release(plugin);
        }
        IOObjectRelease(service);
        if (result == KERN_SUCCESS) break;
    }
    IOObjectRelease(iterator);
    return result;
}
