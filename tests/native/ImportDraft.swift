import Foundation
import AppKit
import SwiftUI

@main struct ImportDraftRegression {
 static func require(_ condition:Bool,_ message:String)throws {
  if !condition{throw NSError(domain:"ImportDraft",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
 }
 static func main() {
  do{try exercise();print("PASS actual import draft identities, labels, group/ungroup/reorder and selected SHA payload")}
  catch{fputs("FAIL \(error.localizedDescription)\n",stderr);exit(1)}
 }
 static func exercise()throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let aURL=root.appendingPathComponent("first.pdf"),bURL=root.appendingPathComponent("second.PPTX"),cURL=root.appendingPathComponent("third.pdf")
  try Data("abc".utf8).write(to:aURL)
  var a=try ImportRow.selected(aURL);a.label="초안 수정 이름"
  var b=ImportRow(label:"별도 원본 이름",urls:[bURL]);b.label="검토본 수정 이름"
  let c=ImportRow(label:"마지막",urls:[cURL]),original=[a,b,c]
  try require(a.members[0].identity?.sha256=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","Selected file digest must bind actual bytes")
  let payload=a.createPayload
  try require((payload["files"] as? [String])==[aURL.path] && (payload["expected_sha256"] as? [String])==[a.members[0].identity!.sha256],"Selected identity must follow create payload")
  let legacy=b.createPayload
  try require(Set(legacy.keys)==Set(["label","files"]),"Legacy create payload must remain unchanged")
  var rows=original
  try require(ImportRow.group(&rows,at:1),"Unlike singleton rows should group")
  let firstGroupID=rows[0].id
  try require(firstGroupID != a.id && firstGroupID != b.id,"A group has its own identity")
  try require(rows[0].members.map(\.id)==[a.id,b.id] && rows[0].urls==[aURL,bURL],"Member identity and explicit order survive grouping, even PDF first")
  let mixedPayload=rows[0].createPayload["expected_sha256"] as? [Any]
  try require(mixedPayload?.count==2 && mixedPayload?[0] as? String==a.members[0].identity?.sha256 && mixedPayload?[1] is NSNull,"A legacy member must not downgrade a selected member's verification")
  try require(ImportRow.ungroup(&rows,at:0) && rows==original,"Unedited group/ungroup must restore every field")
  try require(ImportRow.group(&rows,at:1),"Regroup")
  try require(rows[0].id != firstGroupID,"A new group gets a new identity")
  rows[0].label="통합 검토본"
  try require(ImportRow.move(&rows,at:0,by:1) && rows[0]==c && rows[1].members.map(\.id)==[a.id,b.id],"A group moves as one unit")
  try require(ImportRow.ungroup(&rows,at:1),"Ungroup moved bundle")
  try require(rows.map(\.id)==[c.id,a.id,b.id] && rows.map(\.label)==[c.label,"통합 검토본",b.label],"Ungroup inserts adjacent rows and preserves edited group name on first member")
  try require(rows[1].members[0].label=="통합 검토본" && rows[2].members[0].label==b.label,"Restored member labels stay internally consistent")
  try require(rows[1].members[0].identity==a.members[0].identity,"Fingerprint stays with its member through group/edit/move/ungroup")
  let unchanged=rows
  try require(!ImportRow.group(&rows,at:0) && !ImportRow.move(&rows,at:0,by:Int.min) && !ImportRow.ungroup(&rows,at:0) && rows==unchanged,"Invalid actions must not mutate draft")
  var sameFormat=[a,c];try require(!ImportRow.group(&sameFormat,at:1) && sameFormat==[a,c],"Same-format grouping rejected")
  var triple=original;try require(ImportRow.group(&triple,at:1) && !ImportRow.group(&triple,at:1),"A group cannot accept a third input")
  try Data("abd".utf8).write(to:aURL)
  try require(try ImportFileIdentity.capture(aURL) != a.members[0].identity,"Same-length file mutation must change digest")
  try require((a.createPayload["expected_sha256"] as? [String])==["ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],"Create keeps the reviewed selection identity after external mutation")
 }
}
