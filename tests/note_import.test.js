'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const data=new Map();
const parent={id:41,libraryID:1,isRegularItem:()=>true,getField:()=> 'Test paper',
  getNotes:()=>[...data.values()].filter(n=>n.parentID===41).map(n=>n.id)};
const attachment={id:42,parentItemID:41,isAttachment:()=>true,isRegularItem:()=>false};
let current=50;
class Item {
 constructor(type){assert.equal(type,'note');this.id=++current;this.text='';this.tags=[];this.saved=false;}
 isNote(){return true;}
 addTag(tag){if(!this.tags.includes(tag))this.tags.push(tag);}
 getTags(){return this.tags.map(tag=>({tag}));}
 setNote(x){this.text=x;}
 getNote(){return this.text;}
 async saveTx(){this.saved=true;data.set(this.id,this);}
 async eraseTx(){this.erased=true;data.delete(this.id);}
}
let backupCalls=0;
const zipPrefs=new Map();
let sectionConfig=null;
const sandbox={
 Zotero:{
  Items:{get:id=>id===41?parent:id===42?attachment:data.get(id)},
  Item, logError:()=>{},
  BetterNotes:{api:{$import:{fromMD:async(file,{noteId})=>{
    assert.equal(file,'/archive/paper.md');
    assert.equal(noteId,current);
    const n=data.get(noteId);n.setNote('<div><h1>Research summary</h1><p>Evidence</p></div>');await n.saveTx();return n;
  }}}},
  Attachments:{importFromFile:async({parentItemID})=>{assert.equal(parentItemID,41);backupCalls++;return{id:99};}},
  ItemPaneManager:{registerSection:config=>{sectionConfig=config;return 'registered-section';},unregisterSection:()=>{}}
 },
 Services:{dirsvc:{get:()=>({path:'/tmp'})},prefs:{
  getBoolPref:(key,def)=>zipPrefs.get(key)??def,
  setBoolPref:(key,val)=>zipPrefs.set(key,val)}},
 PathUtils:{join:(...pieces)=>pieces.join('/'),parent:p=>p.slice(0,p.lastIndexOf('/'))},
 Ci:{nsIFile:'nsIFile'},
 IOUtils:{exists:async()=>true,stat:async()=>({size:512}),readUTF8:async()=> '# Research summary\n\nOne paragraph',makeDirectory:async()=>{},remove:async()=>{}},
 Cc:{},
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname,'../src/note_import.js'),'utf8')+'\nthis.IMPORTER=ZCGNoteImporter;',sandbox);
const imp=sandbox.IMPORTER;
async function rejects(f,re){await assert.rejects(f,re);}
(async()=>{
 // Regression for the real Windows error:
 // nsIFilePicker.init's first argument must be BrowsingContext, never Window.
 const browserContext={contextToken:'zotero-main'};
 let observedContext=null;
 let pickerResult=0;
 const fakePicker={
   init:(context,title,mode)=>{
     if(context!==browserContext) throw new TypeError('Could not convert JavaScript argument arg 0 [nsIFilePicker.init]');
     observedContext=context;
     assert.equal(mode,0);
     assert(title.includes('ChatGPT'));
   },
   appendFilter:()=>{},
   appendFilters:()=>{},
   get file(){return {path:'/tmp/research.zip'};},
   open:callback=>callback(pickerResult),
 };
 sandbox.Ci.nsIFilePicker={modeOpen:0,returnOK:0,returnCancel:1,filterAll:1};
 sandbox.Cc['@mozilla.org/filepicker;1']={createInstance:()=>fakePicker};
 const pickerWindow={browsingContext:browserContext};
 assert.equal(await imp.pickFile(pickerWindow),'/tmp/research.zip');
 assert.strictEqual(observedContext,browserContext);
 pickerResult=1;
 assert.equal(await imp.pickFile(pickerWindow),null,'cancelling the picker must not import');
 pickerResult=0;
 sandbox.Zotero.getMainWindow=()=>({browsingContext:browserContext});
 assert.equal(await imp.pickFile({}),'/tmp/research.zip','nested pane can use main browsingContext');
 sandbox.Zotero.getMainWindow=()=>({browsingContext:null});
 await rejects(()=>imp.pickFile({}),/BrowsingContext/);
 sandbox.Zotero.getMainWindow=()=>({browsingContext:browserContext});
 console.log('PASS Windows native picker uses BrowsingContext, handles cancel and nested pane');
 assert.equal(imp.getParent(parent).id,41);
 assert.equal(imp.getParent(attachment).id,41);
 assert.throws(()=>imp.getParent({isNote:()=>true}),/请选择/);
 assert.throws(()=>imp.checkEntryPath('../evil.md'),/不安全|路径穿越/);
 for(const name of ['/root.md','C:/root.md','./foo.md','a/../b.md','a//b.md','a\\b.md','a/b:bad.md','foo\u0000.md'])
   assert.throws(()=>imp.checkEntryPath(name),/不安全|路径穿越|异常名称/,name);
 assert.deepEqual(Array.from(imp.checkEntryPath('paper/images/fig-1.png')),['paper','images','fig-1.png']);
 const manifest=[
  {name:'paper/paper.md',size:1024,directory:false},
  {name:'paper/images/fig-1.png',size:1024,directory:false},
  {name:'paper/images/fig-2.jpg',size:800,directory:false},
  {name:'paper/extra.json',size:200,directory:false},
  {name:'__MACOSX/_junk.md',size:10,directory:false}
 ];
 const plan=imp.planEntries(manifest);
 assert.equal(plan.markdown.length,1);
 assert.equal(plan.accepted.length,3,'only Markdown/images extracted');
 assert.equal(imp.chooseMarkdown(plan.markdown).name,'paper/paper.md');
 assert.throws(()=>imp.planEntries([{name:'evil.md',size:125*1024*1024}]),/120 MB/);
 assert.throws(()=>imp.planEntries([{name:'a.md',size:100},{name:'A.MD',size:100}]),/重复|冲突/);
 assert.throws(()=>imp.planEntries([{name:'a.txt',size:1}]),/没有 Markdown/);
 assert.throws(()=>imp.chooseMarkdown([{parts:['one.md']},{parts:['two.md']}]),/多个 Markdown/);
 const source=await imp.inspectMarkdown('/archive/paper.md');
 assert.equal(source.imageRefs.length,0);
 assert.throws(()=>imp.fileFromDrop({dataTransfer:{files:[{name:'a.pdf'}]}}),/ZIP|Markdown/);
 assert.equal(imp.fileFromDrop({dataTransfer:{files:[{name:'a.zip',mozFullPath:'/tmp/a.zip'}]}}),'/tmp/a.zip');
 const saved=[];
 const win={alert:s=>saved.push(s)};
 // Only a top-level reference item should show the Zotero import section.
 imp.registerItemPane('resource://zcg/');
 assert.equal(imp.sectionID,'registered-section');
 let isEnabled=null;
 sectionConfig.onItemChange({item:parent,setEnabled:x=>isEnabled=x});
 assert.equal(isEnabled,true,'regular parent should show the import section');
 sectionConfig.onItemChange({item:attachment,setEnabled:x=>isEnabled=x});
 assert.equal(isEnabled,false,'PDF attachment must not show the import section');
 sectionConfig.onItemChange({item:{isRegularItem:()=>false,isNote:()=>true},setEnabled:x=>isEnabled=x});
 assert.equal(isEnabled,false,'child note must not show the import section');
 sectionConfig.onItemChange({item:null,setEnabled:x=>isEnabled=x});
 assert.equal(isEnabled,false,'no selected reference hides the import section');
 // ZIP backup preference is OFF unless the user explicitly opts in.
 assert.equal(imp.getKeepZIP(),false);
 assert.equal(imp.getChildNotes(parent).length,0);
 assert.equal(imp.getImportedNotes(parent).length,0);
 const doc={createElementNS:(_ns,type)=>({
   type,children:[],style:{},ownerDocument:doc,
   replaceChildren(){this.children=[];},appendChild(child){this.children.push(child);},
   addEventListener(){},set textContent(x){this.text=x;},get textContent(){return this.text;}
 })};
 const status={ownerDocument:doc,children:[],replaceChildren(){this.children=[];},appendChild(el){this.children.push(el);}};
 imp.renderStatus(status,parent,win);
 assert.match(status.children[0].textContent,/已有子笔记 0 篇 · ChatGPT 导入 0 篇/);

 // Verify plain Markdown path and parent binding / no replace-on-duplicate.
 const n=await imp.runImport(parent,'/archive/paper.md',win);
 assert.equal(n.parentID,41);
 assert(n.getNote().includes('Research summary'));
 assert(saved.some(x=>x.includes('已导入')));
 assert.equal(data.size,1);
 assert.equal(imp.getImportedNotes(parent).length,1,'imported note retains provenance marker');
 imp.renderStatus(status,parent,win);
 assert.match(status.children[0].textContent,/已有子笔记 1 篇 · ChatGPT 导入 1 篇/);
 assert.equal(status.children.length,2,'the import status offers an open-last-note link');
 const n2=await imp.runImport(parent,'/archive/paper.md',win);
 assert.notEqual(n.id,n2.id,'re-import should create a separate child note');
 sandbox.Zotero.BetterNotes=null;
 await rejects(()=>imp.runImport(parent,'/archive/paper.md',win),/Better Notes/);
 assert.equal(data.size,2,'no empty notes created when dependency missing');
 sandbox.Zotero.BetterNotes={api:{$import:{fromMD:async(file,{noteId})=>{
   const n=data.get(noteId);n.setNote('<div><h1>ZIP research summary</h1></div>');await n.saveTx();return n;
 }}}};
 // No redundant ZIP attached by default; explicit opt-in creates one.
 imp.extractZIP=async()=>({mdPath:'/archive/paper.md',root:'/tmp/test-zcg',imageCount:2});
 const n3=await imp.runImport(parent,'/tmp/research.zip',win);
 assert.equal(backupCalls,0,'default ZIP import must not create an attachment');
 assert.equal(n3.parentID,41);
 imp.setKeepZIP(true);
 assert.equal(imp.getKeepZIP(),true);
 await imp.runImport(parent,'/tmp/research.zip',win);
 assert.equal(backupCalls,1,'explicit ZIP backup opt-in must attach original');
 assert.equal(imp.getImportedNotes(parent).length,4,'each imported child is individually marked');
 imp.renderStatus(status,parent,win);
 assert.match(status.children[0].textContent,/已有子笔记 4 篇 · ChatGPT 导入 4 篇/);
 imp.unregisterItemPane();
 assert.equal(imp.panelStates.size,0);

 console.log('PASS ZIP security validation, child-note binding, Better Notes API, duplicate-safe import, dependency failure');
})().catch(e=>{console.error(e);process.exitCode=1;});
