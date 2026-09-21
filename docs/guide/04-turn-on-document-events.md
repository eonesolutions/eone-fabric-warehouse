# Turn on Document Events

In Business Central, open eOne Integration Setup and switch on Document Events.

This is not optional, and it is the step most likely to be missed. A watermark pull sees inserts and updates but never sees a row leave, so without this feed a posted or deleted sales order stays in the warehouse as an open document forever. While the feature is off the feed returns an error rather than an empty page, which at least fails loudly.

Add Posted Document Status Events only if you act on settlement. Recording those means watching every customer and vendor ledger entry application, which is real work in Business Central for a signal many warehouses do not use.

---

[Back: Create the warehouse](03-create-the-warehouse.md) | [Contents](README.md) | [Next: Build the maps](05-build-the-maps.md)
