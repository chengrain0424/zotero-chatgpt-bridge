'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const records=new Map();
const prefs=new Map();
function attachment(id, name, parentItemID=7, exists=true, size=3000){
  return {
    id, parentItemID, attachmentFilename:name,
    attachmentContentType:name.endsWith('.pdf') ? 'application/pdf' : 'application/octet-stream',
    isAttachment:()=>true,
    isRegularItem:()=>false,
    getField: field=>field==='title'?name:'',
    getFilePathAsync:async()=>exists?`/fake/${id}/${name}`:null
  };
}
const files=[
  attachment(11,'main.pdf'),
  attachment(12,'random_001.docx'),
  attachment(13,'experiment.xlsx'),
  attachment(14,'Supporting information.pdf'),
  attachment(15,'SI extra.docx'),
  attachment(16,'web_snapshot.html'),
  attachment(17,'missing.docx',7,false),
];
files.forEach(x=>records.set(x.id,x));
const parent={
  id:7,
  isAttachment:()=>false,
  isRegularItem:()=>true,
  getAttachments:()=>files.map(f=>f.id),
  getField: field=>({title:'Test article',DOI:'10.1/test',date:'2026'}[field]||'')
};
records.set(7,parent);
// Different parent must not be included even if on disk.
records.set(99,attachment(99,'Other library SI.docx',55));
const sandbox={
  Services:{prefs:{getStringPref:(k,fallback)=>prefs.get(k)??fallback,setStringPref:(k,v)=>prefs.set(k,v)}},
  Zotero:{Items:{get:id=>records.get(id)}},
  IOUtils:{
    exists:async p=>!p.includes('missing.docx'),
    stat:async p=>({size:3000}),
    read:async p=>new TextEncoder().encode('%PDF-')
  },
  TextEncoder
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname,'../src/bridge.js'),'utf8')+'\nthis.TEST_BRIDGE=ZCGBridge;',sandbox);
const bridge=sandbox.TEST_BRIDGE;
(async()=>{
  const all=await bridge.attachmentsFor(files[0]);
  assert.deepEqual(Array.from(all.ordered.map(f=>f.id)),[11,14,15,12,13]);
  assert(all.ordered.some(f=>f.filename==='random_001.docx'));
  assert(all.ordered.some(f=>f.filename==='experiment.xlsx'));
  assert(!all.ordered.some(f=>f.id===99));
  assert(all.missing.includes('missing.docx'));
  assert(all.ignored.some(s=>s.includes('web_snapshot.html')));
  assert.equal(bridge.getAttachmentMode(),'all');
  bridge.setAttachmentMode('si');
  const onlySI=await bridge.attachmentsFor(files[0]);
  assert.deepEqual(Array.from(onlySI.ordered.map(f=>f.id)),[11,14,15]);
  assert(onlySI.ignored.some(s=>s.includes('random_001.docx')));
  assert(onlySI.ignored.some(s=>s.includes('experiment.xlsx')));
  console.log('PASS: all-supported mode includes arbitrary DOCX/XLSX; SI-only filters; other-parent excluded; missing tracked');
})().catch(err=>{console.error(err);process.exitCode=1;});
