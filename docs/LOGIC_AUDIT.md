# Application logic audit — 2026-11-15

Scope: native macOS application, reviewed against current working-tree code. This began as a specification/source audit; the follow-up below implements and tests five corrections. It is not a proof of correctness. Existing dirty work was preserved; sources changed during the review, so conclusions apply to the cited mechanisms as inspected. Requirements remain in DECISIONS; mechanisms in ARCHITECTURE; this document owns the audit's proposed contracts, counterexamples and acceptance criteria.

## Follow-up status — 2026-11-15

| Finding | Status |
| --- | --- |
| L1 structural metadata | Fixed for new edits: shared save validation, coordinated PDF/manifest rollback journal, page/star/current-page updates and AI model invalidation. Existing invalid manifests remain preserved; AI history migration is still absent. |
| L2 reading-position retry | Fixed: cache advances only after successful persistence; save errors are surfaced. |
| L3 active removal | Fixed: flush before removal, abort on failure, clear buffers/history and cancel owned AI work. Delayed fake-provider completion cannot save after deletion. |
| L4 chat-delete errors | Fixed: persistence returns success and the failure remains visible. |
| L5 chat retention | Open product decision; existing policy unchanged. |
| L6 Unread definition | Open product decision; existing predicate unchanged. |
| L7 malformed optional store | Fixed preservation/duplicate-UUID guard and retry after external repair; no repair UI. |

