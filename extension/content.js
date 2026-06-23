// ═══════════════════════════════════════════════════════════════════════════
// Dark Downloader Bridge — Content Script
// Automatically detects video URLs on supported platforms and sends them
// to the Dark Downloader app via the background service worker.
// ═══════════════════════════════════════════════════════════════════════════

(function() {
  'use strict';

  const DETECTED_URLS = new Set();
  let debounceTimer = null;

  // ─── Platform-specific video URL extractors ─────────────────────────────
  
  function detectYouTube() {
    const url = window.location.href;
    if (url.includes('/watch') || url.includes('/shorts/')) {
      return {
        url: url,
        title: document.title.replace(' - YouTube', '').trim(),
        platform: 'youtube',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectTikTok() {
    const url = window.location.href;
    if (url.includes('/video/') || url.includes('/@')) {
      return {
        url: url,
        title: document.title.replace(' | TikTok', '').trim(),
        platform: 'tiktok',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectInstagram() {
    const url = window.location.href;
    if (url.includes('/reel/') || url.includes('/p/') || url.includes('/tv/')) {
      return {
        url: url,
        title: document.title.replace(' • Instagram', '').trim(),
        platform: 'instagram',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectTwitter() {
    const url = window.location.href;
    if (url.includes('/status/')) {
      return {
        url: url,
        title: document.title.trim(),
        platform: 'twitter',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectFacebook() {
    const url = window.location.href;
    if (url.includes('/videos/') || url.includes('/watch/') || url.includes('/reel/')) {
      return {
        url: url,
        title: document.title.replace(' | Facebook', '').trim(),
        platform: 'facebook',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectVimeo() {
    const url = window.location.href;
    const pathMatch = url.match(/vimeo\.com\/(\d+)/);
    if (pathMatch) {
      return {
        url: url,
        title: document.title.replace(' on Vimeo', '').trim(),
        platform: 'vimeo',
        thumbnail: document.querySelector('meta[property="og:image"]')?.content
      };
    }
    return null;
  }

  function detectReddit() {
    const url = window.location.href;
    if (url.includes('/comments/')) {
      // Check if post has video
      const videoEl = document.querySelector('video source, shreddit-player');
      if (videoEl) {
        return {
          url: url,
          title: document.title.replace(' : ', ' - ').trim(),
          platform: 'reddit',
          thumbnail: document.querySelector('meta[property="og:image"]')?.content
        };
      }
    }
    return null;
  }

  function detectGeneric() {
    const url = window.location.href;
    const hostname = window.location.hostname;
    
    // Detect by hostname
    const platformMap = {
      'dailymotion.com': 'dailymotion',
      'soundcloud.com': 'soundcloud',
      'twitch.tv': 'twitch',
      'pinterest.com': 'pinterest',
      'rumble.com': 'rumble',
    };

    for (const [domain, platform] of Object.entries(platformMap)) {
      if (hostname.includes(domain)) {
        return {
          url: url,
          title: document.title.trim(),
          platform: platform,
          thumbnail: document.querySelector('meta[property="og:image"]')?.content
        };
      }
    }
    return null;
  }

  // ─── Main detection logic ──────────────────────────────────────────────

  function runDetection() {
    const detectors = [
      detectYouTube,
      detectTikTok,
      detectInstagram,
      detectTwitter,
      detectFacebook,
      detectVimeo,
      detectReddit,
      detectGeneric,
    ];

    for (const detector of detectors) {
      try {
        const result = detector();
        if (result && result.url && !DETECTED_URLS.has(result.url)) {
          DETECTED_URLS.add(result.url);
          
          // Send to background script → app
          chrome.runtime.sendMessage({
            type: 'DARK_MEDIA_DETECTED',
            ...result
          });

          console.log(`[Dark Downloader] Detected: ${result.platform} — ${result.title}`);
        }
      } catch (e) {
        // Silent fail per detector
      }
    }
  }

  // ─── Observe page changes (SPA navigation) ────────────────────────────

  function debouncedDetection() {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(runDetection, 1500);
  }

  // Initial detection
  if (document.readyState === 'complete') {
    setTimeout(runDetection, 2000);
  } else {
    window.addEventListener('load', () => setTimeout(runDetection, 2000));
  }

  // Watch for URL changes (SPA like YouTube, TikTok)
  let lastUrl = window.location.href;
  const urlObserver = new MutationObserver(() => {
    if (window.location.href !== lastUrl) {
      lastUrl = window.location.href;
      debouncedDetection();
    }
  });

  urlObserver.observe(document.body, {
    childList: true,
    subtree: true,
  });

  // Also listen to History API navigation
  const originalPushState = history.pushState;
  history.pushState = function() {
    originalPushState.apply(this, arguments);
    debouncedDetection();
  };

  const originalReplaceState = history.replaceState;
  history.replaceState = function() {
    originalReplaceState.apply(this, arguments);
    debouncedDetection();
  };

  window.addEventListener('popstate', debouncedDetection);

})();
