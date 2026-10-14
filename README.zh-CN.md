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

1. 从仓库 [`dist/`](dist/) 目录下载 `.xpi` 原始文件，或在发布后从 [Releases](../../releases) 下载。
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


### v0.3.7 本地诊断测试版

增加了 Zotero 桥接代码与 Safari AppleScript 独立版本标记，参见 [诊断指南](UPGRADE_v0.3.7.md)。尚未发布到 GitHub。


### v0.3.8 quick-confirm test

See [v0.3.8 test guide](UPGRADE_v0.3.8.md). This is a local testing build, not a stable release.
