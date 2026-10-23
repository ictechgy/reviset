# README screenshots

These unedited screenshots show the actual SwiftUI/AppKit/PDFKit application built from clean runtime source `9ba86af1a24f0caa3603ee577e81b5bec3d00701` (`release/Reviset-Languages-7.app`). They use only the repository's bundled synthetic demos. The English captures come from fresh projects; the Korean captures reopen the same fixed reports. Report bodies, retained original asset hashes and read-only SQLite bytes were verified unchanged across languages and reopening.

- `document-comparison-en.png` (English) and `document-comparison.png` (Korean): a five-version synthetic demo showing the 100→120 numeric change and its source evidence. The visible left pane is a LibreOffice-converted PPTX (page 2), and the right pane is an original PDF (page 3).
- `workbook-comparison-en.png` (English) and `workbook-comparison.png` (Korean): the three-version workbook demo showing inferred A2→A3 row movement, exact physical addresses and the stored input string SKU001 on both sides. It does not illustrate a formula or a newly calculated result.

The captures come from the app's model actions and actual rendered native views. Korean source names and text remain unchanged in the English interface. This qualification does not establish OS mouse/keyboard automation, a VoiceOver audit, universal OCR accuracy or PowerPoint rendering equivalence. No screenshot was retouched.

The [localization qualification record](../LOCALIZATION-2026-10-23.md) lists the exact capture hashes and execution scope.
