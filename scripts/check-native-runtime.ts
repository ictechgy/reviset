import {preparePdfjs} from './prepare-pdfjs.js';
await preparePdfjs();
if(process.platform==='darwin'&&process.arch==='arm64'){
  await import('./build-native-helpers.js');
}
