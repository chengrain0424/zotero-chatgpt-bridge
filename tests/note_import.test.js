'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const data=new Map();
const parent={id:41,libraryID:1,isRegularItem:()=>true,getField:()=> 'Test paper'};
const attachment={id:42,parentItemID:41,isAttachment:()=>true,isRegularItem:()=>false};
let current=50;
class Item {
 constructor(type){assert.equal(type,'note');this.id=++current;this.text='';this.saved=false;}
 setNote(x){this.text=x;}
 getNote(){return this.text;}
 async saveTx(){this.saved=true;data.set(this.id,this);}
 async eraseTx(){this.erased=true;data.delete(this.id);}
}
const sandbox={
 Zotero:{
  Items:{get:id=>id===41?parent:id===42?attachment:data.get(id)},
  Item, logError:()=>{},
  BetterNotes:{api:{$import:{fromMD:async(file,{noteId})=>{
    assert.equal(file,'/archive/paper.md');
    assert.equal(noteId,current);
    const n=data.get(noteId);n.setNote('<div><h1>Research summary</h1><p>Evidence</p></div>');await n.saveTx();return n;
  }}}},
  Attachments:{importFromFile:async({parentItemID})=>{assert.equal(parentItemID,41);return{id:99};}}
 },
 Services:{dirsvc:{get:()=>({path:'/tmp'})}},
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
 // Verify plain Markdown path and parent binding / no replace-on-duplicate.
 const n=await imp.runImport(parent,'/archive/paper.md',win);
 assert.equal(n.parentID,41);
 assert(n.getNote().includes('Research summary'));
 assert(saved.some(x=>x.includes('已导入')));
 assert.equal(data.size,1);
 const n2=await imp.runImport(parent,'/archive/paper.md',win);
 assert.notEqual(n.id,n2.id,'re-import should create a separate child note');
 sandbox.Zotero.BetterNotes=null;
 await rejects(()=>imp.runImport(parent,'/archive/paper.md',win),/Better Notes/);
 assert.equal(data.size,2,'no empty notes created when dependency missing');
 console.log('PASS ZIP security validation, child-note binding, Better Notes API, duplicate-safe import, dependency failure');
})().catch(e=>{console.error(e);process.exitCode=1;});
