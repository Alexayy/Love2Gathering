"""Typed preferences and one-time migration in owned temporary SQLite only."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from storage import Storage

class PresentationSettingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.store=Storage(self.root/'data',self.root/'empty')
    def tearDown(self):self.tmp.cleanup()
    def reopen(self):return Storage(self.store.root,self.root/'empty')
    def raw(self,values):
        with self.store.connection(write=True)as c:
            c.execute("DELETE FROM settings WHERE key='presentationVersion'")
            for key,value in values.items():c.execute('INSERT OR REPLACE INTO settings VALUES(?,?)',(key,json.dumps(value)))
    def test_fresh_applied_defaults_and_typed_custom_values(self):
        s=self.store.settings();self.assertEqual((s['fontFamily'],s['titleFontFamily'],s['cursorStyle'],s['windowMode'],s['resolution']),('Beleren','Beleren','Kenney','Borderless','Desktop'))
        self.assertEqual((s['panelOpacity'],s['theme'],s['autoFollowTurn'],s['builderLayout']),(.65,'Midnight',False,'Classic'))
        values={'panelOpacity':.2,'theme':'Ember','accentColor':'#aAbB12','opponentColor':'#123ABC','autoFollowTurn':False,'builderLayout':'Simplified'}
        self.store.save_settings(values)
        for key,value in values.items():self.assertEqual(self.reopen().settings()[key],value)
        for values in ({'panelOpacity':-1},{'panelOpacity':True},{'theme':'URL'},{'accentColor':'red'},{'opponentColor':'#abc'},{'autoFollowTurn':1},{'builderLayout':'Unknown'},{'presentationVersion':99}):
            with self.assertRaises(ValueError):self.store.save_settings(values)
    def test_historical_defaults_migrate_once_without_resetting_later_choices(self):
        self.raw({'fontFamily':'Old family','titleFontFamily':'Application font','cursorStyle':'System','windowMode':'Windowed','resolution':'1440x900'})
        migrated=self.reopen().settings();self.assertEqual((migrated['resolution'],migrated['windowMode'],migrated['fontFamily'],migrated['cursorStyle']),('Desktop','Borderless','Beleren','Kenney'))
        self.store.save_settings({'windowMode':'Windowed','resolution':'1280x720','cursorStyle':'System'})
        later=self.reopen().settings();self.assertEqual((later['resolution'],later['windowMode'],later['cursorStyle']),('1280x720','Windowed','System'))
    def test_explicit_custom_display_is_preserved_during_version_migration(self):
        self.raw({'windowMode':'Fullscreen','resolution':'1920x1080','musicVolume':.17})
        result=self.reopen().settings();self.assertEqual((result['windowMode'],result['resolution'],result['musicVolume']),('Fullscreen','1920x1080',.17));self.assertEqual(result['presentationVersion'],2)
    def test_table_controls_round_trip_and_reject_invalid_saved_values(self):
        values={'vfxIntensity':.31,'ambientKeywordFX':False,'presentationPacing':'Minimal','cameraShake':False,'parallax':False,'distortion':False,'cardScale':1.2,'groupEquivalent':False,'autoFollowTurn':True}
        self.store.save_settings(values)
        for key,value in values.items():self.assertEqual(self.reopen().settings()[key],value)
        for bad in ({'vfxIntensity':1.01},{'vfxIntensity':True},{'cardScale':.79},{'cardScale':1.31},{'presentationPacing':'Instant'},{'ambientKeywordFX':1},{'cameraShake':'false'},{'parallax':0},{'distortion':[]},{'groupEquivalent':1}):
            with self.assertRaises(ValueError):self.store.save_settings(bad)
        self.raw({'autoFollowTurn':True,'vfxIntensity':.31})
        self.assertTrue(self.reopen().settings()['autoFollowTurn'])
        self.assertEqual(self.reopen().settings()['vfxIntensity'],.31)

if __name__=='__main__':unittest.main()
