#!/usr/bin/env python3
"""Lightweight YAML helpers for the CI/CD scripts.

These scripts run in Jenkins images that may not have PyYAML installed.
The helper implements a narrow parser for the repository's service metadata
files so the pipelines can keep running without external dependencies.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple


def _parse_scalar(value: str) -> Any:
    value = value.strip()
    if value in {"", "null", "Null", "~"}:
        return None
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def parse_services_metadata(path: str | os.PathLike[str]) -> Tuple[Dict[str, Any], Dict[str, Dict[str, Any]]]:
    """Parse the repository's ci/services.yaml structure.

    Supports the subset used in this repo:
    - top-level keys: version, platform, services
    - platform: nested mapping of scalars
    - services: mapping of service names to nested mappings with nested blocks
      such as helm/sonar.
    """
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    root: Dict[str, Any] = {}
    platform: Dict[str, Any] = {}
    services: Dict[str, Dict[str, Any]] = {}

    current_section: str | None = None
    current_service: str | None = None
    current_block: str | None = None

    for raw_line in lines:
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        indent = len(raw_line) - len(raw_line.lstrip(" "))
        line = raw_line.split("#", 1)[0].rstrip()
        stripped = line.strip()

        if indent == 0:
            current_block = None
            if stripped == "platform:":
                current_section = "platform"
                current_service = None
                continue
            if stripped == "services:":
                current_section = "services"
                current_service = None
                continue
            key, sep, value = stripped.partition(":")
            if sep:
                root[key.strip()] = _parse_scalar(value)
            continue

        if current_section == "platform" and indent == 2:
            key, sep, value = stripped.partition(":")
            if sep:
                platform[key.strip()] = _parse_scalar(value)
            continue

        if current_section == "services" and indent == 2 and stripped.endswith(":"):
            current_service = stripped[:-1]
            services[current_service] = {}
            current_block = None
            continue

        if current_service is None:
            continue

        if indent == 4:
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            if value.strip():
                services[current_service][key.strip()] = _parse_scalar(value)
                current_block = None
            else:
                services[current_service][key.strip()] = {}
                current_block = key.strip()
            continue

        if indent == 6 and current_block:
            key, sep, value = stripped.partition(":")
            if sep:
                services[current_service][current_block][key.strip()] = _parse_scalar(value)
            continue

    root["platform"] = platform
    root["services"] = services
    return root["platform"], services


def get_platform_value(path: str | os.PathLike[str], field: str) -> Any:
    platform, _ = parse_services_metadata(path)
    return (platform or {}).get(field)


def get_service_value(path: str | os.PathLike[str], service: str, field: str) -> Any:
    _, services = parse_services_metadata(path)
    config = (services or {}).get(service, {})
    if not isinstance(config, dict):
        return None
    if "." in field:
        current: Any = config
        for part in field.split("."):
            if not isinstance(current, dict):
                return None
            current = current.get(part)
        return current
    return config.get(field)


def list_enabled_services(path: str | os.PathLike[str]) -> List[str]:
    _, services = parse_services_metadata(path)
    return [name for name, config in sorted(services.items()) if config.get("enabled", False)]


def write_enabled_services(path: str | os.PathLike[str], out_path: str | os.PathLike[str]) -> None:
    services = list_enabled_services(path)
    output = Path(out_path)
    output.write_text('\n'.join(services) + ('\n' if services else ''), encoding='utf-8')


def write_changed_services(path: str | os.PathLike[str], out_path: str | os.PathLike[str], changed_files: List[str]) -> None:
    _, services = parse_services_metadata(path)
    matched = []
    for service, config in sorted(services.items()):
        if not config.get('enabled', False):
            continue
        source = config.get('source', '')
        if any(changed.startswith(f"{source}/") for changed in changed_files if changed):
            matched.append(service)
    output = Path(out_path)
    output.write_text('\n'.join(sorted(set(matched))) + ('\n' if matched else ''), encoding='utf-8')


def update_helm_values(services_file: str | os.PathLike[str], values_file: str | os.PathLike[str], image_tag: str, report_dir: str | os.PathLike[str], changed_file: str | os.PathLike[str]) -> None:
    services_data = parse_services_metadata(services_file)[1]
    values_path = Path(values_file)
    values_data = {}
    if values_path.exists():
        values_data = {}
        with values_path.open(encoding='utf-8') as handle:
            for line in handle:
                line = line.rstrip('\n')
                if not line.strip() or line.lstrip().startswith('#'):
                    continue
                if line.startswith(''):
                    pass
    if values_path.exists():
        try:
            import json
            import ast
            import re
            _ = json  # keep import for linting
            _ = ast
            _ = re
        except Exception:
            pass

    parsed_values: Dict[str, Any] = {}
    if values_path.exists():
        content = values_path.read_text(encoding='utf-8')
        lines = content.splitlines()
        stack: List[Tuple[int, Dict[str, Any]]] = [(-1, parsed_values)]
        for raw_line in lines:
            if not raw_line.strip() or raw_line.lstrip().startswith('#'):
                continue
            indent = len(raw_line) - len(raw_line.lstrip(' '))
            line = raw_line.split('#', 1)[0].rstrip()
            if not line.strip():
                continue
            while len(stack) > 1 and indent <= stack[-1][0]:
                stack.pop()
            parent = stack[-1][1]
            key, sep, value = line.strip().partition(':')
            if sep:
                if value.strip():
                    parent[key.strip()] = _parse_scalar(value)
                else:
                    new_dict: Dict[str, Any] = {}
                    parent[key.strip()] = new_dict
                    stack.append((indent, new_dict))
        values_data = parsed_values

    changed_services = []
    if Path(changed_file).exists():
        changed_services = [line.strip() for line in Path(changed_file).read_text(encoding='utf-8').splitlines() if line.strip()]

    for service in changed_services:
        config = services_data.get(service, {})
        values_key = config.get('helm', {}).get('valuesKey')
        if not values_key:
            continue
        value_path = values_key.split('.')
        current = values_data
        for part in value_path[:-1]:
            if part not in current or not isinstance(current[part], dict):
                current[part] = {}
            current = current[part]
        current[value_path[-1]] = image_tag

    output = []
    def dump_dict(data: Any, indent: int = 0) -> None:
        if isinstance(data, dict):
            for key, value in data.items():
                if isinstance(value, dict):
                    output.append(' ' * indent + f'{key}:')
                    dump_dict(value, indent + 2)
                else:
                    output.append(' ' * indent + f'{key}: {value}')
        else:
            output.append(' ' * indent + str(data))

    dump_dict(values_data)
    values_path.write_text('\n'.join(output) + '\n', encoding='utf-8')

    report_dir_path = Path(report_dir)
    report_dir_path.mkdir(parents=True, exist_ok=True)
    (report_dir_path / 'helm-values-overrides.yaml').write_text(
        '\n'.join(f'{service}: {image_tag}' for service in changed_services if service) + '\n',
        encoding='utf-8',
    )


def main() -> None:
    parser = argparse.ArgumentParser(description='Lightweight YAML helper for deployment scripts')
    parser.add_argument('--platform-value', nargs=2)
    parser.add_argument('--service-value', nargs=3)
    parser.add_argument('--list-enabled-services', nargs=2)
    parser.add_argument('--match-services', nargs=3)
    parser.add_argument('--update-helm-values', nargs=5)
    args = parser.parse_args()

    if args.platform_value:
        path, field = args.platform_value
        print(get_platform_value(path, field))
        return
    if args.service_value:
        path, service, field = args.service_value
        print(get_service_value(path, service, field))
        return
    if args.list_enabled_services:
        path, out_path = args.list_enabled_services
        write_enabled_services(path, out_path)
        return
    if args.match_services:
        path, out_path, changed_files_raw = args.match_services
        changed_files = [item for item in changed_files_raw.splitlines() if item]
        write_changed_services(path, out_path, changed_files)
        return
    if args.update_helm_values:
        services_file, values_file, image_tag, report_dir, changed_file = args.update_helm_values[:5]
        update_helm_values(services_file, values_file, image_tag, report_dir, changed_file)
        return

    parser.error('No action specified')


if __name__ == '__main__':
    sys.exit(main())
