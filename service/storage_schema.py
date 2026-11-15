"""Validation shared by SQLite imports and API writes."""
import json
import re
import uuid

FORMATS = {"modern", "standard", "pioneer", "commander"}
ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,99}$")
DEFAULT_SETTINGS = {"manualTriggers": False, "autoMana": True, "showCardArt": True, "localArtworkOnly": True, "artworkMemoryMiB":256,
    "resolution": "Desktop", "windowMode": "Borderless", "vsync": True, "msaa": 0,
    "renderScale": 1.0, "textureFilter": "linear", "frameLimit": 0, "uiScale": 1.0,
    "animations": True, "particles": True, "musicEnabled": False, "musicVolume": 0.25,
    "sfxEnabled": True, "sfxVolume": 0.45, "masterVolume": 0.7, "reducedMotion": False,
    "highContrast": False, "colorblindMode": "Off", "showTooltips": True,
    "fontFamily": "Beleren", "titleFontFamily":"Beleren", "skybox":"Galaxy", "skyboxBrightness":0.32,
    "playmatOpacity":0.88,"counterStyle":"Dice","cursorStyle":"Kenney","keywordReminders":True,
    "panelOpacity":0.65,"theme":"Midnight","accentColor":"","opponentColor":"","autoFollowTurn":True,
    "builderLayout":"Classic","presentationVersion":2,"fontQuality":"High","cursorScale":0.55,"boardImpactIntensity":0.55,"cardBackStyle":"Arcane"}

