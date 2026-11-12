from copy import deepcopy
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validation import validate

def card(name, text="", types="Creature", colors=()):
    return {"name": name, "oracle_text": text, "type_line": types, "color_identity": list(colors),
            "legalities": {fmt: "legal" for fmt in ("modern", "standard", "pioneer", "commander")}}

class Catalog:
    def __init__(self, *cards): self.cards={c["name"]: c for c in cards}
    def get(self, name): return deepcopy(self.cards.get(name))

def deck(format="Modern", main=(), side=(), commander=()):
    entries=lambda zone:[{"name": name, "count": count} for name,count in zone]
    return {"format": format, "main": entries(main), "sideboard": entries(side), "commander": entries(commander)}

class ValidationTest(unittest.TestCase):
    def setUp(self):
        self.catalog=Catalog(card("Forest", types="Basic Land — Forest",colors="G"),
            card("Island", types="Basic Land — Island",colors="U"),
            card("Giada, Font of Hope", types="Legendary Creature — Angel", colors="W"),
            card("Plains", types="Basic Land — Plains",colors="W"),
            card("Sol Ring", types="Artifact"),
            card("Hare Apparent", "A deck can have any number of cards named Hare Apparent.",colors="W"),
            card("Rat Colony", "A deck can have any number of cards named Rat Colony.",colors="B"),
            card("Seven Dwarves", "A deck can have up to seven cards named Seven Dwarves.",colors="R"),
            card("Nazgûl", "A deck can have up to nine cards named Nazgûl.",colors="B"))

    def codes(self, result): return {error["code"] for error in result["errors"]}

    def test_combined_copy_limit_and_basic_exception(self):
        result=validate(deck(main=(("Sol Ring",4),("Forest",56)),side=(("Sol Ring",1),)),self.catalog)
        self.assertIn("copy_limit",self.codes(result))
        result=validate(deck(main=(("Forest",100),)),self.catalog)
        self.assertTrue(result["playable"])

    def test_oracle_text_unlimited_and_numbered_exceptions(self):
        for name,count in (("Hare Apparent",60),("Rat Colony",60),("Seven Dwarves",7),("Nazgûl",9)):
            result=validate(deck(main=((name,count),)),self.catalog)
            self.assertTrue(result["saveAllowed"], result)
        for name,count in (("Seven Dwarves",8),("Nazgûl",10)):
            self.assertIn("copy_limit",self.codes(validate(deck(main=((name,count),)),self.catalog)))

    def test_commander_singleton_identity_and_no_sideboard(self):
        result=validate(deck("Commander",main=(("Sol Ring",2),("Island",96)),side=(("Plains",1),),commander=(("Giada, Font of Hope",1),)),self.catalog)
        self.assertTrue({"copy_limit","color_identity","commander_sideboard"}<=self.codes(result))
        result=validate(deck("Commander",main=(("Hare Apparent",99),),commander=(("Giada, Font of Hope",1),)),self.catalog)
        self.assertTrue(result["playable"], result)
        result=validate(deck("Commander",main=(("Hare Apparent",100),),commander=(("Giada, Font of Hope",1),)),self.catalog)
        self.assertIn("commander_size",self.codes(result))
        self.assertFalse(result["saveAllowed"])

    def test_commander_2026_legendary_vehicle_and_pair_rules(self):
        self.catalog.cards["Vehicle"]=card("Vehicle",types="Legendary Artifact — Vehicle")
        self.assertTrue(validate(deck("Commander",main=(("Sol Ring",1),("Forest",98)),commander=(("Vehicle",1),)),self.catalog)["saveAllowed"] is False) # Forest identity does not fit colorless commander.
        result=validate(deck("Commander",main=(("Sol Ring",1),),commander=(("Vehicle",1),)),self.catalog)
        self.assertNotIn("commander_type", self.codes(result))
        result=validate(deck("Commander",commander=(("Giada, Font of Hope",1),("Vehicle",1))),self.catalog)
        self.assertIn("commander_pair",self.codes(result))

    def test_incomplete_size_is_draft_but_illegal_cards_are_errors(self):
        result=validate(deck(main=(("Forest",2),)),self.catalog)
        self.assertTrue(result["draft"] and result["saveAllowed"] and not result["playable"])
        self.catalog.cards["Sol Ring"]["legalities"]["standard"]="not_legal"
        result=validate(deck("Standard",main=(("Sol Ring",1),)),self.catalog)
        self.assertFalse(result["saveAllowed"])
        self.assertIn("Sol Ring",result["errors"][0]["cards"])

if __name__=="__main__": unittest.main()
