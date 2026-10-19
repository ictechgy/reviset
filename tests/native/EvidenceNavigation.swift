import Foundation
import AppKit
import SwiftUI
@main struct EvidenceNavigationRegression {
 @MainActor static func main() async {
  do {try await exercise()}catch {fputs("FAIL \(error.localizedDescription)\n",stderr);exit(1)}
 }
 @MainActor static func exercise() async throws {
  let model=AppModel()
  for (width,height,expectedWidth,expectedHeight) in [(960.0,540.0,400.0,225.0),(100.0,2000.0,12.5,250.0),(2000.0,100.0,400.0,20.0),(0.5,10.0,12.5,250.0)] {
   guard let fitted=fittedPageSize(width:width,height:height,available:CGSize(width:400,height:250)),abs(fitted.width-expectedWidth)<0.000001,abs(fitted.height-expectedHeight)<0.000001 else{throw NSError(domain:"PageFitDistortedAcceptedAspect",code:14)}
  }
  for (width,height) in [(0.0,100.0),(-1.0,100.0),(Double.nan,100.0),(100.0,Double.infinity)] {
   guard fittedPageSize(width:width,height:height,available:CGSize(width:400,height:250))==nil else{throw NSError(domain:"PageFitAcceptedInvalidDimensions",code:15)}
  }
  let revisions:[[String:Any]]=[
   ["revision_occurrence_id":"occ_before","assets":[["asset_id":"pptx_before","format":"pptx"],["asset_id":"pdf_before","format":"pdf"]],"pages":[["page_id":"source_before","asset_id":"pptx_before","appearance":["source_page_id":"reference_before"]],["page_id":"reference_before","asset_id":"pdf_before"],["page_id":"source_before_b","asset_id":"pptx_before"]]],
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
  model.changes=[JSON(["change_id":"unmapped","evidence":[["revision_occurrence_id":"occ_before","page_id":"unmapped_secondary"],["revision_occurrence_id":"occ_after","page_id":"unmapped_secondary_after"]]])]
  model.evidenceWarning="";model.status="분석 완료";model.chooseChange("unmapped")
  guard model.leftPageID=="source_before",model.rightPageID=="source_after",!model.evidenceWarning.isEmpty,model.status=="분석 완료" else{throw NSError(domain:"AutomaticUnmappedEvidenceBlankedPrimaryPicker",code:7,userInfo:[NSLocalizedDescriptionKey:"Automatic evidence selected \(model.leftPageID)/\(model.rightPageID) instead of preserving primary selectors or warning overwrote unrelated status"])}
  model.changes=[JSON(["change_id":"mixed","evidence":[["revision_occurrence_id":"occ_before","page_id":"unmapped_secondary"],["revision_occurrence_id":"occ_before","page_id":"reference_before"],["revision_occurrence_id":"occ_after","page_id":"reference_after"]]])]
  model.leftPageID="";model.rightPageID="";model.chooseChange("mixed")
  guard model.leftPageID=="source_before",model.rightPageID=="source_after",model.evidenceWarning.isEmpty,model.status=="분석 완료" else{throw NSError(domain:"AutomaticMixedEvidenceSelectedSecondary",code:8)}
  model.navigateEvidence(left);model.navigatePage("source_before_b",in:"occ_before");model.selectEvidence()
  guard model.leftPageID=="source_before_b",model.rightPageID=="source_after" else{throw NSError(domain:"ManualPageChoiceLostToOlderPin",code:11)}
  model.navigatePage("reference_before",in:"occ_before")
  guard model.leftPageID=="source_before_b" else{throw NSError(domain:"ManualPickerAcceptedSecondaryPage",code:12)}
  model.navigatePage("source_before",in:"occ_before")
  let split=JSON(["from_occurrence":"a","to_occurrence":"b","evidence":[["revision_occurrence_id":"a","page":1],["revision_occurrence_id":"b","page":2],["revision_occurrence_id":"b","page":1],["revision_occurrence_id":"b","page":1]]])
  guard evidencePageSummary(split)=="p.1 → p.1, p.2",versionDisplayName(0,JSON(["label":"v1"]))=="v1",versionDisplayName(1,JSON(["label":"검토본"]))=="v2 검토본" else{throw NSError(domain:"PageSetsOrVersionLabelsAmbiguous",code:13)}
  model.changes=[JSON(["change_id":"before_only","evidence":[["revision_occurrence_id":"occ_before","page_id":"source_before"]]])];model.chooseChange("before_only")
  guard model.leftPageID=="source_before",model.rightPageID.isEmpty else{throw NSError(domain:"AbsentSideRetainedUnrelatedPage",code:9)}
  model.report=JSON(["report_id":"report_pdf_only","revisions":[["revision_occurrence_id":"occ_pdf","assets":[["asset_id":"pdf_only","format":"pdf"]],"pages":[["page_id":"pdf_page","asset_id":"pdf_only"]]]]]);model.from=0;model.to=0;model.leftPageID="";model.rightPageID="";model.navigateEvidence(JSON(["revision_occurrence_id":"occ_pdf","page_id":"pdf_page"]))
  guard model.leftPageID=="pdf_page",model.rightPageID=="pdf_page" else{throw NSError(domain:"PDFOnlyEvidenceNavigationRegressed",code:6)}
  model.initializing=false;model.evidenceWarning="이전 근거 경고";await model.run("prj_no_bundled_backend_in_isolated_probe")
  guard model.evidenceWarning.isEmpty,!model.busy else{throw NSError(domain:"AnalysisRetainedStaleEvidenceWarning",code:10)}
  print("PASS actual AppModel evidence button mapping, pin, unmapped automatic/mixed/absent-side guards, original source and PDF-only navigation")
 }
}
