#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${DANTE_APP_PATH:-$ROOT/build/Dante Live.app}"
OUT="$ROOT/build/tests"
mkdir -p "$OUT" evidence/runtime
ARCH="$(uname -m)"
xcrun clang++ -std=c++17 -fobjc-arc -O2 -target "$ARCH-apple-macos14.0" \
  -I vendor/obs-studio/libobs -I vendor/simde -I build/generated -I Sources/Bridge \
  -F "$ROOT/vendor/guest-runtime/LiveKitWebRTC.xcframework/macos-arm64_x86_64" \
  -F "$APP/Contents/Frameworks" Sources/Bridge/DanteEngine.mm Tests/EngineSmoke.mm \
  -framework AppKit -framework Foundation -framework VideoToolbox -framework LiveKitWebRTC -framework libobs \
  -Wl,-rpath,"$APP/Contents/Frameworks" -o "$OUT/EngineSmoke"
codesign --force --sign - "$OUT/EngineSmoke"
# libobs resolves its mux helper beside the process executable. Keep test helper
# inside the isolated build tree; no installed application is changed.
ln -sfn "$APP/Contents/MacOS/obs-ffmpeg-mux" "$OUT/obs-ffmpeg-mux"
if [[ "${DANTE_TEST_RTMP:-0}" == 1 ]]; then
  command -v ffmpeg >/dev/null
  ffmpeg -nostdin -hide_banner -loglevel error -listen 1 -i rtmp://127.0.0.1:19350/live/test \
    -c copy -f flv -y evidence/runtime/loopback-received.flv > evidence/runtime/loopback-receiver.log 2>&1 &
  RECEIVER_PID=$!
  trap 'kill "$RECEIVER_PID" 2>/dev/null || true' EXIT
  sleep 1
  kill -0 "$RECEIVER_PID"
fi
"$OUT/EngineSmoke" "$APP" "$ROOT/evidence/runtime"
if command -v ffprobe >/dev/null; then
  RECORDING="$(python3 -c 'import json;print(json.load(open("evidence/runtime/engine-smoke.json"))["recording"])')"
  ffprobe -v error -show_format -show_streams -of json "$RECORDING" > evidence/runtime/recording-probe.json
  python3 - <<'PY'
import json
p=json.load(open('evidence/runtime/recording-probe.json'))
assert float(p['format']['duration']) >= 3, 'Recording too short'
assert any(s.get('codec_name')=='h264' and s.get('width')==640 and s.get('height')==360 for s in p['streams']), 'H264 video missing'
assert any(s.get('codec_name')=='aac' for s in p['streams']), 'AAC track missing'
print('PASS ffprobe H264/AAC MKV >=3 seconds')
PY
  python3 - <<'PY'
import array,json,math,subprocess
path=json.load(open('evidence/runtime/engine-smoke.json'))['recording']
levels=[]
for start in (0.6,2.6,4.6):
    data=subprocess.check_output(['ffmpeg','-v','error','-ss',str(start),'-t','0.8','-i',path,'-vn','-ac','1','-ar','48000','-f','f32le','pipe:1'])
    samples=array.array('f');samples.frombytes(data)
    levels.append(math.sqrt(sum(x*x for x in samples)/max(1,len(samples))))
report={'windowsSeconds':[0.6,2.6,4.6],'rms':levels,'passed':levels[0]>0.01 and levels[1]<0.001 and levels[2]>0.01}
json.dump(report,open('evidence/runtime/audio-mixer-proof.json','w'),indent=2)
assert report['passed'],report
print('PASS decoded recording audio audible -> muted -> audible',levels)
replay=json.load(open('evidence/runtime/engine-smoke.json'))['replay']
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-of','json',replay]))
json.dump(probe,open('evidence/runtime/replay-probe.json','w'),indent=2)
assert float(probe['format']['duration'])>0.5,'Replay too short'
assert any(s.get('codec_name')=='h264' for s in probe['streams']),'Replay missing video'
assert any(s.get('codec_name')=='aac' for s in probe['streams']),'Replay missing audio'
print('PASS ffprobe saved replay H264/AAC duration',probe['format']['duration'])
PY
fi
