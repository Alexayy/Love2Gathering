# Builder color controls

Simplified layout keeps the search field, Mana color toggles, **Exact** and **More filters** together above the card browser. White, Blue, Black, Red and Green are independent toggles. Selected buttons stay pressed.

The default mode is **any selected color**: selecting White and Black shows cards with White **or** Black in their color identity. Selecting Green as well adds Green cards. Multicolor cards containing one of those colors can appear even when their identity also has another color.

**Exact** requires the complete selected color identity and excludes other colors. White + Black + Green with Exact shows Abzan identity only; mono-color cards, two-color cards, four/five-color cards and other three-color identities are excluded. The colorless button selects empty identity and clears colored toggles. Selecting a colored toggle clears colorless. **All** clears the color filters and Exact mode.

These filters use catalog color identity, so a Plains is White identity despite its colorless printed frame, and a White/Black hybrid card belongs to both colors. Filtering changes the browser; it does not alter a deck or decide runtime legality. Classic retains its single-color selector and the existing type/set/sort controls remain available.

Search, card grid, page controls and deck drop targets share `Builder.layout`. Classic rows have explicit vertical spacing; Simplified Mana/Exact/More controls have separate padded hit regions at tested window/UI scales. Deck quantities persist when switching layouts.

## Catalog contract

- `/cards?color=WB&colorMode=any` selects identity union (White or Black).
- `/cards?color=WBG&colorMode=exact` selects exactly Abzan identity, independently of color-array order.
- `/cards?color=C&colorMode=exact` selects empty identity.
- Omitting `colorMode` retains the legacy all-listed-colors search used by Classic.

The existing indexed `colors` column already stores color identity, so these modes do not rebuild or duplicate the source catalog. Results retain format/set/type filters, bounded pagination and sorting.

`service/tests/test_builder_colors.py` exercises isolated catalog and real local HTTP behavior for mono-color, two/three/four/five-color, hybrid and land identities. `tests/builder_colors.lua` exercises toggle state, request semantics and stale-response fencing. `tests/builder_modes_ui.sh` drives actual LÖVE/Slab buttons, search, drag/drop, validation and temporary saves against an explicitly isolated catalog; its report records exact query paths and separates this frontend/catalog acceptance from native gameplay.
