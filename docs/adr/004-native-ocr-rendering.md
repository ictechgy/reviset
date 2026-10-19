# ADR-004: native raster evidence, local OCR and actual PPTX rendering

2026-10-19. The user requires continued improvements to PDF interpretation, OCR and PPTX rendering fidelity. This supersedes ADR-003's initial no-OCR / PPTX-structure-only checkpoint.

The app bundles a Swift Vision/PDFKit helper and an unmodified signed LibreOffice app. These are local subprocesses behind the existing SwiftUI/AppKit UI and staged Node compute/atomic commit boundary. The renderer receives a validated copy of the exact imported bytes, never a mutable path re-read. Macro/OLE, external-resource relationships and embedded SVG resource links are rejected before rendering; ordinary web/mail hyperlinks remain links. XML relationships are parsed and entity-decoded, including nested XLSX chart packages. LibreOffice has its own profile, HOME, temp/font caches, direct IP network access denied, file reads limited to its job/vendor/explicit OS and font dependencies, and writes limited to its job/devices plus the named LibreOffice bootstrap socket in /private/tmp. Other process execution is denied. These are defense-in-depth controls, not a claim of a hermetic sandbox against a compromised OS service. Local Unix IPC and required macOS services remain available for bootstrap. A timeout or cancellation kills the owned process group and cleans the job. Vendor signatures and the pinned official DMG digest are checked; the outer app preserves the TDF signature. Python bytecode writes into the vendor bundle are disabled.

Headless LibreOffice uses explicit system/user/bundled fontconfig directories. Without this, an empirical test lost Korean text even though AppleGothic was installed. System fonts are read, not redistributed. The font inventory, OS/build, renderer version/binary/config and output hash are observation provenance. Hidden slides are exported; page count and aspect ratio must agree before source-to-render mapping is used. Missing fonts, omitted extracted text and unsupported object semantics remain explicit warnings. The converted PDF is a derived asset. When an imported same-version PDF has a content-consistent mapping, the native viewer uses that exact PDF first.

PDFKit's cropped/rotated native appearance is captured in bounded batches of at most sixteen pages. OCR uses Vision revision3, accurate Korean/English, correction off, 300-DPI target / 4096-pixel dimension cap. Overlapping tiles and focused numeric crops cross-check values. macOS26+ RecognizeDocumentsRequest revision1 supplies inferred table cells; earlier supported OS versions preserve the unavailable structure status. Confidence is an uncalibrated model score, not probability. The 0.5 threshold plus numeric consensus is exercised on synthetic cases; this is not a broad-corpus accuracy claim.

Raw PDF text, original visible/suppressed/unresolved layers and the OCR annex remain separate. The selected comparison basis is explicit. An unresolved raw layer can use separately labeled raster OCR for an inferred comparison, without changing the original visibility assessment. OCR never proves absence. Unpaired/missing OCR regions, ambiguity or uncertain values withhold precise text change; source-review gaps remain. Both full-page OCR pairing and regional pairing require reciprocal one-to-one correspondence; merged/split or uncertain OCR observations cannot prove text removal. Geometrically substantial readable source regions may be compared independently with text_scope=region while other regions stay unresolved. Inferred numeric replacements additionally require the same text pattern and one numeric value. Changed evidence includes spatial identity, so swapping repeated values cannot promote OCR to observed facts. Unmatched OCR-only pages remain lineage gaps, not proof of removal. Pixel strike heuristics produce inferred candidates, never author intent. Thin/low-contrast strokes, dash-like glyphs and unusual bitmap formats remain recall/false-candidate limits requiring source review.

Identical source PDF raster hashes suppress text-layer-only differences, including nondeterministic OCR or hidden PDF text changes. A derived LibreOffice raster never suppresses observed OOXML source edits; equal derived pixels get a separate source/appearance gap. Different pixels can produce visual_region_changed, with no semantic deletion claim; PPTX-derived same-renderer contributions remain inferred. Cross-format pixel differences stay in page raster/fidelity evidence and produce one explicit visual-comparison gap for the entire revision interval, rather than a visual-change event for every page. Source annotation state changes without native pixel change remain marked. Exact immutable asset-and-page identity takes precedence during matching, including textless PPTX pages; unresolved nontext correspondence remains a gap. The same raster hash and environment can reuse OCR across versions, while raw extraction stays source-specific. Source, pixel and environment cache identities are validated independently; no OCR runs or caches under an unverified environment. Failed batches leave prior completed page observations available. The engine skips pixel-cache pre-render for the first OCR-bearing revision of a project, even in a warm library. Later related revisions may use a render pre-pass to reuse unchanged pixel OCR; an unrelated later scan can still cost an additional render.

Reports retain the canonical complete snapshot. Native page projections are additionally stored in SQLite within the same report/run/latest transaction; displayed-source hash checks stream bytes without allocating the entire source on every page navigation. The original PPTX is not re-read when a verified reference/derived PDF is displayed. Old reports can fall back to canonical loading without rewriting them. MCP remains read-only and uses the canonical snapshot/query contract. Page indexing reduces navigation memory; it does not remove full-snapshot parsing from all query/view/commit paths.

Range-net queries bind to the snapshot's engine version. The released0.1.0-native.1 diff kernel, its schema constant and candidate matcher are archived from commit6a736379; current snapshots use the new kernel. Unknown historical engines fail explicitly for recomputed ranges while stored history/export remain readable. New fixes never silently reinterpret an old snapshot's range under the current kernel.

The broader quality gate is empirical: real OCR, rotated/cropped geometry, raster strike/underline controls, missing-region guards, font-aware conversion, hidden-page mapping, fixed derived bytes, immutable report/page indexes, cancellation and actual packaged app execution. Office reference exports are independent upstream-declared PowerPoint outputs with pinned hashes. Nonzero pixel differences are recorded as failures of strict pixel equivalence, never rebranded as an accuracy percentage. The user-selected reference environment, licensed source fonts, broad real-document corpus and any remaining discrepancies must be resolved before claiming universal fidelity.

