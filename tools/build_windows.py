"""Export the desktop game as one Windows x64 executable with embedded assets."""
from pathlib import Path
import argparse
import json
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--template',type=Path,required=True,help='Matching windows_release_x86_64.exe')
    parser.add_argument('--output',type=Path,default=ROOT/'build/WarmToyroom-V30-Windows.exe')
    args=parser.parse_args()
    if not args.template.is_file():parser.error('Windows release template not found')
    output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
    preset=ROOT/'game/export_presets.cfg'
    previous=preset.read_bytes() if preset.exists() else None
    config='''[preset.0]
name="Windows Single File"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="assets/**/*.json,assets/**/*.bin,room_kit/**/*.json,room_kit/**/*.bin,third_party/*.txt"
script_export_mode=2

[preset.0.options]
custom_template/release=TEMPLATE
binary_format/embed_pck=true
binary_format/architecture="x86_64"
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
debug/export_console_wrapper=0
codesign/enable=false
'''.replace('TEMPLATE',json.dumps(args.template.resolve().as_posix()))
    try:
        preset.write_text(config,encoding='utf-8')
        subprocess.run([args.godot,'--headless','--path',str(ROOT/'game'),'--editor','--import'],check=True)
        subprocess.run([args.godot,'--headless','--path',str(ROOT/'game'),'--export-release','Windows Single File',str(output)],check=True)
    finally:
        if previous is None:preset.unlink(missing_ok=True)
        else:preset.write_bytes(previous)
    print(output)

if __name__=='__main__':main()
