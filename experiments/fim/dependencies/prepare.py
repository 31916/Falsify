"""Install pinned FIM/AT sources locally without changing any existing checkout.

Uses only Python's standard library, git and patch. Pass local clones to work
offline. MATLAB example data must come from your licensed MATLAB installation.
Never replaces an existing installation; validates its complete content manifest.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive(source, definition, destination, temporary):
    if source is None:
        source = temporary / (destination.name + '-clone')
        subprocess.run(['git', 'clone', '--no-checkout', definition['url'], str(source)], check=True)
    source = source.resolve()
    commit = subprocess.check_output(
        ['git', '-C', str(source), 'rev-parse', definition['commit'] + '^{commit}'], text=True).strip()
    if commit != definition['commit']:
        raise ValueError('Unexpected dependency commit')
    command = ['git', '-C', str(source), 'archive', '--format=tar', commit]
    if 'path' in definition:
        command.append(definition['path'])
    payload = subprocess.check_output(command)
    destination.mkdir()
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive_file:
        for member in archive_file.getmembers():
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                raise ValueError('Unsafe archive member: ' + member.name)
        archive_file.extractall(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fim-source', type=Path)
    parser.add_argument('--arch-source', type=Path)
    parser.add_argument('--model-data', type=Path, required=True,
                        help='Path to licensed sldemo_autotrans_data.mat')
    args = parser.parse_args()
    if not args.model_data.is_file():
        parser.error('--model-data must be an existing file')
    lock = json.loads((HERE / 'versions.json').read_text())
    fingerprint = dict(Versions=lock, PatchSHA256=sha(HERE / 'fim-r2026a.patch'),
                       ModelDataSHA256=sha(args.model_data))
    destination = REPO / '.deps' / 'fim'
    if destination.exists():
        saved = json.loads((destination / 'installed.json').read_text())
        if saved['Inputs'] != fingerprint:
            raise RuntimeError('Existing dependency inputs differ; preserve them and choose an explicit migration.')
        for name, digest in saved['Files'].items():
            if sha(destination / name) != digest:
                raise RuntimeError('Installed dependency changed: ' + name)
        print('PASS: existing pinned dependencies and all file hashes verified')
        return
    destination.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='fim-install-', dir=destination.parent) as temporary:
        temporary = Path(temporary)
        staging = temporary / 'installation'
        staging.mkdir()
        archive(args.fim_source, lock['fim'], staging / 'fimtool', temporary)
        archive(args.arch_source, lock['arch'], staging / 'arch', temporary)
        if sha(staging / 'arch' / lock['arch']['path']) != lock['arch']['sha256']:
            raise RuntimeError('AT model hash does not match the locked source')
        patched = staging / 'fimtool-r2026a'
        shutil.copytree(staging / 'fimtool', patched)
        subprocess.run(['patch', '--batch', '--forward', '-p1', '-i',
                        str(HERE / 'fim-r2026a.patch')], cwd=patched, check=True)
        (staging / 'model-data').mkdir()
        shutil.copy2(args.model_data, staging / 'model-data' / 'sldemo_autotrans_data.mat')
        files = {str(p.relative_to(staging)): sha(p) for p in sorted(staging.rglob('*')) if p.is_file()}
        (staging / 'installed.json').write_text(json.dumps(dict(Inputs=fingerprint, Files=files), indent=2) + '\n')
        staging.rename(destination)
    print('Installed pinned dependencies:', destination)


if __name__ == '__main__':
    main()
