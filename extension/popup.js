document.addEventListener('DOMContentLoaded', async () => {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const downloadBtn = document.getElementById('downloadBtn');
  const urlDisplay = document.getElementById('urlDisplay');

  // Get current tab URL
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const currentUrl = tab.url;
  urlDisplay.textContent = currentUrl;

  // Check if Dark Downloader is running
  async function checkApp() {
    try {
      const response = await fetch('http://localhost:3030/ping');
      if (response.ok) {
        statusDot.className = 'status-dot online';
        statusText.textContent = 'App Connected';
        downloadBtn.disabled = false;
        return true;
      }
    } catch (e) {}
    statusDot.className = 'status-dot offline';
    statusText.textContent = 'App Offline (Open Dark Downloader)';
    downloadBtn.disabled = true;
    return false;
  }

  await checkApp();

  downloadBtn.addEventListener('click', async () => {
    downloadBtn.disabled = true;
    downloadBtn.textContent = 'SENDING...';

    try {
      const response = await fetch('http://localhost:3030/download', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: currentUrl })
      });

      if (response.ok) {
        downloadBtn.textContent = 'SENT SUCCESSFULLY!';
        downloadBtn.style.backgroundColor = '#00FF85';
        setTimeout(() => window.close(), 1500);
      } else {
        throw new Error('Failed');
      }
    } catch (e) {
      downloadBtn.textContent = 'FAILED (Retry)';
      downloadBtn.style.backgroundColor = '#FF3B30';
      setTimeout(() => {
        downloadBtn.disabled = false;
        downloadBtn.textContent = 'SEND TO DARK';
        downloadBtn.style.backgroundColor = '#00A3FF';
      }, 2000);
    }
  });
});
