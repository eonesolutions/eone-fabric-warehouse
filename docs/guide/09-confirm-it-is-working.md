# Confirm it is working

bcModel.vw_loadHealth reports, per entity set and company, the row count, the exited row count, when a map last wrote, and how current the source data is. It reads the landed rows rather than a bookkeeping table, so it measures what actually happened rather than what a loader claimed. Alert on lastLoadedUtc going stale.

bcModel.vw_dataQuality answers the question load health cannot: not whether the maps ran, but whether what landed hangs together. Every map can be green while a header never arrived for lines that did. No rows means clean.

Then point Power BI at the bcModel schema. The reports are already there.

---

[Back: The first load](08-the-first-load.md) | [Contents](README.md) | [Next: What you get](10-what-you-get.md)
