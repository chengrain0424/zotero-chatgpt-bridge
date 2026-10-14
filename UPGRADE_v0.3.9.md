# v0.3.9 — 恢复 v0.3.0 快捷键流程（实验版）

此版本专门针对 macOS Safari 文件选择器在 v0.3.5–v0.3.8 中因为 `entire contents` 辅助功能扫描导致的约 40 秒/文件的延迟。**已经在一台 Mac 上完成 PDF + SI 实机功能验证**。

- 继续使用 Zotero 当前文献的所有受支持本地附件（PDF、DOCX、XLSX 等），可在 `⚙` 修改 SI 筛选模式和 Prompt。
- 每个附件在 `single_file_picker/01`、`02` 等目录中准备单独一个文件；优先硬链接，不复制文献内容；跨磁盘时使用符号链接。
- 恢复用户验证流畅的 v0.3.0 上传快捷键：`⌘⇧G` → 目录 → Return → `⌘A` → Return，逐个附件执行。
- 不再执行复杂文件列表行/Upload 按钮辅助功能树扫描。**若快捷键失效，及时停止并保留文件选择器，需手动点选，不会再等待数十秒去尝试扫描**。
- 每次 `status.log` 会写入 `BRIDGE_BUILD v0.3.9 v030-keyboard-20261014`、`SCRIPT_BUILD v0.3.9 v030-keyboard-20261014` 及 `FILE_V030_...` 日志。
- 仍然不会点击 ChatGPT 的 Send；请核对附件是否真实上传完成和 Chat / Work 模式。

安装后完全退出并重启 Zotero，重新打开 PDF 再测试同一篇含 1 PDF + 1 DOCX 的文献。可将成功/失败的 `status.log` 去标识化后发给我以确认实际耗时。

该版本拟替换 GitHub `main` 上的当前发行安装包；保留旧版 Git 历史和历史 Release。