New reports and query envelopes use schema0.2.0. Historical0.1 snapshots remain readable/exportable without rewriting; their archived range result retains the original change schema version and pre-schema-bump net-ID inputs. Native protocol0.1 and response schema0.2 are checked separately; the Swift bridge smoke exercises a real bundled backend response. Region value provenance and inferred region pairing are distinct fields.

Quality-loop2 introduces a persisted `hybrid_regions_v1` comparison annex. Complete observed visible/observed-strike runs have priority over overlapping OCR. Each existing observation records selected, unresolved, shadowed, or excluded roles and an explicit reason/order; original text, visibility, confidence and alternatives are untouched. Glyph-span envelopes and at most two native pixels of edge tolerance are used for source-priority containment. This tolerance never suppresses an appearance-blocking overlap. OCR crossing readable and unresolved raw runs is withheld as a whole. Independently imaged OCR can fill isolated unverified or image regions only as inferred evidence. Raw/OCR disagreement remains a gap even when the raw region is selected. Selection roles travel with observations through occurrence-ID stamping and bounded page/element queries. Old comparison bases retain their meaning.

PDF OCR joined-order differences alone cannot establish a text modification. An unchanged-region conclusion requires equal cardinality and reciprocal unique matching of normalized text and location; differing pixels still produce visual evidence and reading order remains unresolved. The source-only OOXML path is not suppressed by this guard.

The ruled-grid observer distinguishes available, not detected, insufficient text, unsupported format/dimensions, exceeded budget, ambiguous boundaries and partial coverage. A weaker contrast/dash observer can reject an unsafe coarse grid but cannot confirm a new ruling. Its status/reasons and bitmap-format diagnostics are preserved in page OCR metadata, queries, exports and native inspection. This is bounded detection, not proof that all faint boundaries were found.

The user-facing engine9 local checkpoint's matcher and diff are also archived. Its historical range events retain engine9 behavior and IDs rather than adopting hybrid selection or the order-only guard. Old erroneous observations remain an immutable record; reanalysis produces a new report.

Engine11 closes pass1 review regressions: an OCR prefix cannot shadow an uncovered source tail. Full raw containment is required; a font-metric margin may be bridged only by an exact complete normalized string with at least95% reciprocal horizontal coverage and60% maximum-area overlap, still inferred and preserving raw uncertainty fields. This exception does not apply to differing or shortened text. Intersecting blocked glyph spans independently block an entire OCR line/grid value even when aggregate visibility is uncertain. Disjoint spans do not block another region. Hybrid projection uses the native mutual-center row rule, and PDF hybrid order-only checks apply even when all OCR lines are shadowed by observed source. Weak grid rejection requires narrow contrast against lighter perpendicular flanks; uniform off-white/filled cells and actual glyph ink have positive controls. Row/column/cell budget drops carry explicit reasons.

Engine12 restores complete observed-strike source priority. A redundant OCR line may become shadowed by an exclusively readable observed-strike/visible source extent; the OCR itself stays uncertain and cannot promote struck grid values. Partial/inferred strikes or blocked glyph spans still withhold the complete OCR line. Regression coverage uses an actual PDF strike annotation plus hidden prior layer and the real supplement path; a100→120 source edit remains observed. Partial OCR coverage also carries an explicit page gap, and gap dedup preserves page/revision qualifiers. Maximum14 inclusive pixel-row faint partial horizontal/vertical divider controls at4096px retain ambiguity (the boundary-index difference is13). Their solid outer rulings remain continuous at intersections; the earlier invalid fixture overwrote those rulings, so its not-detected result was not a detector regression.

Engine13 requires rectangle-union coverage for clear-source priority. Only the OCR target's outer two-native-pixel rim is tolerated; individual source rectangles are not expanded, so even a tiny internal punctuation gap remains uncovered. A256-run union budget fails explicit and unresolved. L-shaped holes and actual raw-label/raster-number/raw-label controls prevent false complete observed projections. A readable observed source pair can compare regionally despite overlapping withheld OCR hypotheses, while overlapping unresolved source, duplicate source candidates and inferred cross-producer ambiguity retain their vetoes. Complete observed strikes are eligible for that same source comparison; partial/inferred/mixed strikes are not.

Rectangular clipping can cut an empty font-metric descender margin. Source extraction loads PDF.js outline paths with disableFontFace, and only a finite positive loaded glyph outline fully inside the known rectangle can resolve that clip. Missing fonts, Type3, accents, remeasurement, invalid fonts, nonstandard matrices and unsupported rendering/graphics state retain uncertainty; outline lookup is capped at4096 glyphs per font with weakly held caches. Font metric boxes, source strings and annotation geometry remain unchanged. The tight ink rectangle is used for paint intersections only where this complete outline proof exists, with explicit inferred evidence. Actual PDFKit render hashes verify the positive empty-margin clip; an ink-cutting clip stays unverified and renders differently. This is a pinned PDF.js loaded-path observation, not proof of every font/renderer's behavior.

Engine14 removes the legacy metric clipping allowance from the new loaded-outline proof. Its normalized path rectangle must be contained with one native-render pixel of inward clearance and no expanded clip; existing metric compatibility checks remain unchanged. Only an actual document-embedded font program qualifies. A standard Helvetica control demonstrated that PDF.js's bundled substitute and native PDFKit ink differ even when the loaded outline fits; it now remains unverified. Embedded LiberationSans positive controls preserve identical native render hashes for empty-margin clips and adjacent disjoint text clips. A0.003pt cut below the embedded H outline remains unverified; no material native pixel loss is claimed for that subpixel control. Reliable proven ink footprints also prevent later text's empty metric margins from falsely occluding an adjacent line.

