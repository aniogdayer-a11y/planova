import { networkInterfaces } from 'node:os';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..',import.meta.url)));
const candidates = Object.entries(networkInterfaces()).flatMap(([name,items]) =>
  items.filter(item => item.family === 'IPv4' && !item.internal && /^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(item.address))
    .map(item => ({name,address:item.address})));
const selected = candidates.find(item => /wi-?fi|wireless/i.test(item.name))
  || candidates.find(item => !/vpn|virtual|vbox|vmware|hyper-v/i.test(item.name));
if (!selected) throw new Error('No private LAN interface was found. Connect to Wi-Fi first.');
const configPath = resolve(root,'config/client.json');
const config = JSON.parse(readFileSync(configPath,'utf8'));
if (config.NATIVE_API_URL?.startsWith('https://')) throw new Error('A hosted HTTPS endpoint is configured. Keep it or clear NATIVE_API_URL before using LAN development.');
config.NATIVE_API_URL = 'http://' + selected.address + ':8787/api/gemini';
writeFileSync(configPath,JSON.stringify(config,null,2)+'\n');
const envPath = resolve(root,'.env');
let env = readFileSync(envPath,'utf8');
if (/^PLANNER_LAN_HOST=/m.test(env)) env = env.replace(/^PLANNER_LAN_HOST=.*$/m,'PLANNER_LAN_HOST='+selected.address);
else env = env.trimEnd()+'\nPLANNER_LAN_HOST='+selected.address+'\n';
writeFileSync(envPath,env);
console.log('Local phone/tablet endpoint: '+config.NATIVE_API_URL);
console.log('Restart the server and rebuild the debug app. Keep the device on the same Wi-Fi.');
