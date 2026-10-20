import { writeFile } from 'node:fs/promises';

async function download(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
  return response;
}

const releases = await (await download('https://nodejs.org/dist/index.json')).json();
const release = releases
  .filter(({ version, lts }) => /^v24\.\d+\.\d+$/.test(version) && lts)
  .sort((a, b) => b.version.localeCompare(a.version, 'en', { numeric: true }))[0];
if (!release) throw new Error('No Node 24 LTS release found.');

const version = release.version.slice(1);
const filename = `node-v${version}-linux-x64.tar.xz`;
const checksums = await (await download(`https://nodejs.org/dist/v${version}/SHASUMS256.txt`)).text();
const sha256 = checksums.split('\n')
  .map(line => line.trim().split(/\s+/))
  .find(([, name]) => name === filename)?.[0];
if (!/^[a-f0-9]{64}$/.test(sha256 ?? '')) throw new Error(`Missing SHA-256 for ${filename}.`);

await writeFile(new URL('./nodejs.json', import.meta.url), `${JSON.stringify({ version, sha256 }, null, 2)}\n`);
console.log(`Selected Node ${version}.`);
