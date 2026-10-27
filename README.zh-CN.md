# Zotero → ChatGPT 普通 Chat（非官方插件）

[English README](README.md) · [开发路线](docs/ROADMAP.md) · [更新记录](CHANGELOG.md)

**v0.3.9 Beta（已在 macOS Safari 环境验证）：Zotero 10 + macOS + Safari。** 在 Zotero PDF 阅读器点击 `✦ ChatGPT`，插件读取**当前论文及同一条目中的受支持本地附件**，通过 Safari 打开 ChatGPT 新对话并尝试附加文件；可以通过 `⚙` 编辑并保存科研分析 Prompt。

它使用你在 Safari 中登录的 **ChatGPT 普通网页聊天**，不调用 OpenAI API，也不消耗 Codex。**必须自行确认页面处于 Chat 而不是 Work**：插件无法可靠检测或切换这一模式；实际额度按你的 ChatGPT 套餐规定执行。

## 功能

- 直接读取 Zotero 原始附件路径，并保留临时符号链接供诊断；实际文件选择器优先使用硬链接，无法建立时使用符号链接，**不复制 PDF 内容**。
- **默认包含同一篇文献父条目下的所有受支持附件**（PDF / DOC / DOCX / XLS / XLSX / CSV / TXT / PPT / PPTX / MD），包括 `data_1.docx` 这种不含 SI 关键词的文件。不会跨条目收集，也不会联网下载缺失文件。
- 打开 Safari 新对话，使用已验证的快速键盘选择流程**逐个添加附件**；**绝不自动点击发送**。
- PDF 工具栏 `⚙` 可修改**附件筛选选项**（勾选：所有受支持附件；取消：正文 PDF + 名称可识别的 SI），并支持编辑 Prompt，可使用 `{{title}}`、`{{doi}}`、`{{date}}`、`{{files}}`、`{{missing}}` 占位符。
- Zotero 文献列表右键菜单提供备用入口。

## 兼容性

| 环境 | 当前状态 |
| --- | --- |
| Zotero 10 + macOS + Safari | 已在一台用户设备完成核心流程测试；**Beta** |
| macOS + Chrome / Edge / 自定义浏览器路径 | 计划支持，未实现 |
| Windows + Chrome / Edge | 计划支持，未实现 |
| Zotero 7–9 | 未验证 |

## 安装

1. 从仓库下载当前 **v0.3.9** 的 [XPI 安装包](dist/Zotero_to_ChatGPT_Direct_v0.3.9_Zotero10.xpi)（点击 **Download raw file**）。原 [v0.3.0-beta Release](../../releases/tag/v0.3.0-beta) 是历史版本，包含旧安装包。
2. Zotero 10 → **工具 → 插件 → 齿轮 → 从文件安装**，安装后重启 Zotero、重新打开 PDF。
3. Safari → 设置 → 高级，启用开发者功能，再在 **开发者菜单**允许 `JavaScript from Apple Events`。
4. 按需授权 macOS「自动化 / 辅助功能」权限。插件当前通过隐藏 Terminal 执行 AppleScript，但**无法保证完全无窗口闪现或系统权限弹窗**。
5. 点击 PDF 顶部 `✦ ChatGPT`。请在 ChatGPT 页面确认使用的是 **普通 Chat**、正文/SI 上传完整且正确，再自行点击发送。

## 限制与安全

- 本工具通过浏览器界面自动化，而不是官方 ChatGPT 上传接口。网站界面改变后可能失效。
- 本地缓存 `~/Library/Caches/ZoteroChatGPTBridge/run-*/` 包含符号链接、Prompt、日志；**原始 PDF 并没有被复制**，但点击发送意味着文献内容将上传到你的 ChatGPT 会话。
- 默认会自动将同一 Zotero 父条目下所有受支持的附件尝试上传到 ChatGPT，包含可能无关或保密的文件；请在 ChatGPT 页面核对附件，必要时在 `⚙` 取消「所有附件」。
- 在用于未发表/保密科研材料前，请先检查上传内容与数据权限。
- 提交 GitHub Issue 前请删除日志中的本机绝对路径、论文标题和可能的敏感信息。
- 生成 `.xpi` 的方法详见 [发布说明](docs/RELEASING.md)。
- 本项目以 [MIT License](LICENSE) 开源；新版本 GitHub Release 建议标记为 **Pre-release**。

