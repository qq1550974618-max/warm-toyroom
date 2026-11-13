"""Build a browser-only copy without changing the desktop project."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, help='Godot 4.8 beta2 executable')
    parser.add_argument('--template', required=True, type=Path, help='Matching web_nothreads_release.zip')
    parser.add_argument('--output', type=Path, default=ROOT/'build/browser')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or ROOT/'game' == output or ROOT/'web' == output:
        parser.error('Choose a separate build output directory')
    template = args.template.resolve()
    if not template.is_file(): parser.error('Web template does not exist')
    if (output/'game/project.godot').exists():
        parser.error('Output already contains a project; select a new output directory to avoid stale resources')
    manifest = json.loads((ROOT/'web/runtime-files.json').read_text(encoding='utf-8'))
    for name in manifest:
        rel = Path(name)
        if rel.is_absolute() or '..' in rel.parts: raise ValueError('Invalid resource path')
        source = ROOT/'web/overlay'/rel
        if not source.is_file(): source = ROOT/'game'/rel
        destination = output/'game'/rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    shutil.copytree(ROOT/'web/tools', output/'tools', dirs_exist_ok=True)
    (output/'web-build').mkdir(parents=True, exist_ok=True)
    preset = '''[preset.0]
name="Web Playtest"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="assets/**/*.json,assets/*.json,assets/lighting_v30/*.bin,room_kit/**/*.json,web/OFL.txt"
export_path="../web-build/index.html"
script_export_mode=2

[preset.0.options]
custom_template/release=TEMPLATE
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=true
html/canvas_resize_policy=0
html/focus_canvas_on_start=true
html/export_icon=true
progressive_web_app/enabled=false
'''.replace('TEMPLATE', json.dumps(template.as_posix()))
    (output/'game/export_presets.cfg').write_text(preset, encoding='utf-8')
    print(f'Prepared {len(manifest)} resources in {output}')
    if args.prepare_only: return
    executable = str(Path(args.godot).resolve()) if Path(args.godot).exists() else args.godot
    subprocess.run([executable, '--headless', '--path', str(output/'game'), '--editor', '--import'], check=True)
    subprocess.run([executable, '--headless', '--path', str(output/'game'), '--export-release', 'Web Playtest', str(output/'web-build/index.html')], check=True)
    subprocess.run(['node', str(output/'tools/stage-site.mjs')], check=True)
    print(f'Ready to serve: {output / "site/dist"}')

if __name__ == '__main__': main()
