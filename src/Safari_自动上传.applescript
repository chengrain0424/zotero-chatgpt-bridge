-- Safari ChatGPT direct-attachment upload. NO PDF is copied, only per-run symlinks.
-- Never presses Send; verify Chat mode, attachment count, and upload completion.
property activeStatusPath : missing value

on run argv
    if (count of argv) < 4 then error "缺少附件链接文件夹、提示词、论文标题或日志路径。"
    set linkFolder to item 1 of argv
    set promptPath to item 2 of argv
    set paperTitle to item 3 of argv
    set statusPath to item 4 of argv
    set activeStatusPath to statusPath
    try
        my statusLog(statusPath, "START " & paperTitle & " | " & linkFolder)
        set resultText to my runUpload(linkFolder, promptPath, paperTitle, statusPath)
        my statusLog(statusPath, "DONE " & resultText)
        return resultText
    on error msg number num
        my statusLog(statusPath, "ERROR " & num & " " & msg)
        error msg number num
    end try
end run

on statusLog(statusPath, messageText)
    try
        do shell script "/bin/echo " & quoted form of messageText & " >> " & quoted form of statusPath
    end try
end statusLog

on runUpload(linkFolder, promptPath, paperTitle, statusPath)
    -- Always open a fresh Safari tab and never reuse any old picker folder.
    tell application "Safari"
        activate
        if (count of windows) < 1 then
            make new document with properties {URL:"https://chatgpt.com/"}
        else
            tell front window
                set current tab to (make new tab with properties {URL:"https://chatgpt.com/"})
            end tell
        end if
    end tell
    delay 2.0
    tell application "Safari"
        set activeAddress to URL of current tab of front window
    end tell
    if activeAddress does not contain "chatgpt.com" then error "Safari 新标签不在 chatgpt.com，已停止。"

    my statusLog(statusPath, "NO_DIALOG: 自动继续，最终发送由用户确认")
    tell application "Safari" to activate
    delay 0.5
    my statusLog(statusPath, "PICKER_START " & linkFolder)
    if my openPicker() is false then error "Safari 没有打开原生选文件窗口。请检查 Safari 的 Allow JavaScript from Apple Events、以及 macOS 自动化/辅助功能权限。"
    my pickAllFromFolder(linkFolder)
    delay 2.0
    if my pickerIsOpen() then error "文件选择窗口仍然打开，没有确认完成。请检查弹窗，避免沿用旧目录。"
    my statusLog(statusPath, "PICKER_CLOSED " & linkFolder)

    set promptResult to my insertPromptWithFallback(promptPath)
    my statusLog(statusPath, "PROMPT " & promptResult)
    -- Silent result: no dialog. The user checks attachments and presses Send.
    my statusLog(statusPath, "UPLOAD_FINISHED_NO_SEND: " & promptResult)
    return "准备完成（上传结果请以 ChatGPT 页面实际附件为准，未发送）"
end runUpload