PDF.js6.4.299 does not publicly expose embedded-program origin on FontFaceObject. A small reproducible build-time worker patch exports a boolean derived from its actual font stream and internal-substitute flag. Exact upstream and patched SHA256s are pinned in scripts/prepare-pdfjs.ts; unknown bytes/versions fail closed. No font names or subset prefixes are trusted and fontExtraProperties remains off. Test preparation and public-corpus tooling patch development dependencies; the app build patches its fresh production dependencies before signing. The signed runtime never writes its worker. Unpatched workers expose no proof and remain conservative. The actual worker hash is part of report observation_environment; build-info and bundled source-change/license notices record the patch.

Complete source rectangle coverage alone cannot shadow an OCR line: a single source run can contain a raster character inside whitespace. Engine14 additionally requires complete normalized non-whitespace text agreement; disagreements retain the whole OCR line as unresolved. Observed source labels can still compare regionally, with a separate page gap for the unresolved raster number. Observed full-strike source priority also requires a nonempty set of observed struck glyph spans, never a vacuous empty-array check.

Engine15 narrows readable-source agreement to actual correlated glyphs centered in the OCR target. Overlapping neighbor metric margins and one source run split into multiple OCR observations no longer append unrelated source text. The full source remains selected, and exact target content plus rectangle-union coverage are both required; raster whitespace holes remain unresolved. Missing glyph correlation, more than256 runs or8192 glyph spans fail explicit and unresolved. Spatial row ordering is applied to the target glyphs; incorrect source correlation is never repaired from the OCR hypothesis. Whitespace-only agreement no longer emits a disagreement gap.

Helper11 treats complete vulgar/slash fractions as one spatial numeric slot and canonicalizes them only for verification. Mixed integer/fraction slots remain separate, denominator/sign conflicts and split numeric observations withhold agreement, and unsupported superscripts/Roman/scripts/incomplete numerators remain unresolved. Original OCR strings and alternatives are unchanged. Diff numeric slot counts/patterns use the same boundaries and preserve literal units for regional inferred edits. The pinned W3C original fraction readings have actual native cross-check evidence; this does not establish universal fraction or OCR accuracy.

Engine16/helper13 attempted the incomplete slash contract:1/,/2 and numeric slash markers missing an operand remain unsupported, including spaced/fullwidth forms. Complete spaced fractions, slash dates and literal unit slashes1/day or km/h retain their lexical support; this is not general mathematical-expression validation. The helper does not promote numericStatus under an unsupported notation. The diff independently checks notation and requires identical fraction/decimal class sequences, so a consistent OCR slash drop1/2→12 or½→14 cannot become an inferred text replacement. Class-aware patterns and counts derive from the same raw tokenization; source strings and units remain unchanged. Valid source-observed edits still use source facts. Per-element numeric shape caching bounds repeated work during pairing. Pass7 review subsequently found signed/vulgar orphan bypasses in the neighbor guard; engine17 supersedes that guard.

Target source agreement preserves the correlation-verified logical glyph subsequence inside each source element, including mixed sizes and RTL. Row ordering applies only between filtered element groups; generic multi-element/bidi layout remains heuristic. Native UserUnit0.5/1/2/10 probes showed PDF.js viewport scaling while this host's PDFKit cropBox thumbnail ignored UserUnit. Outline-proof clearance therefore scales conservatively with max(1,UserUnit); it never shrinks the native floor if another renderer honors the unit. Actual embedded-font controls verify positive native render equality and at least one actual native pixel of clearance; subpixel-margin controls remain unverified. This is still inferred, pinned-renderer evidence rather than universal font/render equivalence.

The initial dangling-slash guard also withheld an existing signed numeric-list control. Helper13 explicitly distinguishes a spaced list separator between complete numeric observations (retaining literal unit labels) from a dangling numeric marker; the same rule exists in TypeScript. The original Korean/English signed amount/cache test and new unit/list controls pass. Lines without slash markers avoid the extra token scan. The failed helper12 full regression log remains preserved rather than reported as a passing run.

Engine17/helper14 classifies slash ranges against complete numeric token spans, bounded three-component slash-date spans, explicit spaced numeric-list delimiters (including currency prefixes), and compact literal letter denominators without whitespace after the slash. Other numeric-adjacent slashes are unsupported, including signed, vulgar and leading-decimal orphan operands. UTF-16 regex ranges avoid Swift grapheme-dependent slash detection. Numeric lines containing invisible format characters, numeric combining marks or unsupported division-slash lookalikes remain unsupported, with original readings preserved. A shared JSON contract drives Swift and TypeScript controls. Numeric suffix paths such as docs/2024 and symbolic A/2 remain conservatively unsupported in OCR; this is not a general path, unit or mathematical-expression parser.

Engine18/helper15 extends the preceding closure after a scoped external review reproduced fullwidth/en-dash prefixes and invisible Hangul filler bypasses. Any non-letter prefix or suffix between an unowned slash and its adjacent numeric token is now numeric-adjacent, rather than relying on a sign/punctuation allowlist; the existing literal-unit suffix rule also remains. Default_Ignorable_Code_Point (including invisible letter fillers), non-whitespace controls and the listed unsupported slash lookalikes withhold numeric verification. Tokenization, canonical whitespace and delimiter tests use Unicode White_Space in both languages, including NEL, and fullwidth minus is a supported canonical sign. Raw strings stay unchanged. Decimal/grouped ratios, compact alphanumeric slash labels and ISO-code-prefixed numeric lists remain conservatively unsupported under this bounded grammar; the shared fixture records those coverage limits. Parenthesized compound expressions are not a mathematical-validation claim.

Engine19/helper16 replaces numeric-neighbor gap heuristics with a closed slash grammar for numeric lines. Each slash must belong to a complete fraction token, bounded date, explicit spaced numeric list or compact literal letter denominator; otherwise numeric verification is unsupported. This closes the Korean-unit suffix mismatch without absorbing units into TypeScript numeric values or masked patterns. Swift unit-inclusive verification spans remain unchanged. The shared corpus includes every combination of several literal unit suffixes and unsupported punctuation. Unrelated numeric-line URLs/alphanumeric paths and unknown slash expressions can conservatively withhold; ordinary letter unit/text denominators and explicit currency/unit lists retain controls. This is lexical support, not semantic arithmetic validation.

