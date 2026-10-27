/* ChatGPT ZIP / Markdown -> a real Zotero child note via Better Notes.
 * Untrusted ZIP archives are validated before any extracted file is written.
 * The Zotero item pane owns a dedicated drop target; do not intercept native item-list drops.
 */
var ZCGNoteImporter = {
  addonID: "zotero-chatgpt-safari@local.bridge",
  paneID: "zcg-ai-note-import",
  sectionID: null,
  busy: false,
  keepZipPref: "extensions.zoteroChatGPTBridge.keepNoteZIP",
  importedTag: "ChatGPT Bridge Import",
  panelStates: new Map(),
  getKeepZIP() {
    try { return Services.prefs.getBoolPref(this.keepZipPref,false); }
    catch (_) { return false; }
  },
  setKeepZIP(value) {
    Services.prefs.setBoolPref(this.keepZipPref,!!value);
  },
  getChildNotes(parent) {
    if(!parent?.isRegularItem?.()) return [];
    try { return (parent.getNotes?.()||[]).map(id=>Zotero.Items.get(id))
      .filter(note=>note?.isNote?.() && !note.deleted); }
    catch(e) { Zotero.logError(e);return []; }
  },
  getImportedNotes(parent) {
    return this.getChildNotes(parent).filter(note=>{
      try { return note.getTags?.().some(t=>t.tag===this.importedTag); }
      catch(_) { return false; }
    });
  },
  refreshStatus(parent) {
    for(const [body,state] of this.panelStates) {
      if(body.isConnected===false) { this.panelStates.delete(body);continue; }
      if(state.itemID!==parent.id) continue;
      this.renderStatus(state.status,parent,state.win);
    }
  },
  renderStatus(target,parent,win) {
    target.replaceChildren();
    const notes=this.getChildNotes(parent), tagged=this.getImportedNotes(parent);
    const summary=target.ownerDocument.createElementNS("http://www.w3.org/1999/xhtml","div");
    summary.textContent="已有子笔记 "+notes.length+" 篇 · ChatGPT 导入 "+tagged.length+" 篇";
    summary.style.cssText="font-size:12px;opacity:.9;";
    target.appendChild(summary);
    if(!tagged.length) return;
    const recent=tagged[tagged.length-1];
    const link=target.ownerDocument.createElementNS("http://www.w3.org/1999/xhtml","button");
    link.type="button";
    link.textContent="打开最近导入的笔记";
    link.style.cssText="border:0;background:transparent;color:var(--fill-primary,#1769aa);cursor:pointer;font-size:12px;text-decoration:underline;padding:5px 0 0;text-align:left;";
    link.addEventListener("click",e=>{
      e.stopPropagation();
      try {
        const pane=win?.ZoteroPane||Zotero.getMainWindow?.()?.ZoteroPane;
        if(typeof pane?.selectItem!=="function") throw new Error("Zotero 笔记定位功能不可用");
        void pane.selectItem(recent.id);
      }catch(err){Zotero.logError(err);this.notify(win,"打开笔记失败："+err.message);}
    });
    target.appendChild(link);
  },
  limits: { zip: 80*1024*1024, total: 120*1024*1024, md: 8*1024*1024,
            image: 24*1024*1024, entries: 400 },
  supportedImage: /\.(?:png|jpe?g|gif|webp)$/i,

  getParent(item) {
    if (item?.isRegularItem?.()) return item;
    if (item?.isAttachment?.() && item.parentItemID) {
      const parent=Zotero.Items.get(item.parentItemID);
      if (parent?.isRegularItem?.()) return parent;
    }
    throw new Error("请选择一条文献（或这条文献的 PDF 附件），不要选择笔记。");
  },
  getBetterNotes() {
    const api=Zotero.BetterNotes?.api?.$import;
    if (!api || typeof api.fromMD!=="function")
      throw new Error("需要安装并启用兼容的 Better Notes 插件，才能把 Markdown 和图片导入 Zotero 子笔记。请先安装 Better Notes。");
    return api;
  },
  checkEntryPath(entryName) {
    const path=String(entryName||"");
    if (!path || path.length>350 || /[\\\u0000-\u001f]/.test(path) ||
        path.startsWith("/") || /^[A-Za-z]:/.test(path))
      throw new Error("不安全的 ZIP 文件路径："+path.slice(0,100));
    const parts=path.replace(/\/$/,"").split("/");
    if (parts.some(p=>!p || p==="." || p===".." || p.length>160 || /[:\u007f]/.test(p)))
      throw new Error("ZIP 包含路径穿越或异常名称："+path.slice(0,100));
    return parts;
  },
  planEntries(entries) {
    // Pure safety gate; never pass a raw archive name to extraction without validation.
    if (!Array.isArray(entries) || !entries.length || entries.length>this.limits.entries)
      throw new Error("ZIP 文件条目数量不符合限制（1–400）。");
    let total=0;const accepted=[],seen=new Set();
    for (const e of entries) {
      const parts=this.checkEntryPath(e.name);
      const key=parts.join("/").toLowerCase();
      if (seen.has(key)) throw new Error("ZIP 含重复或大小写冲突文件："+e.name);
      seen.add(key);
      const bytes=Number(e.size);
      if (!Number.isSafeInteger(bytes) || bytes<0) throw new Error("ZIP 文件大小无效："+e.name);
      total+=bytes;
      if (total>this.limits.total) throw new Error("ZIP 解压总量超过 120 MB，可能是 ZIP bomb。");
      if (e.directory || /^__MACOSX$/i.test(parts[0]) || parts.some(p=>p===".DS_Store")) continue;
      const ext=parts.at(-1).split(".").pop().toLowerCase();
      if (ext==="md") {
        if (bytes<1 || bytes>this.limits.md) throw new Error("Markdown 文件为空或超过 8 MB："+e.name);
        accepted.push({name:e.name,parts,kind:"md",size:bytes});
      } else if (this.supportedImage.test(e.name)) {
        if (bytes>this.limits.image) throw new Error("图片超过 24 MB："+e.name);
        accepted.push({name:e.name,parts,kind:"image",size:bytes});
      }
      // Ignore all other file types, including scripts/HTML/SVG, without executing them.
    }
    const markdown=accepted.filter(x=>x.kind==="md");
    if(!markdown.length) throw new Error("ZIP 内没有 Markdown（.md）文件。");
    return {accepted,markdown,total};
  },
  chooseMarkdown(markdown) {
    if(markdown.length===1) return markdown[0];
    // Do not silently import README or pick the wrong paper when ZIP has multiple notes.
    const candidates=markdown.filter(x=>!/^(readme|license|changelog|index)\.md$/i.test(x.parts.at(-1)));
    if(candidates.length===1) return candidates[0];
    throw new Error("ZIP 中有多个 Markdown 文件，无法安全确定哪一份属于此文献。请先整理为一个主 .md 再导入。");
  },
  newRunDirectory() {
    const base=Services.dirsvc.get("TmpD",Ci.nsIFile).path;
    const name="zcg-note-"+Date.now()+"-"+Math.random().toString(36).slice(2,10);
    return PathUtils.join(base,"ZoteroChatGPTBridge","note-import",name);
  },
  localFile(path) {
    const file=Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    file.initWithPath(path);
    return file;
  },
  async extractZIP(zipPath) {
    const st=await IOUtils.stat(zipPath);
    if(!st?.size || st.size>this.limits.zip) throw new Error("ZIP 为空或超过 80 MB。");
    const reader=Cc["@mozilla.org/libjar/zip-reader;1"].createInstance(Ci.nsIZipReader);
    reader.open(this.localFile(zipPath));
    let root=null;
    try {
      const list=[];const iterator=reader.findEntries(null);
      while(iterator.hasMore()) {
        const name=iterator.getNext();
        const ent=reader.getEntry(name);
        list.push({name,size:Number(ent.realSize),directory:!!ent.isDirectory});
        if(list.length>this.limits.entries) throw new Error("ZIP 条目超过 400。");
      }
      const plan=this.planEntries(list);
      const selected=this.chooseMarkdown(plan.markdown);
      root=this.newRunDirectory();
      await IOUtils.makeDirectory(root,{createAncestors:true});
      for(const file of plan.accepted) {
        const dest=PathUtils.join(root,...file.parts);
        const parent=PathUtils.join(root,...file.parts.slice(0,-1));
        await IOUtils.makeDirectory(parent,{createAncestors:true});
        // Path segments were already verified, so zipReader cannot escape root.
        reader.extract(file.name,this.localFile(dest));
        const actual=await IOUtils.stat(dest);
        if(actual.size!==file.size || actual.size>(file.kind==="md"?this.limits.md:this.limits.image))
          throw new Error("ZIP 解压内容与目录预检不一致："+file.name);
      }
      return {mdPath:PathUtils.join(root,...selected.parts),root,
              imageCount:plan.accepted.filter(x=>x.kind==="image").length};
    } catch(err) {
      if(root) try {await IOUtils.remove(root,{recursive:true});}catch(_) {}
      throw err;
    } finally {reader.close();}
  },
  async inspectMarkdown(mdPath) {
    const st=await IOUtils.stat(mdPath);
    if(!st?.size || st.size>this.limits.md) throw new Error("Markdown 为空或超过 8 MB。");
    const source=await IOUtils.readUTF8(mdPath);
    if(!source.trim()) throw new Error("Markdown 内容为空。");
    // Prevent remote HTML resources from being treated as local images in the report.
    const imageRefs=[...source.matchAll(/!\[[^\]]*\]\((?:<([^>]+)>|([^\s)]+))/g)]
      .map(x=>x[1]||x[2]).filter(x=>!/^https?:\/\//i.test(x));
    const missing=[];
    for(const ref of imageRefs) {
      let decoded=ref;
      try {decoded=decodeURIComponent(ref);}catch(_) {}
      if(/^[a-z]+:/i.test(decoded) || decoded.startsWith("/") ||
        decoded.split(/[\\/]/).includes("..")) {missing.push(ref);continue;}
      const p=PathUtils.join(PathUtils.parent(mdPath),...decoded.split("/"));
      if(!(await IOUtils.exists(p))) missing.push(ref);
    }
    if(missing.length) throw new Error("Markdown 引用了不存在或不安全的图片："+missing.slice(0,4).join(", "));
    return {source,imageRefs};
  },
  async pickFile(win) {
    const picker=Cc["@mozilla.org/filepicker;1"].createInstance(Ci.nsIFilePicker);
    // Firefox/Zotero's modern nsIFilePicker.init expects a BrowsingContext,
    // not an nsIDOMWindow. Passing win directly raises NS_ERROR_XPC_BAD_CONVERT_JS.
    // The item-pane document can be a nested window; prefer its own context,
    // falling back to the top-level Zotero window.
    const browsingContext=win?.browsingContext || Zotero.getMainWindow?.()?.browsingContext;
    if(!browsingContext)
      throw new Error("无法获取 Zotero 主窗口 BrowsingContext；请从 Zotero 文献列表右键打开导入。");
    picker.init(browsingContext,"选择 ChatGPT 阅读笔记 ZIP 或 Markdown",Ci.nsIFilePicker.modeOpen);
    picker.appendFilter("ChatGPT 阅读笔记 (*.zip; *.md)","*.zip;*.md");
    picker.appendFilters(Ci.nsIFilePicker.filterAll);
    const result=await new Promise(resolve=>picker.open(resolve));
    if(result!==Ci.nsIFilePicker.returnOK) return null;
    return picker.file?.path||null;
  },
  notify(win,message) {
    try {win.alert(message);}catch(_){Zotero.debug("ChatGPT Import: "+message);}
  },
  async runImport(parentItem, filePath, win) {
    if(this.busy) throw new Error("已有一项笔记正在导入，请等待当前操作完成。");
    const parent=this.getParent(parentItem);
    const bn=this.getBetterNotes();
    if(!filePath || !/\.zip$|\.md$/i.test(filePath))
      throw new Error("请选择 .zip 或 .md 文件。");
    if(parent.deleted || !parent.id) throw new Error("目标文献无效或已删除。");
    if(!await IOUtils.exists(filePath)) throw new Error("找不到导入文件。");
    this.busy=true;
    let extracted=null, note=null;
    try {
      const isZip=/\.zip$/i.test(filePath);
      extracted=isZip?await this.extractZIP(filePath):{mdPath:filePath,root:null,imageCount:0};
      const examined=await this.inspectMarkdown(extracted.mdPath);
      note=new Zotero.Item("note");
      note.libraryID=parent.libraryID;
      note.parentID=parent.id;
      note.setNote("<div><p>AI Research Note — importing…</p></div>");
      await note.saveTx();
      const result=await bn.fromMD(extracted.mdPath,{noteId:note.id,ignoreVersion:true});
      if(!result?.id || result.id!==note.id) throw new Error("Better Notes 没有确认完成 Markdown 导入。");
      const saved=Zotero.Items.get(note.id);
      if(!saved?.getNote()?.trim() || !saved.getNote().includes("<"))
        throw new Error("导入后子笔记内容为空或无效。");
      // Apply a lightweight, persistent marker to the child note.
      // Never rewrite the imported Markdown title or existing Zotero notes.
      try { saved.addTag(this.importedTag); await saved.saveTx(); }
      catch(e) { Zotero.logError(e); }
      // ZIP backup is optional. Default OFF: an embedded Zotero child note
      // should not automatically create a redundant ZIP attachment.
      let attached=false;
      if(isZip && this.getKeepZIP() && Zotero.Attachments?.importFromFile) {
        try {
          const source=await Zotero.Attachments.importFromFile({
            file:filePath,parentItemID:parent.id,libraryID:parent.libraryID,
            title:"ChatGPT Research Note — original ZIP"
          });
          attached=!!source?.id;
        } catch(e) {Zotero.logError(e);}
      }
      this.refreshStatus(parent);
      this.notify(win,"已导入到「"+String(parent.getField("title")||"文献")+"」的子笔记。"+
        (isZip?"\nZIP 内图片 "+extracted.imageCount+" 张；"+
          (this.getKeepZIP()?(attached?"ZIP 已作为附件保留。":"ZIP 备份失败，请保留下载原件。"):"默认不保存 ZIP 附件。"):"")+
        "\n请打开笔记确认图片和公式显示正确。");
      return saved;
    } catch(e) {
      if(note?.id) {
        try {await note.eraseTx();}catch(err){Zotero.logError(err);}
      }
      throw e;
    } finally {
      this.busy=false;
      // Keep the extracted working tree temporarily: Zotero/Better Notes can
      // finish note-embedded image operations after fromMD resolves.
      // The original ZIP remains the authoritative backup.
    }
  },
  async importSelected(win,path) {
    try {
      const selected=win.ZoteroPane?.getSelectedItems?.()||[];
      if(selected.length!==1) throw new Error("请先在 Zotero 中选择一篇文献。");
      const parent=this.getParent(selected[0]);
      const picked=path||await this.pickFile(win);
      if(picked) await this.runImport(parent,picked,win);
    }catch(e){Zotero.logError(e);this.notify(win,"导入 ChatGPT 笔记失败：\n"+e.message);}
  },
  fileFromDrop(event) {
    const dt=event.dataTransfer;
    if(!dt || dt.files?.length!==1) throw new Error("每次只能拖入一个 ZIP 或 Markdown 文件。");
    let file=null;
    try{file=dt.mozGetDataAt?.("application/x-moz-file",0);}catch(_) {}
    const name=String(file?.leafName||dt.files[0]?.name||"");
    if(!/\.(zip|md)$/i.test(name)) throw new Error("请拖入 ZIP 或 Markdown 文件。");
    const path=file?.path||dt.files[0]?.mozFullPath;
    if(!path) throw new Error("无法访问拖入文件的本地路径。请改用右键菜单的文件选择方式。");
    return path;
  },
  registerItemPane(rootURI) {
    if(this.sectionID || !Zotero.ItemPaneManager?.registerSection) return;
    this.sectionID=Zotero.ItemPaneManager.registerSection({
      paneID:this.paneID, pluginID:this.addonID,
      header:{l10nID:"general-notes",icon:rootURI+"icon.svg"},
      sidenav:{l10nID:"general-notes",icon:rootURI+"icon.svg"},
      // Zotero calls onItemChange before rendering. Disabling a section also
      // hides its navigation icon, including for PDF, SI, and note children.
      onItemChange:({item,setEnabled})=>{
        setEnabled(!!item?.isRegularItem?.());
        return true;
      },
      onDestroy:({body})=>{this.panelStates.delete(body);},
      onRender:({body,item,setSectionSummary})=>{
        body.replaceChildren();
        this.panelStates.delete(body);
        if(!item?.isRegularItem?.()) return; // defensive even if Zotero renders it
        const doc=body.ownerDocument;
        const mainWindow=Zotero.getMainWindow?.()||doc.defaultView;
        const current=item.id;
        const status=doc.createElementNS("http://www.w3.org/1999/xhtml","div");
        status.style.cssText="padding:4px 8px 8px;";
        body.appendChild(status);
        this.panelStates.set(body,{itemID:current,status,win:mainWindow});
        this.renderStatus(status,item,mainWindow);
        const n=this.getImportedNotes(item).length;
        if(typeof setSectionSummary==="function")setSectionSummary(n?"AI 笔记 "+n+" 篇":"导入 ChatGPT 笔记");
        const area=doc.createElementNS("http://www.w3.org/1999/xhtml","div");
        area.textContent="拖入 ChatGPT ZIP / Markdown，创建关联子笔记；或点击选择文件";
        area.style.cssText="border:2px dashed #8d99a6;border-radius:7px;padding:12px 9px;text-align:center;cursor:pointer;margin:3px 0 8px;font-size:12px;";
        body.appendChild(area);
        area.addEventListener("click",()=>{
          void (async()=>{try{const path=await this.pickFile(mainWindow);
            if(path) await this.runImport(Zotero.Items.get(current),path,mainWindow);
          }catch(e){Zotero.logError(e);this.notify(mainWindow,"导入失败："+e.message);}})();
        });
        area.addEventListener("dragover",e=>{
          if(!e.dataTransfer?.types?.includes("Files")) return;
          e.preventDefault();e.dataTransfer.dropEffect="copy";area.style.borderColor="#1e8e5a";
        });
        area.addEventListener("dragleave",()=>{area.style.borderColor="#8d99a6";});
        area.addEventListener("drop",e=>{
          e.preventDefault();e.stopPropagation();
          area.style.borderColor="#8d99a6";
          void (async()=>{try{const path=this.fileFromDrop(e);
            await this.runImport(Zotero.Items.get(current),path,mainWindow);
          }catch(err){Zotero.logError(err);this.notify(mainWindow,"导入失败："+err.message);}})();
        });
        const label=doc.createElementNS("http://www.w3.org/1999/xhtml","label");
        label.style.cssText="display:flex;gap:6px;align-items:center;font-size:11px;cursor:pointer;padding:2px 8px 6px;";
        const checkbox=doc.createElementNS("http://www.w3.org/1999/xhtml","input");
        checkbox.type="checkbox";checkbox.checked=this.getKeepZIP();
        checkbox.addEventListener("change",()=>this.setKeepZIP(checkbox.checked));
        const caption=doc.createElementNS("http://www.w3.org/1999/xhtml","span");
        caption.textContent="同时保留原始 ZIP 附件（默认不保留）";
        label.append(checkbox,caption);
        body.appendChild(label);
      }
    });
  },
  unregisterItemPane() {
    if(!this.sectionID) return;
    try{Zotero.ItemPaneManager.unregisterSection(this.sectionID);}catch(e){Zotero.logError(e);}
    this.sectionID=null;
    this.panelStates.clear();
  }
};
