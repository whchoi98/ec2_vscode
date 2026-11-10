#!/usr/bin/env python3
"""Update Codex TOML while retaining unrelated settings and comments."""

import argparse
from collections.abc import MutableMapping
from copy import deepcopy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from urllib.parse import urlsplit

import tomlkit


# Portable settings from the working Codex configuration, checked 2026-11-07.
BEDROCK_MODEL = "openai.gpt-6-astra"
STATUS_LINE = [
    "model-with-reasoning", "task-progress", "current-dir", "git-branch",
    "context-used", "five-hour-limit", "weekly-limit", "fast-mode",
]
AWS_SERVERS = {
    "awslabs-terraform-mcp-server": {
        "command": "uvx",
        "args": ["awslabs.terraform-mcp-server@latest"],
        "env": {"FASTMCP_LOG_LEVEL": "ERROR"},
        "startup_timeout_sec": 60,
    },
    "awslabs-core-mcp-server": {
        "command": "uvx",
        "args": ["awslabs.core-mcp-server@latest"],
        "env": {
            "FASTMCP_LOG_LEVEL": "ERROR",
            "aws-foundation": "true",
            "solutions-architect": "true",
        },
        "startup_timeout_sec": 60,
    },
    "bedrock-agentcore-mcp-server": {
        "command": "uvx",
        "args": ["awslabs.amazon-bedrock-agentcore-mcp-server@latest"],
        "env": {"FASTMCP_LOG_LEVEL": "ERROR"},
        "startup_timeout_sec": 60,
    },
}
MCP_FIELDS = {
    "command", "args", "env", "env_vars", "cwd", "url",
    "bearer_token_env_var", "http_headers", "env_http_headers",
    "startup_timeout_sec", "tool_timeout_sec", "enabled",
    "enabled_tools", "disabled_tools",
}


def table(document, key):
    if key not in document:
        document[key] = tomlkit.table()
    value = document[key]
    if not isinstance(value, MutableMapping):
        raise ValueError(f"{key} 항목이 TOML 테이블이 아닙니다.")
    return value


def choose(label, default, supplied, automatic):
    if supplied is not None:
        return supplied
    if automatic:
        return default
    suffix = f" [기본값: {default}]" if default else " [Enter: 생략]"
    return input(f"{label}{suffix}: ").strip() or default


def merge_missing_settings(document, defaults, path=()):
    for key, value in defaults.items():
        if key not in document:
            document[key] = deepcopy(value)
        elif (
            path != ("mcp_servers",)
            and isinstance(document[key], MutableMapping)
            and isinstance(value, MutableMapping)
        ):
            merge_missing_settings(document[key], value, path + (key,))


def include_ec2_settings(document, provider, model):
    example = Path(__file__).with_name("config.example.toml")
    defaults = tomlkit.parse(example.read_text(encoding="utf-8"))
    if provider != defaults.get("model_provider"):
        defaults.pop("openai_base_url", None)
    if provider != defaults.get("model_provider") or model != defaults.get("model"):
        for key in [
            "model", "model_reasoning_effort", "model_context_window",
            "model_auto_compact_token_limit", "service_tier",
        ]:
            defaults.pop(key, None)
    if "default_permissions" in document:
        defaults.pop("sandbox_mode", None)
        defaults.pop("sandbox_workspace_write", None)
    merge_missing_settings(document, defaults)
    print(f"EC2 전체 설정 병합: {example}")


