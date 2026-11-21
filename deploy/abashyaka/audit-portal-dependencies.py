"""Record npm audit results without modifying application dependencies."""
import json
from pathlib import Path
import subprocess

release = Path('/opt/abashyaka/releases/8d5eb0f-d03')
for portal in ['admin', 'merchant']:
    image = f'abashyaka-{portal}'
    if subprocess.run(['docker','image','inspect',image], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        print(portal + ': image not built yet')
        continue
    result = subprocess.run(['docker','run','--rm','--network','bridge',
                             '-v', f'{release}/apps/{portal}-web:/audit:ro', '-w','/audit',
                             '--entrypoint','npm', image, 'audit','--omit=dev','--json'],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90)
    try:
        report = json.loads(result.stdout)
    except ValueError:
        raise RuntimeError(f'{portal}: npm audit did not return a JSON report') from None
    if 'metadata' not in report:
        raise RuntimeError(f'{portal}: npm audit failed to inspect dependencies')
    (release / f'evidence/{portal}-dependency-audit.json').write_text(json.dumps(report, indent=2))
    print(json.dumps({'portal':portal,'exit':result.returncode,
                      'vulnerabilities':report['metadata']['vulnerabilities'],
                      'affected':{key:value['severity'] for key,value in report.get('vulnerabilities',{}).items()}}))