Engine20/helper17 requires complete integer-fraction operand boundaries: a numerator cannot begin inside a numeric/decimal continuation, and a denominator cannot terminate before another numeric scalar or decimal/grouping separator plus digits. Regex backtracking cannot shorten a denominator to claim ownership. Unsupported decimal/grouped/mixed ratios therefore leave the slash unowned and fail the numeric-line grammar. Whole raw strings and inferred/source roles are unchanged. Sentence/list punctuation separated from numeric continuations and bounded slash dates with sentence punctuation retain controls. This closes actual full-page denominator-prefix and regional leading-decimal numerator reproductions without adding a general expression parser.

Leading-decimal scalar observations such as .5 are now complete decimal slots, retaining the point in both the raw range and canonical verification value; an independent5 reading conflicts. Compact decimal ratios .5/2 remain unsupported. Explicit two-sided spaced numeric lists .5 / 2 retain the list interpretation, just like the existing decimal/signed lists; no mathematical interpretation is inferred. Spaced text/text slashes in numeric lines such as Revenue / Cost2026 remain an explicit conservative recall limit.

The explicit spaced-list rule also supports1 / 2.3 and1 / 2,000 as two observations; compact1/2.3 and1/2,000 remain unsupported ratios. Spaces on both sides are an existing lexical list convention, not evidence of author arithmetic intent.

Source PDF font metrics can be unavailable even for ordinary unembedded Times
or Courier fonts. Engine22 retains their exact observed strings and finite
estimated display bounds (or an empty box when the transform cannot locate
text), with `pdf_text_geometry_estimated_or_unavailable` inferred evidence and
an explicit visibility gap. Original metrics remain unavailable: these runs
cannot establish visible glyphs, strikes, occlusion, original PDF grid cells,
or complete source coverage/shadowing. Independently localized OCR may coexist
as inferred comparison evidence; it does not resolve the raw geometry. Unknown
painted text extent conservatively withholds earlier paint visibility across
the page, while subsequent reliable text retains its own checks. Hidden text
paint does not introduce this overlay. Canonical Page validation occurs before
extraction succeeds; a remaining invalid asset is isolated by the engine's
per-file failure path. The public corpus validates source and variant pages
before JSON serialization and exercises every original and variant through
DesktopService create/analyze/commit, reopened report and native-page storage.
This avoids treating successful OCR scoring as successful app ingestion.

Estimated source bounds do not drive hybrid row ordering: marked unresolved
observations follow localized evidence in original source reading order. A
page mixing unknown-metric fonts can require OCR for every reliable run painted
before the last unknown-metric run; this conservative recall cost is explicit.
Paint, annotation overlay and strikeout coverage share one [0,1] ratio helper,
so fractional-coordinate roundoff cannot invalidate an otherwise supported page.

Engine23 permits a reciprocal unique selected OCR-to-OCR numeric regional edit
without using marked estimated source boxes as geometry candidates or vetoes.
Raw source remains unresolved and the page gap stays visible; the edit cites
only inferred OCR quotes and adds
`estimated_source_geometry_not_used_for_raster_pairing`. Localized uncertain
source, uncertain OCR, duplicate regions, numeric grammar/one-slot checks and
equal native raster suppression remain blockers. This is independent raster
comparison, not recovery or verification of the source extent. The actual
Times-Roman32 Revenue100→120 native control exercises this boundary through
coordinator commit and reopened report/native-page storage. Identical unknown
paint extents are aggregated at the last visible unknown order; earlier and
intermediate paint stays uncertain, later reliable paint retains its checks.

Engine24 records page annotation metadata as empty `pdf_page_annotation` shape
observations, excluded from comparison text/rows/pairing. Inferred zero-coverage
annotation-region evidence is a withholding signal, never proof of visible
strikeout or applied deletion. Hidden/NoView and no-appearance Link/Popup follow
the existing exclusions; unapplied Redact intent remains available. The pure
region accessor scans complete page observations and actual annotation bounds,
independent of estimated glyph bounds. OCR admission/grid cells, independent
hybrid fallback and inferred OCR regional edits check those regions. Readable
observed-source/observed-strike priority is preserved. Carriers do not append
empty source-text lines or turn an image-only page into a text-layer page.
Annotation count2048, aggregate quad coordinates32768 and per-annotation geometry
limits fail conservatively with a full-page review carrier and explicit gaps;
they do not silently truncate intent or promote unsupported source visibility.

Estimated raw source also remains text evidence. Before an inferred OCR numeric
edit, nearby estimated source runs are checked only in the withholding direction.
Disagreement is recorded with exact raw/OCR quotes; a single numeric-slot conflict
in the same literal context (including fraction/decimal class disagreement)
withholds the edit. No reading is rewritten and no agreement resolves source
geometry. Split-run text is retained in source reading order;256 runs/16384 chars
bound the check and exceeding that budget withholds with a gap. Unrelated textual
context remains explicitly unresolved rather than being treated as a proven
source-to-raster correspondence. Native pale-StrikeOut and unapplied-Redact
controls now retain their source intent and withhold numeric edits after commit
and reopened report/native-page retrieval.

Engine25 preserves supplement OCR observations under annotation carriers: only
text-bearing source observations deduplicate imaged lines. Annotation overlap
withholds admission as uncertain/unresolved instead of discarding the reading,
including a full-page unknown annotation region. A real native image-text
observation under a Highlight and a controlled unknown-region carrier exercise
both paths. Estimated source runs with zero-area bounds have unknown location;
they participate in the bounded source contradiction review for every proposed
OCR region, solely to warn or withhold. Matching text still permits the inferred
numeric edit and never certifies source geometry. Numeric conflicts always leave
an explicit quoted gap. Page-level text evidence takes its fallback method and
provenance from a text-bearing observation, never an empty annotation carrier;
the native source panel labels carriers as annotation metadata rather than hidden
source text. These changes preserve raw strings and confidence without claiming
universal source-to-raster correspondence.