def setup(document, args):
    previous_provider = str(document.get("model_provider", "openai"))
    previous_model = str(document.get("model", ""))
    provider_default = (
        previous_provider if previous_model or "model_provider" in document else "amazon-bedrock"
    )
    provider = choose(
        "Provider (bedrock / openai / custom / 기존 provider ID)",
        provider_default, args.provider, args.yes,
    )
    provider = {"bedrock": "amazon-bedrock", "custom": "openai-compatible"}.get(provider, provider)
    providers = document.get("model_providers", {})
    if not isinstance(providers, MutableMapping):
        raise ValueError("model_providers 항목이 TOML 테이블이 아닙니다.")
    if (
        provider not in {"amazon-bedrock", "openai", "openai-compatible"}
        and provider != previous_provider
        and provider not in providers
    ):
        raise ValueError("새 provider는 bedrock, openai, custom 중에서 선택하세요.")

    default_model = previous_model if provider == previous_provider else ""
    if not default_model and provider == "amazon-bedrock":
        default_model = BEDROCK_MODEL
    model = choose("모델 ID", default_model, args.model, args.yes)
    if not model:
        raise ValueError("이 provider에서 사용할 모델 ID를 --model로 지정하세요.")
    if args.include_ec2_settings:
        include_ec2_settings(document, provider, model)
    same_model = previous_provider == provider and previous_model == model
    if not same_model:
        for key in ["model_context_window", "model_auto_compact_token_limit", "model_reasoning_effort"]:
            document.pop(key, None)
    document["model_provider"] = provider
    document["model"] = model

    is_default_model = provider == "amazon-bedrock" and model == BEDROCK_MODEL
    effort = choose(
        "추론 수준 (모델이 지원하는 값, 예: high / max)",
        str(document.get("model_reasoning_effort", "max" if is_default_model else "")),
        args.reasoning_effort, args.yes,
    )
    if effort:
        document["model_reasoning_effort"] = effort
    if is_default_model:
        document.setdefault("model_context_window", 1048576)
    document.setdefault("service_tier", "default")
    reviewer = choose(
        "승인 검토 (auto_review / user)",
        str(document.get("approvals_reviewer", "auto_review")),
        args.approvals_reviewer, args.yes,
    )
    if reviewer not in {"auto_review", "user"}:
        raise ValueError("승인 검토는 auto_review 또는 user여야 합니다.")
    document["approvals_reviewer"] = reviewer
    document.setdefault("approval_policy", "on-request")
    if "default_permissions" not in document:
        document.setdefault("sandbox_mode", "workspace-write")
    table(document, "tui").setdefault("status_line", STATUS_LINE)

    if provider == "amazon-bedrock":
        aws = table(table(table(document, "model_providers"), provider), "aws")
        aws["region"] = choose("AWS 리전", str(aws.get("region", "us-east-1")), args.region, args.yes)
        profile = choose(
            "AWS 프로파일 (생략하면 AWS 기본 인증 체인)",
            str(aws.get("profile", "")), args.aws_profile, args.yes,
        )
        if profile:
            aws["profile"] = profile
        else:
            aws.pop("profile", None)
    elif provider == "openai-compatible":
        custom = table(table(document, "model_providers"), provider)
        base_url = choose(
            "Responses API Base URL", str(custom.get("base_url", "")),
            args.base_url, args.yes,
        )
        url = urlsplit(base_url)
        if url.scheme not in {"http", "https"} or not url.hostname or url.username or url.password:
            raise ValueError("사용자명·비밀번호가 포함되지 않은 http(s) Base URL을 입력하세요.")
        custom.setdefault("name", "OpenAI-compatible Responses API")
        custom["base_url"] = base_url
        custom["wire_api"] = "responses"
        if not any(key in custom for key in ["auth", "experimental_bearer_token", "requires_openai_auth"]):
            custom.setdefault("env_key", "OPENAI_API_KEY")
    print(f"Provider: {provider}\nModel: {model}\n승인 검토: {reviewer}")


