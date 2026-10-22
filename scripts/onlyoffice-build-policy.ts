// Host paths and generated font metadata may enter only an explicitly selected
// private reference-viewer build, even when a previous provision left dist data.
export function optionalSidecarBuild(appName:string,selection:string|undefined):boolean {
  if(selection===undefined)return false;
  if(selection!=='host-bound'||!['Reviset-Render.app','Reviset-Review.app','Docver-Render.app','Docver-Review.app'].includes(appName))throw new Error('REVISET_OPTIONAL_SIDECAR=host-bound requires REVISET_APP_NAME=Reviset-Render.app or Reviset-Review.app (legacy DOCVER names are accepted).');
  return true;
}