-- Returns PROMPT_PRESENT only if reading back the editor confirms the prompt.
-- If not, prompt.txt stays in clipboard for manual Cmd+V.
on insertPromptWithFallback(promptPath)
    try
        set promptB64 to do shell script "/usr/bin/base64 -i " & quoted form of promptPath & " | /usr/bin/tr -d '\n'"
        do shell script "/bin/cat " & quoted form of promptPath & " | /usr/bin/pbcopy"
        tell application "Safari" to activate
        delay 0.5

        -- Locate a visible contenteditable / textarea and move actual focus to it.
        set focusJS to "(function(){var s=['#prompt-textarea[contenteditable=true]','[data-testid=composer-input][contenteditable=true]','[contenteditable=true][role=textbox]','.ProseMirror[contenteditable=true]','div[contenteditable=true]','textarea'];var e;for(var x of s){e=[...document.querySelectorAll(x)].find(n=>n.getClientRects().length&&!n.closest('[aria-hidden=true]'));if(e)break;}if(!e)return 'NO_COMPOSER';e.scrollIntoView({block:'nearest'});e.focus();e.click();return document.activeElement===e?'FOCUSED':'FOCUS_UNCERTAIN';})()"
        set focusResult to my pageJS(focusJS)
        delay 0.4
        if focusResult is not "NO_COMPOSER" then
            tell application "System Events" to keystroke "v" using {command down}
            delay 1.1
            if my isPromptPresent(promptB64) then return "PROMPT_PRESENT"
        end if

        -- Backup: real user paste sometimes stays in browser chrome instead of
        -- the web editor; use insertText and dispatch a normal input event.
        -- Never overwrite text in a nonempty editor.
        set jsFill to "(function(){const b='" & promptB64 & "';const txt=new TextDecoder('utf-8').decode(Uint8Array.from(atob(b),c=>c.charCodeAt(0)));const ss=['#prompt-textarea[contenteditable=true]','[data-testid=composer-input][contenteditable=true]','[contenteditable=true][role=textbox]','.ProseMirror[contenteditable=true]','div[contenteditable=true]','textarea'];let e;for(const sel of ss){e=[...document.querySelectorAll(sel)].find(n=>n.getClientRects().length&&!n.closest('[aria-hidden=true]'));if(e)break;}if(!e)return 'NO_COMPOSER';const val=()=>e.value!==undefined?e.value:(e.innerText||e.textContent||'');if(val().includes(txt.slice(0,40)))return 'ALREADY_FILLED';if(val().trim())return 'EDITOR_NOT_EMPTY';e.focus();if(e.tagName==='TEXTAREA'){const setter=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,'value').set;setter.call(e,txt);e.dispatchEvent(new Event('input',{bubbles:true}));return 'TEXTAREA_INSERTED';}const selection=window.getSelection();const r=document.createRange();r.selectNodeContents(e);r.collapse(false);selection.removeAllRanges();selection.addRange(r);const ok=document.execCommand('insertText',false,txt);if(!ok)return 'INSERT_TEXT_REJECTED';e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:txt}));return 'EDITABLE_INSERTED';})()"
        set fillStatus to my pageJS(jsFill)
        delay 0.8
        if my isPromptPresent(promptB64) then return "PROMPT_PRESENT"
        do shell script "/bin/cat " & quoted form of promptPath & " | /usr/bin/pbcopy"
        return "聚焦：" & focusResult & "；备用插入：" & fillStatus & "；回读验证未通过"
    on error errMsg number errNum
        try
            do shell script "/bin/cat " & quoted form of promptPath & " | /usr/bin/pbcopy"
        end try
        return "ERROR " & errNum & ": " & errMsg
    end try
end insertPromptWithFallback

on isPromptPresent(promptB64)
    try
        set probeJS to "(function(){const txt=new TextDecoder('utf-8').decode(Uint8Array.from(atob('" & promptB64 & "'),c=>c.charCodeAt(0)));const ss=['#prompt-textarea[contenteditable=true]','[data-testid=composer-input][contenteditable=true]','[contenteditable=true][role=textbox]','.ProseMirror[contenteditable=true]','div[contenteditable=true]','textarea'];for(const sel of ss){for(const e of document.querySelectorAll(sel)){if(!e.getClientRects().length)continue;const t=e.value!==undefined?e.value:(e.innerText||e.textContent||'');if(t.includes(txt.slice(0,40))&&t.length>=Math.min(250,txt.length*0.65))return 'YES';}}return 'NO';})()"
        return my pageJS(probeJS) is "YES"
    on error
        return false
    end try
end isPromptPresent

on pageJS(codeText)
    try
        tell application "Safari"
            return (do JavaScript codeText in current tab of front window) as text
        end tell
    on error errText number errNum
        error "Safari 无法执行网页脚本。请在 Safari → 设置 → 高级打开开发者功能，并在“开发者”菜单勾选 Allow JavaScript from Apple Events。详情：" & errText number errNum
    end try
end pageJS

on pickerIsOpen()
    try
        tell application "System Events"
            tell process "Safari"
                if (count of windows) = 0 then return false
                if (count of sheets of front window) > 0 then return true
                -- Some macOS versions expose the native file chooser as a window.
                repeat with w in windows
                    try
                        set wname to name of w as text
                        if wname is "Open" or wname is "Choose File" or wname is "打开" or wname is "选择文件" then return true
                    end try
                end repeat
            end tell
        end tell
    on error errMsg number errNum
        my statusLog(activeStatusPath, "PICKER_AX_CHECK_ERROR " & errNum & " " & errMsg)
    end try
    return false
