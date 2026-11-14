# PDF editing verification design

Research and case design, 2026-11-14. This document describes the method and acceptance cases; actual executed results belong in [TESTING](TESTING.md). It is not a certification of PDFKit, a proof of arbitrary PDF fidelity, or evidence that every case has run.

## Public primary material

- [TLA+ / TLC source, MIT licensed](https://github.com/tlaplus/tlaplus): describes systems with states and transitions, and checks specifications with a model checker. Useful here for specifying transaction/history/document identity invariants independently of view code. A finite checked model establishes properties only for its modeled state space; connecting that model to production PDFKit operations still requires tests.
- [Hypothesis stateful testing](https://hypothesis.readthedocs.io/en/latest/stateful.html): generates sequences of actions and checks invariants after each step. Apply the method with dependency-free Swift/XCTest enumeration or deterministic generated sequences; installing Python Hypothesis is unnecessary. This is model-based testing, not a mathematical proof of the implementation.
- [Mozilla PDF.js highlight integration cases, Apache 2.0](https://raw.githubusercontent.com/mozilla/pdf.js/master/test/integration/highlight_editor_spec.mjs) and [FreeText integration cases](https://raw.githubusercontent.com/mozilla/pdf.js/master/test/integration/freetext_editor_spec.mjs): practical examples cover serialized annotation data, selection after scrolling, color changes, editing and copying text. Borrow the observable cases, not the browser implementation.
- [PDF Association public ISO 32000-2 errata, interactive features](https://pdf-issues.pdfa.org/32000-2-2020/clause12.html): reference for annotation dictionaries, appearance streams, markup and FreeText. Use page coordinates and standard annotation types, retaining PDF page content rather than rebuilding pages.
- [qpdf CLI reference](https://qpdf.readthedocs.io/en/stable/cli.html): a useful optional independent structural check. Its documentation explicitly notes that it cannot detect all PDF problems. A successful structural check cannot replace rendering and roundtrip editing checks.
- [Apple WWDC22 PDFKit saving example](https://developer.apple.com/videos/play/wwdc2022/10089/) (10:22 and 10:35): primary platform sample for a custom stamp subclass, drawing override and private annotation data. PDFKit records custom drawing in the saved appearance stream. Preserve PNG data in a private key to reconstruct an editable image after reopening. The sample is platform guidance, separate from the open-source formal-methods material above.

All links were retrieved during this research. No user PDF or document text was sent to those sources.

## Model and implementation boundary

Model state as `(document identity, annotation groups, selected group, active tool, undo stack, redo stack, left panel, notes panel)`. Actions include add, replace, delete, undo, redo, no-op, failed save, switch document, select tool and toggle panels. Give each logical annotation a stable group ID; several line marks may share that ID. Prefer before/after replacement transactions over mutating a live object in place because snapshots make inverse edits and rollback explicit.

Use a small, independent reference history model and compare actual transactions after every generated action. Enumerate short sequences over a bounded alphabet, with at least two documents and two annotation IDs. Report the action alphabet, sequence bound and number checked. An exhaustive finite transition-model check is a formal check of that model; executing finite histories against Swift/PDFKit is bounded model-based testing. Neither proves all runtime behavior. A model that simply duplicates production functions gives weak evidence.

Global invariants:

1. Successful edits update only the active managed document. Source bytes never change.
2. A failed save restores the exact preceding annotation state and does not create a history entry. A subsequent successful edit remains possible.
3. Undo restores the semantic before-state; redo restores the semantic after-state. One gesture or multiline selection is one transaction. A new edit after undo clears redo.
4. Cancel, empty input and off-page/no-hit gestures do not save or consume Undo. Switching documents clears selection, pending gesture and cross-document history.
5. Every newly created annotation has finite, nonempty page-space bounds; IDs and group membership survive save/reopen. Hit testing chooses the topmost visible supported markup annotation and never erases a link, form field or unrelated annotation.
6. Page count, media/crop boxes, rotation, extracted source text and existing unrelated annotations survive editing/export. Notes contain written comments or attachments, never bare marks or ordinary text boxes.

## Per-tool acceptance cases

| Area | Cases | Observable invariant / check |
| --- | --- | --- |
| Select | Drag source text; click a mark/text/note/image; click empty canvas; Escape; type in editor | Source selection/copy works; annotation selection is exclusive; shortcuts never fire while typing; no edit on selection alone. |
| Highlight | One line; multiple lines; across pages; four colors; select first then choose tool; choose tool then select | Correct line regions; one group/Undo; no permanent tool switching required for a preexisting selection; selected color survives reopen. |
| Underline | Same selection cases; mixed line lengths; cropped/rotated pages | Lines follow selected text rather than a combined whitespace rectangle; same grouping/history guarantees as Highlight. |
| Color/edit mark | Pick existing group; change color; add/update/remove its comment; cancel editor | All regions share one color/comment; edit is reversible; written comment appears once in Notes, bare group does not. |
| Text | Click blank page; enter multiline/Unicode; edit existing; change font size/color; move/resize; empty/cancel | Standard editable FreeText persists; bounds contain visible text and stay on page; one completed change per Undo; source PDF text unchanged. |
| Note | Click point; attach to selection; edit/delete; whitespace-only; cancel; document switch during editing | Anchor is captured at start; no duplicate notes on editing; group comment shown once; cancel leaves no empty pin or history. |
| Eraser | Single hit; drag across groups; overlap; empty space; original foreign annotations | Only supported markup objects removed; one drag is one Undo; stable original ordering restored; unrelated PDF objects untouched. |
| Image paste | PNG/JPEG clipboard; large/tall/wide image; resize/move; delete; reopen and resave | Aspect preserved; visible on independent reopen; PNG/private data and geometry retained; no flattened/rebuilt page; unavailable clipboard is a no-op. |
| History/save | Add→edit→delete→undo×3→redo×3; undo→new edit; forced write failure; reopen; two documents | Compare semantic annotation snapshots after every step; rejected write restores memory/disk; history never targets another document. |
| Navigation/panels | Open PDF; toggle Pages/Outline and Notes; return Library; narrow window; Find/zoom/page/star | Library navigation does not occupy a second reader sidebar; panels are optional and mutually intelligible; canvas retains usable width; no inactive feature tabs. |
| Export | Generated fixture with source text, link, marks, comments, FreeText and image; reopen in PDFKit and another renderer if available | Annotation semantics and visual appearance retained, source bytes/geometry/text unchanged; record renderer/version and explicit fixture limits. |

Cross every geometry-sensitive tool with media box origin `(0,0)`, nonzero crop origin, page rotations `0/90/180/270`, zoom/scroll and near-edge gestures. Check both page-coordinate data and rendered position; a roundtrip bounding-box assertion alone cannot establish visual correctness. Render image stamps before and after resaving a reopened document to catch missing appearance streams or lost subclass data.

## Interaction decisions informed by the cases

Keep Select/Highlight/Underline/Text/Note/Eraser visible in one compact row. Show text formatting or mark editing only for the relevant selection. Applying a mark to an already selected passage should work immediately; an active marking tool should also apply to the next selection. A note editor needs a stable captured anchor and appears beside that target; opening the Notes panel remains optional. Notes remains a focused written-notes view, not an inventory of all annotation types.

Hide application/library navigation during reading, with an obvious return-to-library action. Provide independent Pages/Outline and Notes controls; start with the PDF taking the available space and reveal supporting panels on demand. Do not add confirmations for reversible annotation edits: Undo/Redo supplies recovery. Unimplemented AI tabs and placeholder overview content do not belong in this editing flow.
