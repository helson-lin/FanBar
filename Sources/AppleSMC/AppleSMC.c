#include "AppleSMC.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <mach/mach.h>
#include <pthread.h>
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
// The connection is process-wide. Each SMCClient/SMCFanDriver holds one reference, so
// a short-lived reader on another thread (diagnostics) cannot close the main reader's
// connection when it is released. Calls through an open connection need no lock,
// but fanbar_smc_reopen replaces it, so a process that may reopen must not make
// SMC calls from more than one thread at a time (the helper runs every call on
// one serial queue).
static pthread_mutex_t connection_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned int connection_users = 0;

static kern_return_t smc_call(SMCParamStruct *input, SMCParamStruct *output) {
    size_t output_size = sizeof(*output);
    return IOConnectCallStructMethod(connection, kSMCMethod, input, sizeof(*input), output, &output_size);
}

// Caller holds connection_lock.
static kern_return_t smc_connect(void) {
    mach_port_t master_port = MACH_PORT_NULL;
    if (__builtin_available(macOS 12.0, *)) {
        master_port = kIOMainPortDefault;
    } else {
        master_port = MACH_PORT_NULL; // Same value as the deprecated kIOMasterPortDefault.
    }
    io_service_t service = IOServiceGetMatchingService(master_port, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return KERN_FAILURE;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) connection = IO_OBJECT_NULL;
    return result;
}

int fanbar_smc_open(void) {
    pthread_mutex_lock(&connection_lock);
    kern_return_t result = KERN_SUCCESS;
    if (connection == IO_OBJECT_NULL) result = smc_connect();
    if (result == KERN_SUCCESS) connection_users += 1;
    pthread_mutex_unlock(&connection_lock);
    return result;
}

int fanbar_smc_reopen(void) {
    pthread_mutex_lock(&connection_lock);
    kern_return_t result = kIOReturnNotOpen;
    if (connection_users > 0) {
        if (connection != IO_OBJECT_NULL) IOServiceClose(connection);
        connection = IO_OBJECT_NULL;
        result = smc_connect();
    }
    pthread_mutex_unlock(&connection_lock);
    return result;
}

void fanbar_smc_close(void) {
    pthread_mutex_lock(&connection_lock);
    if (connection_users > 0) connection_users -= 1;
    if (connection_users == 0 && connection != IO_OBJECT_NULL) {
        IOServiceClose(connection);
        connection = IO_OBJECT_NULL;
    }
    pthread_mutex_unlock(&connection_lock);
}

int fanbar_smc_read(uint32_t key, FanBarSMCValue *value) {
    int stage = 0;
    return fanbar_smc_read_diagnostic(key, value, &stage);
}

int fanbar_smc_key_at_index(uint32_t index, uint32_t *key) {
    if (connection == IO_OBJECT_NULL || key == NULL) return KERN_INVALID_ARGUMENT;
    SMCParamStruct input = {0}, output = {0};
    input.data8 = 8;
    input.data32 = index;
    kern_return_t result = smc_call(&input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return 0x10000 | output.result;
    *key = output.key;
    return KERN_SUCCESS;
}

int fanbar_smc_read_diagnostic(uint32_t key, FanBarSMCValue *value, int *stage) {
    if (stage != NULL) *stage = 1;
    if (connection == IO_OBJECT_NULL) return kIOReturnNotOpen;
    if (value == NULL) return KERN_INVALID_ARGUMENT;
    SMCParamStruct input = {0}, output = {0};
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    kern_return_t result = smc_call(&input, &output);
    if (result != KERN_SUCCESS) return result;
    if (output.result != 0) return 0x10000 | output.result;

    input.key_info = output.key_info;
    value->data_type = input.key_info.data_type;
    value->data_size = input.key_info.data_size;
    if (stage != NULL) *stage = 2;
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
    if (connection == IO_OBJECT_NULL) return kIOReturnNotOpen;
    if (value == NULL || value->data_size > 32) return KERN_INVALID_ARGUMENT;
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

#if defined(__arm64__)
// Discovering the sensors means creating an event-system client and reading
// the Product name of every HID service, which is far more work than reading
// their temperatures. Telemetry asks every two seconds, so discover once and
// keep the client, the services and their names. Diagnostics collect on a
// background thread with their own SMC reader, so the shared cache is locked.
static pthread_mutex_t hid_lock = PTHREAD_MUTEX_INITIALIZER;
static IOHIDEventSystemClientRef hid_client = NULL;
static CFMutableArrayRef hid_services = NULL;
static CFMutableArrayRef hid_names = NULL;

static void fanbar_discard_hid_sensors(void) {
    if (hid_names != NULL) CFRelease(hid_names);
    if (hid_services != NULL) CFRelease(hid_services);
    if (hid_client != NULL) CFRelease(hid_client);
    hid_names = NULL;
    hid_services = NULL;
    hid_client = NULL;
}

static bool fanbar_discover_hid_sensors(void) {
    // Apple-vendor usage page, temperature-sensor usage.
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
        return false;
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
    if (matching == NULL) return false;

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        CFRelease(matching);
        return false;
    }
    IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        CFRelease(client);
        return false;
    }

    CFMutableArrayRef sensors = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFMutableArrayRef names = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    CFIndex service_count = CFArrayGetCount(services);
    for (CFIndex index = 0; sensors != NULL && names != NULL && index < service_count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)
            CFArrayGetValueAtIndex(services, index);
        CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (product != NULL && CFGetTypeID(product) == CFStringGetTypeID()) {
            CFArrayAppendValue(sensors, service);
            CFArrayAppendValue(names, product);
        }
        if (product != NULL) CFRelease(product);
    }
    CFRelease(services);

    if (sensors == NULL || names == NULL || CFArrayGetCount(sensors) == 0) {
        if (sensors != NULL) CFRelease(sensors);
        if (names != NULL) CFRelease(names);
        CFRelease(client);
        return false;
    }
    hid_client = client;
    hid_services = sensors;
    hid_names = names;
    return true;
}

