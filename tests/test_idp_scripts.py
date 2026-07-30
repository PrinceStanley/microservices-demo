from pathlib import Path

repo = Path(__file__).resolve().parent.parent
scripts = [
    repo / 'scripts' / 'build-images.sh',
    repo / 'scripts' / 'push-images.sh',
    repo / 'scripts' / 'update-helm.sh',
    repo / 'scripts' / 'sync-argocd.sh',
    repo / 'scripts' / 'validate-deployment.sh',
]

for path in scripts:
    if not path.exists() or path.stat().st_size == 0:
        raise SystemExit(f'Missing implementation: {path}')
    content = path.read_text(encoding='utf-8')
    if 'set -Eeuo pipefail' not in content:
        raise SystemExit(f'{path} is missing strict shell guards')

sonar_script = repo / 'scripts' / 'run-sonarqube.sh'
sonar_content = sonar_script.read_text(encoding='utf-8')
if 'sonar.token' not in sonar_content or 'sonar.exclusions' not in sonar_content:
    raise SystemExit('SonarQube scanner configuration is missing token and exclusion settings')

print('IDP automation scripts verified successfully.')