Uniform explicitly nonpainting text modes3/7 remain observed hidden state even
when font metrics cannot locate the run. Complete, unique source/operator text correlation
is required; mixed, repeated or unmatched text stays unverified. Type3 character
programs and unsupported graphics state are not relied upon for this nonpainting
proof (see Adobe PDF1.4 Reference, section5.2.5: https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/pdfreference1.4.pdf). The geometry marker and
raw text remain, and the hidden-state evidence has zero-area/zero-coverage bounds.
It neither invents a location nor establishes visibility/coverage. A real native
image100→180 control with stale hidden Times text100→120 verifies that a prior
invisible OCR layer cannot veto a new raster edit. Mixed visible text remains a
source-conflict guard; unsupported geometry does not become readable source.


Engine26 retains every nonempty native OCR line before selection. Global text
containment and mere geometric intersection cannot discard an imaged observation.
Only the existing complete source-union/content proof shadows a redundant OCR
line; disjoint repeated text remains independent, and partial-overlap lines stay
unresolved with their original primary/alternative strings and confidence. A
same-place fully shadowed verification retains verification mode; this does not
turn OCR into confirmed source. Actual native repeated-header/image100→120
controls exercise the prior missed edit, with same-place duplicate and partial
source/image controls. The unique uniform nonpainting-mode proof also precedes
metric/color/clip reliability for known-metric fonts (Helvetica7Tr/gray3Tr), so
an independently known hidden state does not depend on font metrics. Estimated
hidden-source UI now separates observed nonpainting state from unknown location.
Empty page quotes use page-observation fallback rather than naming an unquoted
text layer. Universal OCR recall/precision and renderer fidelity remain open.


Engine27 evaluates hybrid completeness from participating observations, not the
hybrid label alone. A fully source-observed selected projection with no unresolved
text remains complete when verification OCR is entirely shadowed. Thus a logo
page's verification annex cannot suppress an unrelated complete-source page add
or delete. Selected inferred OCR, unresolved OCR/source, raster-only evidence,
failed/partial revisions and unavailable text remain incomplete. Both absence
directions and participating inferred/unresolved negatives are covered; unchanged
revision-level failed/partial, raster-only and unavailable-text production code
paths are retained; raw roles and the hybrid
annex are retained, without restoring a basis that would ignore the roles.

Retaining OCR also expands conservative recall limits on image-bearing readable
source pages: native OCR case/character disagreement, outer bounds beyond the
source union, and multiline/cell gaps can remain unresolved. An observed source
regional pair may survive where a whole-page text edit is withheld. The mixed
fixture's exact native header OCR exceeds the source right edge by about3.5pt;
its stored OCR remains unresolved and source is compared once. No union tolerance
was relaxed. Same-place fully covered controls shadow; partial coverage is kept
unresolved. This is observed uncertainty, not proof that the page is unchanged.
The engine25/27 native-observation replay records this qualification cost on
pinned public PDFs and synthetic row controls separately from OCR accuracy.


The native inspector keeps raster origin separate from confidence: the noun is
always rendered screen, with observed/inferred level from evidence provenance.
Legacy evidence may omit provenance; OCR still displays inferred, and other
methods explicitly display unknown evidence level. Reasons lack per-item origin
tags, so human-confirmed reason lists remain verbatim to preserve free text,
including engine-like prefixes. Such lists may also contain raw engine reason
codes; this is a deliberate preservation limit, not a new mapping-review warning.
Automatic appearance transitions use the exact producer arrow separator; other
known gap/range reasons are localized and unknown labels remain neutral/deduped.


Engine28 repairs two actual public-PDF source-visibility regressions without
rewriting OCR. Fonts used only by whitespace may be absent from
`textContent.styles`. Worker patch V2 exports the same finite actual font
ascent/descent pair alongside the embedded-program origin flag. Missing or
invalid values remain unavailable; this is not a fontBBox or default estimate.
The known V1 worker is accepted only at build time, reconstructed to the pinned
upstream hash, then upgraded to the pinned V2 hash. Runtime remains read-only.

Reliable fill text from a genuine embedded program also uses its loaded glyph
outline as the maximum later-text ink extent. This avoids withholding an
earlier number merely because a later parenthesis overlaps its empty metric
margin. It does not narrow target source boxes, relax annotation/clip
thresholds, or certify substitute fonts, Type3, accented, remeasured, stroked,
unsupported or missing paths. The one-native-pixel inward clearance for clip
rescue remains unchanged. Actual source strings and OCR primaries remain exact.
A native control compares every baseline digit ink pixel: separated actual ink
leaves them unchanged, true overlap changes them and remains uncertain; a
substitute-font negative retains the metric-only uncertainty.


Engine28's first later-ink rule was rejected by independent code and
architecture review and Claude. Embedded LiberationSans20 `f` has a right
outline overhang beyond its advance width: a later parenthesis can change
2 of659 actual native nonwhite baseline pixels while missing the target
metric box. The failed PDFs, native PNGs, raw reviews and131-pass suite are
preserved; passing that suite was not sufficient.

Engine29 retains original source/display boxes and every existing
fill/annotation/unknown-paint target rule. Only text-versus-text uses an
additional qualified pair: the target must have a reliable actual embedded
fill outline, and every potentially painting glyph in the later run must
have one as well. Missing, empty or unsupported paths are not whitespace
proof. Otherwise the entire old run footprint is retained. Each qualified
ink envelope is expanded by the shared one-native-pixel floor (including
UserUnit/cap behavior), requiring clearance on both sides. Thus target
overhang and near-contact anti-aliasing are withheld as well as true overlap.
Nonstandard font matrices and Type3 programs cannot acquire a bounded
painted extent merely from finite metrics. Raw strings and external boxes
remain exact; the native positive now checks every nonwhite channel value
including faint anti-aliasing. This is a tested conservative guard, not a
universal theorem about native font rendering.

