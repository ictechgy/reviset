# Native screenshot provenance

The five captures retain exact original bytes and literal producers: Mac36 M1/M2/M3 and Windows41 W1/W3. Captions describe the selected original pixels. No crop, resize, composition, annotation or retouching is part of publication.

| Slot | Public file | Literal producer | Original SHA-256 |
| --- | --- | --- | --- |
| M1 | `macos-git-source-en.png` | Mac36 `158dd2146f1a1aaa4775a11aa40df324fb888430` | `9e67e0253ce6d474d3bc6c227bff832a9968a60cecd0188c692df801fed03b2e` |
| M2 | `macos-git-text-en.png` | Mac36 `158dd2146f1a1aaa4775a11aa40df324fb888430` | `7dd0c269b3b6ed74bd6b597d8539fc11c4a019ab10aaf001c970d09dd2f291e7` |
| M3 | `macos-git-workbook-en.png` | Mac36 `158dd2146f1a1aaa4775a11aa40df324fb888430` | `64149ac6b37714cafdcdf4ba10258b4ea67b08b9a9dd8d2e1c21330fdb11b445` |
| W1 | `windows-git-source-en.png` | Windows41 `13bee235b063b66e0668ccc3c24f599e9bc1acc6` | `7419459247b2d8a53add7e47f5e8379ecaffdab1e6c812ccacfa9886dc0ab665` |
| W3 | `windows-git-workbook-en.png` | Windows41 `13bee235b063b66e0668ccc3c24f599e9bc1acc6` | `3f44f589b5245c1b0b20eb954c45e3ac5f26e2f7b5b45e5c5c52924e64945987` |

Captions:

- **M1** — macOS original sources v2 → v3; compact Changes beside large PDFKit pages. macOS 원문 v2 → v3. 간결한 변경 목록 옆에 PDFKit 페이지를 크게 표시합니다.
- **M2** — macOS extracted text: query v1 → v3, selected intermediate event v1 → v2, with source terminators. macOS 추출 문구. 조회 v1 → v3에서 중간 변경 v1 → v2를 선택하며 원문 줄 끝을 표시합니다.
- **M3** — macOS workbook physical source grids and stored values; correspondence is inferred and formulas are not recalculated. macOS 통합 문서의 실제 셀 격자와 저장값. 대응 관계는 추정이며 수식을 재계산하지 않습니다.
- **W1** — Windows source pages at 100%: query v1 → v3 and selected event v1 → v2 remain distinct. Windows 원문 페이지 100%. 조회 v1 → v3과 선택한 변경 v1 → v2를 구분합니다.
- **W3** — Windows native workbook grids for the selected v1 → v2 event within the wider v1 → v5 query. Windows 네이티브 통합 문서 격자. 조회 v1 → v5에서 선택한 v1 → v2 변경의 원문을 표시합니다.

The combined original-image manifest contains 75 literal Mac36 originals and 164 Windows41 originals (239 total), SHA-256 `33ecdbe0ce071ea9c942253b0f66423273cb0d0461638a3385ed8161ecc3ef96`. Root, the project owner responsible for the evidence disposition, directly inspected eight retained Mac36 and 14 current Windows41 frames, including all five public selections M1/M2/M3/W1/W3. The historical Claude36 full22 review included the exact public Mac36 M1/M2/M3 originals; its REQUEST CHANGES verdict remains preserved. Current Claude41 APPROVE covers only Windows41 W7/W11/W12/W13/W14. The public Windows41 W1/W3 originals have root direct inspection, without a provider static opinion on those exact current bytes. Provider review coverage is not 239 images. The byte-exact five originals are staged without pixel changes, with plan `b4a5c87b448a46ac733515556130e585a7d990bc8942e151f96538b6b38bc58e`, captions `89910cc13b718c8c52862cc60a9bf54cb0fe7d69020bbc410039e5c3b8c8d468` and copy receipt `890ed181dd3ad4d6c9efae347d6bfd8fa2e56beab1a3e1fef06b4265a18a9ca8`. The plan's earlier in-progress static label records staging time; later root admission retains the distinct direct-inspection and provider scopes above. Public image files were not changed by staging.

The implementation baseline is the Windows41 producer above; a later documentation-only publication commit does not change either literal producer. The plan, manifests, captions and copy receipt are local unpublished records identified here by hash. The complete current image manifest is identified by its hash and count; its five selected entries are represented separately. Provenance counts do not imply equivalent provider-review coverage. The [qualification record](../NATIVE-GIT-DIFF-2026-10-24.md) retains original static findings and the scoped source41 disposition rather than rewriting earlier verdicts.

Client-content captures omit OS title chrome. Cached PDFKit views can omit annotation pixels. OS input, screen readers, OCR and PowerPoint fidelity remain separately bounded. Synthetic previews and unselected icon proposals are outside native screenshot provenance. See the [earlier localization provenance](../LOCALIZATION-2026-10-23.md).

## Retained historical screenshots

The following eight earlier PNGs remain in this directory with their original provenance; they are not captures from the current mixed-producer delivery.

| Files | Literal producer and capture | Historical record |
| --- | --- | --- |
| `document-comparison-en.png`, `document-comparison.png` | `9ba86af1a24f0caa3603ee577e81b5bec3d00701`, `Reviset-Languages-7.app` | [Localization validation](../LOCALIZATION-2026-10-23.md) |
| `workbook-comparison-en.png`, `workbook-comparison.png` | `9ba86af1a24f0caa3603ee577e81b5bec3d00701`, `Reviset-Languages-7.app` | [Localization validation](../LOCALIZATION-2026-10-23.md) |
| `macos-document-stacked-en.png`, `macos-workbook-changes-left-en.png` | `29f3a8ad58698bdd5f410efa786ed39022512756`, `Reviset-Workspace8.app` | [Native workspace validation](../NATIVE-WORKSPACES-2026-10-23.md) |
| `windows-document-focus-en.png`, `windows-workbook-en.png` | `29f3a8ad58698bdd5f410efa786ed39022512756`, Windows workflow `39975028777` | [Native workspace validation](../NATIVE-WORKSPACES-2026-10-23.md) |

The localization document captures use synthetic five-version inputs, including a 100 → 120 change, with a LibreOffice-converted PPTX page 2 and an original PDF page 3. The workbook captures show inferred A2 → A3 row movement and actual physical coordinates, with input SKU001 on both sides; they do not show formula recalculation. English/Korean localization captures reuse the same fixed report, assets and SQLite bytes. Native model actions and client views do not establish OS input, VoiceOver traversal, OCR accuracy or original PowerPoint fidelity. The [localization contract](../LOCALIZATION.md) and [quality history](../QUALITY.md) retain their separate scope and limits.