## 版本路线

建议先公开 **macOS + Safari Beta**，随后抽象浏览器适配层：macOS Chrome、Edge、自定义路径；最后开发 Windows 专用的文件对话框自动化。不要把未测试的平台标成已支持。

## Windows 10/11 + Zotero 10（实验性版本）

Windows 代码位于 `feature/windows-edge-chrome` 分支，**尚未在真实 Windows 桌面完成端到端验证**。请从该分支自行构建 XPI；旧版 v0.3.9 XPI 仍然只支持 macOS。

- 在 PDF 阅读器的 `⚙` 选择 Edge（默认）或 Chrome。请提前在目标浏览器登录 ChatGPT，并确认处于普通 Chat。
- 插件将 Prompt 和 Zotero **原始本地附件绝对路径**写入 `%TEMP%\\ZoteroChatGPTBridge\\run-*`；不复制原始文件，也不需要 Windows 符号链接权限。
- Windows PowerShell 5.1 辅助脚本通过 UI Automation 尝试打开 ChatGPT 上传菜单和原生文件选择对话框，并逐个选择文件。如果 ChatGPT 网页或系统的无障碍控件变化，可能失败；检测不可靠时会停止。Prompt 同时进入剪贴板，可用 Ctrl+V 手动粘贴。
- Zotero 和浏览器建议都以普通用户权限运行。请查看任务文件夹里的 `status.log`，并在 ChatGPT 网页上核对全部附件。**文件选择器关闭不代表上传成功**；脚本绝不自动发送。
- 启动命令只对该 PowerShell 进程采用 `-ExecutionPolicy Bypass`，不修改 Windows 全局设置。建议运行前阅读脚本源码。

**隐私提醒：** 默认收集同一 Zotero 父条目下全部受支持附件；未发表和保密材料务必核对附件及目标 ChatGPT 账户后再使用。

### Windows beta.4 上传按钮诊断

如果能打开 ChatGPT 但没有自动选择文件，请检查该次任务目录的 `status.log` 中的 `UPLOAD_PLUS_*`、`UPLOAD_MENU_*` 和 `UIA_CANDIDATE`。请先在 Edge/Chrome 完成登录，并确认当前是普通 Chat。程序会首先尝试将 Prompt 粘贴到空白输入框，无法确认输入框时仍会把 Prompt 留在剪贴板供 Ctrl+V。自动上传为实验功能，**文件选择器关闭不代表 ChatGPT 已成功读取文件，也不会自动发送**。提供错误日志前请先隐藏本地路径和私人标题。

### Windows beta.5 故障定位说明

beta.4 的实际 Windows 日志显示已识别到 `Add files and more`，但该控件没有实现通常使用的 UI Automation 调用动作。beta.5 增加焦点确认后的空格键和经过 UIA 命中验证的鼠标点击后备方案，补齐缺失的 `Log-UploadCandidates` 诊断函数，并进一步尝试把 ChatGPT 编辑框识别为 `Document` 类型。仍属于实验性自动化，**不能保证当前网页版 ChatGPT 已成功添加附件或填入 Prompt**，也不会自动点击发送。

### Windows beta.6 文件选择器检测修复

beta.5 运行日志表明网页的 `Add files and more` 和 `Upload from computer` 已被点击，但随后没有识别到 Windows 文件对话框。beta.6 不再假设原生文件选择器必须由 Edge/Chrome 的前台进程承载；在尝试选取文件前会验证文件窗口属于当前 ChatGPT 浏览器窗口，且包含文件名输入控件。如果暂时没能检测到，日志会记录 `WINDOW_STATE`（进程/窗口类型，不包含网页标题），并只在确认为 ChatGPT 前台时尝试一次经过命中验证的上传菜单鼠标点击。请勿自动发送文献和 Prompt 前未经确认的内容；务必手动确认已上传附件。

### Windows beta.7：上传菜单打开后立即关闭

