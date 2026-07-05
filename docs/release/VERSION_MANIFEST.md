# AtlasEA v1.0.0 — Version Manifest

## Project Identity
- **Name:** AtlasEA
- **Version:** 1.0.0
- **Status:** Production Release
- **Release Date:** 2025-01-05
- **Platform:** MetaTrader 5
- **Language:** MQL5

## Frozen Items

| Item | Status | Hash/Version |
|------|--------|-------------|
| Folder Structure | FROZEN | 37 folders, 258 files |
| Architecture | FROZEN | Event-driven 4-phase pipeline |
| Interfaces | FROZEN | 51 interfaces |
| Configuration | FROZEN | AtlasConfig with mm_*, tcm_*, profile_*, safety, performance fields |
| Event Formats | FROZEN | AtlasEvent (13 types, 256-byte payload) |
| Persistence Format | FROZEN | Key=value text snapshot + CSV event log |
| Replay Format | FROZEN | SourcedEvent with EventMetadata |
| Recovery Format | FROZEN | Snapshot + event log integrity check |
| Public APIs | FROZEN | All I* interfaces |

## File Count by Category

| Category | Files | Lines |
|----------|:-----:|:-----:|
| Core | 24 | ~5,000 |
| Interfaces | 51 | ~4,000 |
| Engines | 27 | ~5,000 |
| Infrastructure | 9 | ~3,000 |
| Contracts | 3 | ~500 |
| Diagnostics | 8 | ~2,000 |
| Strategies | 8 | ~1,600 |
| Trading | 27 | ~6,000 |
| Profiles | 3 | ~1,000 |
| Validation | 14 | ~4,000 |
| Optimization | 6 | ~2,000 |
| Production | 6 | ~1,600 |
| Performance | 5 | ~1,400 |
| Recovery | 5 | ~1,500 |
| Replay | 7 | ~2,000 |
| Config | 14 | ~2,000 |
| Testing | 8 | ~2,000 |
| Audit | 4 | ~1,000 |
| Plugins | 4 | ~1,000 |
| StrategySDK | 6 | ~1,000 |
| Events | 7 | ~1,500 |
| Entry Point | 1 | ~150 |
| Docs/Specs/Tests | 16 | ~5,000 |
| **TOTAL** | **258** | **~58,000** |

## Schema Versions

| Schema | Version |
|--------|---------|
| Validation Schema | 2 |
| Validation Report | 2 |
| AtlasConfig | 1 (v1.0) |
| Event Format | 1 (AtlasEvent) |
| Snapshot Format | 1 (key=value text) |

## License
Proprietary. All rights reserved.
