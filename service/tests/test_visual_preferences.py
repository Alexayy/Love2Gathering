"""Actual presentation choices persist in isolated storage and reject bad values."""
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from storage import Storage


class VisualPreferenceTests(unittest.TestCase):
    def test_quality_pointer_and_card_back_choices_are_typed_and_durable(self):
        with tempfile.TemporaryDirectory()as tmp:
            root=Path(tmp);storage=Storage(root/'saves',root/'bundled')
            defaults=storage.settings()
            self.assertEqual(defaults['fontQuality'],'High');self.assertEqual(defaults['cursorScale'],.55);self.assertEqual(defaults['cardBackStyle'],'Arcane')
            for quality in('Standard','High'):
                for style in('Arcane','Azure','Verdant','Crimson','Classic Magic','Mystic Eye'):
                    storage.save_settings({'fontQuality':quality,'cardBackStyle':style,'cursorScale':.4,'boardImpactIntensity':0})
                    reopened=Storage(root/'saves',root/'bundled').settings()
                    self.assertEqual((reopened['fontQuality'],reopened['cardBackStyle'],reopened['cursorScale']),(quality,style,.4))
            saved=storage.settings()
            for invalid in({'fontQuality':'Ultra'},{'fontQuality':True},{'cardBackStyle':'copyrighted'},{'cursorScale':.39},{'cursorScale':1.01},{'cursorScale':True},{'boardImpactIntensity':-1},{'boardImpactIntensity':1.01}):
                with self.subTest(value=invalid),self.assertRaises(ValueError):storage.save_settings(invalid)
                self.assertEqual(storage.settings(),saved)
