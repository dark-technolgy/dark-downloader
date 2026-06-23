const Cloudflare = require('cloudflare');
require('dotenv').config();

async function transferDomain(domainName) {
  const sourceToken = process.env.CF_SOURCE_TOKEN;
  const destToken = process.env.CF_DEST_TOKEN;
  const destAccountId = process.env.CF_DEST_ACCOUNT_ID;

  if (!sourceToken || !destToken || !destAccountId) {
    console.error('Error: CF_SOURCE_TOKEN, CF_DEST_TOKEN, and CF_DEST_ACCOUNT_ID must be set in .env');
    console.log('Please copy .env.example to .env and fill in the values.');
    process.exit(1);
  }

  const sourceCf = new Cloudflare({ apiToken: sourceToken });
  const destCf = new Cloudflare({ apiToken: destToken });

  try {
    console.log(`\n--- Transferring domain: ${domainName} ---`);

    // 1. Find the zone in the source account
    console.log(`Searching for zone: ${domainName} in source account...`);
    const zones = await sourceCf.zones.list({ name: domainName });
    const sourceZone = zones.result[0];

    if (!sourceZone) {
      throw new Error(`Zone ${domainName} not found in source account. Please check the domain name and token permissions.`);
    }

    const sourceZoneId = sourceZone.id;
    console.log(`Found source zone ID: ${sourceZoneId}`);

    // 2. Export DNS records (BIND format)
    console.log('Exporting DNS records from source...');
    const exportRes = await fetch(`https://api.cloudflare.com/client/v4/zones/${sourceZoneId}/dns_records/export`, {
      headers: { 'Authorization': `Bearer ${sourceToken}` }
    });

    if (!exportRes.ok) {
      const errText = await exportRes.text();
      throw new Error(`Export failed: ${errText}`);
    }

    const bindFileContent = await exportRes.text();
    console.log('DNS records exported successfully.');

    // 3. Create the zone in the destination account
    console.log(`Creating zone: ${domainName} in destination account...`);
    let destZoneId;
    try {
      const newZone = await destCf.zones.create({
        name: domainName,
        account: { id: destAccountId },
        type: 'full'
      });
      destZoneId = newZone.result.id;
      console.log(`Created destination zone ID: ${destZoneId}`);
    } catch (e) {
      if (e.message && e.message.includes('already exists')) {
        console.log('Zone already exists in destination account, skipping creation...');
        const destZones = await destCf.zones.list({ name: domainName });
        destZoneId = destZones.result[0].id;
      } else {
        throw e;
      }
    }

    // 4. Import DNS records to the destination
    console.log('Importing DNS records to destination...');
    // We use a simple POST with the file content as text/plain or multipart
    // Cloudflare API supports importing via POST to /zones/:id/dns_records/import

    const { Blob } = require('buffer');
    const formData = new FormData();
    const blob = new Blob([bindFileContent], { type: 'text/plain' });
    formData.append('file', blob, 'dns_export.txt');

    const importRes = await fetch(`https://api.cloudflare.com/client/v4/zones/${destZoneId}/dns_records/import`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${destToken}`
      },
      body: formData
    });

    const importResult = await importRes.json();
    if (importResult.success) {
      console.log('DNS records imported successfully.');
      console.log(`Added ${importResult.result.recs_added} records.`);
    } else {
      console.error('Failed to import DNS records:', JSON.stringify(importResult.errors));
    }

    console.log('\n--- TRANSFER INITIATED ---');
    console.log('Next steps:');
    console.log(`1. In the NEW account (${process.env.CF_DEST_TOKEN.substring(0, 5)}...), find the new nameservers.`);
    console.log('2. Update the nameservers at your domain registrar (e.g., Namecheap, GoDaddy).');
    console.log('3. Once Cloudflare confirms the nameserver update, the domain will be active in the new account.');
    console.log('4. IMPORTANT: Re-configure any Workers, Pages, or SSL settings in the new account manually.');

  } catch (error) {
    console.error('\n[ERROR] Transfer failed:', error.message);
  }
}

const domain = process.argv[2] || 'keenx.net';
transferDomain(domain);