The public training example involves `1` followed by Korean `시`, whose
actual outlines are19.6459 native pixels apart despite slightly overlapping
metric margins. The parenthesis is the independent synthetic control, not
the glyph in that public example. Primary OCR remains unchanged in both.

Engine30 adds bounded, additive multi-context Vision ROI observations. Up to4
weak nonnumeric lines/page receive2 relative paddings x2 scales x2 language
sets, with4M pixels/crop,128 characters and32 tokens/context. The helper keeps
primary strings, alternatives, confidence, numeric and strike metadata intact.
Unsupported/transparent/dark backgrounds, empty ink, crop boundaries, multiple
lines, failed requests and budgets remain explicit statuses. The original
primary-band Otsu core ink must be entirely inside mapped token envelopes.
This envelope test is a geometric coverage check, not character-shape proof.

Admission requires all8 distinct contexts to agree at confidence>=0.5 without
strong alternative dissent. Numeric readings/contradictions and changed
punctuation/confusable characters are withheld. Korean-capable contexts must
support changed Hangul. Original/crop source appearance, annotation, strike
and page-geometry vetoes remain. A new inferred vision_ocr observation stores
full support and the page-local primary reference; raw primary projections
stay exact. Selection rechecks evidence, unique relationship and duplicate
claims before shadowing the original primary. Same-engine votes remain
correlated evidence and are never advertised as calibrated certainty or
perfect OCR. Full JSON/native page projections/export retain both readings;
bounded queries summarize support and expose one context via
get_element.ocr_context_index. Helper18 source/policy participates in cache
identity. Pairwise embedded-ink padding is cached and earlier paint is skipped
without changing its visibility contract.

Engine30 was blocked despite135 passing regressions: its optional annex could
invalidate a page/batch, its largest retained context could not be traversed
through bounded MCP responses, and coarse word envelopes could not justify
character deletion. Engine31 keeps invalid optional ROI metadata as an
explicit gap while retaining the primary; each native page is decoded
independently. Swift uses a conservative128 UTF-16-unit cap and clamps mapped
boxes, marking clipped contexts. Rejected derived candidates are excluded
from comparison, with the original primary participating exactly once;
ingest and replay both veto neighboring raster strike evidence. Admitted
candidates keep the primary bbox, and all OCR pages use the same hybrid
selection/order path irrespective of whether a candidate was admitted.

Engine31 permits at most one scalar edit, never a whole whitespace-token
deletion. A deleted scalar additionally needs the original Vision candidate's
exact character range/UTF-16 offset and a positive mapped rectangle expanded
by one native pixel that is uniformly opaque white in EVERY8-bit color
channel. A single nonwhite or nonopaque pixel, including faint ink or
antialiasing, withholds that certificate. This is separate from Otsu core-ink
envelope coverage; neither check alone is presented as character-shape proof.
Actual W3C phantom-char rectangle contains344 white pixels and no nonwhite
pixels; genuine native-rendered trailing Hangul/Korean-word controls never
certify the Korean glyphs as empty. Missing bounds/unsupported layouts or
budgets withhold deletion. Same-engine recognition/positioning can still be
correlated; inferred readings never become observed original text.

Context evidence is traversed by context index, reading index, four token
boxes/page and32-unit text/alternative chunks, including the actual MCP
transport's smaller payload allowance. Empty-character certificates have a
separate indexed/chunked query. Canonical JSON/native pages/full export keep
complete support. Core bands are capped at262144 pixels with about1MiB of
row-prefix storage; token-union coverage replaces point-array x token scans.
ROI has a shared12-second/page budget with best-effort VNRequest.cancel,
weak timer capture and explicit budget statuses. Cancellation is not a hard
real-time guarantee. The original30-second ruled-grid failure is retained;
fix qualification includes timing and the actual native/full regression.

The native30-second table failure recurred under parallel test-file execution;
the same control passed in1.58s alone. A separate instrument-free native probe
measured24.85s total (process24.74s, document structure0.11s),216.6MB maximum
RSS, with the ROI contexts available. These observations support contention
and cold framework cost as factors, without proving a single OS-level cause.
Native integration test files now run sequentially. The outer helper budget is
finite60s/page (with existing process-group cancellation), allowing cold
primary recognition plus bounded ROI; this change does not assert faster OCR
or a hard latency bound. Initial failures, isolated success and probe timings
are all retained separately.

Engine32 isolates the optional document-table and ruled-grid annexes from
each other and from primary OCR decoding. Invalid geometry, oversized arrays
or invalid status metadata suppress only that annex and add a persistent
coverage gap; valid neighboring annexes and primary strings/confidences survive
both initial decoding and cache replay. Mandatory raster/primary metadata
remains strict. Component-query cursors are validated against the selected
component only, including when unrelated primary text has a surrogate pair
at that numeric offset. The actual MCP transport exercises both positive
component pagination and invalid selected-primary boundaries.

The exact255 empty-character criterion normally withholds certificates for
noisy/JPEG/scanned backgrounds. It supports clean rendered empty footprints,
not universal scan correction. Original character positioning remains Vision
evidence, correlated with its recognition. Native genuine-Hangul controls
establish eight retained context slots and no Korean empty certificate; a
slot may carry a budget status, so slot count alone does not establish eight
completed Vision requests.

Engine33 closes the broader boundary-edit class: all supporting readings and
competitive alternatives must agree on normalized token structure, and exactly
one aligned original token may differ. A same-count word split elsewhere
cannot hide a certified deletion or substitution. The one-edit/certificate,
script/numeric/appearance vetoes and immutable primary evidence remain.
Persisted optional-annex error flags force that annex empty on every decode;
mandatory native page failures expose schema/mode/helper/protocol reasons
through canonical page gaps rather than silently becoming a generic absence.

