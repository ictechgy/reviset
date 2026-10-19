import Foundation
import AppKit
import SwiftUI
@main struct EvidenceNavigationRegression {
 @MainActor static func main() {
  do {try exercise()}catch {fputs("FAIL \(error.localizedDescription)\n",stderr);exit(1)}
 }
 @MainActor static func exercise() throws {
  let model=AppModel()
  let revisions:[[String:Any]]=[
   ["revision_occurrence_id":"occ_before","assets":[["asset_id":"pptx_before","format":"pptx"],["asset_id":"pdf_before","format":"pdf"]],"pages":[["page_id":"source_before","asset_id":"pptx_before","appearance":["source_page_id":"reference_before"]],["page_id":"reference_before","asset_id":"pdf_before"]]],
   ["revision_occurrence_id":"occ_after","assets":[["asset_id":"pptx_after","format":"pptx"],["asset_id":"pdf_after","format":"pdf"]],"pages":[["page_id":"source_after","asset_id":"pptx_after","appearance":["source_page_id":"reference_after"]],["page_id":"reference_after","asset_id":"pdf_after"]]]]
  model.report=JSON(["report_id":"report_navigation","revisions":revisions]);model.from=0;model.to=1;model.tab="compare";model.loadingChanges=false
  let left=JSON(["revision_occurrence_id":"occ_before","page_id":"reference_before"]),right=JSON(["revision_occurrence_id":"occ_after","page_id":"reference_after"])
  model.leftPageID="source_before";model.rightPageID="source_after";model.navigateEvidence(left)
  guard model.leftPageID=="source_before" else{throw NSError(domain:"EvidenceButtonSelectedSecondaryPDF",code:1,userInfo:[NSLocalizedDescriptionKey:"Left evidence click selected \(model.leftPageID), expected primary source_before"])}
  model.navigateEvidence(right)
  guard model.rightPageID=="source_after" else{throw NSError(domain:"EvidenceButtonSelectedSecondaryPDF",code:2,userInfo:[NSLocalizedDescriptionKey:"Right evidence click selected \(model.rightPageID), expected primary source_after"])}
  model.selectEvidence()
  guard model.leftPageID=="source_before",model.rightPageID=="source_after" else{throw NSError(domain:"NavigationPinRetainedSecondaryPDF",code:3)}
  model.navigateEvidence(JSON(["revision_occurrence_id":"occ_before","page_id":"unmapped_secondary"]))
  guard model.leftPageID=="source_before" else{throw NSError(domain:"UnmappedEvidenceBlankedSourcePicker",code:4)}
  model.navigateEvidence(JSON(["revision_occurrence_id":"occ_before","page_id":"source_before"]))
  guard model.leftPageID=="source_before" else{throw NSError(domain:"OriginalSourceNavigationRegressed",code:5)}
  model.report=JSON(["report_id":"report_pdf_only","revisions":[["revision_occurrence_id":"occ_pdf","assets":[["asset_id":"pdf_only","format":"pdf"]],"pages":[["page_id":"pdf_page","asset_id":"pdf_only"]]]]]);model.from=0;model.to=0;model.leftPageID="";model.rightPageID="";model.navigateEvidence(JSON(["revision_occurrence_id":"occ_pdf","page_id":"pdf_page"]))
  guard model.leftPageID=="pdf_page",model.rightPageID=="pdf_page" else{throw NSError(domain:"PDFOnlyEvidenceNavigationRegressed",code:6)}
  print("PASS actual AppModel evidence button mapping, pin, unmapped guard, original source and PDF-only navigation")
 }
}
