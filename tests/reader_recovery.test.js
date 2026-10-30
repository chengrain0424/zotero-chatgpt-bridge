'use strict';
// Test both Zotero 10 reader session recovery and normal official toolbar rendering.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

function node(tag,doc) {
  const element={
    tagName:tag,ownerDocument:doc,parentNode:null,children:[],attributes:{},
    textContent:'',style:{},className:'',
    setAttribute(k,v){this.attributes[k]=String(v);},
    getAttribute(k){return this.attributes[k]??null;},
    appendChild(c){c.parentNode=this;this.children.push(c);return c;},
    append(...nodes){nodes.forEach(n=>this.appendChild(n));},
    remove(){if(!this.parentNode)return;const p=this.parentNode;
      p.children=p.children.filter(n=>n!==this);this.parentNode=null;},
    closest(selector){
      for(let e=this.parentNode;e;e=e.parentNode) {
        if(selector==='[data-zcg-restored="true"]'&&e.attributes['data-zcg-restored']==='true')
          return e;
      }
      return null;
    },
    addEventListener(event,fn){(this.listeners??={})[event]=fn;},
    contains(v){return this===v||this.children.some(c=>c.contains(v));},
    querySelector(selector){
      if(selector==='[data-zcg-toolbar="true"]')return find(this,n=>n.attributes['data-zcg-toolbar']==='true');
      return null;
    },
    querySelectorAll(selector){
      if(selector==='[data-zcg-toolbar="true"]')return collect(this,n=>n.attributes['data-zcg-toolbar']==='true');
      return [];
    },
    replaceChildren(){for(const c of this.children)c.parentNode=null;this.children=[];}
  };
  return element;
}
function find(root,pred){for(const c of root.children){if(pred(c))return c;const found=find(c,pred);if(found)return found;}return null;}
function collect(root,pred){let out=[];for(const c of root.children){if(pred(c))out.push(c);out.push(...collect(c,pred));}return out;}
function fixture(){
  const doc={defaultView:{closed:false,setTimeout:()=>{}},createElement(tag){return node(tag,doc);}};
  const slot=node('div',doc);
  slot.className='custom-sections';
  doc.querySelector=selector=>
    selector==='.toolbar .end .custom-sections'?slot:
    selector==='[data-zcg-toolbar="true"]'?slot.querySelector(selector):null;
  doc.querySelectorAll=selector=>slot.querySelectorAll(selector);
  const reader={itemID:88,_iframeWindow:{document:doc}};
  return {doc,slot,reader};
}
const restored=fixture(),closed=fixture();
const readers=[restored.reader,closed.reader];
let hooked=null,registered=0,unregistered=0,delayCalls=0;
const sandbox={
 Zotero:{
  Reader:{
    _readers:readers,
    registerEventListener(type,handler,id){assert.equal(type,'renderToolbar');
      assert.equal(id,'zotero-chatgpt-safari@local.bridge');hooked=handler;registered++;},
    unregisterEventListener(type,handler){assert.equal(type,'renderToolbar');
      assert.equal(handler,hooked);unregistered++;},
  },
  Promise:{delay:async()=>{delayCalls++;}},
  Items:{get:()=>({id:88})},
  logError(e){throw e;}
 },
 Services:{prefs:{}},
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(path.join(__dirname,'../src/bridge.js'),'utf8')+'\nthis.BRIDGE=ZCGBridge;',sandbox);
const bridge=sandbox.BRIDGE;
(async()=>{
  // A tab reopened from Zotero's previous session is already mounted before
  // startup registers the renderToolbar listener. This was the regression.
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,0);
  const initial=bridge.registerReaderToolbar();
  assert.equal(initial,undefined);
  assert.equal(registered,1);
  // recovery is asynchronous but its first scan happens before first await
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  assert.equal(closed.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  const rendered=restored.slot.querySelector('[data-zcg-toolbar="true"]');
  assert.equal(rendered.children.length,2);
  assert.equal(rendered.children[0].textContent,'✦ ChatGPT');
  assert.equal(rendered.children[1].textContent,'⚙');
  // Scan reruns must not duplicate any controls.
  assert.equal(bridge.ensureExistingReaderToolbar(restored.reader),true);
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  // A native React re-render clears the slot and emits renderToolbar;
  // the official listener repopulates exactly one set of controls.
  restored.slot.replaceChildren();
  hooked({reader:restored.reader,doc:restored.doc,
    append:(root)=>{const section=restored.doc.createElement('div');
      section.className='section';section.appendChild(root);restored.slot.appendChild(section);}});
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  hooked({reader:restored.reader,doc:restored.doc,
    append:()=>{throw Error('duplicate should not append');}});
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  // Zotero's reader isn't initialized yet: a later retry should fill it.
  const late=fixture(), notReady={_iframeWindow:null},first=bridge.ensureExistingReaderToolbar(notReady);
  assert.equal(first,false);
  notReady._iframeWindow={document:late.doc};
  assert.equal(bridge.ensureExistingReaderToolbar(notReady),true);
  assert.equal(late.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  // Disabling/removing the add-on deletes both recovered and event-created UI.
  bridge.unregisterReaderToolbar();
  assert.equal(unregistered,1);
  assert.equal(bridge.toolbarHandler,null);
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,0);
  assert.equal(closed.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,0);
  // A stale pending recovery must not bring disabled UI back.
  await Promise.resolve();await Promise.resolve();await Promise.resolve();
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,0);
  // A subsequent re-enable can re-register without duplicates.
  readers.splice(0,readers.length,restored.reader);
  bridge.registerReaderToolbar();
  assert.equal(registered,2);
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,1);
  bridge.unregisterReaderToolbar();
  assert.equal(unregistered,2);
  assert.equal(restored.slot.querySelectorAll('[data-zcg-toolbar="true"]').length,0);
  console.log('PASS Zotero session-restored PDF toolbar, normal re-render, idempotence, late init, shutdown/re-enable cleanup');
})().catch(e=>{console.error(e);process.exitCode=1;});
