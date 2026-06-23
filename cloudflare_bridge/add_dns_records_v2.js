const token = "cfoat_qc6KTL128RuaGcE-sYWBK9F6kSHOSgisOadHjMBUHrg.WeXHujW7-7hBkSB0xcKzcjKBm0ObHpx-CoMPuQluom4";
const zoneId = "a7bf67f02a51f7999d90574a579df506";
const target = "keenx-website-cek.pages.dev";

async function addRecord(name, type, content) {
  console.log(`Adding ${type} record for ${name}...`);
  const response = await fetch(`https://api.cloudflare.com/client/v4/zones/${zoneId}/dns_records`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      type: type,
      name: name,
      content: content,
      ttl: 1,
      proxied: true
    })
  });
  const data = await response.json();
  if (data.success) {
    console.log(`✅ ${name} added successfully.`);
  } else {
    console.error(`❌ Failed to add ${name}:`, data.errors);
  }
}

async function run() {
  await addRecord('keenx.net', 'CNAME', target);
  await addRecord('www', 'CNAME', target);
}

run();