end pickerIsOpen

on openPicker()
    -- 1) Click the actual HTML file input, if present. Safari may decline it.
    set r to my pageJS("(function(){var es=[...document.querySelectorAll('input[type=file]')].filter(x=>!x.disabled);if(!es.length)return 'NO_FILE_INPUT';es[es.length-1].click();return 'FILE_INPUT_CLICKED';})()")
    delay 0.8
    my statusLog(activeStatusPath, "OPEN_PICKER_FILE_INPUT " & r)
    if my pickerIsOpen() then return true

    -- 2) Click ChatGPT's composer + / add control, then upload menu item.
    set r to my pageJS("(function(){var es=[...document.querySelectorAll('button,[role=button]')];var b=es.find(x=>/composer-plus-btn/i.test(x.getAttribute('data-testid')||''))||es.find(x=>/add files|add photos|attach|上传|添加文件|添加照片|附件/i.test([x.getAttribute('aria-label'),x.getAttribute('title'),x.innerText].join(' ')));if(!b)return 'NO_ADD_BUTTON';b.click();return 'ADD_CLICKED';})()")
    delay 0.7
    my statusLog(activeStatusPath, "OPEN_PICKER_PLUS " & r)
    if my pickerIsOpen() then return true
    set r to my clickUploadMenu()
    my statusLog(activeStatusPath, "OPEN_PICKER_MENU " & r)
    delay 0.9
    if my pickerIsOpen() then return true

    -- 3) If scripted DOM clicks are rejected, try genuine macOS AX GUI clicks.
    if my accessibilityClick({"Add files and more", "Add photos & files", "Attach files", "添加文件", "添加照片", "添加附件", "附件"}) then
        delay 0.6
        if my pickerIsOpen() then return true
        set r to my clickUploadMenu()
        delay 0.8
        if my pickerIsOpen() then return true
        if my accessibilityClick({"Upload from computer", "Upload files", "Upload file", "Add photos & files", "从电脑上传", "上传文件", "上传照片和文件"}) then
            delay 0.8
            if my pickerIsOpen() then return true
        end if
    end if
    my statusLog(activeStatusPath, "OPEN_PICKER_FAILED: no native picker detected; check Terminal accessibility permission or changed ChatGPT UI")
    return false
end openPicker

on clickUploadMenu()
    return my pageJS("(function(){var es=[...document.querySelectorAll('[role=menuitem],[role=option],button,[role=button]')];var b=es.find(x=>/^(upload files?|upload from computer|add photos? (?:&|and) files?|上传文件|从电脑上传|添加照片和文件)$/i.test((x.innerText||x.getAttribute('aria-label')||'').trim()))||es.find(x=>/upload (?:file|from computer)|add photos? (?:&|and) files?|上传文件|从电脑上传|添加照片和文件/i.test([x.innerText,x.getAttribute('aria-label')].join(' ')));if(!b)return 'NO_UPLOAD_MENU';b.click();return 'UPLOAD_CLICKED';})()")
end clickUploadMenu

on accessibilityClick(wordsToFind)
    try
        tell application "System Events"
            tell process "Safari"
                set nodes to entire contents of front window
                repeat with e in nodes
                    set nm to ""
                    set ds to ""
                    try
                        set nm to name of e as text
                    end try
                    try
                        set ds to description of e as text
                    end try
                    repeat with term in wordsToFind
                        set needle to contents of term
                        if (nm contains needle) or (ds contains needle) then
                            try
                                click e
                                return true
                            end try
                        end if
                    end repeat
                end repeat
            end tell
        end tell
    end try
    return false
end accessibilityClick

on pickAllFromFolder(folderPath)
    tell application "Safari" to activate
    tell application "System Events"
        -- In the native file chooser, navigate to the staging directory.
        keystroke "g" using {command down, shift down}
        delay 0.5
        set the clipboard to folderPath
        keystroke "v" using {command down}
        delay 0.4
        keystroke return
        delay 1.2
        -- Only actual uploadable files are present in this staging folder.
        keystroke "a" using {command down}
        delay 0.4
        keystroke return
    end tell
end pickAllFromFolder
