/* Zotero 10 / macOS - Reader toolbar -> Safari ChatGPT Chat.
 * Uses ORIGINAL Zotero PDF/SI via temporary symlinks, no PDF copies.
 * No auto-send; normal Chat page only; no public OpenAI API.
 */
var ZCGBridge = {
  addonID: "zotero-chatgpt-safari@local.bridge",
  promptPref: "extensions.zoteroChatGPTBridge.promptTemplate",
  scriptSource: null,
  busy: false,
  toolbarHandler: null,
  init(script) { this.scriptSource=script; },
  defaultTemplate: `你是一名严谨的科研文献阅读助手，请只依据本对话上传的文献正文及 SI 进行分析，禁止编造结果或图表信息。

论文：{{title}}
DOI：{{doi}}
日期：{{date}}

请用中文分析，保留关键英文术语：
1. 研究背景、知识空白、核心假设与创新性；
2. 实验方法、材料、装置、重要参数与对照实验；
3. 主要结果与定量结论，指明图号/表号/页码；
4. 物理或化学机理及证据强弱，区分作者结论与推测；
5. SI 中的额外证据、潜在局限及值得进一步验证的问题；
6. 生成可保存到 Zotero 的结构化阅读笔记。

本次预期附件：
{{files}}
缺失或跳过：{{missing}}

如任何附件无法读取，请明确说明，不得假装已阅读。`,
  getTemplate() {
    try {
      const s=Services.prefs.getStringPref(this.promptPref, "");
      return s.trim() || this.defaultTemplate;
    } catch (e) { return this.defaultTemplate; }
  },
  setTemplate(value) {
    const s=String(value || "").trim();
    if (s.length > 20000) throw new Error("Prompt 超过 20000 字符");
    Services.prefs.setStringPref(this.promptPref, s);
  },
  renderPrompt(data,files) {
    const vals={
      title:data.title,
      doi:data.doi || "未记录",
      date:data.date || "未记录",
      files:files.map(f=>`${f.role}: ${f.displayName}`).join("\n"),
      missing:[...data.missing,...data.ignored].join("；") || "无"
    };
    return this.getTemplate().replace(/\{\{\s*(title|doi|date|files|missing)\s*\}\}/gi,
      (_m,key) => vals[key.toLowerCase()] || "");
  },
  registerReaderToolbar() {
    if (this.toolbarHandler) return;
    this.toolbarHandler = event => {
      try { this.renderToolbar(event); } catch(e) { Zotero.logError(e); }
    };
    Zotero.Reader.registerEventListener("renderToolbar", this.toolbarHandler, this.addonID);
  },
  unregisterReaderToolbar() {
    if (!this.toolbarHandler) return;
    try { Zotero.Reader.unregisterEventListener("renderToolbar",this.toolbarHandler); }
    catch(e) { Zotero.logError(e); }
    this.toolbarHandler=null;
  },
  renderToolbar({reader,doc,append}) {
    if (!reader || !doc || typeof append !== "function") return;
    // Each toolbar render belongs to ONE reader. Never fall back to stale selection.
    const root=doc.createElement("div");
    root.style.cssText="display:inline-flex;align-items:center;gap:4px;margin:0 6px;flex-shrink:0;";
    const analyze=doc.createElement("button");
    analyze.type="button";
    analyze.title="将当前论文 PDF 和 SI 添加到 ChatGPT 普通 Chat";
    analyze.setAttribute("aria-label","用 ChatGPT 分析当前论文");
    analyze.textContent="✦ ChatGPT";
    analyze.style.cssText="border:1px solid var(--color-border,#9ca3af);background:var(--material-toolbar,#f5f5f5);color:inherit;border-radius:5px;padding:4px 9px;cursor:pointer;font-size:12px;white-space:nowrap;";
    analyze.addEventListener("click",event=>{
      event.preventDefault();event.stopPropagation();
      const itemID = reader.itemID || reader._item?.id;
      if (!itemID) { Zotero.logError(new Error("ChatGPT: 当前阅读器没有 itemID")); return; }
      const item=Zotero.Items.get(itemID);
      if (!item) { Zotero.logError(new Error(`ChatGPT: 找不到阅读器附件 ${itemID}`));return; }
      analyze.disabled=true;
      analyze.textContent="⏳ 准备中";
      void this.runForItem(item).then(ok=>{
        analyze.disabled=false;
        analyze.textContent=ok ? "✓ 已启动" : "⚠ 查看日志";
        doc.defaultView?.setTimeout(()=>{analyze.textContent="✦ ChatGPT";},4500);
      });
    });
    root.appendChild(analyze);
    const edit=doc.createElement("button");
    edit.type="button";
    edit.textContent="⚙";
    edit.title="编辑并保存文献分析 Prompt";
    edit.setAttribute("aria-label","编辑 ChatGPT Prompt");
    edit.style.cssText="border:1px solid var(--color-border,#9ca3af);background:transparent;color:inherit;border-radius:5px;padding:4px 8px;cursor:pointer;";
    edit.addEventListener("click",e=>{e.preventDefault();e.stopPropagation();this.toggleEditor(doc, edit);});
    root.appendChild(edit);
    append(root);
  },
  toggleEditor(doc,anchor) {
    const id="zcg-prompt-editor-v030";
    let panel=doc.getElementById(id);
    if (panel) {panel.remove();return;}
    panel=doc.createElement("div");
    panel.id=id;
    panel.setAttribute("role","region");
    panel.setAttribute("aria-label","ChatGPT Prompt 编辑器");
    panel.style.cssText="position:fixed;top:58px;right:18px;width:min(500px,calc(100vw - 36px));padding:14px;background:var(--material-sidepane,#fff);color:var(--fill-primary,#222);border:1px solid var(--color-border,#aaa);box-shadow:0 6px 20px #0003;border-radius:9px;z-index:2147483600;display:flex;flex-direction:column;gap:8px;box-sizing:border-box;";
    const heading=doc.createElement("strong");heading.textContent="ChatGPT 文献分析 Prompt";panel.appendChild(heading);
    const note=doc.createElement("div");note.style.cssText="font-size:11px;opacity:.8;";
    note.textContent="可使用 {{title}}、{{doi}}、{{date}}、{{files}}、{{missing}}；保存后所有论文使用该模板。";panel.appendChild(note);
    const area=doc.createElement("textarea");
    area.value=this.getTemplate();area.spellcheck=false;area.maxLength=20000;
    area.style.cssText="width:100%;height:300px;box-sizing:border-box;resize:vertical;border:1px solid #888;border-radius:5px;padding:10px;background:var(--material-background,#fff);color:inherit;line-height:1.5;font-size:12px;";
    panel.appendChild(area);
    const controls=doc.createElement("div");controls.style.cssText="display:flex;gap:8px;justify-content:flex-end;";
    const make=(label,callback)=>{const btn=doc.createElement("button");btn.type="button";btn.textContent=label;btn.style.cssText="cursor:pointer;padding:5px 10px;border-radius:5px;border:1px solid #aaa;background:transparent;color:inherit;";btn.addEventListener("click",callback);controls.appendChild(btn);};
    make("恢复默认",()=>{area.value=this.defaultTemplate;area.focus();});
    make("取消",()=>panel.remove());
    make("保存",()=>{try{this.setTemplate(area.value);panel.remove();}catch(e){note.textContent=e.message;}});
    panel.appendChild(controls);
    doc.body.appendChild(panel);
    area.focus();
  },
  // Keep a right-click fallback in the library, but the primary UI is the reader toolbar.
  addUI(win) {
    const doc=win.document;
    const context=doc.getElementById("zotero-itemmenu");
    if(context && !doc.getElementById("zcg-context-command")){
      const m=doc.createXULElement("menuitem");
      m.id="zcg-context-command";
      m.setAttribute("label","用 ChatGPT 分析所选论文（Safari）");
      m.addEventListener("command",()=>{
        const sel=win.ZoteroPane?.getSelectedItems?.() || [];
        if(sel.length!==1) {Zotero.logError(new Error("ChatGPT: 请只选择一篇论文"));return;}
        void this.runForItem(sel[0]);
      });
      context.appendChild(m);
    }
  },
  removeUI(win){try{win.document.getElementById("zcg-context-command")?.remove();}catch(_){}},
  async attachmentsFor(item) {
    if (item.isNote?.()) throw new Error("选中的是笔记，请选择论文或 PDF 附件。");
    const parent = item.isAttachment?.() && item.parentItemID
      ? Zotero.Items.get(item.parentItemID)
      : item.isRegularItem?.() ? item : null;
    const record = parent || item;
    const all = parent?.isRegularItem?.()
      ? parent.getAttachments().map(id => Zotero.Items.get(id)).filter(Boolean)
      : item.isAttachment?.() ? [item] : [];
    const title = String(record.getField("title") || "Untitled").trim();
    const doi = parent?.isRegularItem?.() ? String(parent.getField("DOI") || "") : "";
    const date = parent?.isRegularItem?.() ? String(parent.getField("date") || "") : "";
    const siRE = /supplement(?:ary|al)?|supporting[\s_-]*information|\bSI\b|\bESI\b|appendi(?:x|ces)|supporting[\s_-]*file|[\s_-]suppl[\s_.-]/i;
    const formats = new Set(["pdf", "doc", "docx", "xls", "xlsx", "csv", "txt", "ppt", "pptx", "md"]);
    let available = [], missing = [], ignored = [];
    for (const a of all) {
      if (!a.isAttachment?.()) continue;
      const label = String(a.getField("title") || "");
      const filename = String(a.attachmentFilename || "");
      let ext = (filename.match(/\.([a-z0-9]{1,8})$/i) || [])[1]?.toLowerCase() || "";
      if (!ext && a.attachmentContentType === "application/pdf") ext = "pdf";
      const si = siRE.test(filename + " " + label);
      if (!formats.has(ext) || (ext !== "pdf" && !si)) {
        if (si) ignored.push(filename || label || `ID ${a.id}`);
        continue;
      }
      let sourcePath = null;
      try { sourcePath = await a.getFilePathAsync(); } catch (_) {}
      if (!sourcePath || !(await IOUtils.exists(sourcePath))) {
        missing.push(filename || label || `ID ${a.id}`); continue;
      }
      const stat = await IOUtils.stat(sourcePath);
      if (!stat.size || stat.size > 100*1024*1024) {
        missing.push((filename || label || `ID ${a.id}`) + "：空文件或超过 100 MB"); continue;
      }
      if (ext === "pdf") {
        const b = await IOUtils.read(sourcePath, { maxBytes: 5 });
        if (Array.from(b, x => String.fromCharCode(x)).join("") !== "%PDF-") {
          missing.push((filename || label) + "：不是有效 PDF"); continue;
        }
      }
      available.push({ id:a.id, filename, label, ext, si, sourcePath, size:stat.size });
    }
    const main = available.find(f=> f.id === item.id && f.ext === "pdf" && !f.si)
      || available.find(f=>f.ext === "pdf" && !f.si)
      || available.find(f=>f.ext === "pdf");
    if (!main) throw new Error("当前论文没有可读取的本地正文 PDF。请检查附件已下载、且 PDF 存储于 Zotero 或链接文件仍存在。");
    const ordered = [main, ...available.filter(f=>f !== main).sort((a,b)=>Number(b.si)-Number(a.si))];
    if (ordered.length > 10) throw new Error("该条目包含超过 10 个符合条件的附件；为避免误传，请先整理附件后重试。");
    return {record, title, doi, date, ordered, missing, ignored};
  },
  createSymlink(source, target) {
    // nsIProcess arguments are passed as argv, no shell expansion/injection.
    const exe = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    exe.initWithPath("/bin/ln");
    const proc = Cc["@mozilla.org/process/util;1"].createInstance(Ci.nsIProcess);
    proc.init(exe);
    const args = ["-s", source, target];
    if (typeof proc.runw === "function") proc.runw(true, args, args.length);
    else proc.run(true, args, args.length);
    if (proc.exitValue !== 0) throw new Error(`建立临时附件链接失败（exit=${proc.exitValue}）：${target}`);
  },
  async prepare(item) {
    const data = await this.attachmentsFor(item);
    const stamp = new Date().toISOString().replace(/[^0-9]/g, "").slice(0,14);
    const nonce = Math.random().toString(36).slice(2,9);
    const cache = PathUtils.join(Services.dirsvc.get("Home", Ci.nsIFile).path, "Library", "Caches", "ZoteroChatGPTBridge");
    // A NEW folder for EVERY invocation: never reuse a previous PDF or SI.
    const runDir = PathUtils.join(cache, `run-${stamp}-${data.record.id}-${nonce}`);
    const linkDir = PathUtils.join(runDir, "links_only");
    await IOUtils.makeDirectory(linkDir, {createAncestors:true});
    const safe = value => Array.from(String(value || "attachment")
      .replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").replace(/^\.+/, "_").trim()).slice(0,54).join("") || "attachment";
    const files = [];
    for (let i=0;i<data.ordered.length;i++) {
      const f=data.ordered[i];
      const role = i===0 ? "MAIN" : f.si ? "SI" : "OTHER_PDF";
      let base = f.filename || f.label || `attachment.${f.ext}`;
      if (base.toLowerCase().endsWith(`.${f.ext}`)) base = base.slice(0,-f.ext.length-1);
      const name = `${String(i+1).padStart(2,"0")}_${role}_${safe(base)}.${f.ext}`;
      const linkPath = PathUtils.join(linkDir, name);
      this.createSymlink(f.sourcePath, linkPath);
      if (!(await IOUtils.exists(linkPath))) throw new Error(`链接未能指向有效文件：${name}`);
      files.push({role, displayName:name, originalPath:f.sourcePath, sourceName:f.filename, size:f.size});
    }
    const prompt = this.renderPrompt(data, files);
    const promptPath = PathUtils.join(runDir, "prompt.txt");
    await IOUtils.writeUTF8(promptPath, prompt);
    const manifestPath = PathUtils.join(runDir, "selection.json");
    await IOUtils.writeUTF8(manifestPath, JSON.stringify({title:data.title, itemID:data.record.id, files,
      missing:data.missing, ignored:data.ignored, linkDir, generatedAt:new Date().toISOString(),
      note:"SYMBOLIC LINKS ONLY: no copies of original PDFs. Do not delete original Zotero attachments."},null,2));
    const scriptPath = PathUtils.join(runDir,"Safari_自动上传.applescript");
    await IOUtils.writeUTF8(scriptPath, this.scriptSource);
    const statusPath = PathUtils.join(runDir,"status.log");
    // The successful standalone v1.4 used Terminal's existing TCC permissions.
    // Running osascript directly as Zotero can have *different* Accessibility/
    // Apple Events permissions and silently cause picker detection to fail.
    // Delegate only the AppleScript UI layer to Terminal; Zotero still selects
    // the current paper and creates a new symlink-only attachment directory.
    const shellQuote = str => "'" + String(str).replace(/'/g, "'\\''") + "'";
    const launcherPath = PathUtils.join(runDir, "Upload_to_ChatGPT.command");
    const args = [scriptPath, linkDir, promptPath, data.title, statusPath]
      .map(shellQuote).join(" ");
    const command = [
      "#!/bin/bash",
      "# Zotero ChatGPT Bridge: one task, original file symlinks, silent UI.",
      "set -o pipefail",
      "# Hide Terminal before using its previously authorized AppleScript environment.",
      "/usr/bin/osascript -e 'tell application \"System Events\" to set visible of process \"Terminal\" to false' >/dev/null 2>&1 || true",
      `/usr/bin/osascript ${args} >> ${shellQuote(statusPath)} 2>&1`,
      'result=$?',
      `printf 'AUTOMATION_EXIT %s\\n' "$result" >> ${shellQuote(statusPath)}`,
      'exit "$result"',
      ""
    ].join("\n");
    await IOUtils.writeUTF8(launcherPath, command);
    try { Zotero.Utilities.copyToClipboard(prompt); } catch (_) {}
    return {...data, files, linkDir, promptPath, scriptPath, statusPath, launcherPath, runDir};
  },
  runProcess(exePath, argv, sync=true) {
    const executable=Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    executable.initWithPath(exePath);
    const proc=Cc["@mozilla.org/process/util;1"].createInstance(Ci.nsIProcess);
    proc.init(executable);
    if(typeof proc.runw==="function") proc.runw(sync,argv,argv.length);
    else proc.run(sync,argv,argv.length);
    return proc;
  },
  async runForItem(item) {
    if(this.busy) return false;
    this.busy=true;
    try {
      if(!Zotero.isMac) throw new Error("仅支持 macOS");
      const draft=await this.prepare(item);
      // No modal dialogs or user confirmation; never automatically presses Send.
      const chmod=this.runProcess("/bin/chmod",["700",draft.launcherPath]);
      if(chmod.exitValue!==0) throw new Error("启动脚本 chmod 失败");
      // -g: background, -j: launch Terminal hidden (best effort); actual
      // AppleScript runs as Terminal descendant to reuse existing TCC rights.
      const open=this.runProcess("/usr/bin/open",["-g","-j","-a","Terminal",draft.launcherPath]);
      if(open.exitValue!==0) throw new Error(`无法在后台启动 Terminal (exit=${open.exitValue})`);
      Zotero.debug(`ZoteroChatGPTBridge silent launch: ${draft.title}, ${draft.files.length} files, ${draft.runDir}`);
      return true;
    } catch(e) {Zotero.logError(e);return false;}
    finally {this.busy=false;}
  }
};
