# Security and privacy

This plugin reads local Zotero attachments and asks your own browser session to attach them to chatgpt.com. It has no API key and does not need or request your ChatGPT password, tokens or cookies. **Review the intended attachments before sending**; the browser upload transmits full file contents.

The plugin creates a task-specific cache under `~/Library/Caches/ZoteroChatGPTBridge/` with symlinks to original Zotero files, a local prompt, metadata and a status log. The cache may reveal document titles and original local paths. Do not include logs or research files in public issues. The plugin does not automatically submit messages, does not fetch SI from journal websites, and does not circumvent access controls or website anti-bot verification.

Do not use it with restricted, unpublished or third-party confidential documents unless permitted under your research data policy and the destination ChatGPT account settings. Browser DOM automation may break, including silently; rely on the visible ChatGPT attachment list for verification.

Report security issues privately to the repository maintainer (contact to be provided by repo owner). Do not publish credentials or confidential examples in an issue.
