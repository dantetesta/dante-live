class DanteTabProcessor extends AudioWorkletProcessor {
  constructor() { super(); this.pending = new Float32Array(4800); this.used = 0; }
  process(inputs, outputs) {
    const channels = inputs[0] || [];
    const length = channels[0]?.length || 0;
    for (let i = 0; i < length; i++) {
      let sample = 0;
      for (const channel of channels) sample += channel[i];
      this.pending[this.used++] = channels.length ? sample / channels.length : 0;
      if (this.used === this.pending.length) {
        this.port.postMessage(this.pending.buffer, [this.pending.buffer]);
        this.pending = new Float32Array(4800);
        this.used = 0;
      }
    }
    for (const output of outputs) for (const channel of output) channel.fill(0);
    return true;
  }
}
registerProcessor('dante-tab-processor', DanteTabProcessor);
