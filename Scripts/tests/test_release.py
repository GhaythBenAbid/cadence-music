import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('cadence_release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_explicit_team_is_used_for_archive_and_export_without_upload(self):
        with tempfile.TemporaryDirectory() as folder:
            calls = []
            config = dict(keyPath='/fixture/AuthKey_FAKE.p8', keyId='FAKE', issuerId='fixture', teamId='FIXTURETEAM')
            ipa = release.release(config, folder, runner=lambda args, **kw: calls.append((args, kw)))
            self.assertEqual(len(calls), 3)
            self.assertIn('DEVELOPMENT_TEAM=FIXTURETEAM', calls[1][0])
            options = plistlib.loads((Path(folder) / 'ExportOptions.plist').read_bytes())
            self.assertEqual(options['teamID'], 'FIXTURETEAM')
            self.assertFalse(options['manageAppVersionAndBuildNumber'])
            self.assertEqual(ipa.name, 'Cadence.ipa')
            self.assertTrue(all(call[1]['check'] for call in calls))

    def test_upload_requires_explicit_flag_and_uses_configured_key_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            calls = []
            config = dict(keyPath='/fixture/AuthKey_FAKE.p8', keyId='FAKE', issuerId='fixture', teamId='FIXTURETEAM')
            release.release(config, folder, upload=True, runner=lambda args, **kw: calls.append((args, kw)))
            self.assertEqual(len(calls), 4)
            self.assertEqual(calls[-1][0][:3], ['xcrun', 'altool', '--upload-app'])
            self.assertEqual(calls[-1][1]['env']['API_PRIVATE_KEYS_DIR'], '/fixture')

    def test_missing_team_or_key_fails_before_building(self):
        with tempfile.TemporaryDirectory() as folder:
            config = Path(folder) / 'config.json'
            key = Path(folder) / 'key.p8'
            key.write_text('synthetic fixture; not a private key')
            valid = dict(keyPath=str(key), keyId='FAKE', issuerId='fixture', teamId='FIXTURETEAM')
            for field in valid:
                value = valid.copy()
                value.pop(field)
                config.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    release.load_config(config)
            config.write_text(json.dumps(valid))
            self.assertEqual(release.load_config(config)['teamId'], 'FIXTURETEAM')
            key.unlink()
            with self.assertRaises(ValueError):
                release.load_config(config)
            config.write_text('[]')
            with self.assertRaises(ValueError):
                release.load_config(config)


if __name__ == '__main__':
    unittest.main()
