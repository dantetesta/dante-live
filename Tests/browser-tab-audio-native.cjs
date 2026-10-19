const {chromium} = require(process.env.DANTE_PLAYWRIGHT || '../build/guest-browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const directory = process.argv[2];
  const connection = JSON.parse(fs.readFileSync(path.join(directory, 'connection.json')));
  const browser = await chromium.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--autoplay-policy=no-user-gesture-required', '--no-first-run']});
  try {
    const context = await browser.newContext();
    await context.addInitScript(() => {
      Object.defineProperty(navigator.mediaDevices, 'getDisplayMedia', {value: async () => {
        const canvas = document.createElement('canvas');
        canvas.width = 320; canvas.height = 180;
        const video = canvas.captureStream(5).getVideoTracks()[0];
        video.getSettings = () => ({displaySurface: 'browser'});
        const audio = new AudioContext({sampleRate: 48000});
        const oscillator = audio.createOscillator(), gain = audio.createGain(), destination = audio.createMediaStreamDestination();
        oscillator.frequency.value = 440; gain.gain.value = 0.25;
        oscillator.connect(gain).connect(destination); oscillator.start(); await audio.resume();
        return new MediaStream([video, destination.stream.getAudioTracks()[0]]);
      }});
    });
    const page = await context.newPage();
    page.on('pageerror', error => console.error('Browser error:', error.message));
    await page.goto(connection.url);
    const denied = await page.evaluate(async () => (await fetch('/pcm', {method: 'POST', headers: {'Authorization': 'Bearer invalid', 'Content-Type': 'application/octet-stream', 'X-Sample-Rate': '48000'}, body: new Float32Array(480)})).status);
    assert.equal(denied, 403, 'loopback endpoint rejects an unknown token');
    await page.locator('#start').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent.includes('Aba conectada'), null, {timeout: 10000});
    let peak = -96;
    for (let i = 0; i < 30 && peak <= -25; i++) {
      await new Promise(resolve => setTimeout(resolve, 200));
      const data = JSON.parse(fs.readFileSync(path.join(directory, 'levels.json')));
      peak = Math.max(peak, ...(data['Aba QA']?.peak || [-96]));
    }
    assert(peak > -25, `A fonte no mixer não recebeu o tom sintético: ${peak} dBFS`);
    await page.locator('#stop').click();
    await page.waitForFunction(() => document.querySelector('#status').textContent.includes('Captura parada'));
    await new Promise(resolve => setTimeout(resolve, 800));
    const afterStop = JSON.parse(fs.readFileSync(path.join(directory, 'levels.json')));
    assert((afterStop['Aba QA']?.peak || [-96]).every(value => value <= -95), 'stopping the tab silences the mixer');
    console.log(`PASS: Chrome sintético -> página local autenticada -> fonte libobs -> medidor (${peak.toFixed(1)} dBFS); token inválido rejeitado; stop silencia`);
  } finally { await browser.close(); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
