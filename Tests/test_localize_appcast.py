import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from xml.dom import minidom

SPEC = importlib.util.spec_from_file_location("localize_appcast", Path(__file__).resolve().parents[1] / "scripts/localize-appcast.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LocalizeAppcastTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.appcast = self.root / "appcast.xml"
        self.original = ('<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                         '<channel><item><description>old</description><enclosure url="https://example.com/a.dmg" '
                         'sparkle:edSignature="signature" length="123"/></item></channel></rss>')
        self.appcast.write_text(self.original)
        self.plist = self.root / "Info.plist"
        self.plist.write_bytes(plistlib.dumps({}))
        for language in MODULE.LANGUAGES:
            (self.root / f"{language}.html").write_text(f"<p>{language} &amp; text</p>")

    def test_embeds_each_language_and_preserves_signed_enclosure(self):
        MODULE.localize(self.appcast, self.root, self.plist)
        document = minidom.parse(str(self.appcast))
        descriptions = document.getElementsByTagName("description")
        self.assertEqual([node.getAttribute("xml:lang") for node in descriptions], list(MODULE.LANGUAGES))
        self.assertEqual(descriptions[0].firstChild.data, "<p>en &amp; text</p>")
        enclosure = document.getElementsByTagName("enclosure")[0]
        self.assertEqual(enclosure.getAttribute("sparkle:edSignature"), "signature")
        self.assertEqual(enclosure.getAttribute("length"), "123")

    def test_missing_translation_leaves_feed_unchanged(self):
        (self.root / "ko.html").unlink()
        with self.assertRaises(FileNotFoundError):
            MODULE.localize(self.appcast, self.root, self.plist)
        self.assertEqual(self.appcast.read_text(), self.original)

    @unittest.skipUnless(sys.platform == "darwin", "The macOS release workflow uses PlistBuddy")
    def test_release_step_stops_before_copying_feed_when_translation_is_missing(self):
        repo = Path(__file__).resolve().parents[1]
        workflow = repo / ".github/workflows/macos-release.yml"
        step = json.loads(subprocess.check_output([
            "ruby", "-ryaml", "-rjson", "-e",
            'steps = YAML.load_file(ARGV[0]).fetch("jobs").fetch("release").fetch("steps"); '
            'puts JSON.generate(steps.find { |s| s["name"] == "Generate signed Sparkle appcast" })',
            str(workflow),
        ]))
        script = self.root / "generate.zsh"
        script.write_text(step["run"])
        command = shlex.split(step.get("shell", "zsh {0}").replace("{0}", "generate.zsh"))

        # Exercise the release commands with a pre-generated fixture and no signing key.
        for directory in ("App", "dist", "scripts", "fanbar-updates"):
            (self.root / directory).mkdir()
        (self.root / "App/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1"}))
        (self.root / "dist/FanBar-1.dmg").touch()
        shutil.copy(self.appcast, self.root / "fanbar-updates/appcast.xml")
        shutil.copy(repo / "scripts/localize-appcast.py", self.root / "scripts")
        generator = self.root / ".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
        generator.parent.mkdir(parents=True)
        generator.write_text("#!/bin/sh\ncat >/dev/null\n")
        generator.chmod(0o755)
        notes = self.root / "docs/releases/v1"
        notes.mkdir(parents=True)
        for language in MODULE.LANGUAGES:
            shutil.copy(self.root / f"{language}.html", notes)
        env = dict(os.environ, RUNNER_TEMP=str(self.root), GITHUB_REF_NAME="v1",
                   GITHUB_REPOSITORY="example/repo", SPARKLE_PRIVATE_KEY="")
        output = self.root / "dist/appcast.xml"
        subprocess.run(command, cwd=self.root, env=env, capture_output=True, check=True)
        self.assertIn('xml:lang="ko"', output.read_text())

        output.unlink()
        (notes / "ko.html").unlink()
        result = subprocess.run(command, cwd=self.root, env=env, capture_output=True, text=True)
        self.assertIn("ko.html", result.stderr)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_signed_feeds_are_not_modified(self):
        self.plist.write_bytes(plistlib.dumps({"SURequireSignedFeed": True}))
        with self.assertRaises(ValueError):
            MODULE.localize(self.appcast, self.root, self.plist)
        self.assertEqual(self.appcast.read_text(), self.original)

    def test_multiple_items_are_rejected(self):
        self.appcast.write_text(self.original.replace('</channel>', '<item/></channel>'))
        with self.assertRaises(ValueError):
            MODULE.localize(self.appcast, self.root, self.plist)


if __name__ == "__main__":
    unittest.main()
