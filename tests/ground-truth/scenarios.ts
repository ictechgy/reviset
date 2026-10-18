// Authored expectations: these are not derived from the matcher or extractor.
export interface SlideSpec { key:string; title:string; body:string; hidden?:boolean; notes?:string }
export interface VersionSpec { formats:('pptx'|'pdf')[]; slides:SlideSpec[]; scan?:boolean; wrongBundle?:boolean }
export interface Scenario { name:string; versions:VersionSpec[]; expected:{ revenue:string[]; temporary?:{added:number;deleted:number}; ambiguity?:boolean; hidden?:boolean; scan?:boolean; inconsistent?:boolean } }
const cover:SlideSpec={key:'overview',title:'사업 개요',body:'지역별 제품 출시 일정과 고객 조사 계획'};
const revenue=(value:string):SlideSpec=>({key:'revenue',title:'매출 전망',body:`예상 매출 ${value}억`,notes:'내부 가정: 계약 일정은 별도 검토'});
const risk:SlideSpec={key:'risk',title:'운영 위험',body:'공급망 지연과 인력 배치 대응책'};
const temporary:SlideSpec={key:'temporary',title:'일회성 실험',body:'이 페이지는 중간 검토에서만 등장'};
const combined:SlideSpec={key:'combined',title:'중장기 전략',body:cover.body+' '+risk.body};
const splitA:SlideSpec={key:'split-a',title:'중장기 전략',body:cover.body};
const splitB:SlideSpec={key:'split-b',title:'중장기 전략',body:risk.body};
const hidden:SlideSpec={key:'hidden',title:'비공개 부록',body:'숨김 슬라이드 유지 여부 확인',hidden:true,notes:'PDF에서 관측할 수 없는 발표자 메모'};
export const scenarios:Scenario[]=[
  {name:'forward',versions:[{formats:['pptx'],slides:[cover,revenue('100'),risk]},{formats:['pdf'],slides:[risk,revenue('120'),cover,temporary]},{formats:['pptx'],slides:[revenue('110'),cover,risk]}],expected:{revenue:['100','120','110'],temporary:{added:1,deleted:1}}},
  {name:'reverse',versions:[{formats:['pdf'],slides:[cover,revenue('100'),risk]},{formats:['pptx'],slides:[risk,revenue('120'),cover,temporary]},{formats:['pdf'],slides:[revenue('110'),cover,risk]}],expected:{revenue:['100','120','110'],temporary:{added:1,deleted:1}}},
  {name:'lifecycle-five',versions:[{formats:['pptx'],slides:[cover,revenue('100'),risk]},{formats:['pdf'],slides:[risk,cover,revenue('120'),temporary]},{formats:['pptx'],slides:[revenue('110'),cover,risk,temporary]},{formats:['pdf'],slides:[cover,risk,revenue('110')]},{formats:['pptx'],slides:[risk,revenue('110'),cover]}],expected:{revenue:['100','120','110','110','110'],temporary:{added:1,deleted:1}}},
  {name:'duplicate-split-merge',versions:[{formats:['pdf'],slides:[cover,revenue('-100.5'),combined]},{formats:['pptx'],slides:[cover,revenue('-120.25'),{...cover,key:'copy'},splitA,splitB]},{formats:['pdf'],slides:[cover,revenue('+110.75'),combined]}],expected:{revenue:['-100.5','-120.25','+110.75'],ambiguity:true}},
  {name:'hidden-gap',versions:[{formats:['pptx'],slides:[cover,revenue('100'),hidden]},{formats:['pdf'],slides:[cover,revenue('120'),hidden]},{formats:['pptx'],slides:[cover,revenue('110'),hidden]}],expected:{revenue:['100','120','110'],hidden:true}},
  {name:'bundle-scan',versions:[{formats:['pptx','pdf'],slides:[cover,revenue('100')]},{formats:['pdf'],slides:[cover,revenue('120')],scan:true},{formats:['pptx','pdf'],slides:[cover,revenue('110')],wrongBundle:true}],expected:{revenue:[],scan:true,inconsistent:true}}
];