PPTX preview input policyv6 materializes standard omitted DrawingML bodyPr
text insets only on ordinary, nonplaceholder slide shapes: lIns/rIns91440EMU
and tIns/bIns45720EMU. Microsoft OpenXML documentation specifies these values;
LibreOffice's implicit250/125hundredth-mm defaults differ from254/127. This
is a source-preserving renderer derivative, never a rewrite of stored original
assets or inferred source semantics. Namespace scopes, explicit values,
placeholder inheritance and unrelated parts are preserved; signed/ambiguous
packages and unsupported XML fall back unchanged. Repacking is deterministic,
input/cache policy versioned and bounded by existing package limits.
Actual native preview and reference qualification remain separate from source
review; lower average RGB error is not strict PowerPoint pixel equivalence.

Primary sources for standard margin defaults:
https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.bodyproperties.leftinset?view=openxml-3.0.1
https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.bodyproperties.topinset?view=openxml-3.0.1


Engine34 binds deletion edit alignment and UTF16 certificate offsets to the
single changed original token, preventing repeated characters in another token
from supplying the certificate. Optional cache writes are diagnostic failures,
never reasons to discard valid native observations or assign an unrelated page
failure; native page-specific reasons survive preview projection.

Renderer input policyv7 guards OPC signature relationship/content-type indicators
regardless of part path, treats extension and MC branches as opaque, preserves
BOMs and enforces post-derivation UTF8 part/aggregate/ZIP budgets. A first bounded
slide/metadata scan avoids inflating media on unchanged inputs. Repacking runs
in a separate process with process-group cancellation, a finite timeout, minimal
environment and source/derived SHA256 verification. Bundled office-input.mjs
is required in packaged apps. Source validation remains partly synchronous.
A per-asset preview input_preparation record retains policy, source/input hashes,
changed-property count, unsupported-part count and conservative skip reason;
cache replay validates that record. This does not normalize master/layout
content, nonstandard slide names, fonts or all PowerPoint rendering behavior.

Native score0.5 low-resolution Korean controls revealed actual incorrect inferred
selections. Independent sandboxed OCR disagrees with three erroneous primary
values, reading two correctly; the prototype remains outside the product.
Neither a higher threshold nor another recognizer score alone establishes truth.
Broader observed disagreement and preservation qualification remains active.


Engine35 observes borderline score0.5 nonnumeric lines within the same four-line
and12-second budget, after weak/ambiguous lines in original order. Primary line
strings, confidences, alternatives, numeric/strike metadata and raw visibility
remain separate from selection. A positive spatially matched contextual reading
in languages that support the primary Latin/Hangul scripts can withhold an
inferred comparison when its token text disagrees; English-only readings cannot
contradict Hangul. Failed, empty, edge-cut, contaminated and unsupported contexts
are not counter-readings. No replacement is admitted by this veto and stronger
positive correction guards remain unchanged. Non-unit ink coverage may retain
uncertainty; it cannot certify a substitution/deletion. Bounded controls and
later heldout qualification are separate from universal OCR correctness.

Preview native capture now reads a private copy of the verified PDF bytes even
on cache hits, avoiding shared-path replacement between hash validation and the
helper read. Cache staging cleanup failure has its own warning, and raw native
rows cannot claim the parent's operational cache-write warning. Renderer input
cache environment additionally fingerprints the Node version and pinned dependency
lock; this is not a full integrity hash of every installed dependency file.
The Office reference verifier requires unchanged clean source, pins the upstream
manifest, writes head-specific runs, retains per-asset preparation metadata and
reports both any-RGB and >24-channel pixel differences including exact geometry.

When another page region becomes unresolved, distant copies of an amount cannot
suppress a uniquely paired selected raster numeric edit at this location.
The exception requires unique bidirectional geometry, available selected raster
observations, supported numeric notation, an identical pattern and exactly one
numeric slot on both sides. Overlapping/unknown neighbors and annotation/source
vetoes remain. The result explicitly carries inferred regional pairing; it is
not evidence that an entity was semantically modified instead of moved.


Engine36 emits contextual selection diagnostics from final unresolved roles,
after validated derived evidence can supersede its primary. It cannot globally
remove all gaps when any one region succeeds. Eligible weak/borderline text with
missing or unusable contextual evidence remains an unresolved observation, not
agreement. Raw OCR confidence/string/alternatives/visibility/projections survive;
annex-level failure reasons are visible even for zero contexts. Score1 recognition
errors remain an independent open qualification issue.

Short selected-raster nonnumeric lines may recover an anchored one-word edit
when a separate region is unresolved. Qualification requires PDF-to-PDF same
native environment, reliable normalized geometry and distinct raster hashes,
confirmed or unambiguous inferred page correspondence, unique bidirectional
footprints and no additional overlapping observation. Both readings are selected,
available,nonambiguous with evaluated strike/numeric metadata(or validated derived
support); zero numeric slots and no Unicode numbers, <=128UTF16,equal token count,
one altered token and an unchanged letter-bearing anchor are mandatory. Existing
elsewhere-text/movement, annotation/source and estimated-source disagreement
vetoes remain. This is inferred change at a location, not semantic entity edit
rather than motion. Reflow/multi-token/unanchored edits stay explicitly incomplete.
The prior single-slot numeric fallback and historical schemas remain compatible.

### Engine37 regional ambiguity repair
Lexical inferred fallback rejects peers touching either the same-page or paired
footprint. Equal token counts do not exclude a split word: when the changed token
is a prefix/suffix and nearby monotonic boundary fragments can complete it, the
pair is withheld with `ocr_fragment_reflow_region_withheld` and unchanged raw
quotes/boxes. A trailing line-break hyphen is ignored only for this negative
check; primary/source strings are never rewritten. Search is limited to3fragments,
8candidate branches and128UTF16 per neighbor; budget uncertainty also withholds.
This is possible reflow, not a positive layout/semantic claim. Unrelated regional
edits survive. Native change details render the selected change's coverage
reasons in Korean, including contextual incompleteness and possible reflow.

