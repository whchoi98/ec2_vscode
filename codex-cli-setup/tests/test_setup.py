"""Exercise configuration updates without modifying the user's Codex home."""

from pathlib import Path
import subprocess
import tempfile
import unittest

import tomlkit


SETUP_DIR = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex-setup-test-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.config = self.directory / "config.toml"

    def run_setup(self, *arguments, script="01-setup-env.sh", success=True):
        result = subprocess.run(
            ["bash", str(SETUP_DIR / script), "--config-file", str(self.config), *arguments],
            input="",
            capture_output=True,
            text=True,
            timeout=20,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def read_config(self):
        self.assertTrue(self.config.exists(), "Codex must receive a config.toml file")
        return tomlkit.parse(self.config.read_text())

    def test_new_setup_uses_native_bedrock_without_writing_credentials(self):
        self.run_setup("--yes")
        config = self.read_config()
        self.assertEqual(config["model_provider"], "amazon-bedrock")
        self.assertTrue(config["model"].startswith("openai."))
        self.assertEqual(config["model_providers"]["amazon-bedrock"]["aws"]["region"], "us-east-1")
        self.assertEqual(config["sandbox_mode"], "workspace-write")
        self.assertNotIn("openai_base_url", config)
        self.assertNotIn("env_key", config["model_providers"]["amazon-bedrock"])
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_update_preserves_existing_preferences_comments_and_extensions(self):
        original = """# Keep my preferences.
model = "openai.custom-model"
model_provider = "amazon-bedrock"
model_reasoning_effort = "high"
approvals_reviewer = "user"
sandbox_mode = "read-only"

[model_providers.amazon-bedrock.aws]
region = "eu-west-1"
profile = "development"

[tui]
status_line = ["git-branch"]

[mcp_servers.local]
command = "node"
args = ["/opt/local/server.js"]
enabled = false

[plugins."example@personal"]
enabled = true

[projects."/workspace"]
trust_level = "trusted"
"""
        self.config.write_text(original)
        self.run_setup("--yes")
        config = self.read_config()
        self.assertEqual(config["model"], "openai.custom-model")
        self.assertEqual(config["model_reasoning_effort"], "high")
        self.assertEqual(config["approvals_reviewer"], "user")
        self.assertEqual(config["sandbox_mode"], "read-only")
        self.assertEqual(config["model_providers"]["amazon-bedrock"]["aws"]["profile"], "development")
        self.assertEqual(config["tui"]["status_line"], ["git-branch"])
        self.assertFalse(config["mcp_servers"]["local"]["enabled"])
        self.assertTrue(config["plugins"]["example@personal"]["enabled"])
        self.assertEqual(config["projects"]["/workspace"]["trust_level"], "trusted")
        self.assertIn("# Keep my preferences.", self.config.read_text())
        backups = list(self.directory.glob("config.toml.backup.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.assertEqual(backups[0].stat().st_mode & 0o777, 0o600)

    def test_repeat_run_does_not_rewrite_or_make_extra_backups(self):
        self.run_setup("--yes")
        original = self.config.read_bytes()
        modified = self.config.stat().st_mtime_ns
        self.run_setup("--yes")
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.config.stat().st_mtime_ns, modified)
        self.assertEqual(list(self.directory.glob("config.toml.backup.*")), [])

    def test_dry_run_does_not_create_files(self):
        self.run_setup("--yes", "--dry-run")
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_invalid_toml_is_not_overwritten(self):
        original = 'model = "unterminated\n'
        self.config.write_text(original)
        self.run_setup("--yes", success=False)
        self.assertEqual(self.config.read_text(), original)
        self.assertEqual(list(self.directory.glob("config.toml.backup.*")), [])

    def test_permission_profiles_are_not_mixed_with_legacy_sandbox_settings(self):
        self.config.write_text('default_permissions = ":read-only"\n')
        self.run_setup("--yes")
        config = self.read_config()
        self.assertEqual(config["default_permissions"], ":read-only")
        self.assertNotIn("sandbox_mode", config)
        self.assertNotIn("sandbox_workspace_write", config)

    def test_existing_openai_model_without_an_explicit_provider_is_preserved(self):
        self.config.write_text('model = "account-model"\n')
        self.run_setup("--yes")
        config = self.read_config()
        self.assertEqual(config["model_provider"], "openai")
        self.assertEqual(config["model"], "account-model")

    def test_existing_builtin_provider_does_not_need_a_custom_definition(self):
        self.config.write_text(
            'model_provider = "amazon-bedrock-runtime"\n'
            'model = "global.openai.gpt-6-astra"\n'
        )
        self.run_setup("--yes")
        config = self.read_config()
        self.assertEqual(config["model_provider"], "amazon-bedrock-runtime")
        self.assertEqual(config["model"], "global.openai.gpt-6-astra")

    def test_switching_models_drops_stale_context_and_reasoning_overrides(self):
        self.config.write_text(
            'model_provider = "amazon-bedrock"\n'
            'model = "openai.gpt-6-astra"\n'
            'model_reasoning_effort = "max"\n'
            "model_context_window = 1048576\n"
            "model_auto_compact_token_limit = 900000\n"
        )
        self.run_setup("--yes", "--provider", "openai", "--model", "account-model")
        config = self.read_config()
        self.assertEqual(config["model_provider"], "openai")
        self.assertEqual(config["model"], "account-model")
        self.assertNotIn("model_context_window", config)
        self.assertNotIn("model_auto_compact_token_limit", config)
        self.assertNotIn("model_reasoning_effort", config)

    def test_custom_provider_uses_responses_and_an_environment_key_reference(self):
        self.run_setup(
            "--yes", "--provider", "custom", "--model", "gateway-model",
            "--base-url", "https://gateway.example.test/v1",
        )
        config = self.read_config()
        provider = config["model_providers"][config["model_provider"]]
        self.assertEqual(provider["base_url"], "https://gateway.example.test/v1")
        self.assertEqual(provider["wire_api"], "responses")
        self.assertEqual(provider["env_key"], "OPENAI_API_KEY")
        self.assertNotIn("experimental_bearer_token", provider)

    def test_model_input_is_toml_escaped(self):
        model = 'account-model"\n[unexpected]\nenabled = true\n#'
        self.run_setup("--yes", "--provider", "openai", "--model", model)
        config = self.read_config()
        self.assertEqual(config["model"], model)
        self.assertNotIn("unexpected", config)

    def test_legacy_entrypoint_uses_the_same_configuration(self):
        self.run_setup("--yes", script="01-setup-openai-env.sh")
        self.assertIn("model_provider", self.read_config())

    def test_mcp_migration_preserves_disabled_servers_and_existing_toml(self):
        self.config.write_text(
            '# My existing server\n'
            '[mcp_servers.existing]\ncommand = "custom"\nenabled = false\n'
            '[plugins."example@personal"]\nenabled = true\n'
        )
        legacy = self.directory / "mcp.json"
        legacy.write_text(
            '{"mcpServers": {'
            '"existing": {"command": "old-command"},'
            '"legacy": {"command": "node", "args": ["server.js"], "disabled": true},'
            '"awslabs-core-mcp-server": {"command": "uvx", "args": ["pinned-package"], "disabled": true}'
            '}}'
        )
        original_legacy = legacy.read_bytes()
        self.run_setup(script="02-setup-mcp-servers.sh")
        config = self.read_config()
        self.assertEqual(config["mcp_servers"]["existing"]["command"], "custom")
        self.assertFalse(config["mcp_servers"]["existing"]["enabled"])
        self.assertFalse(config["mcp_servers"]["legacy"]["enabled"])
        self.assertNotIn("disabled", config["mcp_servers"]["legacy"])
        self.assertEqual(config["mcp_servers"]["awslabs-core-mcp-server"]["args"], ["pinned-package"])
        self.assertFalse(config["mcp_servers"]["awslabs-core-mcp-server"]["enabled"])
        self.assertIn("awslabs-terraform-mcp-server", config["mcp_servers"])
        self.assertTrue(config["plugins"]["example@personal"]["enabled"])
        self.assertEqual(legacy.read_bytes(), original_legacy)
        self.assertIn("# My existing server", self.config.read_text())

    def test_invalid_legacy_json_leaves_config_untouched(self):
        original = 'model = "my-model"\n'
        self.config.write_text(original)
        (self.directory / "mcp.json").write_text('{"mcpServers": invalid}')
        self.run_setup(script="02-setup-mcp-servers.sh", success=False)
        self.assertEqual(self.config.read_text(), original)


if __name__ == "__main__":
    unittest.main()
