-- =====================================================================
-- eOne Integration for Business Central -> Microsoft Fabric Warehouse
-- 01 — Schemas
--
-- Fabric Warehouse has no CREATE DATABASE: the warehouse itself is a Fabric
-- workspace item, created in the portal or by Deploy-EOneWarehouse.ps1
-- -CreateWarehouse. Everything from here down is inside that warehouse.
--
--   bcRaw    what the maps INSERT into: every version of every row they
--            have seen, never updated and never deleted. One table per
--            published Core entity set.
--   bc       the contract everything else is written against: one row per
--            record, resolved from bcRaw as the latest version per id,
--            with _rowState derived from the document event feed.
--   bcModel  the views Power BI points at, plus the calendar dimension.
--            Prefixed, because this is the customer's warehouse and
--            `model` is both a common noun and a SQL Server system
--            database name.
--
-- The maps only ever INSERT. Fabric Warehouse has no table hints and no
-- upsert a scheduled map can use, so rather than bolt staging tables and a
-- generated MERGE onto every feed, nothing is ever rewritten: bcRaw is
-- append-only and bc resolves it on read. Replay, overlap and retries stop
-- being correctness problems and become duplicate rows the view collapses.
--
-- Three schemas, and the only table outside bcRaw is bcModel.dimDate. The
-- warehouse holds data and views; everything that MOVES data - cursors,
-- the load plan, run history - belongs to the integration that owns the
-- schedule, not to a stored procedure here.
--
-- Core only. Core is the app that ships; the Project and Service add-ons
-- are not in the ship set, and the API queries are joined projections of
-- data the pages already land.
-- =====================================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bcRaw')    EXEC ('CREATE SCHEMA [bcRaw]');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bc')     EXEC ('CREATE SCHEMA [bc]');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bcModel')  EXEC ('CREATE SCHEMA [bcModel]');
GO
