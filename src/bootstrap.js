/* Zotero 7+ bootstrapped extension. */
var ZCGBridge = null;
var ZCGNoteImporter = null;

function install() {}
function uninstall() {}

async function startup({ rootURI }) {
  await Zotero.initializationPromise;
  if (Zotero.unlockPromise) await Zotero.unlockPromise;
  if (Zotero.uiReadyPromise) await Zotero.uiReadyPromise;
  const scope = { Zotero, Services, Cc, Ci, IOUtils, PathUtils };
  Services.scriptloader.loadSubScript(rootURI + "safari_source.js", scope);
  Services.scriptloader.loadSubScript(rootURI + "bridge.js", scope);
  Services.scriptloader.loadSubScript(rootURI + "note_import.js", scope);
  ZCGNoteImporter = scope.ZCGNoteImporter;
  ZCGBridge = scope.ZCGBridge;
  Services.scriptloader.loadSubScript(rootURI + "windows_source.js", scope);
  ZCGBridge.init(scope.SAFARI_SOURCE, scope.WINDOWS_SOURCE);
  Zotero.PreferencePanes.register({ pluginID: "zotero-chatgpt-safari@local.bridge", src: rootURI + "prefs.xhtml", label: "ChatGPT Bridge", image: rootURI + "icon.svg" });
  ZCGBridge.registerReaderToolbar();
  ZCGNoteImporter.registerItemPane(rootURI);
  for (const win of Zotero.getMainWindows()) ZCGBridge.addUI(win);
}

function shutdown() {
  if (ZCGBridge) {
    ZCGBridge.unregisterReaderToolbar();
    ZCGNoteImporter?.unregisterItemPane();
    for (const win of Zotero.getMainWindows()) ZCGBridge.removeUI(win);
    ZCGBridge = null;
    ZCGNoteImporter = null;
  }
}

function onMainWindowLoad({ window }) { if (ZCGBridge) ZCGBridge.addUI(window); }
function onMainWindowUnload({ window }) { if (ZCGBridge) ZCGBridge.removeUI(window); }
