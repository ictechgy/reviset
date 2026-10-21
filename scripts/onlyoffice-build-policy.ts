// Host paths and generated font metadata may enter only an explicitly selected
// private reference-viewer build, even when a previous provision left dist data.
export function optionalSidecarBuild(appName:string,selection:string|undefined):boolean {
  if(selection===undefined)return false;
  if(selection!=='host-bound'||!['Docver-Render.app','Docver-Review.app'].includes(appName))throw new Error('DOCVER_OPTIONAL_SIDECAR=host-bound requires DOCVER_APP_NAME=Docver-Render.app or Docver-Review.app.');
  return true;
}
