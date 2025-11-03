/* host-compat/endian.h */
#ifndef HOST_COMPAT_ENDIAN_H
#define HOST_COMPAT_ENDIAN_H

#include <stdint.h>

#define __LITTLE_ENDIAN 1234
#define __BIG_ENDIAN    4321

#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#  define __BYTE_ORDER __LITTLE_ENDIAN
#else
#  define __BYTE_ORDER __BIG_ENDIAN
#endif

/* byte-swap builtins */
#ifndef bswap_16
#  define bswap_16(x) __builtin_bswap16((uint16_t)(x))
#endif
#ifndef bswap_32
#  define bswap_32(x) __builtin_bswap32((uint32_t)(x))
#endif
#ifndef bswap_64
#  define bswap_64(x) __builtin_bswap64((uint64_t)(x))
#endif

/* little-endian <-> host */
#if __BYTE_ORDER == __LITTLE_ENDIAN
#  define le16toh(x) ((uint16_t)(x))
#  define le32toh(x) ((uint32_t)(x))
#  define le64toh(x) ((uint64_t)(x))
#  define htole16(x) ((uint16_t)(x))
#  define htole32(x) ((uint32_t)(x))
#  define htole64(x) ((uint64_t)(x))
#else
#  define le16toh(x) bswap_16(x)
#  define le32toh(x) bswap_32(x)
#  define le64toh(x) bswap_64(x)
#  define htole16(x) bswap_16(x)
#  define htole32(x) bswap_32(x)
#  define htole64(x) bswap_64(x)
#endif

/* (optional) big-endian helpers if anything asks for them */
#ifndef be16toh
#  define be16toh(x) (__BYTE_ORDER == __BIG_ENDIAN ? (uint16_t)(x) : bswap_16(x))
#endif
#ifndef be32toh
#  define be32toh(x) (__BYTE_ORDER == __BIG_ENDIAN ? (uint32_t)(x) : bswap_32(x))
#endif
#ifndef be64toh
#  define be64toh(x) (__BYTE_ORDER == __BIG_ENDIAN ? (uint64_t)(x) : bswap_64(x))
#endif

#endif /* HOST_COMPAT_ENDIAN_H */
