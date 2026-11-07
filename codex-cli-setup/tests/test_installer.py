"""Keep installer tests off the network and outside the user's shell files."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


INSTALLER = Path(__file__).resolve().parents[1] / "03-update-codex.sh"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-installer-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.prefix = self.directory / "user npm"
        self.shell_rc = self.directory / "bashrc"
        self.environment = {
            **os.environ,
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "CODEX_INSTALL_PREFIX": str(self.prefix),
            "CODEX_SHELL_RC": str(self.shell_rc),
        }
        self.stub("sudo", "exit 99\n")
        self.stub("node", 'echo "v22.0.0"\n')

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_installer(self, *arguments):
        result = subprocess.run(
            ["bash", str(INSTALLER), *arguments],
            env=self.environment, text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_existing_cli_is_updated_by_its_native_updater(self):
        marker = self.directory / "updated"
        self.stub(
            "codex",
            'case "$*" in\n'
            '  --version) echo "codex-cli 0.167.0" ;;\n'
            '  "update --help") exit 0 ;;\n'
            f'  update) touch {shlex.quote(str(marker))} ;;\n'
            '  *) exit 2 ;;\nesac\n',
        )
        self.stub("npm", "exit 98\n")
        self.run_installer()
        self.assertTrue(marker.exists())
        self.assertFalse(self.prefix.exists())
        self.assertFalse(self.shell_rc.exists())

    def legacy_install_stubs(self):
        self.stub(
            "codex",
            'if [[ "$*" == "--version" ]]; then echo "codex-cli old"; else exit 1; fi\n',
        )
        self.stub(
            "npm",
            '[[ "$1" == "install" && "$2" == "--global" && "$3" == "--prefix" ]]\n'
            '[[ "$5" == "@openai/codex@latest" ]]\n'
            'mkdir -p "$4/bin"\n'
            'printf \'#!/bin/bash\\necho "codex-cli updated"\\n\' > "$4/bin/codex"\n'
            'chmod +x "$4/bin/codex"\n',
        )

    def test_legacy_install_updates_user_path_and_keeps_shell_customizations(self):
        self.legacy_install_stubs()
        self.shell_rc.write_text('export USER_SETTING="keep me"\n')
        self.run_installer()
        original = self.shell_rc.read_bytes()
        self.run_installer()
        self.assertEqual(self.shell_rc.read_bytes(), original)
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; command -v codex; printf "%s" "$USER_SETTING"',
             "check-path", str(self.shell_rc)],
            env=self.environment, capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(self.prefix / "bin/codex") + "\nkeep me")

    def test_install_dry_run_does_not_write_to_user_paths(self):
        self.legacy_install_stubs()
        self.run_installer("--dry-run")
        self.assertFalse(self.prefix.exists())
        self.assertFalse(self.shell_rc.exists())


if __name__ == "__main__":
    unittest.main()
