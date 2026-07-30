import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

repo = Path(__file__).resolve().parent.parent


def assert_script_has_strict_shell_guards(path: Path) -> None:
    if not path.exists() or path.stat().st_size == 0:
        raise SystemExit(f'Missing implementation: {path}')
    content = path.read_text(encoding='utf-8')
    if 'set -Eeuo pipefail' not in content:
        raise SystemExit(f'{path} is missing strict shell guards')


def resolve_bash_executable() -> str:
    candidates = []
    for name in ('bash', 'bash.exe'):
        resolved = shutil.which(name)
        if resolved:
            candidates.append(resolved)

    candidates.extend([
        r'C:\Program Files\Git\bin\bash.exe',
        r'C:\Program Files\Git\usr\bin\bash.exe',
    ])

    seen = set()
    for candidate in candidates:
        if not candidate or candidate in seen:
            continue
        seen.add(candidate)
        try:
            subprocess.run([candidate, '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            return candidate
        except (OSError, subprocess.CalledProcessError):
            continue

    raise RuntimeError('Unable to locate a working bash executable for tests')


def test_detect_services_initial_deployment() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        (tmp_path / 'ci').mkdir(parents=True, exist_ok=True)
        (tmp_path / 'ci' / 'services.yaml').write_text(
            textwrap.dedent(
                '''
                version: "1.0"
                platform:
                  registry: "example.com"
                  repository: "demo"
                  namespace: "online-boutique"
                services:
                  frontend:
                    enabled: true
                    source: "src/frontend"
                    dockerfile: "src/frontend/Dockerfile"
                    image: "frontend"
                    deployment: "frontend"
                    helm:
                      valuesKey: "frontend.image.tag"
                  cartservice:
                    enabled: false
                    source: "src/cartservice"
                    dockerfile: "src/cartservice/Dockerfile"
                    image: "cartservice"
                    deployment: "cartservice"
                    helm:
                      valuesKey: "cartservice.image.tag"
                '''
            ).strip() + '\n',
            encoding='utf-8',
        )
        subprocess.run(['git', 'init'], cwd=tmp_path, check=True, capture_output=True, text=True)
        subprocess.run(['git', 'config', 'user.email', 'ci@example.com'], cwd=tmp_path, check=True)
        subprocess.run(['git', 'config', 'user.name', 'CI Bot'], cwd=tmp_path, check=True)
        subprocess.run(['git', 'add', '.'], cwd=tmp_path, check=True)
        subprocess.run(['git', 'commit', '-m', 'init'], cwd=tmp_path, check=True, capture_output=True, text=True)

        env = os.environ.copy()
        env['INITIAL_DEPLOYMENT'] = 'true'
        bash_executable = resolve_bash_executable()
        result = subprocess.run(
            [bash_executable, str(repo / 'scripts' / 'detect-services.sh')],
            cwd=tmp_path,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        changed_services = (tmp_path / 'changed-services.txt').read_text(encoding='utf-8').splitlines()
        assert changed_services == ['frontend'], result.stdout + result.stderr


def test_update_helm_values_cli_accepts_script_arguments() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        (tmp_path / 'ci').mkdir(parents=True, exist_ok=True)
        services_file = tmp_path / 'ci' / 'services.yaml'
        services_file.write_text(
            textwrap.dedent(
                '''
                version: "1.0"
                platform:
                  registry: "example.com"
                services:
                  frontend:
                    enabled: true
                    helm:
                      valuesKey: "frontend.image.tag"
                '''
            ).strip() + '\n',
            encoding='utf-8',
        )
        values_file = tmp_path / 'values.yaml'
        values_file.write_text('frontend:\n  image:\n    tag: "old"\n', encoding='utf-8')
        changed_file = tmp_path / 'changed-services.txt'
        changed_file.write_text('frontend\n', encoding='utf-8')
        report_dir = tmp_path / 'reports' / 'images'

        result = subprocess.run(
            [
                sys.executable,
                str(repo / 'scripts' / 'yaml_support.py'),
                '--update-helm-values',
                str(services_file),
                str(values_file),
                '1.2.3',
                str(report_dir),
                str(changed_file),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        assert result.returncode == 0, result.stdout + result.stderr
        assert (report_dir / 'helm-values-overrides.yaml').read_text(encoding='utf-8') == 'frontend: 1.2.3\n'
        assert 'tag: 1.2.3' in values_file.read_text(encoding='utf-8')


scripts = [
    repo / 'scripts' / 'build-images.sh',
    repo / 'scripts' / 'push-images.sh',
    repo / 'scripts' / 'update-helm.sh',
    repo / 'scripts' / 'sync-argocd.sh',
    repo / 'scripts' / 'validate-deployment.sh',
]

for path in scripts:
    assert_script_has_strict_shell_guards(path)

sonar_script = repo / 'scripts' / 'run-sonarqube.sh'
sonar_content = sonar_script.read_text(encoding='utf-8')
if 'sonar.token' not in sonar_content or 'sonar.exclusions' not in sonar_content:
    raise SystemExit('SonarQube scanner configuration is missing token and exclusion settings')

test_detect_services_initial_deployment()
print('IDP automation scripts verified successfully.')
