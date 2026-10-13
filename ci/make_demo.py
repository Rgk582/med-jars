"""Writes sample jars and doses for the simulator preview. Generic supplements only."""
import json
import sys
import time

now = time.time()
lt = time.localtime(now)
hhmm = lambda h, m: f"{h:02d}:{m:02d}"
# Put one dose just before "now" (already logged), one due now, one later.
h = lt.tm_hour

jars = [
    {
        "id": "vitamin-d3", "name": "Vitamin D3", "kind": "supplement", "form": "softgel",
        "strength": "2000 IU", "lid": "teal", "order": 1, "food": "with",
        "schedule": [{"id": "d1", "label": "Morning", "time": hhmm(max(h - 1, 0), 0), "amount": "2000 IU", "pills": 1}],
        "howTo": "Swallow with breakfast and a glass of water.",
        "avoid": ["Taking more than one softgel a day", "Taking it with a high fiber cereal"],
        "absorb": ["Take it with a meal that has some fat.", "Morning works better than night for most people."],
        "summary": "Helps the body absorb calcium and supports bones and the immune system.",
    },
    {
        "id": "magnesium", "name": "Magnesium Glycinate", "kind": "supplement", "form": "capsule",
        "strength": "120 mg", "lid": "plum", "order": 2, "food": "either",
        "schedule": [
            {"id": "m1", "label": "Midday", "time": hhmm(h, 15 if lt.tm_min < 45 else 50), "amount": "240 mg", "pills": 2},
            {"id": "m2", "label": "Bedtime", "time": hhmm(min(h + 6, 23), 30), "amount": "120 mg", "pills": 1},
        ],
        "howTo": "Swallow whole.",
        "avoid": ["Zinc or iron in the same hour"],
        "absorb": ["Split the dose through the day."],
        "summary": "Supports muscle relaxation and sleep.",
    },
]
jars[0]["tagIds"] = ["04a1b2c3d4e5f6"]
def e(i, jar, name, form, amount, pills, slot, label, t, note=""):
    return {"id": i, "jarId": jar, "jarName": name, "kind": "supplement", "form": form, "amount": amount,
            "pills": pills, "slotId": slot, "slotLabel": label, "takenAt": t, "note": note}
day = 86400
entries = [
    e("e1", "vitamin-d3", "Vitamin D3", "softgel", "2000 IU", 1, "d1", "Morning", now - 600),
    e("e2", "magnesium", "Magnesium Glycinate", "capsule", "120 mg", 1, "m2", "Bedtime", now - day + 3600),
    e("e3", "magnesium", "Magnesium Glycinate", "capsule", "240 mg", 2, "m1", "Midday", now - day - 4 * 3600, "Took with lunch"),
    e("e4", "vitamin-d3", "Vitamin D3", "softgel", "2000 IU", 1, "d1", "Morning", now - day - 6 * 3600),
]
json.dump({"version": 1, "jars": jars, "entries": entries, "settings": {"faceIDLock": False, "reminders": False}},
          open(sys.argv[1], "w"))
