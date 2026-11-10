/* Aether Astra — background service worker.
 *
 * "ChatGPT Astra" is not a public API. This extension provides three honest
 * integration points:
 *   1. omnibox keyword "astra" -> ChatGPT web with the query
 *   2. context menu on selected text -> floating ChatGPT window
 *   3. a local side panel that talks to the OpenAI API with a user-supplied key
 */

const CHATGPT = "https://chatgpt.com/";

function chatUrl(query) {
  return query ? `${CHATGPT}?q=${encodeURIComponent(query)}` : CHATGPT;
}

async function openFloating(query) {
  await chrome.windows.create({
    url: chatUrl(query),
    type: "popup",
    width: 480,
    height: 820,
    focused: true
  });
}

async function openPanel(windowId) {
  try {
    await chrome.sidePanel.open({ windowId });
  } catch (_) {
    await openFloating("");
  }
}

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "ask-astra",
      title: 'Ask Astra about "%s"',
      contexts: ["selection"]
    });
  });
});

chrome.contextMenus.onClicked.addListener((info) => {
  if (info.menuItemId === "ask-astra" && info.selectionText) {
    openFloating(info.selectionText.slice(0, 4000));
  }
});

chrome.action.onClicked.addListener(async (tab) => {
  await openPanel(tab.windowId);
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== "open-astra") return;
  const [tab] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (tab?.windowId != null) await openPanel(tab.windowId);
});

chrome.omnibox.onInputEntered.addListener((text) => {
  openFloating(text.trim());
});
