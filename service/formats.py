"""Installed validator profiles from the pinned XMage capability fixture.
These basic preflight bounds are not a reproduction of native format rules.
Source: bridge installed capabilities, engine d9b266fc981024873ac7ec5f90ee7121a060725e.
Fixture SHA256: 9cae320ee4b88109f274dd09d364e46d904b4b2a23feee196bd74af83b256710.
Limited remains a native draft pool; unavailable game variants are excluded.
"""
ROWS = [
    ('AmonkhetBlock', 'Amonkhet Block', 60, None),
    ('AusHighlander', 'AU Highlander', 60, None),
    ('BattleForZendikarBlock', 'Battle for Zendikar Block', 60, None),
    ('CanadianHighlander', 'Canadian Highlander', 60, None),
    ('Commander', 'Commander', 98, 'commander'),
    ('Eternal', 'Eternal', 60, None),
    ('EuropeanHighlander', 'EuroLander', 100, None),
    ('Extended', 'Extended', 60, None),
    ('Freeform', 'Freeform', 40, None),
    ('FreeformUnlimited', 'Freeform Unlimited', 0, None),
    ('Frontier', 'Frontier', 60, None),
    ('Historic', 'Historic', 60, None),
    ('HistoricalType2', 'Hist. Type 2', 60, None),
    ('InnistradBlock', 'Innistrad Block', 60, None),
    ('IxalanBlock', 'Ixalan Block', 60, None),
    ('KaladeshBlock', 'Kaladesh Block', 60, None),
    ('KamigawaBlock', 'Kamigawa Block', 60, None),
    ('KhansOfTarkirBlock', 'Khans of Tarkir Block', 60, None),
    ('Legacy', 'Legacy', 60, None),
    ('LorwynBlock', 'Lorwyn Block', 60, None),
    ('Modern', 'Modern', 60, 'modern'),
    ('ModernNoBannedList', 'Modern - No Banned List', 60, None),
    ('OldSchool9394', 'Old School 93/94', 60, None),
    ('OldSchool9394CFB', 'Old School 93/94 - Channel Fireball Rules', 60, None),
    ('OldSchool9394EC', 'Old School 93/94 - EC Rules', 60, None),
    ('OldSchool9394EG', 'Old School 93/94 - EudoGames Rules', 60, None),
    ('OldSchool9394Italian', 'Old School 93/94 - Italian Rules', 60, None),
    ('Pauper', 'Pauper', 60, None),
    ('Pioneer', 'Pioneer', 60, 'pioneer'),
    ('Premodern', 'Premodern', 60, None),
    ('ReturnToRavnicaBlock', 'Return to Ravnica Block', 60, None),
    ('ScarsOfMirrodinBlock', 'Scars of Mirrodin Block', 60, None),
    ('ShadowmoorBlock', 'Shadowmoor Block', 60, None),
    ('ShadowsOverInnistradBlock', 'Shadows over Innistrad Block', 60, None),
    ('ShardsOfAlaraBlock', 'Shards of Alara Block', 60, None),
    ('Standard', 'Standard', 60, 'standard'),
    ('StarWarsBlock', 'Star Wars Block', 60, None),
    ('SuperType2', 'Super Type 2', 60, None),
    ('TherosBlock', 'Theros Block', 60, None),
    ('Vintage', 'Vintage', 60, None),
    ('ZendikarBlock', 'Zendikar Block', 60, None),
]
PROFILES = {row[0].lower(): {'id': row[0], 'label': row[1], 'minimum': row[2], 'snapshotKey': row[3], 'nativeValidationRequired': True, 'snapshotFilterAvailable': row[3] is not None} for row in ROWS}
ALIASES = {row[1].lower(): row[0].lower() for row in ROWS}
FORMATS = set(PROFILES)
INDEXED_FORMATS = {'modern', 'standard', 'pioneer', 'commander'}

def profile(value):
    key = str(value).lower();result = PROFILES.get(ALIASES.get(key, key))
    if result is None:raise ValueError('Unsupported editable deck format; choose an installed constructed validator')
    return dict(result)

def clause(value, prefix=""):
    selected = profile(value);key = selected["snapshotKey"]
    if not key:return None
    column = prefix + key
    return column + " IN ('legal','restricted')"
