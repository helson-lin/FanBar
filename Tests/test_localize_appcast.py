import importlib.util
from pathlib import Path
import plistlib
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
