# Tests

Read root and source rules. Generate fixtures in a UUID temporary directory and clean up only that directory. Never import or write real research files or default Application Support data in automated tests. Favor persistence/failure recovery, original-byte preservation and PDF annotation round trips over tests that mirror view declarations. Record actual commands/results in TESTING; GUI checks remain separate.