### Engine38 contextual scope and fragment closure
Both applicable prefix/suffix continuation orientations share64search nodes;
terminal ASCII,soft andUnicode hyphens are removed only from negative-check
boundary tokens, never raw evidence. Node/branch/depth/character budget uncertainty
withholds the pair. Native21adds natural high-score pure-Latin nonnumeric lines
after weak/borderline priorities within the existing4line/shared12s cap. Those
lines request2broadpadding.75 en-US contexts,scales1/2. Spatial supported
counterevidence can only withhold; failed/missing context does not supply agreement
or automatic correction. Numeric/mixed-script/Hangul and observed-source
contracts remain intact. Positive correction still requires its original weak
primary and8complete contexts.480prospective correlated conditions support a
bounded risk reduction, not full OCR correctness. Current production qualification
and unique-page latency remain separate gates.


### Engine39: Unicode scope and same-image work within one capture

The consumer's Latin presence test uses Script=Latin,matching the native
high-score eligibility profile. Terminal Unicode dash punctuation/soft/minus
normalization remains only a conservative possible-reflow veto;source strings
are never normalized in place.

When the existing warm raster-cache lookup already rendered pending pages,
equal native PNG SHA and pixel dimensions may reuse one current-environment
NativePageResult. Clone before per-page supplementation/selection,retain own
viewport/rotation,strip representative cache-write warnings and apply own I/O
warnings. Validate actual OCR hash/dimensions against the pre-render;otherwise
keep the representative's own actual observation and independently process its
peers. Failed/missing render evidence never prevents ordinary OCR. Fixed
original-work progress,cancellation,16page/32MiB/60s-per-page process budgets
remain. Cold/no-reuse paths add no render calls. The disk key includes dimensions
as well as environment and image SHA. Optional annex availability can be shared;
this optimization does not promise independent retry equivalence or accuracy
improvement. Actual native primary/numeric/strike/token/raster preservation is
covered separately from deterministic subprocess failure/cache controls.


### Engine40/helper22: supported countercontext languages

For exactly0.5,nonambiguous mixed Hangul/Latin lines,positive correction is
ineligible under the unchanged admission contract. Contextual dissent requires
both ko-KR and en-US,so monolingual contexts cannot contribute. Keep the four
bilingual padding(.25/.75)×scale(1/2) contexts and omit four ignored monolingual
calls. Weak or ambiguous lines retain all eight correction contexts;monoscript
borderline and high-scoreLatin profiles retain their existing evidence. The
four-line/12s ordering,budgets,primary readings and language correction=false
remain. Helper22/ROIpolicyv4 are environment-bound. The32paired native component
experiment preserves primary/raster/usable-context/canonical results with23.6094%
median improvement;this does not measure app latency,unique-corpus p95 or
universal OCR accuracy. Parent capture also retains a representative's own
pre-render cache diagnostic after successful independent OCR,without sharing
that execution-local warning across its peers.


### Engine41/helper23: one OCR comparison-key contract

Engine40's four-context optimization exposed an existing normalization
mismatch: native Unicode White_Space also removedNEL,while TS\s retained it.
This could conceal native ambiguity and prune still correction-eligible
contexts. Align native ambiguity and Latin eligibility to the explicit
ECMAScript whitespace set;preserve raw primary text. After NFC/whitespace
processing,use NSString default contextual lowercase to match JS handling of
finalGreek sigma,also covered by dottedI/NFC/NFD/shared whitespace fixtures.
The source of the whitespace set is [ECMAScript lexical grammar12.2/12.3](https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-white-space).
Eight correction contexts remain available for the actual NEL supplement
counterexample. Shared45fixtures and producer/consumer end-to-end policy
controls qualify the bounded repair,not every Unicode sequence or OCR accuracy.
Helper23/ROIpolicyv5 separate observation caches. Current packaged/runtime
qualification remains a separate gate.


### Engine42/helper24: strict scope and literal key equality

ICU dollar can match before one finalNEL;use absolute whole-string anchors for
native Latin eligibility. JavaScript compares normalized keys as literalUTF16;
Swift String equality also applies canonical equivalence to the post-lowercase
result. Compare UTF16 elements to preserve the actual consumer relation.
Shared61fixtures include end-of-string controls and5canonical-equivalent but
code-unit-distinct pairs;actual producer/supplement controls preserve8context
correction. As an additional eligibility proof,the4context mixed optimization
requires every competitive alternative to have the exact same NFC raw input.
Unknown/differing alternatives retain8,even if case/space compaction could make
them appear equivalent. Exact equal NFC inputs necessarily yield equal consumer
keys,without requiring a universal cross-runtime case-mapping proof. Rawtext,
confidence,positive-admission semantics and source visibility remain intact.
Helper24/policyv6 are separate observation identities. Component timings from40
and ordinary480counts do not certify current42app performance or everyUnicode
case;current packaged verification remains required.


### Engine43: literal raw guard across normalization versions

Claude's focused42 review requested a stricter raw-input guarantee: platform NFC
normalization tables may differ for newly assigned combining characters. No
actual Vision misreading or concrete installed-version disagreement was supplied;
this is a guard-contract finding, not an observed accuracy regression. Competitive
alternatives now must be literally equal UTF16 raw inputs for the four-context
profile. NFC-equivalent, case/spacing-distinct or unknown containers keep eight
contexts. Native producer regressions include decomposed/precomposed alternatives
and malformed containers. Primary readings and comparison admission are unchanged.
Helper25/vision-roi-v7 invalidate old cached profile observations. Actual42 app and
480 results belong to frozen42 only;43 qualification remains separate.
