# The documentEvents map

This map is different from the other 135, and it is what makes in-flight work correct. It lands the event feed like any other map - and because landing is append-only, that is all it does. It writes no _rowState anywhere.

The exit is DERIVED. bcModel.vw_documentExit resolves the event feed to one exit per document, and the bc views join it, so a document reads as Posted, Cancelled or Deleted because an event says so rather than because a map stamped it. Land the events correctly and the state follows; there is no apply step to get wrong, and no ordering window in which a report can see a stale state.

Its cursor is sequence, not lastModifiedDateTime. Sequence is a monotonic gapless event number, which is strictly better than a timestamp here: a resume needs no overlap window because there is no commit-versus-write skew to tolerate.

manifest.json carries documentEventExits, a generated list of 77 rules that is the map's instruction set. Each rule names an event type, the warehouse table it affects, how to match the row, and the state to set:

{
 "eventType": "salesDocumentDeleted",
 "documentType": "Quote",
 "table": "bc.salesQuotes",
 "matchOn": "documentId = id, falling back to documentNumber = number when documentId is blank",
 "setRowState": "Deleted",
 "setExitRef": null
}

There are three exits and only three: posted, cancelled and deleted. Archiving is not an exit, because Business Central takes a snapshot and leaves the document open.

### Order still matters

Run the documentEvents map first in each cycle. Because the exit is derived rather than stamped, running it late no longer writes a wrong state - it just means a document that has already left Business Central still reads as open until the events land. Running it first keeps that window as short as the schedule allows.

---

[Back: Build the maps](05-build-the-maps.md) | [Contents](README.md) | [Next: Schedule](07-schedule.md)
