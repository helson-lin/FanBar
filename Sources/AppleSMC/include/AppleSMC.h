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
int fanbar_smc_read(uint32_t key, FanBarSMCValue *value);
int fanbar_smc_write(uint32_t key, const FanBarSMCValue *value);

#endif
