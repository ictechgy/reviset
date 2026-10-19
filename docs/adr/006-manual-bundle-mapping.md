# ADR-006: explicit same-version supplied-PDF page decisions

Status: implemented in working engine53; strict Swift and full200 regression pass. Frozen source review and actual new app qualification are pending. Native52 remains the qualified interim package, not product completion.

Use a separate fixed-scope native sheet for one revision containing one PPTX and one supplied PDF. Keep adjacent-version mapping/split/merge validation unchanged. Single-file revisions stay fully valid.

## Canonical decision and source contract

Introduce schema0.4.0/current engine0.4.0-native.bundle.53, retaining0.1/0.2/0.3 reads and exact archived44/45/50/51 range kernels. Archive the current reference helper as well before changing it: historical50/51 diff imports must not inherit new human-reference semantics.

A decision binds the observed report, revision occurrence, both original asset hashes, primary source page, optional supplied PDF page, link/unlink action, nonblank verbatim reason and prior displaced pairs. IDs deterministically include preceding log state and the actual source/target similarity score. Preserve `bundle_mapping_basis` as the raw automatic associations before manual changes; replay requires the exact displaced set, including score, origin and prior decision identity. The final effective mapping must equal that replay, including explicit unlinks and displaced sources. A first decision on an old52 report seeds the validation copy from its unmodified raw mapping; a history already present without a basis fails closed. Engine53 independently reconstructs that basis from actual asset extraction and rejects baseline drift. Reasons are bounded to2000UTF16 units. Append decisions; reversal is a new decision. Current manifest/report include the log in mapping identity. Reordering inputs invalidates active mappings while immutable old reports retain their history.

A link is1:1. Record every conflicting prior source/target pair, including its inferred/human origin and prior decision ID; show those effects and prior human reasons before one Apply action. A displaced source is explicitly unlinked, rather than automatically filled with another PDF page. Unlink is source-wide: its wording says so, and any recorded prior pair must belong to that source. An empty source can also receive an explicit no-PDF directive. Do not allow unsupported handout1:N through this API.

Validate project/report/latest/draft CAS, exact occurrence and PPTX/PDF endpoint ownership, both source asset hashes, reason/cardinality and log consistency. A stale sheet retains edits and shows an error; it does not resubmit automatically. Save the dirty draft and run analysis; cancellation leaves that draft pending and the prior report readable. No user source bytes are overwritten.

## Appearance authority

Raw OOXML elements/text/notes/hidden state and raw supplied PDF pages remain independent. A human link is labelled `사용자 연결 · 참고용`; it does not authenticate an export or prove a PPTX graphical edit. Use a typed human appearance annex with original PDF identity/transform and available native raster plus decision ID/reason. Preserve all text mismatch, geometry, stale/reused-PDF, OCR and fidelity warnings. Missing raster yields a comparison gap rather than invented pixels.

Run existing full-bundle automatic qualification on raw associations first. Keep an automatic appearance only if its original qualified pair survives the manual decisions unchanged. Clear displaced/explicitly unlinked automatic appearances. Partial raw bundles do not gain broader automatic qualification. Explicit human links can provide their own selected pages, with persistent warnings. The same PDF reused with different PPTX assets still fails automatic qualification; a human association retains the reuse warning.

Defer LO when every visible primary page has an eligible automatic/human appearance. For partial appearance, prepare the full conversion on clones and merge preview/raster/capability/gaps only into unreferenced pages. Do not mutate raw parse cache or attach a reference raster as Page.raster. Hidden/missing previews remain explicit.

Compare actual raster provenance/environment/geometry only. Supplied-PDF observations remain inferred associations and actual PDF evidence, including source-unchanged PDF differences as review gaps. Cross-renderer comparisons retain gaps. Read-only query/MCP never renders or mutates.

## Native flow and shared queries

Entry only for a bundle version; freeze project/report/revision at sheet open and load the snapshot-scoped draft/assets. Past/dirty reports allow history/reference inspection while Apply stays disabled. Lazy searchable primary/PDF page lists, selected source structure/current display and selected PDF preview. Do not present a provided PDF as an independent PPTX rendering. Show current association, exact proposed displacement and persistent warnings, reason field, source-wide unlink and Apply. Save by explicit button, preserving Hangul composition and unsaved edits on failure.

Use a bounded shared `list_bundle_decisions` query with occurrence/source/decision filters and reason offsets/length. Include full typed decisions in JSON/JSONL/Markdown export. Native bridge exposes compact bundle metadata/page payload and a scoped write action; MCP exposes only the shared read query. All evidence retains actual source hashes/pages and human/inferred provenance.

## Additional native fixes in the same cycle

The latest explicit page Picker/go action supersedes older evidence/history pins. Regression: evidenceA -> manualB -> range refresh retainsB. Show split/merge page sets as `p.1 -> p.1, p.2`, with one arrow between versions. Import copy explicitly mentions optional PPTX+PDF bundles. Deduplicate generated version prefixes when the supplied label already equals vN.

## Acceptance

- Reordered/partial/duplicate/image-only PDFs; link/unlink/relink/displacement; same-source and target conflicts; missing/wrong hashes and cross-revision/project/format rejection.
- Human reasons/history survive commit/reopen/export/query/MCP; old reports and archived event IDs/evidence remain exact.
- Source-unchanged PDF delta, identical reference despite OOXML edit, mixed renderers, missing raster, repeated PDF/stale warning, hidden and unobserved source pages remain honest.
- Draft/report CAS and cancelled staging preserve prior reports and source bytes. Native sheet opens on p240/300 without rendering all pages; source and PDF page selections resolve correctly.
- Actual clean packaged app performs correction -> reanalysis -> both source origins/history -> reopen and read-only MCP. Static/pure tests alone do not qualify native UI.

## Storage and downgrade scope

New desktop draft bodies use `desktop_projects_v4`, seeded idempotently from legacy `desktop_projects`. New staged results use `staging-v4`. Old draft writers therefore cannot strip new history fields or replace the new latest pointer. Assets, immutable reports, projects and runs remain shared; this is draft/staging isolation, not simultaneous support for arbitrary older standalone writers. The native app keeps the same exclusive library lock. Under serialized use, old explicit snapshots remain readable; old binaries fail clearly on future0.4 snapshots. Older standalone recovery can interrupt a concurrently running new backend for the same legacy project ID, so cross-version standalone writers must be serialized. No automatic schema downgrade or rewriting of immutable reports occurs.

Native history uses the shared bounded query, with paginated entries and Unicode-safe reason expansion. The source preview explicitly requests `basis:source`; a supplied PDF is never shown as an independently rendered PPTX. Proposed mismatch/geometry/hidden/missing-raster/transform/reuse warnings and persisted page gaps remain visible; prior human reasons are shown with replacement effects before Apply.
