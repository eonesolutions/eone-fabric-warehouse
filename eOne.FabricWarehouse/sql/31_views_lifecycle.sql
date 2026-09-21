-- =====================================================================
-- 31 — Lifecycle views (schema model)
--
-- Point Power BI here, not at [bc].
--
-- All three are built on [bcModel].[vw_documentHistory] (generated, file 30),
-- which unions every in-flight document feed onto one column vocabulary. How
-- many that is comes from the generator and moves when the API surface does,
-- so it is not repeated here. The distinction that matters:
--
--   vw_openDocuments      what is in flight RIGHT NOW
--   vw_documentLifecycle  every document ever seen, and how it ended
--   vw_openDocumentAging  today's open book bucketed by age
--
-- vw_documentLifecycle is the one Business Central itself cannot give you.
-- BC deletes the sales order when you post it; the order and the invoice
-- never coexist there. Here they do, so quote-to-cash cycle time, cancel
-- rates and abandoned-quote analysis are ordinary queries.
-- =====================================================================

DROP VIEW IF EXISTS [bcModel].[vw_openDocuments];
GO
CREATE VIEW [bcModel].[vw_openDocuments] AS
SELECT *
FROM [bcModel].[vw_documentHistory]
WHERE [_rowState] = 'Active';
GO

DROP VIEW IF EXISTS [bcModel].[vw_documentLifecycle];
GO
CREATE VIEW [bcModel].[vw_documentLifecycle] AS
SELECT
    h.[entitySet],
    h.[side],
    h.[documentType],
    h.[id],
    h.[documentNumber],
    h.[integrationId],
    h.[status]        AS bcStatus,
    -- The lifecycle state, straight off the row. Active | Posted | Cancelled | Deleted.
    --
    -- There is no CASE here any more and no 'Unexplained' bucket: _rowState is the single column
    -- that holds it, so a flag and a reason can no longer disagree. Archiving is deliberately not a
    -- state - BC's archive snapshots the document and leaves it open, so it annotates a document
    -- rather than ending it.
    --
    -- A missed event does NOT show up here as a distinct state; it leaves the row Active forever.
    -- bcModel.vw_dqEventsWithoutDocument is where a missed event shows up: an exit recorded
    -- for a document the warehouse never landed.
    h.[_rowState]     AS lifecycleState,
    h.[_exitRef]      AS becameDocumentNumber,
    h.[partyNumber],
    h.[partyName],
    h.[currencyCode],
    h.[orderDate],
    h.[documentDate],
    h.[dueDate],
    h.[requestedDate],
    h.[promisedDate],
    h.[locationCode],
    h.[personCode],
    h.[externalDocumentNumber],
    h.[amountExcludingTax],
    h.[taxAmount],
    h.[amountIncludingTax],
    h.[fullyHandled],
    -- The FIRST load, not the latest. _loadedAt on the surviving row moves every time the
    -- document changes, so using it here made "first seen" drift forward week by week.
    h.[_firstLoadedAt] AS firstSeenUtc,
    h.[_exitedAt]    AS exitedUtc,
    -- How long it was in flight: to its exit if it has one, to now if not.
    DATEDIFF(day, h.[documentDate], CAST(COALESCE(h.[_exitedAt], SYSUTCDATETIME()) AS date)) AS daysInFlight,
    h.[dimensionSetId],
    h.[dimension1Code],
    h.[dimension1Name],
    h.[dimension1ValueCode],
    h.[dimension1ValueName],
    h.[dimension2Code],
    h.[dimension2Name],
    h.[dimension2ValueCode],
    h.[dimension2ValueName],
    h.[dimension3Code],
    h.[dimension3Name],
    h.[dimension3ValueCode],
    h.[dimension3ValueName],
    h.[dimension4Code],
    h.[dimension4Name],
    h.[dimension4ValueCode],
    h.[dimension4ValueName],
    h.[dimension5Code],
    h.[dimension5Name],
    h.[dimension5ValueCode],
    h.[dimension5ValueName],
    h.[dimension6Code],
    h.[dimension6Name],
    h.[dimension6ValueCode],
    h.[dimension6ValueName],
    h.[dimension7Code],
    h.[dimension7Name],
    h.[dimension7ValueCode],
    h.[dimension7ValueName],
    h.[dimension8Code],
    h.[dimension8Name],
    h.[dimension8ValueCode],
    h.[dimension8ValueName],
    h.[lastModifiedDateTime],
    h.[bcCompanyId],
    h.[bcCompanyName],
    h.[_environment]
FROM [bcModel].[vw_documentHistory] h;
GO

DROP VIEW IF EXISTS [bcModel].[vw_openDocumentAging];
GO
CREATE VIEW [bcModel].[vw_openDocumentAging] AS
SELECT
    [entitySet],
    [side],
    [documentType],
    [id],
    [documentNumber],
    [status],
    [partyNumber],
    [partyName],
    [currencyCode],
    [amountExcludingTax],
    [documentDate],
    [dueDate],
    [requestedDate],
    DATEDIFF(day, [documentDate], CAST(SYSUTCDATETIME() AS date)) AS ageDays,
    CASE
        -- Explicit, because a NULL documentDate makes every test below evaluate UNKNOWN and the
        -- CASE falls through to ELSE. That silently reported brand-new documents as the oldest
        -- bucket. An undated document is not old, it is undated.
        WHEN [documentDate] IS NULL THEN 'Unknown'
        WHEN DATEDIFF(day, [documentDate], CAST(SYSUTCDATETIME() AS date)) <=  7 THEN '0-7'
        WHEN DATEDIFF(day, [documentDate], CAST(SYSUTCDATETIME() AS date)) <= 30 THEN '8-30'
        WHEN DATEDIFF(day, [documentDate], CAST(SYSUTCDATETIME() AS date)) <= 60 THEN '31-60'
        WHEN DATEDIFF(day, [documentDate], CAST(SYSUTCDATETIME() AS date)) <= 90 THEN '61-90'
        ELSE '90+'
    END AS ageBucket,
    CASE WHEN [dueDate] IS NOT NULL AND [dueDate] < CAST(SYSUTCDATETIME() AS date) THEN 1 ELSE 0 END AS isOverdue,
    [locationCode],
    [personCode],
    [dimensionSetId],
    [dimension1Code],
    [dimension1Name],
    [dimension1ValueCode],
    [dimension1ValueName],
    [dimension2Code],
    [dimension2Name],
    [dimension2ValueCode],
    [dimension2ValueName],
    [dimension3Code],
    [dimension3Name],
    [dimension3ValueCode],
    [dimension3ValueName],
    [dimension4Code],
    [dimension4Name],
    [dimension4ValueCode],
    [dimension4ValueName],
    [dimension5Code],
    [dimension5Name],
    [dimension5ValueCode],
    [dimension5ValueName],
    [dimension6Code],
    [dimension6Name],
    [dimension6ValueCode],
    [dimension6ValueName],
    [dimension7Code],
    [dimension7Name],
    [dimension7ValueCode],
    [dimension7ValueName],
    [dimension8Code],
    [dimension8Name],
    [dimension8ValueCode],
    [dimension8ValueName],
    [bcCompanyId],
    [bcCompanyName]
FROM [bcModel].[vw_documentHistory]
WHERE [_rowState] = 'Active';
GO
