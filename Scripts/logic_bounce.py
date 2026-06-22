#!/usr/bin/env python3
"""Drive Logic Pro 12.2's Bounce dialog to produce an audio file at a target path.

Logic exposes no AppleScript bounce verb and its save panel's filename field is not
Accessibility-exposed, so this drives the dialog with cliclick (CGEvent). Coordinates
are computed from the save-panel window frame (AX-readable) for portability. The bounce
is written to a staging folder (a sidebar Favorite, default Downloads) and moved to the
requested output_dir afterwards, because Cmd+Shift+G "Go to Folder" cannot be confirmed
via automation.

CRITICAL: the input source MUST be ABC before typing or a Korean IME mangles the name.

Usage:
  logic_bounce.py --name NAME --output-dir DIR [--staging ~/Downloads] [--set-abc PATH]
Prints a one-line JSON result.
"""
import sys, json, subprocess, time, os, glob, argparse


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)


def osa(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True).stdout.strip()


def cliclick(*args):
    subprocess.run(["cliclick", *args], capture_output=True)


def bounce_dialog_present():
    """True iff a Logic window/sheet whose name contains "Bounce"/"바운스" exists.

    Cmd+B opens the Bounce settings dialog asynchronously; clicking OK before it
    appears mis-fires into the wrong window. Collect every window/sheet name (a
    sheet is the front window's child, not a top-level window) and substring-match
    case-insensitively so this survives Logic's locale (EN "Bounce", KO "바운스").
    """
    names = osa(
        'tell application "System Events" to tell process "Logic Pro" to '
        'return (name of windows) & (name of sheets of windows)'
    )
    hay = names.lower()
    return "bounce" in hay or "바운스" in hay


SET_ABC_SWIFT = """
import Carbon
import Foundation
let cf = TISCreateInputSourceList(nil, false).takeRetainedValue()
let sources = cf as NSArray as! [TISInputSource]
for s in sources {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { continue }
    let id = Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    if id == "com.apple.keylayout.ABC" || id == "com.apple.keylayout.US" {
        TISSelectInputSource(s); break
    }
}
"""


def set_input_abc():
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".swift", delete=False) as f:
        f.write(SET_ABC_SWIFT)
        path = f.name
    sh(f"swift {path}")
    os.unlink(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="filename without extension")
    ap.add_argument("--output-dir", required=True, help="final destination dir (absolute)")
    ap.add_argument("--staging", default=os.path.expanduser("~/Downloads"))
    args = ap.parse_args()

    result = {"name": args.name, "output_dir": args.output_dir}

    # 1. deterministic input-source switch (avoid Korean IME mangling the filename)
    set_input_abc()
    time.sleep(0.4)

    # 2. open the Bounce settings dialog
    osa('tell application "Logic Pro" to activate')
    time.sleep(0.8)
    osa('tell application "System Events" to tell process "Logic Pro" to key code 11 using {command down}')

    # 2b. VERIFY the Bounce settings dialog actually appeared before clicking OK.
    # A blind sleep mis-fires when the dialog is slow/absent (#127): the OK click
    # lands on the wrong window. Bounded poll (~10x0.5s); fail fast on timeout.
    dialog_up = False
    for _ in range(10):
        if bounce_dialog_present():
            dialog_up = True
            break
        time.sleep(0.5)
    if not dialog_up:
        result["success"] = False
        result["error"] = "bounce_dialog_did_not_appear"
        print(json.dumps(result)); return 1

    # 3. OK on the (AX-accessible) settings dialog -> save panel
    osa('tell application "System Events" to tell process "Logic Pro" to click button "OK" of front window')
    time.sleep(2.5)

    # 4. read the save-panel window frame
    pos = osa('tell application "System Events" to tell process "Logic Pro" to get position of front window')
    size = osa('tell application "System Events" to tell process "Logic Pro" to get size of front window')
    try:
        ox, oy = [int(v.strip()) for v in pos.split(",")]
        w, h = [int(v.strip()) for v in size.split(",")]
    except Exception:
        result["success"] = False
        result["error"] = f"could_not_read_save_panel_frame pos={pos!r} size={size!r}"
        print(json.dumps(result)); return 1
    result["panel_frame"] = [ox, oy, w, h]

    # 5. set a clean Save As name (offsets calibrated live against the standard
    # Logic 12.2 bounce save panel: frame [520,142,880,604] -> field (1040,196))
    saveas = (ox + int(0.591 * w), oy + 54)
    cliclick(f"c:{saveas[0]},{saveas[1]}"); time.sleep(0.4)
    cliclick("kd:cmd", "t:a", "ku:cmd"); time.sleep(0.2)
    cliclick("kp:delete"); time.sleep(0.2)
    cliclick(f"t:{args.name}"); time.sleep(0.4)

    # 6. navigate to the staging Favorite (sidebar Downloads); go-to-folder is unusable.
    # Sidebar is a fixed-width left column: Downloads row at frame +(86,184).
    downloads = (ox + 86, oy + 184)
    cliclick(f"c:{downloads[0]},{downloads[1]}"); time.sleep(1.0)

    # 7. clear any prior staged artifact, then click the Bounce default button
    # (bottom-right corner of the panel: frame +(w-60, h-32) -> (1340,714)).
    staged = os.path.join(args.staging, f"{args.name}.aif")
    if os.path.exists(staged):
        os.remove(staged)
    bounce_btn = (ox + w - 60, oy + h - 32)
    cliclick(f"c:{bounce_btn[0]},{bounce_btn[1]}")

    # 8. poll the staging folder for the produced artifact
    appeared = None
    for _ in range(25):
        if os.path.exists(staged):
            appeared = staged; break
        time.sleep(1.0)
    if not appeared:
        cands = sorted(glob.glob(os.path.join(args.staging, f"{args.name}.*")),
                       key=lambda p: os.path.getmtime(p), reverse=True)
        if cands:
            appeared = cands[0]
    if not appeared:
        result["success"] = False
        result["error"] = "artifact_not_produced_in_staging"
        print(json.dumps(result)); return 1

    # 9. move to the requested output_dir (locate-and-move)
    os.makedirs(args.output_dir, exist_ok=True)
    final = os.path.join(args.output_dir, os.path.basename(appeared))
    os.replace(appeared, final)
    result["success"] = True
    result["artifact"] = final
    result["size_bytes"] = os.path.getsize(final)
    print(json.dumps(result)); return 0


if __name__ == "__main__":
    sys.exit(main())