beta.6 的真实运行日志表明，附件加号已由物理鼠标点击成功打开；但调用 ChatGPT 的 `Upload from computer` 这一浏览器 UIA 控件的 `InvokePattern` 后，原生文件选择器没有出现。beta.7 仅对**可命中验证的指定上传菜单项**使用单次物理鼠标点击，避免 UIA 的程序式 InvokePattern 因缺少网页用户激活而只关闭菜单。若控件无法验证，则停止；不会反复点击 `+`。仍是实验修复，需实际 Edge 验证上传结果。

### Windows beta.8：找到“Add files and more”却不能点击

在 beta.7 日志中，诊断器能枚举到 `Add files and more`，但用于点击的 `Find-UIA` 没有返回按钮。二者检查条件不同：后者会过滤掉暂时禁用和不可见的控件，而诊断器没有过滤禁用状态。beta.8 改为**先选择并上传附件，最后粘贴 Prompt**，避免长文本使输入区域重新渲染；对暂不可用的附件按钮短暂重试并记录 `UPLOAD_PLUS_STATE enabled=...` 和 `offscreen=...`。失败时若 ChatGPT 网页仍在前台，仍会尝试安全地粘贴 Prompt；否则放在剪贴板供手动 Ctrl+V。依然不会自动发送，上传须人工核对。

### Windows beta.9：Windows 文件名输入框不支持 ValuePattern

beta.8 的实机日志已经确认打开了受 ChatGPT Edge 窗口拥有的原生文件选择器，但其文件名输入框拒绝 `ValuePattern`。beta.9 在校验文件选择器与“文件名”输入框焦点后，用键盘 `Ctrl+A`、`Ctrl+V` 填入 Zotero 原始附件的**完整绝对路径**，再在同一控件内用 `Ctrl+A`、`Ctrl+C` 读回并与原路径逐字核对。只有读回一致才点击“打开”；如果无法确认焦点或内容，立即停止并保留 Prompt 的剪贴板后备。仍然不会自动发送，点击发送前务必核对 ChatGPT 是否确实附加了目标论文。

### Windows beta.10：文件选择器弹出，但文件路径没有填写

beta.9 的实际日志识别到文件选择器，但 `AutomationId 1148` 对应 `ControlType.Pane` 而不是真正的输入框；因此 `ValuePattern` 和 `SetFocus` 都失败。beta.10 枚举同一 1148 控件及其内部子元素，优先唯一且可交互的 `Edit` 类型控件；如自动聚焦失败，仅在目标命中验证后尝试物理鼠标聚焦，再逐字核验填入的 PDF 全路径。不存在明确的唯一输入框时不执行 Ctrl+A、Ctrl+V，也不点击打开。日志会记录控件类型和 ID，而不记录本地 PDF 路径或 Prompt 内容。仍处于实机测试阶段。

### Windows beta.11：针对文件名输入框 UIA 只暴露 Pane 的情况

beta.10 的实机日志确认文件对话框中 1148 节点全部为 `Pane`，没有 `Edit`。beta.11 使用 Windows 原生窗口句柄检查焦点。通过 `Alt+N` 尝试聚焦“文件名”，随后验证当前焦点的 Win32 父窗口链中包含对话框的 1148 控件，且确实属于已验证的文件选择窗口。只有验证成功才粘贴附件的绝对路径并剪贴板读回；如验证失败，仅记录 `FILENAME_WIN32_FOCUS` 而不尝试输入。这个方法与 Windows 界面语言有关，属于实验性解决方案。不会自动发送 ChatGPT 消息。

### Windows beta.12：通过地址栏进入 PDF 文件夹，独立校验文件名

beta.11 虽然记录 `FILENAME_NATIVE_READBACK_VERIFIED`，但用户实机截图显示原生文件选择器仍停留在 `Script > ICONS`，甚至上传了图片。原因是旧“读取校验”使用 Ctrl+C 读剪贴板，复制失败时剪贴板可能保留了原先路径，导致假阳性。**beta.12 已删除这套剪贴板校验**。

新版上传依次执行：①解析并检查 Zotero 附件文件夹及文件名；②在已验证的原生文件对话框中，通过 Ctrl+L/Alt+D 聚焦地址栏；③粘贴目标文件夹绝对路径，使用 Win32 `WM_GETTEXT` 直接读取地址栏内真实文字并核对；④回车导航到目录，再重新聚焦地址栏并核实当前路径；⑤Alt+N 聚焦原生文件名编辑框 `Edit#1148`，仅输入文件名，用 `WM_GETTEXT` 验证原生编辑框内文本；⑥全部通过后才点击 Open。校验失败立即停止，不会误点导致上传其他文件。仍不会自动发送 Prompt。

