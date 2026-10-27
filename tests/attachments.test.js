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
  attachment(18,'SI methods.doc'),
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
  assert.deepEqual(Array.from(all.ordered.map(f=>f.id)),[11,14,15,18,12,13]);
  assert(all.ordered.some(f=>f.filename==='random_001.docx'));
  assert(all.ordered.some(f=>f.filename==='SI extra.docx'));
  assert(all.ordered.some(f=>f.filename==='SI methods.doc'));
  assert(all.ordered[0].filename==='main.pdf');
  assert(all.ordered.some(f=>f.filename==='experiment.xlsx'));
  assert(!all.ordered.some(f=>f.id===99));
  assert(all.missing.includes('missing.docx'));
  assert(all.ignored.some(s=>s.includes('web_snapshot.html')));
  assert.equal(bridge.getAttachmentMode(),'all');
  bridge.setAttachmentMode('si');
  const onlySI=await bridge.attachmentsFor(files[0]);
  assert.deepEqual(Array.from(onlySI.ordered.map(f=>f.id)),[11,14,15,18]);
  assert(onlySI.ignored.some(s=>s.includes('random_001.docx')));
  assert(onlySI.ignored.some(s=>s.includes('experiment.xlsx')));
  // One shared template powers Windows/Edge and macOS/Safari.
  const required = [
    'You are a rigorous academic research assistant',
    '[Authors of This Paper]', '[Cited Studies]', '[AI Analysis]',
    '[My Reflections — To Be Completed]',
    '## 0. At-a-Glance Summary',
    '## 3. Key Findings and Quantitative Evidence',
    '## 7. Key Figures, Tables, and SI Navigation',
    '## 8. My Reflections — To Be Completed',
    '## 9. Reading Summary and Retrieval Information',
    'Australian/British academic English',
    'Where file creation is supported',
    'Never invent primary-source evidence',
    '{{title}}', '{{doi}}', '{{date}}', '{{files}}', '{{missing}}'
  ];
  for (const term of required) assert(bridge.defaultTemplate.includes(term), 'Missing English prompt: '+term);
  assert.equal(bridge.defaultTemplate.length, 33608, 'Full balance/MathJax default must be intact');
  assert.equal(bridge.promptMaxLength, 120000);
  assert(bridge.defaultTemplate.length < bridge.promptMaxLength);
  assert(bridge.defaultTemplate.includes('## IV. Scientific tables: structure, readability, and presentation'));
  assert(bridge.defaultTemplate.includes('## II. Mandatory cross-source consistency and quantitative verification'));
  assert(bridge.defaultTemplate.includes('## III. Scientific figure integration and image handling'));
  assert(bridge.defaultTemplate.includes('## 7. Key Figures, Tables, and SI Navigation'));
  assert(bridge.defaultTemplate.includes('Use a compact three-column table:'));
  assert(bridge.defaultTemplate.includes('### Final quality-control checklist'));
  bridge.setTemplate(bridge.defaultTemplate);
  assert.equal(prefs.get(bridge.promptPref).length,33608,'Full prompt must survive preference save');
  assert.equal(bridge.getTemplate().length,33608);
  assert.throws(()=>bridge.setTemplate('X'.repeat(120001)),/120000/);
  bridge.setTemplate('X'.repeat(120000));
  assert.equal(bridge.getTemplate().length,120000,'120k capacity must work');
  prefs.delete(bridge.promptPref);
  assert(bridge.defaultTemplate.includes('## Additional mandatory audit: material, elemental and energy balances'));
  assert(bridge.defaultTemplate.includes('## Mandatory Obsidian/MathJax mathematical formatting'));
  assert(bridge.defaultTemplate.includes('NEVER use \\[ and \\]'));
  assert(!bridge.defaultTemplate.includes('请用中文'));
  const expanded = bridge.renderPrompt({
    title: 'An Academic Study',doi:'',date:'',missing:['Supplement not on disk'],ignored:[]
  },[{role:'MAIN',displayName:'actual-paper.pdf'}]);
  assert(expanded.includes('Title: An Academic Study'));
  assert(expanded.includes('DOI: Not recorded'));
  assert(expanded.includes('Date: Not recorded'));
  assert(expanded.includes('Expected attachments: MAIN: actual-paper.pdf'));
  assert(expanded.includes('Missing or skipped attachments: Supplement not on disk'));
  assert(!expanded.includes('{{title}}'));
  assert(!expanded.includes('{{missing}}'));
  assert(!expanded.includes('：未记录'));
  prefs.set(bridge.promptPref, bridge.legacyDefaultTemplate);
  assert.equal(bridge.getTemplate(), bridge.defaultTemplate, 'Stored old default should migrate');
  prefs.set(bridge.promptPref, bridge.previousBeta18DefaultTemplate);
  assert.equal(bridge.getTemplate(),bridge.defaultTemplate,'Saved beta18 built-in should migrate');
  prefs.set(bridge.promptPref, bridge.previousEnglishDefaultTemplate);
  assert.equal(bridge.getTemplate(),bridge.defaultTemplate,'Saved beta17 English default should migrate');
  prefs.set(bridge.promptPref, 'Custom text; preserve personal preferences');
  assert.equal(bridge.getTemplate(),'Custom text; preserve personal preferences');
  prefs.delete(bridge.promptPref);
  assert.equal(bridge.getTemplate(),bridge.defaultTemplate);
  console.log('PASS: shared English Markdown default, metadata substitutions, legacy default migration, custom prompt preserved');
  console.log('PASS: all-supported mode includes arbitrary DOCX/XLSX; SI-only filters; other-parent excluded; missing tracked');
})().catch(err=>{console.error(err);process.exitCode=1;});
