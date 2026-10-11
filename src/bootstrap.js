/* Zotero 7+ bootstrapped extension. */
var ZCGBridge = null;

function install() {}
function uninstall() {}

async function startup({ rootURI }) {
  await Zotero.initializationPromise;
  if (Zotero.unlockPromise) await Zotero.unlockPromise;
  if (Zotero.uiReadyPromise) await Zotero.uiReadyPromise;
  const scope = { Zotero, Services, Cc, Ci, IOUtils, PathUtils };
  Services.scriptloader.loadSubScript(rootURI + "safari_source.js", scope);
  Services.scriptloader.loadSubScript(rootURI + "bridge.js", scope);
  ZCGBridge = scope.ZCGBridge;
  ZCGBridge.init(scope.SAFARI_SOURCE);
  ZCGBridge.registerReaderToolbar();
  for (const win of Zotero.getMainWindows()) ZCGBridge.addUI(win);
}

function shutdown() {
  if (ZCGBridge) {
    ZCGBridge.unregisterReaderToolbar();
    for (const win of Zotero.getMainWindows()) ZCGBridge.removeUI(win);
    ZCGBridge = null;
  }
}

function onMainWindowLoad({ window }) { if (ZCGBridge) ZCGBridge.addUI(window); }
function onMainWindowUnload({ window }) { if (ZCGBridge) ZCGBridge.removeUI(window); }
