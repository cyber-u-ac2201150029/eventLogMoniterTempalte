#!/usr/bin/env bash
# Render a Salesforce External Client App template without modifying the source.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash scripts/render-template.sh APP_API_NAME RUN_AS_USERNAME [TEMPLATE_DIR] [OUTPUT_DIR]

Example:
  bash scripts/render-template.sh MyEventLogCollector target-user@example.com \
    templates/force-app build/force-app

Required placeholders in XML and filenames:
  @@APP_API_NAME@@
  @@RUN_AS_USERNAME@@

The output directory must not exist. Source files are never modified.
EOF
}
if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then usage; exit 0; fi
if (( $# < 2 || $# > 4 )); then usage >&2; exit 2; fi
app_name=$1
run_as=$2
source_dir=${3:-templates/force-app}
output_dir=${4:-build/force-app}

python3 - "$app_name" "$run_as" "$source_dir" "$output_dir" <<'PY'
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

app, run_as, src_arg, dst_arg = sys.argv[1:]
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', app):
    sys.exit('ERROR: APP_API_NAME must start with a letter and contain only letters, digits, or underscores.')
if not run_as.strip() or any(ch in run_as for ch in '\r\n\x00'):
    sys.exit('ERROR: Invalid RUN_AS_USERNAME.')

src = Path(src_arg).expanduser().resolve()
dst = Path(dst_arg).expanduser().resolve()
if not src.is_dir():
    sys.exit(f'ERROR: Template directory not found: {src}')
if dst.exists():
    sys.exit(f'ERROR: Output directory already exists (no overwrite): {dst}')
if src == dst or src in dst.parents or dst in src.parents:
    sys.exit('ERROR: Source and output directories must not contain one another.')

values = {
    '@@APP_API_NAME@@': app,
    '@@RUN_AS_USERNAME@@': run_as,
}
pattern = re.compile(r'@@[A-Z][A-Z0-9_]*@@')
# A temporary directory prevents partially completed deployment artifacts.
dst.parent.mkdir(parents=True, exist_ok=True)
stage = Path(tempfile.mkdtemp(prefix='.render-', dir=dst.parent))
try:
    count = 0
    warnings = []
    for root, dirs, files in os.walk(src, followlinks=False):
        root_path = Path(root)
        for name in dirs + files:
            if (root_path / name).is_symlink():
                raise ValueError(f'Symlinks are not allowed: {root_path / name}')
        for filename in files:
            path = root_path / filename
            relative = path.relative_to(src)
            new_parts = []
            for part in relative.parts:
                for token, value in values.items():
                    # Only APP_API_NAME is expected in metadata filenames.
                    if token == '@@RUN_AS_USERNAME@@' and token in part:
                        raise ValueError(f'Username placeholder is not allowed in a filename: {relative}')
                    part = part.replace(token, value)
                if pattern.search(part):
                    raise ValueError(f'Unresolved filename placeholder: {part}')
                new_parts.append(part)
            target = stage.joinpath(*new_parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                raise ValueError(f'Output path collision: {target}')
            if path.suffix.lower() in {'.xml', '.json', '.md', '.txt', '.yml', '.yaml'}:
                contents = path.read_text(encoding='utf-8-sig')
                for token, value in values.items():
                    contents = contents.replace(token, escape(value) if path.suffix.lower() == '.xml' else value)
                unresolved = pattern.findall(contents)
                if unresolved:
                    raise ValueError(f'Unresolved placeholders in {relative}: {sorted(set(unresolved))}')
                if path.suffix.lower() == '.xml':
                    # Ignore references contained only in XML comments.
                    no_comments = re.sub(r'<!--.*?-->', '', contents, flags=re.S)
                    if re.search(r'<\s*oauthLink(?:\s|/|>)', no_comments):
                        raise ValueError(f'Active oauthLink element remains in {relative}; remove it from the template.')
                    if re.search(r'<orgScopedExternalApp>[^<]+</orgScopedExternalApp>', no_comments):
                        warnings.append(f'{relative}: orgScopedExternalApp is present; review for source-org references.')
                    if '<contactEmail>' in no_comments or '<contactPhone>' in no_comments:
                        warnings.append(f'{relative}: contact information is present; verify it belongs to the target org.')
                target.write_text(contents, encoding='utf-8', newline='\n')
            else:
                shutil.copy2(path, target)
            count += 1
    if count == 0:
        raise ValueError('Template directory contains no files.')
    stage.rename(dst)
except Exception as exc:
    shutil.rmtree(stage, ignore_errors=True)
    sys.exit(f'ERROR: {exc}')

print(f'Generated {count} file(s) in {dst}')
print(f'Application API name: {app}')
print('Run As username: configured (not printed)')
if warnings:
    print('WARNINGS:')
    for warning in sorted(set(warnings)):
        print(f'  - {warning}')
print('Review generated files and deployment dependencies before running sf project deploy start.')
PY
