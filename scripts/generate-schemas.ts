import { z } from 'zod';
import { writeFile, mkdir } from 'node:fs/promises';
import { Report, Manifest, FixtureMetadata, Page, Element, Change, Decision,MappingRelation,RelationSelection } from '../packages/schema/index.js';
import { Envelope, querySchemas } from '../packages/query/index.js';
await mkdir('docs/schemas',{recursive:true});
for(const [name,schema] of Object.entries({report:Report,manifest:Manifest,fixture_manifest:FixtureMetadata,page:Page,element:Element,change:Change,mapping_decision:Decision,mapping_relation:MappingRelation,relation_selection:RelationSelection,query_response:Envelope,...querySchemas})) {
  await writeFile(`docs/schemas/${name}.schema.json`,JSON.stringify(z.toJSONSchema(schema,{target:'draft-2020-12',io:name==='manifest'||Object.hasOwn(querySchemas,name)?'input':'output'}),null,2)+'\n');
}
console.log('Wrote versioned model and query schemas (0.3.0; stored0.1/0.2 readable). Bbox sum invariant is enforced at runtime.');
