#ifndef HOST_COMPAT_BYTESWAP_H
#define HOST_COMPAT_BYTESWAP_H
#include <stdint.h>
#ifndef bswap_16
#  define bswap_16(x) __builtin_bswap16((uint16_t)(x))
#endif
#ifndef bswap_32
#  define bswap_32(x) __builtin_bswap32((uint32_t)(x))
#endif
#ifndef bswap_64
#  define bswap_64(x) __builtin_bswap64((uint64_t)(x))
#endif
#endif
