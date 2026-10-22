import test from 'node:test';
import assert from 'node:assert/strict';
import {appBuildName} from '../../scripts/app-build-name.js';

test('Reviset build names retain legacy invocations without allowing a path outside release', () => {
  assert.equal(appBuildName({}), 'Reviset.app');
  assert.equal(appBuildName({REVISET_APP_NAME:'Reviset-Local.app'}), 'Reviset-Local.app');
  assert.equal(appBuildName({DOCVER_APP_NAME:'Docver-Review.app'}), 'Docver-Review.app');
  assert.equal(appBuildName({DOCVER_APP_NAME:'Reviset-Local.app'}), 'Reviset-Local.app');
  assert.equal(appBuildName({REVISET_APP_NAME:'Reviset.app',DOCVER_APP_NAME:'Docver.app'}), 'Reviset.app');
  for (const name of ['', '../Reviset.app', '/Applications/Reviset.app', 'Reviset/Other.app', 'Reviset..app', 'Reviset-.app', 'Other.app', 'Reviset.app/']) {
    assert.throws(() => appBuildName({REVISET_APP_NAME:name}));
    assert.throws(() => appBuildName({DOCVER_APP_NAME:name}));
  }
});
