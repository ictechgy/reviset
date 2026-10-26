// Bundle warnings are captions, not occurrence-level evidence. Preserve every
// distinct reason while full repeated/page-qualified gaps stay in the report.
export function nativeWarningReasons(gaps:readonly {feature:string;reason:string}[]){
  const seen=new Set<string>(),result:{feature:string;reason:string}[]=[];
  for(const {feature,reason} of gaps){const key=JSON.stringify([feature,reason]);if(!seen.has(key)){seen.add(key);result.push({feature,reason});}}
  return result;
}
