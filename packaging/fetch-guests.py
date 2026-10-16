#!/usr/bin/env python3
"""Pinned native WebRTC and HTTPS tunnel. No account or credentials in this bundle."""
import hashlib,json,os,pathlib,shutil,subprocess,tarfile,urllib.request
root=pathlib.Path(__file__).resolve().parent.parent
lock=json.loads((root/"packaging/guests-lock.json").read_text())
base=root/"vendor/guest-runtime";base.mkdir(parents=True,exist_ok=True)
app=root/os.environ.get("DANTE_BUILD_DIR","build")/"Dante Live.app"
def fetch(url,path,digest):
    if not path.exists():
        tmp=path.with_suffix(".download");urllib.request.urlretrieve(url,tmp);tmp.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise SystemExit("Guest dependency checksum mismatch")
w=lock["webrtc"];archive=root/"vendor/livekit-webrtc/LiveKitWebRTC.xcframework.zip"
archive.parent.mkdir(parents=True,exist_ok=True);fetch(w["url"],archive,w["sha256"])
framework=base/"LiveKitWebRTC.xcframework/macos-arm64_x86_64/LiveKitWebRTC.framework"
if not framework.exists(): subprocess.run(["ditto","-x","-k",str(archive),str(base)],check=True)
target=app/"Contents/Frameworks/LiveKitWebRTC.framework"
if target.exists():shutil.rmtree(target)
shutil.copytree(framework,target,symlinks=True)
for p in sorted(target.rglob("*"),key=lambda p:len(p.parts),reverse=True):
    if p.name in ("Headers","Modules","_CodeSignature"):
        if p.is_symlink():p.unlink()
        elif p.is_dir():shutil.rmtree(p)
binaries=[]
t=lock["tunnel"]
# Upstream 2026.10.1 macOS binaries target 15.0. Rebuild the identical source with
# the supported Go toolchain and an explicit Sonoma target; never patch Mach-O.
source=root/"vendor/cloudflared-source"
if not source.exists():subprocess.run(["git","clone","--depth","1","--branch",t["version"],"https://github.com/cloudflare/cloudflared.git",str(source)],check=True)
if subprocess.check_output(["git","-C",str(source),"rev-parse","HEAD"],text=True).strip()!=t["source_commit"]:raise SystemExit("Unexpected cloudflared source commit")
if subprocess.check_output(["git","-C",str(source),"status","--porcelain"],text=True).strip():raise SystemExit("Modified cloudflared source")
for arch in ("arm64","amd64"):
    folder=base/arch;folder.mkdir(exist_ok=True);binary=folder/"cloudflared"
    env=dict(os.environ,GOTOOLCHAIN=t["toolchain"],GOOS="darwin",GOARCH=arch,CGO_ENABLED="1",MACOSX_DEPLOYMENT_TARGET="14.0",CGO_CFLAGS="-mmacosx-version-min=14.0",CGO_LDFLAGS="-mmacosx-version-min=14.0",CC="clang -arch "+("x86_64" if arch=="amd64" else arch))
    subprocess.run(["go","build","-mod=readonly","-trimpath","-ldflags","-s -w -X main.Version="+t["version"],"-o",str(binary),"./cmd/cloudflared"],cwd=source,env=env,check=True)
    binaries.append(str(binary))
helpers=app/"Contents/Helpers";helpers.mkdir(exist_ok=True)
subprocess.run(["lipo","-create",*binaries,"-output",str(helpers/"cloudflared")],check=True)
resources=app/"Contents/Resources/GuestWeb"
if resources.exists():shutil.rmtree(resources)
shutil.copytree(root/"Sources/GuestWeb",resources)
licenses=app/"Contents/Resources/Licenses"
shutil.copy2(base/"LiveKitWebRTC.xcframework/LICENSE",licenses/"WebRTC-BSD.txt")
shutil.copy2(source/"LICENSE",licenses/"cloudflared-LICENSE.txt")
print("Pinned Universal 2 guest runtime embedded")
