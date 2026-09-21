# Known limits

Stated here rather than discovered later.

An event can be lost silently

The documentEvents feed is an outbox written in the caller's transaction. If the row is written and the map never reads it before the retention window closes, the exit is gone and the document stays Active. Watch the cursor gap rather than assuming delivery.

Retention bounds replay

Events are purged after 7, 14 or 28 days. A map stopped for longer than the window cannot catch up by replaying; it needs a reload of the affected feeds.

The feature is off by default

Document Events can also be switched off mid-stream. While it is off, exits are not recorded at all, and turning it back on does not backfill them.

Backlog over time is not captured

The warehouse holds current state and posted history. It does not snapshot the open document set daily, so "what did the backlog look like last Tuesday" cannot be answered retrospectively. Unlike everything else here this cannot be backfilled, because Business Central deletes the open document when it posts. Schedule a capture of vw_openDocumentAging into your own table if you need it, and start early.

Re-running the deployment discards data

The table DDL drops and recreates. That is how you pick up a product upgrade, and it costs a reload rather than data for everything except the exited rows above.

---

[Back: What you get](10-what-you-get.md) | [Contents](README.md) | [Next: Appendix A. Entity set reference](12-appendix-a-entity-set-reference.md)