def setup_mcp(document, args):
    servers = table(document, "mcp_servers")
    legacy_path = args.config_file.parent / "mcp.json"
    if legacy_path.exists():
        legacy = json.loads(legacy_path.read_text(encoding="utf-8"))
        if not isinstance(legacy, dict) or not isinstance(legacy.get("mcpServers"), dict):
            raise ValueError("mcp.json의 mcpServers 항목이 객체가 아닙니다.")
        for name, server in legacy["mcpServers"].items():
            if name in servers:
                continue
            if not isinstance(server, dict):
                raise ValueError(f"기존 MCP 서버 {name}의 설정이 객체가 아닙니다.")
            if bool(server.get("command")) == bool(server.get("url")):
                raise ValueError(f"기존 MCP 서버 {name}에는 command 또는 url 하나가 필요합니다.")
            migrated = {key: value for key, value in server.items() if key in MCP_FIELDS}
            if "disabled" in server:
                if not isinstance(server["disabled"], bool):
                    raise ValueError(f"기존 MCP 서버 {name}의 disabled 값이 boolean이 아닙니다.")
                migrated["enabled"] = not server["disabled"]
            servers[name] = migrated
        print("기존 mcp.json을 병합합니다. 같은 이름의 TOML 설정이 우선합니다.")
    for name, server in AWS_SERVERS.items():
        if name not in servers:
            servers[name] = server
    if not args.dry_run and shutil.which("uvx") is None:
        raise ValueError("uvx가 필요합니다. uv를 설치하고 PATH를 확인하세요.")
    print("MCP 서버: " + ", ".join(servers))


def save(path, original, document, dry_run):
    updated = tomlkit.dumps(document)
    tomlkit.parse(updated)
    if updated == original:
        print(f"변경할 설정이 없습니다: {path}")
        return
    if dry_run:
        print(f"미리보기: {path}에 설정을 병합합니다. 파일은 변경하지 않았습니다.")
        return
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    current = path.read_text(encoding="utf-8") if path.exists() else ""
    if current != original:
        raise ValueError("읽은 후 설정 파일이 변경되었습니다. 다시 실행하세요.")
    if path.exists():
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
        fd, backup = tempfile.mkstemp(prefix=f"{path.name}.backup.{stamp}.", dir=path.parent)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(original)
        print(f"백업: {backup}")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(updated)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"설정 저장: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["setup", "mcp"])
    default_path = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml"
    parser.add_argument("--config-file", type=Path, default=default_path)
    parser.add_argument("--dry-run", action="store_true", help="파일을 쓰지 않고 변경 계획 확인")
    parser.add_argument("--yes", action="store_true", help="기존 값 또는 기본값을 사용")
    parser.add_argument(
        "--include-ec2-settings", action="store_true",
        help="config.example.toml의 EC2 전체 설정을 기존 값 보존하여 병합 (setup 전용)",
    )
    parser.add_argument("--provider", help="bedrock, openai, custom 또는 기존 provider ID")
    parser.add_argument("--model")
    parser.add_argument("--region")
    parser.add_argument("--aws-profile", help="빈 문자열이면 저장된 프로파일 제거")
    parser.add_argument("--reasoning-effort")
    parser.add_argument("--approvals-reviewer", choices=["auto_review", "user"])
    parser.add_argument("--base-url")
    args = parser.parse_args()
    if args.include_ec2_settings and args.operation != "setup":
        parser.error("--include-ec2-settings는 01-setup-env.sh에서 사용하세요.")
    args.config_file = args.config_file.expanduser().resolve()
    try:
        original = args.config_file.read_text(encoding="utf-8") if args.config_file.exists() else ""
        document = tomlkit.parse(original)
        if args.operation == "setup":
            setup(document, args)
        else:
            setup_mcp(document, args)
        save(args.config_file, original, document, args.dry_run)
    except (OSError, ValueError, TypeError, tomlkit.exceptions.ParseError) as exc:
        # Parser errors can contain credentials from malformed input.
        message = "설정 파일 문법을 확인하세요." if isinstance(
            exc, (json.JSONDecodeError, tomlkit.exceptions.ParseError)
        ) else str(exc)
        print(f"오류: {message}", file=sys.stderr)
        return 1
    except (EOFError, KeyboardInterrupt):
        print("\n설정을 취소했습니다. 비대화형 실행에는 --yes를 사용하세요.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
