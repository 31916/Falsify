"""Standard-library checks for relocatable sources and installed dependency hashes."""
import ast
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]


class LayoutTests(unittest.TestCase):
    def test_python_syntax(self):
        for folder in ('python', 'tests', 'dependencies'):
            for source in (ROOT / folder).glob('*.py'):
                ast.parse(source.read_text(), filename=str(source))

    def test_no_legacy_runtime_paths(self):
        for folder in ('matlab', 'python', 'config'):
            for source in (ROOT / folder).glob('*'):
                if source.suffix not in ('.m', '.py'):
                    continue
                text = source.read_text()
                self.assertNotIn('/Users/', text, source)
                self.assertNotIn("'FIM','work'", text, source)
                self.assertNotIn("'FIM','vendor'", text, source)

    def test_installed_manifest(self):
        deps = REPO / '.deps' / 'fim'
        if not (deps / 'installed.json').exists():
            self.skipTest('Run dependencies/prepare.py first')
        saved = json.loads((deps / 'installed.json').read_text())
        for name, digest in saved['Files'].items():
            self.assertEqual(hashlib.sha256((deps/name).read_bytes()).hexdigest(), digest, name)
        code = (deps/'fimtool-r2026a'/'fault_suite.m').read_text()
        self.assertIn('strcmp(block_inform{i}, level_final)', code)


if __name__ == '__main__':
    unittest.main()
