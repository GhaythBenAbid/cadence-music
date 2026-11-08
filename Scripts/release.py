#!/usr/bin/env python3
"""Archive/export paired iPhone and Watch apps; upload only with --upload."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def load_config(path):
    config = json.loads(Path(path).expanduser().read_text())
    if not isinstance(config, dict):
        raise ValueError('Apple configuration must be a JSON object')
    for key in ('keyPath', 'keyId', 'issuerId', 'teamId'):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError('Apple configuration requires a non-empty ' + key)
    config['keyPath'] = str(Path(config['keyPath']).expanduser().resolve())
    if not Path(config['keyPath']).is_file():
        raise ValueError('Apple private key file does not exist')
    return config


def release(config, build, upload=False, runner=subprocess.run):
    build = Path(build).resolve()
    build.mkdir(parents=True, exist_ok=True)

    def run(args, env=None):
        runner(args, cwd=ROOT, env=env, check=True)

    auth = ['-allowProvisioningUpdates', '-authenticationKeyPath', config['keyPath'],
            '-authenticationKeyID', config['keyId'],
            '-authenticationKeyIssuerID', config['issuerId']]
    run(['xcodegen', 'generate'])
    run(['xcodebuild', '-project', 'Cadence.xcodeproj', '-scheme', 'Cadence',
         '-destination', 'generic/platform=iOS', '-archivePath', str(build / 'Cadence.xcarchive'),
         *auth, 'DEVELOPMENT_TEAM=' + config['teamId'], 'archive'])
    options = build / 'ExportOptions.plist'
    with options.open('wb') as file:
        plistlib.dump({'method': 'app-store-connect', 'teamID': config['teamId'],
                      'signingStyle': 'automatic', 'destination': 'export',
                      'uploadSymbols': True, 'manageAppVersionAndBuildNumber': False}, file)
    run(['xcodebuild', '-exportArchive', '-archivePath', str(build / 'Cadence.xcarchive'),
         '-exportPath', str(build / 'export'), '-exportOptionsPlist', str(options), *auth])
    ipa = build / 'export/Cadence.ipa'
    if upload:
        env = os.environ.copy()
        env['API_PRIVATE_KEYS_DIR'] = str(Path(config['keyPath']).parent)
        run(['xcrun', 'altool', '--upload-app', '-f', str(ipa), '-t', 'ios',
             '--apiKey', config['keyId'], '--apiIssuer', config['issuerId']], env=env)
    return ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default=os.environ.get(
        'CADENCE_ASC_CONFIG', str(Path.home() / '.config/cadence/apple.json')))
    parser.add_argument('--upload', action='store_true', help='Also upload to App Store Connect')
    parser.add_argument('--build-dir', default='.build')
    args = parser.parse_args()
    try:
        config = load_config(args.config)
    except (OSError, ValueError):
        parser.error('Provide a private Apple config with keyPath, keyId, issuerId and teamId; see docs/RELEASE.md')
    print('IPA:', release(config, ROOT / args.build_dir, args.upload))


if __name__ == '__main__':
    main()
