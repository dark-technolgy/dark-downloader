const token = "cfoat_qc6KTL128RuaGcE-sYWBK9F6kSHOSgisOadHjMBUHrg.WeXHujW7-7hBkSB0xcKzcjKBm0ObHpx-CoMPuQluom4";

async function checkDns() {
  try {
    const zonesRes = await fetch('https://api.cloudflare.com/client/v4/zones?name=keenx.net', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const zonesData = await zonesRes.json();
    if (!zonesData.result || zonesData.result.length === 0) {
        console.log("Zone not found.");
        return;
    }
    const zoneId = zonesData.result[0].id;
    console.log(`Zone ID: ${zoneId}`);

    const dnsRes = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const dnsData = await dnsRes.json();
    if (!dnsData.success) {
        console.error("DNS API Error:", dnsData.errors);
        return;
    }
    console.log(`Found ${dnsData.result.length} DNS records in the new account:`);
    dnsData.result.forEach(r => {
      console.log(`- [${r.type}] ${r.name} -> ${r.content}`);
    });

  } catch (error) {
    console.error('Error:', error.stack);
  }
}

checkDns();
