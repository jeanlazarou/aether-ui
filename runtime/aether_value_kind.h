/* aether_value_kind.h — kind discriminator for AetherValue containers.
 *
 * Aether's collections (HashMap and ArrayList) carry a leading
 * `uint32_t _kind_magic` field set at construction time. Hosts
 * holding an opaque `AetherValue*` use the predicates in
 * runtime/aether_config.h (`aether_value_kind`,
 * `aether_value_is_map`, `aether_value_is_list`) to discriminate
 * map / list / scalar safely without a schema lookup.
 *
 * This header isolates the magic constants so the producing side
 * (std/collections/aether_collections.c) and the consuming side
 * (runtime/aether_config.c) cannot drift.
 *
 * Magic numbers are 32-bit. Probability of an arbitrary 4-byte
 * pattern accidentally matching either magic is 1 in 2^32. The
 * kind-discriminator predicates additionally apply a low-address
 * guard (zero page + first 64 KiB are unmapped on every modern
 * OS) so common intptr-cast scalars (small integers stored as
 * `(void*)(intptr_t)42`) are filtered before any deref attempt.
 */

#ifndef AETHER_VALUE_KIND_H
#define AETHER_VALUE_KIND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AETHER_KIND_LIST_MAGIC ((uint32_t)0xAE57E715u)
#define AETHER_KIND_MAP_MAGIC  ((uint32_t)0xAE571A99u)

/* Lower bound for a "definitely-mapped" address. Linux's
 * vm.mmap_min_addr defaults to 65536 (== 0x10000). macOS reserves
 * even more of the low address space. Windows the same. Any
 * pointer below this is treated as "not a container" without
 * deref. */
#define AETHER_KIND_MIN_VALID_ADDR ((uintptr_t)0x10000u)

#ifdef __cplusplus
}
#endif

#endif /* AETHER_VALUE_KIND_H */
