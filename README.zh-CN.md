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
