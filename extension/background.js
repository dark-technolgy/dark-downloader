// ═══════════════════════════════════════════════════════════════════════════
// Dark Downloader Bridge — Background Service Worker
// Handles: Context Menu, Extension Downloads, App Health Check
// ═══════════════════════════════════════════════════════════════════════════

const DARK_API = 'http://localhost:3030';

// ─── Context Menu ──────────────────────────────────────────────────────────
chrome.runtime.onInstalled.addListener(() => {
  console.log("Dark Downloader Bridge v2.1.0 Installed.");

  // Right-click on page → "Send to Dark Downloader"
  chrome.contextMenus.create({
    id: "dark-download-page",
    title: "⬇ Send to Dark Downloader",
    contexts: ["page", "link", "video", "audio"]
  });

  // Right-click on a link → "Download this link with Dark"
  chrome.contextMenus.create({
    id: "dark-download-link",
    title: "⬇ Download link with Dark",
    contexts: ["link"]
  });

  // Right-click on video element → "Download video with Dark"
  chrome.contextMenus.create({
    id: "dark-download-video",
    title: "🎬 Download video with Dark",
    contexts: ["video"]
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let url = null;

  switch (info.menuItemId) {
    case "dark-download-link":
      url = info.linkUrl;
      break;
    case "dark-download-video":
      url = info.srcUrl || info.pageUrl;
      break;
    case "dark-download-page":
      url = info.linkUrl || info.pageUrl || tab?.url;
      break;
  }

  if (!url) return;

  try {
    const response = await fetch(`${DARK_API}/download`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url: url,
        title: tab?.title || 'Unknown',
        platform: detectPlatform(url),
        source: 'context_menu'
      })
    });

    if (response.ok) {
      // Show success badge briefly
      chrome.action.setBadgeText({ text: "✓", tabId: tab?.id });
      chrome.action.setBadgeBackgroundColor({ color: "#00FF85" });
      setTimeout(() => {
        chrome.action.setBadgeText({ text: "", tabId: tab?.id });
      }, 2000);
    }
  } catch (e) {
    // App is offline
    chrome.action.setBadgeText({ text: "!", tabId: tab?.id });
    chrome.action.setBadgeBackgroundColor({ color: "#FF3B30" });
    setTimeout(() => {
      chrome.action.setBadgeText({ text: "", tabId: tab?.id });
    }, 3000);
  }
});

// ─── Listen for messages from Content Script ────────────────────────────────
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'DARK_MEDIA_DETECTED') {
    // Forward detected media to the app
    fetch(`${DARK_API}/sniff`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        url: message.url,
        title: message.title,
        platform: message.platform,
        thumbnail: message.thumbnail,
        source: 'content_script'
      })
    }).then(() => {
      sendResponse({ success: true });
    }).catch(() => {
      sendResponse({ success: false });
    });
    return true; // async response
  }
});

// ─── Utility ──────────────────────────────────────────────────────────────
function detectPlatform(url) {
  if (!url) return 'unknown';
  const u = url.toLowerCase();
  if (u.includes('youtube.com') || u.includes('youtu.be')) return 'youtube';
  if (u.includes('tiktok.com')) return 'tiktok';
  if (u.includes('instagram.com')) return 'instagram';
  if (u.includes('twitter.com') || u.includes('x.com')) return 'twitter';
  if (u.includes('facebook.com') || u.includes('fb.watch')) return 'facebook';
  if (u.includes('vimeo.com')) return 'vimeo';
  if (u.includes('dailymotion.com')) return 'dailymotion';
  if (u.includes('soundcloud.com')) return 'soundcloud';
  if (u.includes('reddit.com')) return 'reddit';
  if (u.includes('twitch.tv')) return 'twitch';
  if (u.includes('pinterest.com')) return 'pinterest';
  if (u.includes('rumble.com')) return 'rumble';
  return 'unknown';
}
