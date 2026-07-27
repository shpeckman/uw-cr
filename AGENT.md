# AGENT.md

Guidance for AI coding agents working on `uw-cr`, a Crystal shard for Unicode
display-width measurement and grapheme-cluster segmentation (Unicode 17.0.0).

The shard is named `uw-cr`. The module it exposes is `UW`. The entrypoint is
`src/uw-cr.cr`, which only requires `src/uw.cr` where the implementation lives.

## Setup commands

- Run tests: `make spec` (or `crystal spec`)
- Build release binary: `make build`
- Regenerate lookup tables from cached UCD: `make gen`
- Regenerate, re-downloading UCD sources first: `make gen-refresh`
- Refresh the grapheme conformance test file: `make fetch-testdata`

Crystal `>= 1.21.0`. No third-party dependencies.

## Project layout

- `src/uw.cr` — the whole implementation: accessors, `State`, `Cluster`,
  UTF-8 decode, and the public API. Edit here.
- `src/uw-cr.cr` — entrypoint, do not add logic to it.
- `src/uw/tables.cr`, `src/uw/stage1.bin`, `src/uw/stage2.bin` — GENERATED. Do
  not hand-edit. Change them only by running `make gen`.
- `tools/gen_tables.cr` — the table generator. Edit here to change table
  contents or the packing.
- `tools/ucd/` — cached Unicode Character Database source files (committed).
- `spec/` — specs and `spec/data/GraphemeBreakTest.txt` (the authoritative
  conformance data, committed).

## Do not touch without regenerating

`src/uw/stage1.bin`, `src/uw/stage2.bin`, and `src/uw/tables.cr` are build
artifacts produced by `tools/gen_tables.cr`. Never edit them directly. If a
table needs to change, change the generator and run `make gen`.

Invariant: running `make gen` from a clean UCD download must reproduce the
committed `stage1.bin`, `stage2.bin`, and `tables.cr` byte-for-byte. If a
regeneration changes the binaries without a deliberate `UCD_VERSION` bump in
`tools/gen_tables.cr`, the derivation drifted — treat that as a bug, not a new
baseline.

## Code style

These are firm project conventions; follow them even where they differ from
common Crystal style.

- No comments in `src/`. The code is meant to read without them. (Generator and
  specs may carry brief explanatory comments.)
- Every source file starts with a one-line path comment, e.g. `# src/uw.cr`.
- Prefer `struct` over `class` for the hot-path types. `State` and `Cluster`
  are structs specifically so the common single-call paths do not heap-allocate.
  Do not convert them to classes.
- Keep the public API allocation-free on the hot path and reentrant. All state
  lives in caller-owned `State`/`Cluster`; there are no mutable globals and the
  tables are read-only.
- The three input flavors (`String`, `Bytes`, `Slice(UInt32)`) are the API
  shape. New functions should offer the same three where it makes sense.
- The packed-property accessors live in the nested `UW::Props` module and are
  `protected def self.` — callable from `State`/`Cluster`/module functions but
  rejected from outside `UW`. The `GCB_*`, `INCB_*`, and `VS*` constants are
  `private`. Keep them locked down; they are not part of the public surface.
- `State`/`Cluster` internal fields are not exposed. `Cluster` has a read-only
  `started` getter because the width functions query it; add getters only when
  an external caller genuinely needs one.

## Testing instructions

- `make spec` runs the full suite (49 examples, ~25 ms). It must be green before
  any change is considered done.
- Segmentation is validated against `spec/data/GraphemeBreakTest.txt`, the
  official UCD conformance file, checking the break decision at every position
  of all 766 cases. This is the source of truth for grapheme boundaries — do not
  weaken or skip it to make a change pass.
- When you change segmentation or width logic, add or update targeted cases in
  the relevant `spec/*_spec.cr` alongside the conformance check.
- There is no width conformance file in the UCD; width assertions are
  hand-written from `EastAsianWidth`/emoji semantics. Add explicit cases for any
  width edge you touch.

## Packed property format

Each code point maps to a `UInt16` via a two-stage trie:
`stage2[stage1[cp >> 8] * 256 + (cp & 0xFF)]`. Stage 1 is 4352 entries; stage 2
is 123 deduplicated 256-entry blocks. The packed bits:

- bits 0–1: width — 0, 1, 2, or 3 (3 means control, reported as -1)
- bits 2–5: grapheme-cluster-break class (0 Other, 1 CR, 2 LF, 3 Control,
  4 Extend, 5 ZWJ, 6 Prepend, 7 SpacingMark, 8 L, 9 V, 10 T, 11 LV, 12 LVT,
  13 Regional_Indicator)
- bit 6: Extended_Pictographic
- bit 7: Emoji_Presentation
- bits 8–9: Indic_Conjunct_Break (0 none, 1 Consonant, 2 Extend, 3 Linker)

The tables are shipped as little-endian `UInt16` binary blobs embedded with
`read_file` at compile time, not as array literals. This is deliberate: an
equivalent nested literal (~31k elements) makes `crystal build --release`
exhaust memory. If you are tempted to inline the tables as a literal, don't —
you will break release builds. The blobs are decoded once at load through
`IO::ByteFormat::LittleEndian`, which also keeps big-endian targets correct.

## Width-policy derivation (generator)

The width field in the packed property is derived in strict precedence order
(first match wins). This is reverse-engineered from the reference tables and
verified to reproduce them for all 1,114,112 code points; preserve the ordering
exactly when editing `tools/gen_tables.cr`:

1. General_Category `Cc` → width 3 (control, -1).
2. Grapheme-break class `Regional_Indicator` → width 1. The pairing of two RIs
   into a width-2 flag happens in `Cluster#push`, not in the base width. This is
   counterintuitive: an RI is NOT width 2 in the table.
3. Grapheme-break class in {Extend, ZWJ, Prepend, SpacingMark}, or category
   `Cf` → width 0.
4. East_Asian_Width in {W, F}, or Emoji_Presentation → width 2.
5. Otherwise → width 1.

The other packed fields (GCB, InCB, pict, epres) are direct property reads and
track the UCD cleanly. Width is the only field with an inferred policy, so it is
the one to scrutinize on a UCD version bump.

## Cluster width cap

`Cluster#display_width` caps at `UW::CLUSTER_WIDTH_CAP` (default 2, the
"Mode 2027" behavior). Setting it to 0 disables the cap. It is a compile-time
constant resolved by a macro `if`; keep it compile-time — do not turn it into a
runtime branch.

## PR / commit conventions

- Run `make spec` before committing; the suite must pass.
- If a change alters generated tables, commit the regenerated binaries and
  `tables.cr` together with the generator change, and confirm the byte-for-byte
  reproduction invariant still holds.
- Keep `README.md` (human-facing) and this file (agent-facing) in sync when the
  API or workflow changes.