重要诊断字段：`ADDRESS_FOCUS`、`ADDRESS_PASTE_VERIFIED`、`FOLDER_NAVIGATED_VERIFIED`、`FILENAME_NATIVE_TEXT_VERIFIED`。**Windows 自动化构建检查不等于实际浏览器上传成功**；请先用公开论文测试并确认附件卡片。

### Windows beta.13：错误上传 .zotero-reader-state 的防护

真实 Edge 截图显示此前上传了 `.zotero-reader-state`，尽管程序执行了地址栏导航与文件名校验。这可能是原生文件对话框的高亮选中项与键入文件名冲突，也可能是 ChatGPT 输入区残留了之前的附件；单凭日志不能确定。beta.13 在浏览器启动前将每个受支持的 Zotero 附件**硬链接到仅含该附件的任务临时目录**（无法建立硬链接时复制），先校验正文必须为 PDF 且以 `%PDF-` 开头、文件扩展名在允许列表中。这样文件选择器里不会再出现 `.zotero-reader-state` 等 Zotero 内部文件。地址栏跳转到新建的单文件临时目录，核实路径，聚焦 `Edit#1148` 并通过 WM_GETTEXT 校验文件名，再从该焦点使用 Enter 提交，不再依赖可能选中高亮项的 Open UIA 调用。不会自动发送。临时目录中可能存在 PDF 硬链接或副本，需要时可手动删除任务目录。若 ChatGPT 输入框中此前已残留错误附件，必须手动移除；插件不会自动移除已添加的附件。

### Windows beta.14：正文 PDF + 多份 SI PDF / Word 顺序上传

已在 Windows 脚本中增加多附件逐个上传：首先上传 Zotero 选中的**正文 PDF**，再按筛选结果上传同一论文父条目下的 SI PDF、DOCX 和旧式 DOC 等受支持文件。每份附件始终使用独立、只有一个文件的暂存目录，避免混入 Zotero 的 `.zotero-reader-state`。每次 Windows 文件选择器关闭后，额外给予浏览器处理时间；上传下一份文件前**重新读取当前 ChatGPT 窗口与“Add files and more”按钮**，等待其变为可用（最多约 50 秒）。如果某份文件无法自动选择，会中止后续附件而不会点击发送。所有文件选择操作结束后才尝试填入 Prompt。文件选择器关闭不保证服务器已经完成上传，请手动核对输入框中的全部附件。

插件提示设置中的“包含全部受支持的本地附件”默认开启；取消勾选则仅上传正文 PDF 与文件名/标题可识别的 SI。为避免漏掉以 `data_1.docx` 等普通名字保存的 SI，通常保留默认设置更实用。日志字段包括 `MULTI_UPLOAD_PLAN`、`STAGED_SINGLE_FILE`、`MULTI_PLUS_READY`、`FILE_START 2/3`、`ALL_PICKERS_CLOSED`。Windows 自动测试覆盖正文 PDF、SI PDF、SI DOCX 三文件单独暂存及排除 Zotero 阅读状态文件；真实 ChatGPT 多附件上传仍需实机确认。

### Windows beta.15：第二份 SI 上传与 Prompt 焦点修复

beta.14 实机日志证实正文 PDF 完成文件选择，第二份 DOCX 的 `Add files and more` 已识别但在 `UIA_MOUSE_TARGET_MISMATCH` 中止；随后因为输入框焦点无法确认，Prompt 仍留在剪贴板。beta.15 保留逐份独立暂存目录与原生文件对话框输入路径流程。新增：附件加号的多个内部点击位置命中检测；每次验证失败重新读取最新浏览器无障碍元素并重试（只会在验证通过后进行**一次**物理点击，不会盲目反复切换“+”）；加入 Chromium RawView 树验证 SVG 图标与按钮的子元素关系；Prompt 先检查已存在内容，自动焦点不可用时仅对确认为 ChatGPT 空编辑框的区域尝试经过命中验证的物理鼠标聚焦，然后再粘贴，绝不覆盖已有草稿、不自动发送。日志可查看 `UPLOAD_PLUS_HIT_RETRY`、`UPLOAD_MENU_PHYSICAL_CLICK item=2`、`FILE_PICKER_CLOSED 2/2`、`PROMPT_FOCUS_VERIFIED`、`PROMPT_PASTE_VERIFIED`。自动化测试不是实际浏览器验证。

