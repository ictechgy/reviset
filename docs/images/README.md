# README screenshots

These unedited screenshots show the actual SwiftUI/AppKit/PDFKit application at runtime source `1b2f98b4f727972b8261516ec82064908600455d`. They show Reviset reopening fixed reports created from the preserved Docver build’s bundled synthetic demos. No user documents were used. The legacy report IDs, bodies, and original bytes were verified unchanged; the document capture also shows the new Reviset footer.

- `document-comparison.png`: a five-version synthetic demo showing the 100→120 numeric change and its source evidence. The visible left pane is a LibreOffice-converted PPTX (page2), and the right pane is an original PDF (page3).
- `workbook-comparison.png`: the three-version workbook demo, showing inferred A2→A3 row movement, exact physical addresses and the stored input string SKU001 on both sides. It does not illustrate a formula or a newly calculated result.

The captures come from the app's internal view-model actions and actual rendered native views. They do not establish OS mouse/keyboard automation, VoiceOver qualification, universal OCR accuracy or PowerPoint rendering equivalence. No screenshot was retouched.
