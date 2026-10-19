const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const script = fs.readFileSync('Sources/TabAudioWeb/capture.js', 'utf8');

async function run(surface, withAudio) {
  const events = {};
  const start = {disabled: false, addEventListener(name, callback) { events.start = callback; }};
  const stop = {disabled: true, addEventListener(name, callback) { events.stop = callback; }};
  const status = {textContent: ''};
  const stopped = [];
  const video = {getSettings: () => ({displaySurface: surface}), addEventListener() {}, stop() { stopped.push('video'); }};
  const audio = {addEventListener() {}, stop() { stopped.push('audio'); }};
  const stream = {getVideoTracks: () => [video], getAudioTracks: () => withAudio ? [audio] : [], getTracks: () => withAudio ? [video, audio] : [video]};
  let node, posts = [];
  class AudioContext {
    sampleRate = 48000;
    destination = {};
    audioWorklet = {addModule: async () => {}};
    createMediaStreamSource() { return {connect(node) { return node; }}; }
    createGain() { return {gain: {value: 1}, connect() {}}; }
    async resume() {}
    async close() {}
  }
  class AudioWorkletNode {
    port = {};
    constructor() { node = this; }
    connect(silent) { return silent; }
    disconnect() {}
  }
  vm.runInNewContext(script, {
    URL, location: {href: 'http://127.0.0.1:1234/capture?session=test-token'},
    document: {getElementById(id) { return {start, stop, status}[id]; }},
    navigator: {mediaDevices: {getDisplayMedia: async () => stream}},
    window: {addEventListener() {}}, AudioContext, AudioWorkletNode,
    fetch: async (path, options) => { posts.push({path, options}); return {ok: true}; }
  });
  await events.start();
  return {events, start, stop, status, stopped, node, posts};
}

(async () => {
  const windowCapture = await run('window', true);
  assert.equal(windowCapture.start.disabled, false);
  assert.match(windowCapture.status.textContent, /Escolha uma aba/);
  assert.deepEqual(windowCapture.stopped, ['video', 'audio']);
  assert.equal(windowCapture.posts.length, 0);

  const mutedTab = await run('browser', false);
  assert.match(mutedTab.status.textContent, /Compartilhar áudio/);
  assert.deepEqual(mutedTab.stopped, ['video']);
  assert.equal(mutedTab.posts.length, 0);

  const selectedTab = await run('browser', true);
  assert.equal(selectedTab.stop.disabled, false);
  assert.match(selectedTab.status.textContent, /Aba conectada/);
  await selectedTab.node.port.onmessage({data: new ArrayBuffer(4800 * 4)});
  assert.equal(selectedTab.posts.length, 1);
  assert.equal(selectedTab.posts[0].path, '/pcm');
  assert.equal(selectedTab.posts[0].options.headers.Authorization, 'Bearer test-token');
  assert.equal(selectedTab.posts[0].options.headers['X-Sample-Rate'], '48000');
  assert.equal(selectedTab.posts[0].options.body.byteLength, 4800 * 4);
  console.log('PASS: tab-only chooser rejects window/no-audio, sends only selected audio PCM');
})().catch(error => { console.error(error); process.exitCode = 1; });
