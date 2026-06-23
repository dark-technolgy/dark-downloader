const token = "cfoat_qc6KTL128RuaGcE-sYWBK9F6kSHOSgisOadHjMBUHrg.WeXHujW7-7hBkSB0xcKzcjKBm0ObHpx-CoMPuQluom4";
const accountId = "c641115b3c264cc5870adfe6e114583b";

async function checkZones() {
  try {
    console.log('Fetching zones from Cloudflare...');
    const response = await fetch('https://api.cloudflare.com/client/v4/zones', {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      }
    });

    const data = await response.json();
    if (!data.success) {
      console.error('API Error:', data.errors);
      return;
    }

    const zones = data.result;
    console.log(`Found ${zones.length} zones in the account.`);

    const keenxZone = zones.find(z => z.name === 'keenx.net');
    if (keenxZone) {
      console.log('✅ Zone keenx.net FOUND in the new account!');
      console.log('Status:', keenxZone.status);
      console.log('Nameservers:', keenxZone.name_servers);
    } else {
      console.log('❌ Zone keenx.net NOT found in the new account.');
      console.log('Available zones:', zones.map(z => z.name).join(', '));
    }
  } catch (error) {
    console.error('Request failed:', error.message);
  }
}

checkZones();