// Caller holds hid_lock and has a discovered cache.
static int fanbar_read_hid_sensors(
    const char *prefix,
    FanBarHIDTemperature *sensors,
    int capacity
) {
    CFStringRef prefix_string = prefix == NULL ? NULL
        : CFStringCreateWithCString(kCFAllocatorDefault, prefix, kCFStringEncodingUTF8);
    int count = 0;
    int answered = 0;
    CFIndex service_count = CFArrayGetCount(hid_services);
    for (CFIndex index = 0; index < service_count && count < capacity; index++) {
        CFStringRef name = (CFStringRef)CFArrayGetValueAtIndex(hid_names, index);
        if (prefix_string != NULL && !CFStringHasPrefix(name, prefix_string)) continue;

        FanBarHIDTemperature *sensor = &sensors[count++];
        memset(sensor, 0, sizeof(*sensor));
        CFStringGetCString(name, sensor->name, sizeof(sensor->name), kCFStringEncodingUTF8);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(
            (IOHIDServiceClientRef)CFArrayGetValueAtIndex(hid_services, index),
            FANBAR_HID_EVENT_TYPE_TEMPERATURE,
            0,
            0
        );
        if (event == NULL) continue;
        sensor->celsius = IOHIDEventGetFloatValue(
            event,
            FANBAR_HID_EVENT_FIELD_BASE(FANBAR_HID_EVENT_TYPE_TEMPERATURE)
        );
        sensor->has_value = 1;
        answered++;
        CFRelease(event);
    }
    if (prefix_string != NULL) CFRelease(prefix_string);
    // Matching services that all stopped answering have gone stale (e.g.
    // after sleep); rediscover on the next call.
    if (count > 0 && answered == 0) fanbar_discard_hid_sensors();
    return count;
}
#endif

int fanbar_hid_temperatures(const char *prefix, FanBarHIDTemperature *sensors, int capacity) {
    if (sensors == NULL || capacity <= 0) return -1;
#if !defined(__arm64__)
    (void)prefix;
    return -1;
#else
    pthread_mutex_lock(&hid_lock);
    int count = -1;
    if (hid_services != NULL || fanbar_discover_hid_sensors()) {
        count = fanbar_read_hid_sensors(prefix, sensors, capacity);
    }
    pthread_mutex_unlock(&hid_lock);
    return count;
#endif
}

int fanbar_embedded_nvme_temperature(double *temperature) {
    if (temperature == NULL) return KERN_INVALID_ARGUMENT;

#if !defined(__arm64__)
    // Intel Macs use the SMC and NVMe SMART paths; this HID sensor family is
    // specific to Apple Silicon's embedded storage controller.
    return KERN_FAILURE;
#else
    FanBarHIDTemperature sensors[32];
    int count = fanbar_hid_temperatures("NAND CH", sensors, 32);
    double total = 0.0;
    int valid = 0;
    for (int index = 0; index < count; index++) {
        double celsius = sensors[index].celsius;
        if (sensors[index].has_value && celsius >= 10.0 && celsius <= 120.0) {
            total += celsius;
            valid++;
        }
    }
    if (valid == 0) return KERN_FAILURE;
    *temperature = total / (double)valid;
    return KERN_SUCCESS;
#endif
}

int fanbar_nvme_temperature(double *temperature) {
    if (temperature == NULL) return KERN_INVALID_ARGUMENT;

    mach_port_t master_port = MACH_PORT_NULL;
    if (__builtin_available(macOS 12.0, *)) {
        master_port = kIOMainPortDefault;
    } else {
        master_port = MACH_PORT_NULL; // Same value as the deprecated kIOMasterPortDefault.
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