class StorageSchema:
    @staticmethod
    def check_id(identifier):
        if not isinstance(identifier, str) or not ID.fullmatch(identifier):
            raise ValueError("Invalid object ID")
        return identifier

    @staticmethod
    def validate_deck(value, identifier=None, legacy=False):
        if not isinstance(value, dict):
            raise ValueError("Deck must be an object")
        deck = {key: value.get(key, "") for key in ("name", "format", "description")}
        deck["id"] = StorageSchema.check_id(identifier or value.get("id") or "deck-" + uuid.uuid4().hex[:12])
        if not isinstance(deck["name"], str) or not 1 <= len(deck["name"].strip()) <= 120:
            raise ValueError("Deck name must contain 1 to 120 characters")
        deck["name"] = deck["name"].strip()
        if not isinstance(deck["format"], str) or deck["format"].lower() not in FORMATS:
            raise ValueError("Unsupported deck format")
        deck["format"] = deck["format"].capitalize()
        cover = value.get("coverCard")
        if cover is not None:
            if not isinstance(cover, str) or not 1 <= len(cover.strip()) <= 300:
                raise ValueError("Cover card must be a card name")
            deck["coverCard"] = cover.strip()
        if not isinstance(deck["description"], str) or len(deck["description"]) > 20000:
            raise ValueError("Invalid deck description")
        for zone in ("main", "sideboard", "commander"):
            entries = value.get(zone, [])
            if not isinstance(entries, list) or len(entries) > 300:
                raise ValueError(f"Invalid {zone} list")
            merged = {}
            for entry in entries:
                if not isinstance(entry, dict):
                    raise ValueError("Invalid card entry")
                name, count = entry.get("name"), entry.get("count")
                if not isinstance(name, str) or not 1 <= len(name.strip()) <= 300:
                    raise ValueError("Invalid card name")
                if isinstance(count, bool) or not isinstance(count, int) or count < 1 or (not legacy and count > 250):
                    raise ValueError("Card count must be an integer from 1 to 250")
                name = name.strip()
                merged[name] = merged.get(name, 0) + count
                if not legacy and merged[name] > 250:
                    raise ValueError("At most 250 copies per card entry can be stored by this client")
            deck[zone] = [{"name": name, "count": count} for name, count in merged.items()]
        if 'printingSelections' in value:
            selections = value['printingSelections']
            if not isinstance(selections, list) or len(selections) > 900: raise ValueError('Invalid printing selections')
            prepared = []
            for selection in selections:
                if not isinstance(selection, dict) or selection.get('zone') not in ('main', 'sideboard', 'commander'): raise ValueError('Invalid printing selection zone')
                name, count = selection.get('name'), selection.get('count')
                if not isinstance(name, str) or not 1 <= len(name) <= 300 or isinstance(count, bool) or not isinstance(count, int) or not 1 <= count <= 250: raise ValueError('Invalid printing selection')
                result = {'name': name, 'count': count, 'zone': selection['zone']}
                for key, length in (('set', 12), ('collectorNumber', 40), ('printingId', 100)):
                    if key in selection:
                        item = selection[key]
                        if not isinstance(item, str) or not 1 <= len(item) <= length or any(ord(c) < 32 for c in item): raise ValueError('Invalid printing selection ' + key)
                        result[key] = item
                prepared.append(result)
            deck['printingSelections'] = prepared
        if 'sourceDeck' in value:
            source=value['sourceDeck']
            if not isinstance(source,dict) or source.get('origin') not in ('user','bundled','preconstructed'):raise ValueError('Invalid source deck provenance')
            StorageSchema.check_id(source.get('id'))
            if not isinstance(source.get('name'),str) or not 1<=len(source['name'])<=300:raise ValueError('Invalid source deck name')
            deck['sourceDeck']={key:source[key] for key in ('id','name','origin')}
        return deck


    @staticmethod
    def validate_settings(value):
        if not isinstance(value, dict) or len(json.dumps(value)) > 20000:
            raise ValueError("Invalid settings object")
        enums = {"artworkMemoryMiB":{128,256,512}, "windowMode": {"Windowed", "Borderless", "Fullscreen"}, "msaa": {0, 2, 4, 8},
                 "textureFilter": {"linear", "nearest"}, "frameLimit": {0, 30, 60, 120, 144},
                 "colorblindMode": {"Off", "Deuteranopia", "Protanopia", "Tritanopia"}, "titleFontFamily":{"Beleren","Application font"},
                 "skybox":{"Galaxy","Nebula","Band","Dark","Day","Off"},"counterStyle":{"Dice","Text"},"cursorStyle":{"System","Kenney"},
                 "theme":{"Midnight","Amethyst","Ocean","Ember","Obsidian"},"builderLayout":{"Classic","Simplified"},"presentationVersion":{2},"fontQuality":{"Standard","High"},"cardBackStyle":{"Arcane","Azure","Verdant","Crimson","Classic Magic","Mystic Eye"}}
        ranges = {"renderScale": (0.5, 1.5), "uiScale": (0.85, 1.75), "musicVolume": (0, 1), "sfxVolume": (0, 1), "masterVolume": (0, 1),"skyboxBrightness":(0,1),"playmatOpacity":(0,1),"panelOpacity":(0,1),"cursorScale":(.4,1),"boardImpactIntensity":(0,1)}
        for key, item in value.items():
            if key not in DEFAULT_SETTINGS:
                raise ValueError("Unknown setting: " + key)
            if key in enums:
                if isinstance(item, bool) or not isinstance(item, (int, str)) or item not in enums[key]:
                    raise ValueError("Invalid setting: " + key)
            elif key in ranges:
                low, high = ranges[key]
                if isinstance(item, bool) or not isinstance(item, (int, float)) or not low <= item <= high:
                    raise ValueError("Invalid setting: " + key)
            elif key in ('accentColor','opponentColor'):
                if not isinstance(item,str)or(item!=''and not re.fullmatch(r'#[0-9a-fA-F]{6}',item)):raise ValueError('Color must be empty or #RRGGBB: '+key)
            elif key == "fontFamily":
                if not isinstance(item, str) or not 1 <= len(item) <= 160 or any(ord(char) < 32 or ord(char) == 127 for char in item):
                    raise ValueError("Font family must contain 1 to 160 printable characters")
            elif key == "resolution":
                if item=='Desktop':continue
                if not isinstance(item, str) or not re.fullmatch(r"\d{3,5}x\d{3,5}", item):
                    raise ValueError("Resolution must be WIDTHxHEIGHT")
                width, height = map(int, item.split("x"))
                if not 800 <= width <= 16384 or not 600 <= height <= 8640:
                    raise ValueError("Resolution is outside supported bounds")
            elif not isinstance(item, bool):
                raise ValueError("Setting must be true or false: " + key)
