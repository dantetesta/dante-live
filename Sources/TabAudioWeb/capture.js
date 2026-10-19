'use strict';
const token = new URL(location.href).searchParams.get('session') || '';
const startButton = document.getElementById('start');
const stopButton = document.getElementById('stop');
const status = document.getElementById('status');
let stream, context, processor, pending = 0, generation = 0;
function tell(message) { status.textContent = message; }
async function stop() {
  generation++;
  stream?.getTracks().forEach(track => track.stop()); stream = null;
  processor?.disconnect(); processor = null;
  if (context) await context.close().catch(() => {}); context = null;
  pending = 0; startButton.disabled = false; stopButton.disabled = true;
}
startButton.addEventListener('click', async () => {
  if (!token || !navigator.mediaDevices?.getDisplayMedia) { tell('Este Chrome não oferece a captura de aba necessária.'); return; }
  startButton.disabled = true;
  const current = ++generation;
  try {
    const chosen = await navigator.mediaDevices.getDisplayMedia({
      video: {displaySurface: 'browser'}, audio: {suppressLocalAudioPlayback: false},
      systemAudio: 'exclude', selfBrowserSurface: 'exclude', surfaceSwitching: 'exclude'
    });
    if (current !== generation) { chosen.getTracks().forEach(track => track.stop()); return; }
    if (chosen.getVideoTracks()[0]?.getSettings().displaySurface !== 'browser' || chosen.getAudioTracks().length === 0) {
      chosen.getTracks().forEach(track => track.stop());
      throw Error('Escolha uma aba do Chrome e habilite Compartilhar áudio da aba.');
    }
    stream = chosen;
    for (const track of chosen.getTracks()) track.addEventListener('ended', () => { stop(); tell('A captura foi encerrada. Escolha a aba novamente se precisar.'); }, {once: true});
    context = new AudioContext({latencyHint: 'interactive'});
    await context.audioWorklet.addModule('/processor.js');
    const input = context.createMediaStreamSource(chosen);
    processor = new AudioWorkletNode(context, 'dante-tab-processor');
    const silent = context.createGain(); silent.gain.value = 0;
    input.connect(processor).connect(silent).connect(context.destination);
    processor.port.onmessage = async event => {
      if (current !== generation || pending >= 1) return;
      pending++;
      try {
        const response = await fetch('/pcm', {
          method: 'POST', headers: {'Authorization': `Bearer ${token}`, 'Content-Type': 'application/octet-stream', 'X-Sample-Rate': String(context.sampleRate)},
          body: event.data, cache: 'no-store'
        });
        if (!response.ok) { await stop(); tell('A fonte foi removida ou o Dante Live encerrou a conexão.'); }
      } catch { await stop(); tell('Conexão local interrompida. Abra novamente a captura no Dante Live.'); }
      finally { pending = Math.max(0, pending - 1); }
    };
    await context.resume();
    stopButton.disabled = false;
    tell('Aba conectada. O áudio desta aba está sendo enviado ao mixer do Dante Live.');
  } catch (error) {
    await stop();
    tell(error.name === 'NotAllowedError' ? 'Permissão cancelada. Clique para escolher uma aba.' : error.message || 'Não foi possível capturar a aba.');
  }
});
stopButton.addEventListener('click', () => { stop(); tell('Captura parada.'); });
window.addEventListener('pagehide', () => { stream?.getTracks().forEach(track => track.stop()); });