### Windows beta.16：连续上传成功后 Prompt 未自动粘贴

beta.15 实际日志显示：两份附件均完成原生文件选择（约 7.7MB PDF + 19.6MB DOCX），第二份文件选择器 13:56:52 关闭，13:56:53 即检查 Prompt。旧脚本因 `editor not empty` 认定 ChatGPT 编辑框已有草稿，因此跳过粘贴，并**不是文件上传等待超时**。beta.16 重新按具体 `Edit` 控件 ID 或严格编辑框名称选择输入区，避免误把整个 ChatGPT 网页的 `Document` 文本当作草稿；识别已知附件名称造成的非空辅助文本（仅附件标签时允许继续，但不使用 Ctrl+A 覆盖任何内容）；在实际可验证的编辑框焦点中粘贴，再核对 Prompt 前缀。如果仍发现未知文字，则停止并将 Prompt 保留在剪贴板，供手动 Ctrl+V。不自动点击发送。日志 `PROMPT_EDITOR_FOUND`、`PROMPT_EDITOR_STATE`、`PROMPT_CHIP_ONLY_TEXT`、`PROMPT_FOCUS_VERIFIED`、`PROMPT_PASTE_VERIFIED` 可进一步定位 Edge 的实际控件语义。

### Windows / macOS beta.17 默认英文 Zotero 文献阅读笔记 Prompt

新 XPI 为 **Windows Edge/Chrome** 和 **macOS Safari** 共享同一份新默认 Prompt，要求 ChatGPT 基于真实读到的正文和 SI，生成英文 Markdown 结构化笔记；严格区分本文作者、被引用研究、AI 分析与留空的个人反思。包括 0–9 节、定量数据及图表出处、图像提取要求和 Better Notes 兼容性。修改仅限默认 Prompt，不影响用户已编辑的个性化版本；如果保存的内容**完全等于旧的中文默认模板**，视为旧默认并自动采用新版。可在 Zotero PDF 工具栏的 ⚙ 中使用“恢复默认”加载新版；不会自动发送消息。

### Windows/macOS beta.18：完整默认 Prompt 与 50,000 字符长度

已将最近讨论的完整英文科研阅读笔记 Prompt（**29,126 字符**）直接设为 Windows/macOS 共享默认：包含正文/SI 数据交叉验证、原始科研图像穿插于正文、紧凑 Markdown 表格规范、公式及数值核查与 0–9 节结构。插件保存上限从 **20,000** 提高至 **50,000** 字符，Zotero PDF 工具栏 ⚙ 设置中显示实时字符计数，偏好设置中的自定义文本框也提高上限。已保存的 beta.17 旧英文默认将自动识别并替换为新版本，用户自行修改的 Prompt 仍保留。Windows 自动粘贴改为**全文校验**，避免仅校验前 30 个字符造成“成功”假阳性。仍不会自动点击发送，必须核对文件和 Prompt 内容。

### Windows/macOS beta.19：解决长 Prompt 粘贴截断

新版本不再让 HTML `maxlength` 属性在编辑时静默裁剪文本。Zotero PDF 工具栏 ⚙ 的 Prompt 编辑器在粘贴前读取剪贴板全文并一次插入，保存前验证写入 Zotero 首选项后的完整文本，显示实时字符数；上限提高至 **120,000 字符**。偏好设置中的另一编辑入口也取消了原生长度裁剪；建议通过阅读器 ⚙ 编辑以获得完整校验。**33,105 字符**新默认 Prompt 内置正文+SI交叉核查、必要的物料及能量衡算、Obsidian MathJax `$...` / `$$...` 格式、图文混排和紧凑表格。安装后选择 **恢复默认→保存**，不用从聊天中复制长提示词。旧的 beta.18 原版默认会被识别并升级，真正个性化编辑的 Prompt 不覆盖。
