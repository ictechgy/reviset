// Keep legacy build invocations working while bounding the generated bundle to
// release/. The build removes only this validated app directory before writing.
export function appBuildName(env: Partial<Pick<NodeJS.ProcessEnv, 'REVISET_APP_NAME' | 'DOCVER_APP_NAME'>>): string {
  const name = env.REVISET_APP_NAME ?? env.DOCVER_APP_NAME ?? 'Reviset.app';
  if (!/^(?:Reviset|Docver)(?:-[A-Za-z0-9]+)*\.app$/.test(name)) {
    throw new Error('REVISET_APP_NAME must be Reviset[-suffix].app inside release/ (legacy Docver names are accepted).');
  }
  return name;
}
