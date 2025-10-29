#pragma once
/* Make Apple headers use __darwin_uuid_t instead of uuid_t while they are parsed. */
#define uuid_t __darwin_uuid_t
#include <unistd.h>     /* pulls gethostuuid.h (uses uuid_t) */
#include <uuid/uuid.h>  /* also uses uuid_t on some SDKs */
#undef uuid_t
/* Do NOT typedef uuid_t here — let file2alias.c's own typedef stand. */
