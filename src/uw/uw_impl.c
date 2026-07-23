// src/uw/uw_impl.c
#define UW_IMPLEMENTATION
#include "uw.h"

// Expose the compile-time cluster-width cap as a runtime symbol so the
// Crystal side reads the exact value this TU was built with, keeping the
// "must match" invariant on a single source of truth.
int uw_active_width_cap(void) { return UW_ACTIVE_WIDTH_CAP; }