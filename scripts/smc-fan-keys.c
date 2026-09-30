// Lists every SMC key starting with "F" (fan keys) with its type, size and raw bytes.
// Read-only; needs no root. Build and run:
//   clang scripts/smc-fan-keys.c -framework IOKit -o /tmp/smc-fan-keys && /tmp/smc-fan-keys
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdint.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } V;
typedef struct { uint16_t version, length; uint32_t c, g, m; } PL;
typedef struct { uint32_t size, type; uint8_t attr; } KI;
typedef struct {
    uint32_t key; V v; uint16_t pls; PL pl; KI ki;
    uint8_t result, status, data8; uint32_t data32; uint8_t bytes[32];
} P;

static io_connect_t conn;

static int call(P *in, P *out) {
    size_t size = sizeof(*out);
    return IOConnectCallStructMethod(conn, 2, in, sizeof(*in), out, &size);
}

static void name(uint32_t k, char out[5]) {
    for (int i = 0; i < 4; i++) out[i] = (char)(k >> (24 - 8 * i));
    out[4] = 0;
}

int main(void) {
    io_service_t svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"));
    if (!svc || IOServiceOpen(svc, mach_task_self(), 0, &conn)) { puts("cannot open AppleSMC"); return 1; }

    P i = {0}, o = {0};
    i.key = ('#' << 24) | ('K' << 16) | ('E' << 8) | 'Y'; i.data8 = 9; call(&i, &o);
    i.ki = o.ki; i.data8 = 5; call(&i, &o);
    uint32_t n = (o.bytes[0] << 24) | (o.bytes[1] << 16) | (o.bytes[2] << 8) | o.bytes[3];
    printf("total keys: %u\n", n);

    for (uint32_t k = 0; k < n; k++) {
        P a = {0}, b = {0};
        a.data8 = 8; a.data32 = k; call(&a, &b);
        char nm[5]; name(b.key, nm);
        if (nm[0] != 'F') continue;
        P x = {0}, y = {0};
        x.key = b.key; x.data8 = 9; call(&x, &y);
        char ty[5]; name(y.ki.type, ty);
        x.ki = y.ki; x.data8 = 5; call(&x, &y);
        printf("%s type=%s size=%u bytes=", nm, ty, x.ki.size);
        for (uint32_t j = 0; j < x.ki.size && j < 32; j++) printf("%02x", y.bytes[j]);
        putchar('\n');
    }
    return 0;
}
