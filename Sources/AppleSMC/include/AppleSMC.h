#ifndef APPLE_SMC_H
#define APPLE_SMC_H

#include <stdint.h>

// This thin C boundary keeps private IOKit ABI structs out of Swift code.
typedef struct {
    uint32_t data_type;
    uint32_t data_size;
    uint8_t bytes[32];
} FanBarSMCValue;

int fanbar_smc_open(void);
void fanbar_smc_close(void);
// Replaces a connection AppleSMC dropped (service restarted, port died) while
// keeping its users; returns kIOReturnNotOpen when nobody has it open. Calls
// racing a reopen on another thread may use the closed port, so a process that
// reopens must make its SMC calls from one thread at a time. Reads and writes
// report kIOReturnNotOpen while no connection is open, so a failed reopen is
// retried on the next call.
int fanbar_smc_reopen(void);
int fanbar_smc_read(uint32_t key, FanBarSMCValue *value);
// stage: 1 = key metadata, 2 = value bytes; output metadata survives a byte-read failure.
int fanbar_smc_read_diagnostic(uint32_t key, FanBarSMCValue *value, int *stage);
int fanbar_smc_key_at_index(uint32_t index, uint32_t *key);
int fanbar_smc_write(uint32_t key, const FanBarSMCValue *value);

// Returns the average temperature of Apple Silicon NAND channels exposed as
// Apple-vendor HID temperature sensors. Intel builds report unavailable.
int fanbar_embedded_nvme_temperature(double *temperature);

typedef struct {
    char name[64];
    double celsius;
    int has_value;
} FanBarHIDTemperature;

// Fills up to `capacity` Apple-vendor HID temperature sensors whose Product
// name starts with `prefix` (NULL for all), with unfiltered values. Returns
// the number filled, or -1 when the sensors are unavailable (always on Intel).
int fanbar_hid_temperatures(const char *prefix, FanBarHIDTemperature *sensors, int capacity);

// Returns the standard NVMe SMART temperature in Celsius when available.
int fanbar_nvme_temperature(double *temperature);

#endif
