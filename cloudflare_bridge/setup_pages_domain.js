const token = "cfoat_qc6KTL128RuaGcE-sYWBK9F6kSHOSgisOadHjMBUHrg.WeXHujW7-7hBkSB0xcKzcjKBm0ObHpx-CoMPuQluom4";
const accountId = "c641115b3c264cc5870adfe6e114583b";
const projectName = "keenx-website";
const domain = "keenx.net";

async function setupDomain() {
  try {
    console.log(`Adding custom domain ${domain} to Pages project ${projectName}...`);
    const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/pages/projects/${projectName}/domains`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ name: domain })
    });

    const data = await response.json();
    if (data.success) {
      console.log('✅ Custom domain added successfully to Pages project.');
    } else {
      console.error('❌ Failed to add domain:', data.errors);
      if (data.errors.some(e => e.message.includes('already exists'))) {
          console.log('Domain might already be associated.');
      }
    }

    // Also add www.
    console.log(`Adding custom domain www.${domain}...`);
    await fetch(`https://api.cloudflare.com/client/v4/accounts/${accountId}/pages/projects/${projectName}/domains`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ name: `www.${domain}` })
    });

  } catch (error) {
    console.error('Error:', error.message);
  }
}

setupDomain();