The detailed counterexamples below describe the audited baseline; resolved behavior is specified in [STATE](STATE.md), the recovery protocol in [ARCHITECTURE](ARCHITECTURE.md#structural-save-and-recovery-boundary--2026-11-15), and fresh tests in [TESTING](TESTING.md#logic-recovery-fixes--2026-11-15).

## Model and assessment method

Let `S = (library, activeID, document, page, draft, pendingWriting, undo, redo, jobs, persistedFiles)`.
A command is a transition `T(S, input) -> (S', result)`. Check its precondition, successful postcondition, failure postcondition, and recovery path. `G(P)` means P must always hold at observable command boundaries. `F(P)` means P must eventually become true if the required resources become available. Intermediate main-actor mutations can occur inside a command; cross-file crash recovery needs its own durable protocol.

“Optimal” here means sufficient guards without blocking valid work, recoverable failures, bounded work, and clear user-visible outcomes. No measured latency/accuracy objective or representative dataset was supplied, so numerical thresholds cannot be certified optimal.

| Aspect / owner | Required formal contract | Assessment |
| --- | --- | --- |
| Import / LibraryRepository | Success implies valid unlocked nonempty PDF, unique managed ID, source bytes unchanged, copy and manifest present. Manifest-write failure implies no new entry and copy rollback attempted. | Strong normal/failure structure; crash between files can leave an orphan. Rollback cleanup errors are ignored. |
| Startup / LibraryRepository.load | `G(loaded => uniqueIDs ∧ pageCount > 0 ∧ 1 <= currentPage <= pageCount ∧ stars ⊆ validPages)`. Decode failure must preserve manifest and disable writes. | Shared load/save validation and recoverable structural metadata updates now cover L1. |
| Reader / Workspace | `G(reading => activeID exists ∧ document != nil ∧ 1 <= page <= document.pageCount)`. Only the current document/session may publish callbacks. | Open clamps pages; PDFCanvas tracks identity/session. `changedPage` now enforces the valid range; removal flushes and clears pending state (L3). |
| Annotation editing / PDFEditHistory | Successful save alone advances history; failure restores independent snapshots and keeps retry/Undo/Redo available. Changed pages must belong to the active document. | Strong central history checks and generated-fixture coverage; arbitrary PDF fidelity remains unproven. |
| Drafts / Workspace | Transition away from an edited document requires successful flush or explicit discard. Failure retains the same draft and input. | Navigation/export/quit/removal use the flush gate. Below-page writing is not crash-durable. |
| Page insertion / Workspace+Notes | PDF page count, record count, current page and stars must describe the same structure after insert/Undo/Redo. Failure must preserve a recoverable consistent state. | L1 corrected with a rollback journal; no power-loss/multi-process guarantee. |
| Resume settings / ReadingPositionStore | `set` success implies cached and durable values agree. Write failure preserves the prior committed cache so an identical retry still writes. | L2/L7 corrected: committed cache only, malformed input preserved, save errors surfaced. Invalid view values retain ReaderState sanitization. |
| AI / service, panel models | Provider call requires explicit action, valid question/page and chosen provider. Cancelled or obsolete results must not publish into a different document revision. Local persistence failure must remain visible and retryable. | Service budgets and cancellation checks exist; Skim has request/document guards. Structure/reopen replaces AI stores; chat delete keeps save failures visible (L1/L4). |
| Library organization / LibraryOrganizer | Filters must express a defined product predicate; sort ties should have stable ordering when needed. | “Unread” means current page <= 1 rather than never visited (L6). Equal title/date/author records have no explicit ID tie-breaker; lower priority. |
| Export / Workspace, StudyCopy | Flush first; export a detached serialization with intrinsic rotation; never mutate the imported source implicitly. Export failure leaves managed state intact. | Existing path rejects lexical managed-library descendants. Symlink/alias identity, arbitrary PDFs, image payloads and third-party viewer fidelity need a fixture/interaction matrix. Explicit save-panel overwrite is a separate user action. |
| Local Skim / Workspace+Skim | Publish only when request ID, document identity and enabled state still match. No network/PDF/history mutation. | Good ownership pattern. Confidence 0.5, block density and token limits are heuristics, not validated optima. |
| Credentials / ClaudeKeyStore | Credential operations must remain non-interactive; no secret in logs or provider child environment. | Source includes multiple non-interactive controls, but a restricted-run policy assertion failed but passed with host services (E1). No credential prompt behavior was inferred. |

## Findings and missing rules

### L1 — P1: writing-page edits can make the whole library fail validation

Owners: [Writing operations](../Sources/FolioMac/Workspace+Notes.swift), [PaperRecord](../Sources/FolioCore/PaperRecord.swift), [manifest load/save](../Sources/FolioCore/LibraryRepository.swift), and the AI loaders in PaperAssistantView/PaperReviewsView/PaperConceptGraphView.

Confirmed by source trace: `pageCount` is immutable in PaperRecord and never updated after insert/Undo/Redo. The operation saves the PDF, shifts stars in a separate manifest write, then navigates and saves currentPage in another write. `save` does not enforce the constraints that `load` enforces.

Counterexample: import N pages, append a writing page, navigate to N+1 (the insertion does this), then relaunch. The persisted record still says N pages but currentPage is N+1, so `load` rejects the library. Stars shifted beyond N can cause the same rejection. Inserting elsewhere still makes fresh AI loaders reject the PDF because they require actual pageCount == record.pageCount. Already-loaded AI state may retain the old text because `ensureAIStore` keys only on paper ID.

Needed: one structural transition updating count, stars and current page together; validate records before saving; recoverable coordination between PDF and manifest, including partial-write/crash recovery; invalidate or explicitly migrate AI snapshots/models when extracted text changes. Merely making pageCount mutable is insufficient.

Acceptance: append/middle insert, star shifts, structural Undo/Redo, then fresh Workspace and fresh AI load; fault injection at each write boundary; no invalid manifest accepted or stranded document. AI history fingerprint mismatch must preserve old files and explain recovery, rather than silently delete history.

### L2 — P2: failed reading-position writes poison the retry cache

Owner: [ReadingPositionStore.set](../Sources/FolioCore/ReadingPosition.swift), lines 30–36; ReaderState.scheduleSave swallows its error.

Confirmed: set mutates `positions[id]` before encoding/writing. If the write fails, a later identical set returns early because the cache already contains the unsaved value. The cache can claim success while disk has the old position, indefinitely until another different change.

Needed: construct a candidate dictionary, encode/write it, then publish the committed cache; retain a retryable dirty value or report failure at the caller. Acceptance: force write failure, restore the directory, retry the exact same position, instantiate a new store and verify the position.

### L3 — P1: removing the active paper can strand pending writing and jobs

Owner: [Workspace.removePaper](../Sources/FolioMac/Workspace.swift), and flushWriting/open; normal UI confirmation comes from LibraryView.

Confirmed transition defect: remove clears document/identity/editor/history but does not flush or clear pendingWriting. A pending value still references the deleted document's page. Every later open calls finishEditorIfNeeded -> flushWriting, which returns false when document is nil. There is no error at that guard, and opening another paper can remain blocked. An unsaved editor is also cleared without a dedicated flush/discard contract. This state is possible through Workspace; reachability through ordinary library navigation is narrower because that navigation normally flushes first.

Removal also does not explicitly cancel/nil aiStore or clear all paper-bound navigation/history state. An in-flight task can retain the old repository and finish after deletion; cancellation/recreation behavior needs a controlled task test.

Needed: define removal as explicit discard or flush-before-delete, execute that policy atomically at Workspace, then reset all paper-bound pending/history/AI/request state. Acceptance: remove with a pending writing buffer, failed save, open editor and delayed fake provider; another paper must open, no late write recreates removed history, and the user's chosen discard/save semantics must be observable.

### L4 — P2: chat deletion suppresses persistence errors

Owner: [PaperAssistantModel](../Sources/FolioMac/PaperAssistantView.swift), lines 57–63.

Confirmed: persist catches a write failure and sets error; delete immediately executes `error = nil`. Threads stay unchanged, but the failure explanation disappears.

Needed: persist returns success/failure; clear stale error/retry only on success. Acceptance: make the threads path unwritable, delete, verify unchanged disk/in-memory threads and visible failure, repair path, retry successfully.

### L5 — P2 product policy risk: creating chat 41 silently evicts saved history

Owner: [AssistantThreads.newThread](../Sources/FolioCore/AssistantThreads.swift), lines 33–37.

Confirmed policy: when 40 nonempty threads exist, creating one removes the oldest in-memory thread. Sending in the new thread then persists that removal. The user chose New Chat, which provides no distinct deletion decision in this model. newThread/select are also memory-only until another persistence action, so “active chat” restoration is not consistently durable.

Needed decision: reject creation with an explanation, archive, or require an explicit deletion policy. A memory/context budget does not itself require deleting durable conversations. Acceptance: capacity boundary 39/40/41, empty-chat reuse, save failure, reopen before/after first Send. This audit recommends retaining saved history; it does not introduce that product requirement unilaterally.

### L6 — P2 semantic ambiguity: “Unread” is a page-position predicate

Owner: [LibraryOrganizer](../Sources/FolioCore/LibraryOrganizing.swift), line 28; PaperRecord.lastVisit already distinguishes visits.

Confirmed: a one-page paper remains Unread forever, and returning a read paper to page 1 makes it Unread again. Tests currently encode this behavior.

Needed decision: if the label means never opened, use lastVisit == nil (respecting legacy inference). If it means not progressed, label/document that predicate or use explicit reading status. Acceptance: never opened, visited one-page paper, return to page 1, and legacy records. Do not infer completion merely from reaching the final page.

### L7 — P2 recovery gap: malformed reading-position data is silently overwritten

Owner: [ReadingPositionStore.init](../Sources/FolioCore/ReadingPosition.swift), lines 20–25.

Confirmed: any read/decode failure becomes an empty dictionary; the next save overwrites the previous file. This differs from the manifest's fail-closed recovery contract, though resume settings are lower impact than PDF contents.

Needed: distinguish absent file from invalid/unreadable file; preserve/quarantine malformed data and surface reset/recovery before replacing it. Acceptance: truncated JSON, permission/read failure, future incompatible values, then a set; original bytes remain available. Also normalize duplicate textual UUID representations before Dictionary(uniqueKeysWithValues:) to avoid a trap if differently cased keys decode to the same UUID.

### E1 — resolved environment-dependent verification discrepancy

A fresh full core run fails `CredentialSessionTests.testEveryKeychainOperationUsesNonInteractivePolicy` at line 46: the returned LAContext does not report interactionNotAllowed == true in this execution environment. Other policy controls exist, including kSecUseAuthenticationUIFail and legacy process interaction disabling. This result alone does not establish that a password prompt appears or that a credential is exposed.

A full rerun with host AppKit services passed this assertion and all 146 tests (two live-provider skips). The restricted result is environment-dependent evidence, not a confirmed application defect. No protections were changed to obtain the passing result and no real credential writes were added. Exhaustive live credential-operation interaction behavior was not checked.

## Verification design and ordering

L1/L2/L3/L4/L7 now have bounded regression coverage. Settle L5/L6 before changing retention/reading semantics; the remaining verification matrices below still apply. Existing [PDF verification design](PDF_EDITING_VERIFICATION.md) remains authoritative for annotation fidelity.

For each command, test a valid input, invalid/stale identity, successful persistence, failed persistence, identical retry, cancellation and fresh reload where applicable. For asynchronous work, delay an injected provider, switch paper/revision or remove the paper, then release completion. A result may publish only if its captured `(paperID, documentRevision, requestID)` still owns the destination.

Add bounded model-based command sequences over import/open/go/star/edit/insert/Undo/Redo/remove/relaunch. At every completed transition assert valid pages/stars, source-byte preservation, valid manifest, and a recoverable pending state. Existing PDFEditingTests already contain a bounded independent history-model test; broaden orchestration coverage rather than duplicating implementation branches.

Missing runtime matrices: disk full/permission failures across both PDF and metadata, cancellation after response before save, corrupt optional stores, structural edits followed by every AI feature, removal during work, symlink/alias export destinations, rotated/cropped selection and third-party PDF export. Multiple simultaneous writers remain unsupported; a lock/version check is needed before claiming safe multi-instance use.

Performance and heuristic optimization require evidence: measure main-actor blocking and peak memory on representative large PDFs/folders; assess Skim precision/recall by facet on a held-out labeled corpus; assess retrieval answer support/coverage before changing excerpt and context budgets. Fixed thresholds cannot establish semantic accuracy or absence of omitted evidence.

## Fresh evidence

See [TESTING](TESTING.md#logic-recovery-fixes--2026-11-15) for follow-up commands/results. L1/L2/L3/L4/L7 now have executable regression cases; L5/L6 remain source-level policy observations. E1 records an environment-dependent assertion failure resolved by the host-service rerun. The follow-up changes the resolved behaviors above. No formal model checker was run and no full correctness/optimality claim is made.


## Correctness and performance follow-up — 2026-11-16

Request: identify native application gaps, implement confirmed corrections and assess optimization needs. Reviewed the dirty working tree; preserved existing work. This is a bounded source/regression audit, not an exhaustive interaction or performance certification.

| Finding / trigger | Resolution and acceptance evidence |
| --- | --- |
| P1: Export's lexical prefix guard allowed a symlinked parent to point into the managed library. A new filename also defeats naive whole-URL link resolution. | `LibraryRepository.allowsExport` resolves the nearest existing ancestor and appends missing components, then compares resolved path components against the resolved root. Workspace checks before serializing/writing. Fixtures cover direct paths, linked root/parents/files, new destinations and similarly named external siblings. Not a filesystem race or multi-process isolation guarantee. |
| P2: Custom zoom lost its saved scale after first restoration; another `applyFit` fell back to Fit Page. | Custom mode uses the pending restored zoom once, then the current valid scale. Rotation, two-page layout, repeated fit and saved settings have generated-PDF regression coverage. |
| P2: The 500 ms view save read paper identity and mutable view state after the delay. A switch could lose the old settings or associate them with a new paper. | Capture store, paper ID and settings together; flush at document changes and editor/navigation/quit gates. Failed snapshots stay pending per paper for retry. Tests switch before debounce, verify fresh disk state and retry a failed write after a switch. Pending failures remain memory-only on process termination. |
| P2 optimization: `.task(id: workspace.papers)` rescanned every library PDF after changes to titles, stars or reading metadata. | Scan identity now consists of paper IDs, document session and PDF revision. Metadata changes no longer invalidate the scan; import/remove/reopen/edit still do. Full scans remain synchronous, and returning to a newly mounted library still scans. This removes redundant triggers; no measured end-to-end speedup claimed. |
| P2 keyboard conflict: both Go to Page and Paper at a Glance used Option-Command-G. | Preserve Go to Page; move Paper at a Glance to Shift-Option-Command-G. Source check/build only; physical keyboard/menu interaction remains pending. |

### Remaining checks and decisions, in priority order

1. **Durable conversation retention (L5):** settle capacity behavior before changing the 40-thread eviction policy or 96-turn truncation. Suggested acceptance: 39/40/41 saved chats, long-chat boundary, reopen, failed save and explicit deletion. Existing behavior remains unchanged.
2. **Large-document responsiveness (Q4):** measure main-thread stalls, peak memory and import/export latency on disposable text-heavy and image-heavy PDFs at several page/library sizes, including structural rollback journals. Then move independent file/manifest work into a bounded worker and cooperatively batch PDFKit traversal where safe. Keep live PDFKit objects on the main actor. No evidence currently justifies numerical speedup or memory targets.
3. **PDF fidelity:** generated rotated/cropped/multi-column and third-party annotation/form/signature fixtures, cross-page pointer selection, save/export/reopen and external-viewer checks. Source preservation and generated fixtures do not certify arbitrary PDF export.
4. **Runtime integration/accessibility:** disposable Finder/drop/save-panel flows (including the symlink rejection), physical shortcuts, VoiceOver/focus, narrow/dark/high-contrast/Reduce Transparency, older supported macOS, and actual timer drag behavior. New tests use AppKit/PDFKit programmatically; no fresh full interactive pass was performed.
5. **Provider/network paths:** explicitly opted-in Claude/OpenReview/arXiv and long-paper answer-support checks; no real provider request was made in this audit.
6. **Unread semantics (L6):** decide whether this means never visited or no page progress; keep the current page-one predicate until settled. Multi-instance storage coordination, OCR, migration and production distribution remain larger feature gaps, not implemented by this audit.

Fresh commands, outcomes and limitations are recorded in [TESTING](TESTING.md#correctness-and-performance-audit--2026-11-16).
