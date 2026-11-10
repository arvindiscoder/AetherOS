/* Aether Astra side panel. Plain DOM, no remote code, no inline scripts. */

const $ = (id) => document.getElementById(id);
const chat = $("chat");
const promptEl = $("prompt");
const sendBtn = document.querySelector('button[type="submit"]');
const keyEl = $("api-key");
const modelEl = $("model");

const SYSTEM = [
  "You are Astra, the concise assistant built into AetherOS.",
  "Prefer short, actionable answers. Use plain text unless code is requested.",
  "You are running in a Chromium side panel on a low-memory Wayland desktop."
].join(" ");

let history = [];
let busy = false;

function addMessage(role, text, cls = role) {
  const article = document.createElement("article");
  article.className = `msg ${cls}`;
  const p = document.createElement("p");
  p.textContent = text;
  article.appendChild(p);
  chat.appendChild(article);
  chat.scrollTop = chat.scrollHeight;
  return article;
}

async function loadSettings() {
  const { apiKey = "", model = "gpt-4o-mini" } = await chrome.storage.local.get(["apiKey", "model"]);
  keyEl.value = apiKey;
  modelEl.value = model;
  if (!apiKey) $("settings").classList.remove("hidden");
}

function saveSettings() {
  const apiKey = keyEl.value.trim();
  const model = modelEl.value.trim() || "gpt-4o-mini";
  chrome.storage.local.set({ apiKey, model });
  $("settings").classList.add("hidden");
  addMessage("assistant", apiKey
    ? "Key saved locally. Ask away."
    : "No key saved. The side panel will use the floating ChatGPT window instead.");
}

async function send() {
  if (busy) return;
  const text = promptEl.value.trim();
  if (!text) return;

  const { apiKey = "", model = "gpt-4o-mini" } = await chrome.storage.local.get(["apiKey", "model"]);
  if (!apiKey) {
    addMessage("assistant", "No API key configured. Opening ChatGPT in a floating window instead.", "error");
    chrome.windows.create({
      url: `https://chatgpt.com/?q=${encodeURIComponent(text)}`,
      type: "popup", width: 480, height: 820, focused: true
    });
    promptEl.value = "";
    return;
  }

  addMessage("user", text);
  history.push({ role: "user", content: text });
  promptEl.value = "";
  busy = true;
  sendBtn.disabled = true;
  const pending = addMessage("assistant", "…");

  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model,
        temperature: 0.7,
        max_tokens: 900,
        messages: [{ role: "system", content: SYSTEM }, ...history.slice(-12)]
      })
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`HTTP ${res.status}: ${err.slice(0, 400)}`);
    }
    const data = await res.json();
    const reply = data?.choices?.[0]?.message?.content?.trim() || "(empty response)";
    pending.querySelector("p").textContent = reply;
    history.push({ role: "assistant", content: reply });
  } catch (err) {
    pending.classList.add("error");
    pending.querySelector("p").textContent = `Request failed: ${err.message}`;
  } finally {
    busy = false;
    sendBtn.disabled = false;
    chat.scrollTop = chat.scrollHeight;
  }
}

$("settings-toggle").addEventListener("click", () => $("settings").classList.toggle("hidden"));
$("save").addEventListener("click", saveSettings);
$("open-chatgpt").addEventListener("click", () => chrome.tabs.create({ url: "https://chatgpt.com/" }));

$("composer").addEventListener("submit", (event) => {
  event.preventDefault();
  send();
});

promptEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    send();
  }
});

loadSettings();
promptEl.focus();
