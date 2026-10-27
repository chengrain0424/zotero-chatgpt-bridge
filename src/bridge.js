/* Zotero 10 / macOS - Reader toolbar -> Safari ChatGPT Chat.
 * Uses ORIGINAL Zotero attachments via hardlinks or original paths for upload; diagnostic symlinks only.
 * No auto-send; normal Chat page only; no public OpenAI API.
 */
var ZCGBridge = {
  addonID: "zotero-chatgpt-safari@local.bridge",
  promptPref: "extensions.zoteroChatGPTBridge.promptTemplate",
  attachmentModePref: "extensions.zoteroChatGPTBridge.attachmentMode",
  browserPref: "extensions.zoteroChatGPTBridge.windowsBrowser",
  windowsScriptSource: null,
  getWindowsBrowser() { try { return Services.prefs.getStringPref(this.browserPref, "edge") === "chrome" ? "chrome" : "edge"; } catch (_) { return "edge"; } },
  setWindowsBrowser(value) { if (!["edge","chrome"].includes(value)) throw new Error("Unsupported browser"); Services.prefs.setStringPref(this.browserPref,value); },
  scriptSource: null,
  busy: false,
  toolbarHandler: null,
  init(script, windowsScript) { this.scriptSource=script; this.windowsScriptSource=windowsScript; },
  defaultTemplate: "You are a rigorous academic research assistant specialising in critical reading, evidence appraisal, and research knowledge management.\n\nBased exclusively on the full text of the paper and any Supplementary Information (SI) that you have actually accessed in this conversation, produce a **complete, detailed, English-language Markdown structured reading note that can be saved directly to Zotero**.\n\n**Bibliographic information**\n\n- Title: {{title}}\n- DOI: {{doi}}\n- Date: {{date}}\n- Expected attachments: {{files}}\n- Missing or skipped attachments: {{missing}}\n\n### I. Principles for reading and evaluating evidence\n\n1. First identify the type of publication, such as an original experimental research article, review, theoretical or computational study, or methodological paper, and adapt the analysis accordingly. For reviews, prioritise the evidence base, cited studies, synthesis of mechanisms, and comparability across studies. For original research, prioritise the methods, experimental controls, results, and the authors' conclusions.\n\n2. Clearly distinguish four sources of knowledge throughout the note:\n\n   - **[Authors of This Paper]**: Research frameworks, original experimental or computational results (where applicable), interpretations, claims, and conclusions put forward by the authors of the paper being analysed.\n   - **[Cited Studies]**: Experiments, calculations, findings, and conclusions reported in other studies cited or discussed by the paper. Never present these as experiments performed by the authors of the present paper. If you have not read the original cited study, do not claim to have independently verified it.\n   - **[AI Analysis]**: Your own evidence-based synthesis, critical appraisal, alternative interpretations, and suggestions for future research. Explicitly separate these from the paper authors' views.\n   - **[My Reflections — To Be Completed]**: Reserve this section for my own thoughts. Do not invent or write personal opinions on my behalf.\n\n3. Further distinguish among **direct experimental measurements, statistical associations, computational predictions, mechanisms proposed by the authors, AI-generated inferences, and unverified hypotheses**. Do not treat indirect characterisation, theoretical calculations, or schematic illustrations as conclusive demonstrations of causality.\n\n4. Provide precise source locations for all important statements wherever possible, for example, `Main PDF p. 8, Fig. 4b` or `SI p. 5, Table S2`. Explicitly state when information is absent, ambiguous, or inaccessible. Never fabricate findings, data, or references.\n\n5. For important quantitative findings, retain the experimental system, control group, operating conditions, numerical values, units, definitions of metrics, and relevant limitations. Do not make unsupported direct comparisons between different experimental systems.\n\n### II. Required structure of the reading note\n\nProduce a substantive Markdown reading note following the structure below. Do not merely provide an empty template. Write the entire final reading note in clear academic English (prefer Australian/British English spelling), including all headings, descriptions, tables, captions, keyword lists, and reflections prompts. Preserve the original article title and established scientific terminology; do not add Chinese translations or bilingual sections.\n\n# Original Title of the Paper\n\n**Bibliographic details:** Authors, year, journal, DOI, publication type, and the full-text/SI attachments actually read.\n\n## 0. At-a-Glance Summary\n\n- Central scientific question\n- Main contributions (up to three)\n- Most representative quantitative findings\n- Most important limitations or controversies\n- One-sentence conclusion\n\n## 1. Background, Research Questions, and Novelty\n\nExplain the background, knowledge gaps, objectives, original contributions, and scope of the research.\n\nClearly distinguish the novelty claimed by the authors from your independent assessment of its significance.\n\n## 2. Research Methods and Sources of Evidence\n\n**Original experimental research:** Describe the experimental apparatus, materials, procedures, key parameters, experimental groups, control design, analytical and characterisation methods, and statistical information.\n\n**Theoretical or computational research:** Describe the models, assumptions, computational methods, boundary conditions, and validation approaches.\n\n**Review articles:** Describe the literature search strategy, inclusion criteria, size and composition of the evidence base, representative cited studies, and the comparability of findings across studies.\n\nIntegrate relevant experimental conditions, additional results, and control experiments reported in the SI.\n\n## 3. Key Findings and Quantitative Evidence\n\nOrganise findings by scientific theme or major discovery rather than simply following the order of paragraphs in the paper.\n\nFor each major finding, explain:\n\n- What did [Authors of This Paper] or [Cited Studies] actually report?\n- What are the results and key numerical values?\n- What were the experimental conditions and control groups?\n- Which page, figure, panel, or table supports the statement?\n- What does the evidence establish, and what does it not establish?\n\nWhere useful, provide a comparative evidence table specifying the study or system, conditions, metrics, numerical results, source location, and limits of interpretation.\n\n## 4. Physical and Chemical Mechanisms and Strength of Evidence\n\nStructure the discussion around the following chain:\n\n**Observed phenomenon → proposed mechanism → supporting evidence → alternative explanations → questions requiring further verification**\n\nClearly distinguish direct experimental observations, indirect experimental support, theoretical calculations, and mechanistic proposals advanced by the authors.\n\nAssess disputed or conflicting mechanisms impartially. Label any independent critical appraisal as [AI Analysis].\n\n## 5. Methodological Value, Engineering Relevance, and Applicability\n\nDiscuss transferable methods, experimental designs, control strategies, and technical approaches.\n\nWhere supported by the paper, evaluate relevance to practical systems, energy consumption, stability, scale-up, cost, material lifetime, and related engineering considerations.\n\nDo not assume that short-term laboratory performance establishes industrial feasibility.\n\n## 6. Limitations and Critical Appraisal\n\nPresent separately:\n\n- Limitations explicitly acknowledged by [Authors of This Paper].\n- Limitations, confounding factors, and alternative explanations identified through [AI Analysis].\n- Questions that cannot be resolved without examining additional primary literature or conducting further experiments.\n\nPropose actionable follow-up studies aimed at addressing critical evidence gaps. Do not present AI-generated research suggestions as [My Reflections].\n\n## 7. Key Figures, Tables, and SI Navigation\n\nIdentify the 3–8 most informative figures, tables, or SI sections. For each, record:\n\n- Figure or table number\n- Exact page in the original PDF or SI\n- Main content and essential numerical information\n- Which conclusion it supports and the associated limitations\n\n**Image-handling rules:**\n\nIf you can genuinely extract images from the uploaded PDFs and save them as files, preferably deliver a `.md` file together with an `images/` folder, using valid relative paths in the Markdown.\n\nIf images have not actually been extracted, write `Original figure to be inserted: Fig. X, PDF p. Y` instead. Do not create broken image links or claim that the Markdown contains images when it does not.\n\n## 8. My Reflections — To Be Completed\n\nLeave the following prompts unanswered for me to complete personally:\n\n- What I consider to be the most valuable contribution of this paper:\n- How this paper relates to my current research:\n- Which conclusions I agree with most or question most:\n- Follow-up research ideas or validation experiments that occurred to me:\n- Additional papers I would like to read:\n\n**Do not fill in this section on my behalf.**\n\n## 9. Reading Summary and Retrieval Information\n\n- 5–10 research keywords in English\n- The 3–5 most important original figures, tables, or page references\n- A concise research takeaway of no more than 100 English words\n\n### III. Final deliverable requirements\n\n**Language requirement: Every part of the final deliverable must be in English. Do not provide Chinese-language summaries, translations, headings, labels, captions, keywords, or commentary.**\n\n1. Produce a **complete, sufficiently detailed, self-contained English-language Markdown reading note**, not merely a brief outline.\n2. Use precise scientific English and preserve quantitative data, control conditions, original figure/table identifiers, and information from the SI.\n3. Clearly separate the views of the paper's authors, findings from cited studies, AI analysis, and my personal reflections.\n4. Adapt the depth and emphasis to the publication type; do not mechanically fill sections that are not applicable.\n5. Use standard Markdown headings, paragraphs, lists, and tables where appropriate, so the note can be retained in Zotero or Better Notes.\n6. Where file creation is supported, also provide a UTF-8 encoded `.md` file. If images have genuinely been extracted, package the Markdown file and `images/` folder together; otherwise, explicitly state that images are not included.\n7. Do not invent primary-source evidence, personal opinions, image files, or download links.\n8. Optimise the note for long-term retrieval, review, and comparison with other research papers in Zotero, rather than for a one-off conversational report.",
  legacyDefaultTemplate: "你是一名严谨的科研文献阅读助手，请只依据本对话上传的文献正文及 SI 进行分析，禁止编造结果或图表信息。\n\n论文：{{title}}\nDOI：{{doi}}\n日期：{{date}}\n\n请用中文分析，保留关键英文术语：\n1. 研究背景、知识空白、核心假设与创新性；\n2. 实验方法、材料、装置、重要参数与对照实验；\n3. 主要结果与定量结论，指明图号/表号/页码；\n4. 物理或化学机理及证据强弱，区分作者结论与推测；\n5. SI 中的额外证据、潜在局限及值得进一步验证的问题；\n6. 生成可保存到 Zotero 的结构化阅读笔记。\n\n本次预期附件：\n{{files}}\n缺失或跳过：{{missing}}\n\n如任何附件无法读取，请明确说明，不得假装已阅读。",
  getTemplate() {
    try {
      const saved=Services.prefs.getStringPref(this.promptPref, "");
      const current=saved.trim();
      // Exact old built-in template selected via the Settings Save button
      // is treated as an unchanged default. Genuine custom text is kept.
      if (!current || current===this.legacyDefaultTemplate.trim()) return this.defaultTemplate;
      return current;
    } catch (_) { return this.defaultTemplate; }
  },
  setTemplate(value) {
    const s=String(value || "").trim();
    if (s.length > 20000) throw new Error("Prompt exceeds 20000 characters");
    Services.prefs.setStringPref(this.promptPref,s);
  },
  getAttachmentMode() {
    // v0.3.0 users have no preference; default to all supported siblings.
    try {
      return Services.prefs.getStringPref(this.attachmentModePref, "all") === "si" ? "si" : "all";
    } catch (_) { return "all"; }
  },
  setAttachmentMode(mode) {
    if (mode !== "all" && mode !== "si") throw new Error("无效的附件筛选模式");
    Services.prefs.setStringPref(this.attachmentModePref, mode);
  },
  renderPrompt(data,files) {
    const vals={
      title:data.title,
      doi:data.doi || "Not recorded",
      date:data.date || "Not recorded",
      files:files.map(f=>`${f.role}: ${f.displayName}`).join("\n"),
      missing:[...data.missing,...data.ignored].join("; ") || "None"
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
  reportError(err) {
    try { Zotero.logError(err); } catch (_) {}
    try { Services.prompt.alert(null,"ChatGPT Bridge", String(err?.message || err)); } catch (_) {}
  },
  renderToolbar({reader,doc,append}) {
    if (!reader || !doc || typeof append !== "function") return;
    // Each toolbar render belongs to ONE reader. Never fall back to stale selection.
    const root=doc.createElement("div");
    root.style.cssText="display:inline-flex;align-items:center;gap:4px;margin:0 6px;flex-shrink:0;";
    const analyze=doc.createElement("button");
    analyze.type="button";
    analyze.title="将当前论文及同一条目下符合筛选条件的附件添加到 ChatGPT 普通 Chat";
    analyze.setAttribute("aria-label","用 ChatGPT 分析当前论文");
    analyze.textContent="✦ ChatGPT";
    analyze.style.cssText="border:1px solid var(--color-border,#9ca3af);background:var(--material-toolbar,#f5f5f5);color:inherit;border-radius:5px;padding:4px 9px;cursor:pointer;font-size:12px;white-space:nowrap;";
    analyze.addEventListener("click",event=>{
      event.preventDefault();event.stopPropagation();
      const itemID = reader.itemID || reader._item?.id;
      if (!itemID) { this.reportError(new Error("ChatGPT: 当前阅读器没有 itemID")); return; }
      const item=Zotero.Items.get(itemID);
      if (!item) { this.reportError(new Error(`ChatGPT: 找不到阅读器附件 ${itemID}`));return; }
      analyze.disabled=true;
      analyze.textContent="⏳ 准备中";
      void this.runForItem(item).then(ok=>{
        analyze.disabled=false;
        analyze.textContent=ok ? "✓ 已启动" : "⚠ 查看日志";
        doc.defaultView?.setTimeout(()=>{analyze.textContent="✦ ChatGPT";},4500);
      }).catch(e=>{ analyze.disabled=false;analyze.textContent="⚠ 错误";this.reportError(e); });
    });
    root.appendChild(analyze);
    const edit=doc.createElement("button");
    edit.type="button";
    edit.textContent="⚙";
    edit.title="编辑并保存文献分析 Prompt";
    edit.setAttribute("aria-label","编辑 ChatGPT Prompt");
    edit.style.cssText="border:1px solid var(--color-border,#9ca3af);background:transparent;color:inherit;border-radius:5px;padding:4px 8px;cursor:pointer;";
    edit.addEventListener("click",e=>{e.preventDefault();e.stopPropagation();try {this.toggleEditor(doc, edit);} catch(err) {this.reportError(err);} });
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
    const optionRow=doc.createElement("label");
    optionRow.style.cssText="display:flex;gap:8px;align-items:flex-start;font-size:12px;line-height:1.5;cursor:pointer;";
    const includeAll=doc.createElement("input");
    includeAll.type="checkbox";
    includeAll.checked=this.getAttachmentMode() === "all";
    includeAll.style.cssText="margin-top:3px;flex:none;";
    optionRow.appendChild(includeAll);
    const optionLabel=doc.createElement("span");
    optionLabel.textContent="包含当前文献条目下全部受支持的本地附件（PDF / DOCX / XLSX 等，不要求文件名含 SI）。取消勾选则仅附加正文 PDF 和名称可识别的 SI。";
    optionRow.appendChild(optionLabel);
    panel.appendChild(optionRow);
    if (Zotero.isWin) {
      const browserRow=doc.createElement("label");browserRow.textContent="Windows 浏览器：";
      const select=doc.createElement("select");
      for (const name of ["edge","chrome"]) { const option=doc.createElement("option");option.value=name;option.textContent=name==="edge"?"Microsoft Edge":"Google Chrome";select.appendChild(option); }
      select.value=this.getWindowsBrowser();select.addEventListener("change",()=>this.setWindowsBrowser(select.value));
      browserRow.appendChild(select);panel.appendChild(browserRow);
    }
    const area=doc.createElement("textarea");
    area.value=this.getTemplate();area.spellcheck=false;area.maxLength=20000;
    area.style.cssText="width:100%;height:300px;box-sizing:border-box;resize:vertical;border:1px solid #888;border-radius:5px;padding:10px;background:var(--material-background,#fff);color:inherit;line-height:1.5;font-size:12px;";
    panel.appendChild(area);
    const controls=doc.createElement("div");controls.style.cssText="display:flex;gap:8px;justify-content:flex-end;";
    const make=(label,callback)=>{const btn=doc.createElement("button");btn.type="button";btn.textContent=label;btn.style.cssText="cursor:pointer;padding:5px 10px;border-radius:5px;border:1px solid #aaa;background:transparent;color:inherit;";btn.addEventListener("click",callback);controls.appendChild(btn);};
    make("恢复默认",()=>{area.value=this.defaultTemplate;area.focus();});
    make("取消",()=>panel.remove());
    make("保存",()=>{try{this.setTemplate(area.value);this.setAttachmentMode(includeAll.checked ? "all" : "si");panel.remove();}catch(e){note.textContent=e.message;}});
    panel.appendChild(controls);
    (doc.body || doc.documentElement).appendChild(panel);
    area.focus();
  },
  // Keep a right-click fallback in the library, but the primary UI is the reader toolbar.
  addUI(win) {
    const doc=win.document;
    const context=doc.getElementById("zotero-itemmenu");
    if(context && !doc.getElementById("zcg-context-command")){
      const m=doc.createXULElement("menuitem");
      m.id="zcg-context-command";
      m.setAttribute("label","用 ChatGPT 分析所选论文");
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
    const includeAll = this.getAttachmentMode() === "all";
    let available = [], missing = [], ignored = [];
    for (const a of all) {
      if (!a.isAttachment?.()) continue;
      const label = String(a.getField("title") || "");
      const filename = String(a.attachmentFilename || "");
      let ext = (filename.match(/\.([a-z0-9]{1,8})$/i) || [])[1]?.toLowerCase() || "";
      if (!ext && a.attachmentContentType === "application/pdf") ext = "pdf";
      const si = siRE.test(filename + " " + label);
      // Publishers often name SI "data_1.docx" without any SI keywords.
      if (!formats.has(ext)) {
        ignored.push((filename || label || `ID ${a.id}`) + "：不支持的附件格式");
        continue;
      }
      if (!includeAll && ext !== "pdf" && !si) {
        ignored.push((filename || label || `ID ${a.id}`) + "：仅 SI 模式已跳过");
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
  createHardlinkIfPossible(source, target) {
    // APFS/POSIX hard links reference the same file bytes; they do not copy data.
    // On external filesystems or cross-volume locations, fall back to choosing
    // the original attachment path in Safari instead of an Alias symlink.
    try {
      const exe = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
      exe.initWithPath("/bin/ln");
      const proc = Cc["@mozilla.org/process/util;1"].createInstance(Ci.nsIProcess);
      proc.init(exe);
      const args = [source, target];
      if (typeof proc.runw === "function") proc.runw(true, args, args.length);
      else proc.run(true, args, args.length);
      return proc.exitValue === 0;
    } catch (e) { Zotero.debug(`ZoteroChatGPTBridge hardlink unavailable: ${e}`); return false; }
  },
  async prepare(item) {
    if (Zotero.isWin) return this.prepareWindows(item);
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
    // Each picker gets one regular hardlink in a dedicated directory, if
    // possible. On cross-volume paths use the original Zotero file directly.
    // links_only remains symlinks solely for inspection/diagnostics.
    const pickerRoot = PathUtils.join(runDir, "single_file_picker");
    await IOUtils.makeDirectory(pickerRoot, {createAncestors:true});
    const pickerPaths = [];
    for (let i=0;i<data.ordered.length;i++) {
      const f=data.ordered[i];
      const role = i===0 ? "MAIN" : f.si ? "SI" : f.ext === "pdf" ? "OTHER_PDF" : "OTHER_ATTACHMENT";
      let base = f.filename || f.label || `attachment.${f.ext}`;
      if (base.toLowerCase().endsWith(`.${f.ext}`)) base = base.slice(0,-f.ext.length-1);
      const name = `${String(i+1).padStart(2,"0")}_${role}_${safe(base)}.${f.ext}`;
      const linkPath = PathUtils.join(linkDir, name);
      this.createSymlink(f.sourcePath, linkPath);
      if (!(await IOUtils.exists(linkPath))) throw new Error(`链接未能指向有效文件：${name}`);
      const singleDir = PathUtils.join(pickerRoot, String(i+1).padStart(2, "0"));
      await IOUtils.makeDirectory(singleDir, {createAncestors:true});
      const pickerPath = PathUtils.join(singleDir, name);
      // Avoid macOS NSOpenPanel treating symbolic links as Finder "Alias" items.
      // Hardlink is a second directory entry to the SAME bytes, not a copy.
      // If impossible (cross-device, provider restrictions), select original.
      const hardLinked = this.createHardlinkIfPossible(f.sourcePath, pickerPath);
      if (hardLinked && !(await IOUtils.exists(pickerPath)))
        throw new Error(`单文件硬链接无法读取：${name}`);
      // Use the same single-item staging directory even if the original
      // attachment is on another disk. v0.3.0 successfully used symlinks in
      // its native keyboard chooser, and it prevents dangerous Cmd+A in a
      // real Zotero directory containing unrelated files.
      if (!hardLinked) this.createSymlink(f.sourcePath, pickerPath);
      if (!(await IOUtils.exists(pickerPath)))
        throw new Error(`暂存附件无法读取：${name}`);
      if (/[\r\n]/.test(pickerPath))
        throw new Error(`文件路径含换行符，无法安全交给上传清单：${name}`);
      pickerPaths.push(pickerPath);
      files.push({role, displayName:name, originalPath:f.sourcePath, sourceName:f.filename, size:f.size});
    }
    const prompt = this.renderPrompt(data, files);
    const promptPath = PathUtils.join(runDir, "prompt.txt");
    await IOUtils.writeUTF8(promptPath, prompt);
    const manifestPath = PathUtils.join(runDir, "selection.json");
    await IOUtils.writeUTF8(manifestPath, JSON.stringify({title:data.title, itemID:data.record.id, files,
      missing:data.missing, ignored:data.ignored, linkDir, generatedAt:new Date().toISOString(),
      note:"SYMBOLIC LINKS ONLY: no copies of original PDFs. Do not delete original Zotero attachments."},null,2));
    // Explicit, ordered file paths: avoid native file-picker multi-select/keyboard-focus problems.
    // Upload candidate paths are hardlinks or original files, not diagnostic symlinks.
    const uploadListPath = PathUtils.join(runDir, "upload_paths.txt");
    const uploadPaths = pickerPaths;
    await IOUtils.writeUTF8(uploadListPath, uploadPaths.join("\n") + "\n");
    const scriptPath = PathUtils.join(runDir,"Safari_自动上传.applescript");
    await IOUtils.writeUTF8(scriptPath, this.scriptSource);
    const statusPath = PathUtils.join(runDir,"status.log");
    // Diagnostic markers identify the *actual loaded code*, independent of
    // whatever version the Zotero addon-manager UI currently displays.
    const codeMarker = "SCRIPT_BUILD v0.3.9 v030-keyboard-20261014";
    const embeddedOK = typeof this.scriptSource === "string" && this.scriptSource.includes(codeMarker);
    await IOUtils.writeUTF8(statusPath,
      "BRIDGE_BUILD v0.3.9 v030-keyboard-20261014\n" +
      "EMBEDDED_SCRIPT_MARKER " + (embeddedOK ? "YES" : "NO") + "\n");
    if (!embeddedOK) throw new Error("ChatGPT Bridge 0.3.8: 打包的 Safari 脚本版本不一致，已停止以避免误用旧脚本。");
    // The successful standalone v1.4 used Terminal's existing TCC permissions.
    // Running osascript directly as Zotero can have *different* Accessibility/
    // Apple Events permissions and silently cause picker detection to fail.
    // Delegate only the AppleScript UI layer to Terminal; Zotero still selects
    // the current paper and prepares read-only upload paths without copies.
    const shellQuote = str => "'" + String(str).replace(/'/g, "'\\''") + "'";
    const launcherPath = PathUtils.join(runDir, "Upload_to_ChatGPT.command");
    const args = [scriptPath, linkDir, promptPath, data.title, statusPath, uploadListPath]
      .map(shellQuote).join(" ");
    const command = [
      "#!/bin/bash",
      "# Zotero ChatGPT Bridge: one task, singleton-stage paths, silent UI.",
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
    return {...data, files, linkDir, promptPath, scriptPath, statusPath, uploadListPath, launcherPath, runDir};
  },
  async prepareWindows(item) {
    const data=await this.attachmentsFor(item);
    if (typeof this.windowsScriptSource!=="string" || !this.windowsScriptSource.includes("WIN_SCRIPT_BUILD v0.4.0beta16 uia-20261027"))
      throw new Error("Windows automation script missing from installed package");
    const stamp=new Date().toISOString().replace(/[^0-9]/g,"").slice(0,14);
    const nonce=Math.random().toString(36).slice(2,10);
    const cache=PathUtils.join(Services.dirsvc.get("TmpD",Ci.nsIFile).path,"ZoteroChatGPTBridge");
    const runDir=PathUtils.join(cache,"run-"+stamp+"-"+data.record.id+"-"+nonce);
    await IOUtils.makeDirectory(runDir,{createAncestors:true});
    const files=data.ordered.map((f,i)=>({
      role:i===0?"MAIN":f.si?"SI":f.ext==="pdf"?"OTHER_PDF":"OTHER_ATTACHMENT",
      displayName:f.filename||f.label||("attachment."+f.ext),
      originalPath:f.sourcePath,sourceName:f.filename,size:f.size
    }));
    for (const f of files) if (/[\r\n]/.test(f.originalPath))
      throw new Error("Attachment path contains a newline");
    const promptPath=PathUtils.join(runDir,"prompt.txt");
    const uploadListPath=PathUtils.join(runDir,"upload_paths.txt");
    const scriptPath=PathUtils.join(runDir,"windows_upload.ps1");
    const statusPath=PathUtils.join(runDir,"status.log");
    const prompt=this.renderPrompt(data,files);
    await IOUtils.writeUTF8(promptPath,prompt);
    await IOUtils.writeUTF8(uploadListPath,files.map(f=>f.originalPath).join("\n")+"\n");
    // Windows PowerShell 5.1 expects a BOM for a UTF-8 script with Chinese text.
    await IOUtils.writeUTF8(scriptPath,"\uFEFF"+this.windowsScriptSource.replace(/^\uFEFF/,""));
    await IOUtils.writeUTF8(statusPath,"BRIDGE_BUILD v0.4.0beta16 windows\nSCRIPT_SAVED_UTF8_BOM\n");
    await IOUtils.writeUTF8(PathUtils.join(runDir,"selection.json"),
      JSON.stringify({itemID:data.record.id,title:data.title,files,
        missing:data.missing,ignored:data.ignored,generatedAt:new Date().toISOString()},null,2));
    try { Zotero.Utilities.copyToClipboard(prompt); } catch (_) {}
    return {...data,files,runDir,promptPath,uploadListPath,scriptPath,statusPath};
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
      if(!Zotero.isMac && !Zotero.isWin) throw new Error("仅支持 macOS / Windows");
      const draft=await this.prepare(item);
      if (Zotero.isWin) {
        const args=["-NoProfile","-STA","-ExecutionPolicy","Bypass",
          "-File",draft.scriptPath,"-Browser",this.getWindowsBrowser(),
          "-PromptPath",draft.promptPath,"-UploadListPath",draft.uploadListPath,"-StatusPath",draft.statusPath];
        const powershell=PathUtils.join(Services.dirsvc.get("WinD",Ci.nsIFile).path,
          "System32","WindowsPowerShell","v1.0","powershell.exe");
        const launchPath=PathUtils.join(draft.runDir,"launch_status.txt");
        await IOUtils.writeUTF8(launchPath,"SPAWN_REQUESTED "+powershell+"\n");
        let process;
        try { process=this.runProcess(powershell,args,false); }
        catch(err) { await IOUtils.writeUTF8(launchPath,"SPAWN_FAILED "+String(err)+"\n"); throw err; }
        await IOUtils.writeUTF8(launchPath,"NSIPROCESS_RETURNED pid="+String(process.pid ?? "unknown")+"\n");
        Zotero.debug("ZoteroChatGPTBridge Windows helper launched: "+draft.runDir);
        return true;
      }
      // No modal dialogs or user confirmation; never automatically presses Send.
      const chmod=this.runProcess("/bin/chmod",["700",draft.launcherPath]);
      if(chmod.exitValue!==0) throw new Error("启动脚本 chmod 失败");
      // -g: background, -j: launch Terminal hidden (best effort); actual
      // AppleScript runs as Terminal descendant to reuse existing TCC rights.
      const open=this.runProcess("/usr/bin/open",["-g","-j","-a","Terminal",draft.launcherPath]);
      if(open.exitValue!==0) throw new Error(`无法在后台启动 Terminal (exit=${open.exitValue})`);
      Zotero.debug(`ZoteroChatGPTBridge silent launch: ${draft.title}, ${draft.files.length} files, ${draft.runDir}`);
      return true;
    } catch(e) {this.reportError(e);return false;}
    finally {this.busy=false;}
  }
};
