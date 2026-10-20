"""Writes a realistic three-month Med Jars data file for the full simulator test.

Times are local (the workflow sets the runner to America/Chicago). Dates are seconds since 1970, like the app's file.
"""
import json
import random
import sys
import time
from datetime import datetime, timedelta

random.seed(7)
now = datetime.now()
DAY_START_HOUR = 4


def dose_day_start(d):
    t = d.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
    return t if d >= t else t - timedelta(days=1)


today = dose_day_start(now)
ts = lambda d: d.timestamp()
cal_weekday = lambda d: d.isoweekday() % 7 + 1  # 1 = Sunday
EVERY = [1, 2, 3, 4, 5, 6, 7]
BEDTIME = 23 * 60


def slot(sid, time_, pills=1, share=1.0, label="", bedtime=None, waking=False, dose=None):
    s = {"id": sid, "label": label, "time": time_, "pills": pills, "share": share, "days": EVERY}
    if bedtime is not None:
        s["bedtimeOffset"] = bedtime
    if waking:
        s["uponWaking"] = True
    if dose is not None:
        s["dose"] = dose
    return s


def plan(pid, days, daily, doses, name="", daily_dose=None, equal=True):
    p = {"id": pid, "name": name, "days": days, "dailyPills": daily, "splitEqual": equal, "doses": doses}
    if daily_dose is not None:
        p["dailyDose"] = daily_dose
    return p


def bottle(bid, form, strength=None, unit="mg", lid="amber", left=None, shape="round", score=False, imprint="",
           placement="left", nickname="", warn=7):
    b = {"id": bid, "form": form, "unit": unit, "lid": lid, "pillShape": shape, "scoreLine": score,
         "imprint": imprint, "imprintPlacement": placement, "refillWarnDays": warn, "nickname": nickname, "tagIds": []}
    if strength is not None:
        b["strength"] = strength
    if left is not None:
        b["pillsLeft"] = left
    return b


def jar(jid, name, kind, bottles, plans=None, as_needed=False, prn_pills=1, **extra):
    j = {"id": jid, "name": name, "labelName": extra.pop("label", ""), "kind": kind, "schedule": [], "plans": plans or [],
         "bottles": bottles, "defaultBottleId": bottles[0]["id"], "asNeeded": as_needed, "howTo": extra.pop("howTo", ""),
         "food": extra.pop("food", "either"), "avoid": extra.pop("avoid", []), "absorb": extra.pop("absorb", []),
         "summary": extra.pop("summary", ""), "interactions": extra.pop("interactions", [])}
    if as_needed:
        j["schedule"] = [{"id": "prn", "label": "As Needed", "pills": prn_pills, "amount": ""}]
        j["plans"] = []
    j.update(extra)
    return j


rule_start = today - timedelta(days=60)
jars = [
    jar("adderall", "Adderall", "rx",
        [bottle("adderall", "tablet", 30, lid="amber", left=40, score=True, imprint="dp 30", placement="split"),
         bottle("adderall-10mg", "tablet", 10, lid="blue", left=6, imprint="dp 10")],
        plans=[plan("adderall.p1", [2, 3, 4, 5, 6], 1, [slot("adderall.d1", "07:00", 1, 0.75, waking=True, dose=30),
                                                        slot("adderall.d2", "13:00", 0.25, 0.25, dose=10)], name="Weekdays",
                    daily_dose=40, equal=False),
               plan("adderall.p2", [1, 7], 1, [slot("adderall.d3", "09:00", 1, 1, dose=30)], name="Weekends", daily_dose=30)],
        label="amphetamine salts", howTo="Swallow whole with water.", food="either",
        avoid=["Taking it after 2 PM", "Acidic juice within an hour"], absorb=["Take on an empty stomach for a faster start."],
        summary="Stimulant for ADHD.",
        effect={"onsetMinutes": 30, "peakMinutes": 150, "durationMinutes": 360, "wearOffAlert": True, "liveActivity": True},
        interactions=[{"jarId": "caffeine-pills", "level": "moderate"}, {"jarId": "melatonin", "level": "minor"}],
        checkIn=True, checkInMinutes=120, pickOrder="wholeFirst"),
    jar("escitalopram", "Escitalopram", "rx", [bottle("escitalopram", "tablet", 10, lid="white", left=25, shape="oval", score=True)],
        plans=[plan("escitalopram.p1", EVERY, 1, [slot("escitalopram.d1", "08:00")])],
        nudge=True, nudgeMinutes=30, nudgeRepeats=2, summary="SSRI."),
    jar("vitamin-d3", "Vitamin D3", "supplement", [bottle("vitamin-d3", "softgel", 2000, unit="iu", lid="yellow", left=80)],
        plans=[plan("vitamin-d3.p1", EVERY, 1, [slot("vitamin-d3.d1", "08:00")])], food="with",
        absorb=["Take it with a meal that has some fat."]),
    jar("magnesium", "Magnesium Glycinate", "supplement", [bottle("magnesium", "capsule", 120, lid="teal", left=110)],
        plans=[plan("magnesium.p1", EVERY, 2, [slot("magnesium.d1", "12:00", 1, 0.5), slot("magnesium.d2", "22:00", 1, 0.5, bedtime=60)])]),
    jar("fish-oil", "Fish Oil", "supplement", [bottle("fish-oil", "softgel", 1000, lid="amber", left=150)],
        plans=[plan("fish-oil.p1", EVERY, 2, [slot("fish-oil.d1", "08:00", 1, 0.5), slot("fish-oil.d2", "18:00", 1, 0.5)])], food="with"),
    jar("creatine", "Creatine", "supplement", [bottle("creatine", "powderG", None, lid="white")],
        plans=[plan("creatine.p1", EVERY, 5, [slot("creatine.d1", "09:00", 5, 1)])]),
    jar("l-theanine", "L-Theanine", "nootropic", [bottle("l-theanine", "capsule", 200, lid="mint", left=55)],
        plans=[plan("l-theanine.p1", EVERY, 1, [slot("l-theanine.d1", "07:15")])]),
    jar("caffeine-pills", "Caffeine", "nootropic", [bottle("caffeine-pills", "tablet", 100, lid="brown", left=70, score=True)],
        as_needed=True, minGapMinutes=240, maxPerDay=3, followUpMinutes=0),
    jar("melatonin", "Melatonin", "supplement", [bottle("melatonin", "gummy", 3, lid="lavender", left=4)],
        plans=[plan("melatonin.p1", EVERY, 1, [slot("melatonin.d1", "22:30", 1, 1, bedtime=30)])]),
    jar("ibuprofen", "Ibuprofen", "rx", [bottle("ibuprofen", "tablet", 200, lid="red", left=60, imprint="I-2")],
        as_needed=True, prn_pills=2, minGapMinutes=360, maxPerDay=4, followUpMinutes=120),
    jar("zinc", "Zinc", "supplement", [bottle("zinc", "tablet", 25, lid="slate", left=90)],
        rule={"kind": "everyN", "everyDays": 2, "start": ts(rule_start),
              "dayPlan": plan("zinc.p1", EVERY, 1, [slot("zinc.d1", "12:30")])}),
    jar("ashwagandha", "Ashwagandha", "supplement", [bottle("ashwagandha", "capsule", 600, lid="green", left=45)],
        rule={"kind": "rotation", "start": ts(rule_start),
              "weeks": [[plan("ash.w1", [2, 4, 6], 1, [slot("ash.d1", "20:00")])], [plan("ash.w2", [3, 5], 1, [slot("ash.d2", "20:00")])]]}),
    jar("nac", "NAC", "supplement", [bottle("nac", "capsule", 600, lid="cream", left=30)],
        rule={"kind": "onOff", "onDays": 5, "offDays": 2, "start": ts(rule_start),
              "dayPlan": plan("nac.p1", EVERY, 1, [slot("nac.d1", "08:30")])}),
    jar("cannabis", "Cannabis", "recreational", [bottle("cannabis", "smoked", None, lid="green")], as_needed=True),
    jar("vitamin-b12", "Vitamin B12", "supplement", [bottle("vitamin-b12", "tablet", 1000, unit="mcg", lid="pink")],
        plans=[plan("b12.p1", EVERY, 1, [slot("b12.d1", "08:00")])], paused=True),
    jar("iron", "Iron", "supplement", [bottle("iron", "tablet", 65, lid="red", left=40)],
        plans=[plan("iron.p1", EVERY, 1, [slot("iron.d1", "10:00")])],
        breakFrom=ts((today - timedelta(days=2)).replace(hour=0)), breakUntil=ts((today + timedelta(days=5)).replace(hour=0))),
]
for i, j in enumerate(jars):
    j["order"] = i + 1

focus_start = today - timedelta(days=10)
stacks = [
    {"id": "focus", "name": "Focus", "goal": "Deep work without the crash", "notes": "Theanine smooths out the caffeine.",
     "color": "indigo", "start": ts(focus_start), "turnedOnAt": ts(focus_start), "cycleOnWeeks": 4, "cycleOffWeeks": 1,
     "order": 1, "members": [
         {"id": "focus.m1", "jarId": "l-theanine", "mode": "controls", "offDays": "off",
          "rule": {"kind": "weekly", "plans": [plan("focus.p1", EVERY, 1, [slot("focus.d1", "07:15")])]}},
         {"id": "focus.m2", "jarId": "caffeine-pills", "mode": "controls", "offDays": "off", "gapAfter": "focus.m1", "gapMinutes": 30,
          "rule": {"kind": "weekly", "plans": [plan("focus.p2", EVERY, 1, [slot("focus.d2", "07:45")])]}},
         {"id": "focus.m3", "jarId": "adderall", "mode": "own"}]},
    {"id": "sleep", "name": "Sleep", "goal": "Fall asleep faster", "color": "plum", "order": 2, "members": [
        {"id": "sleep.m1", "jarId": "magnesium", "mode": "own"},
        {"id": "sleep.m2", "jarId": "melatonin", "mode": "controls", "offDays": "normal",
         "rule": {"kind": "weekly", "plans": [plan("sleep.p1", EVERY, 1, [slot("sleep.d1", "22:00", 1, 1, bedtime=60)])]}}]},
]

by_id = {j["id"]: j for j in jars}


def at(day, hhmm, bedtime=None):
    if bedtime is not None:
        m = (BEDTIME - bedtime) % 1440
    else:
        h, mi = map(int, hhmm.split(":"))
        m = h * 60 + mi
    t = day.replace(hour=m // 60, minute=m % 60)
    if m < DAY_START_HOUR * 60:
        t += timedelta(days=1)
    return t


def day_slots(j, day, index):
    """The doses a substance has on a dose day (mirrors the app for the seed's simple cases)."""
    if j.get("paused") or j.get("asNeeded"):
        return []
    if "breakFrom" in j and j["breakFrom"] <= ts(day) <= j["breakUntil"] + 86400:
        return []
    wd = cal_weekday(day)
    rule = j.get("rule")
    if rule:
        n = (day - rule_start).days
        if rule["kind"] == "everyN":
            return rule["dayPlan"]["doses"] if n >= 0 and n % rule["everyDays"] == 0 else []
        if rule["kind"] == "onOff":
            return rule["dayPlan"]["doses"] if n >= 0 and n % 7 < 5 else []
        if rule["kind"] == "rotation":
            week = rule["weeks"][(n // 7) % 2]
            return next((p["doses"] for p in week if wd in p["days"]), [])
    for p in j["plans"]:
        if wd in p["days"]:
            return p["doses"]
    return []


entries = []


def entry(j, sid, label, when, pills, skipped=False, parts=None, note="", amount=""):
    b = j["bottles"][0]
    e = {"id": f"e{len(entries)}", "jarId": j["id"], "jarName": j["name"], "kind": j["kind"], "form": b["form"], "amount": amount,
         "pills": pills, "slotId": sid, "slotLabel": label, "takenAt": ts(when), "note": note, "skipped": skipped,
         "skipReason": "Felt fine without it" if skipped else ""}
    if parts:
        e["parts"] = parts
    entries.append(e)


DAYS = 90
for back in range(DAYS, -1, -1):
    day = today - timedelta(days=back)
    for j in jars:
        doses = day_slots(j, day, back)
        if j["id"] == "l-theanine" and day >= focus_start:
            doses = [slot("focus.d1", "07:15")]
        for s in doses:
            when = at(day, s["time"], s.get("bedtimeOffset"))
            if back == 0 and when > now - timedelta(minutes=50):
                continue  # today's later doses stay open
            # Missed on purpose: yesterday's evening fish oil, today's first magnesium.
            if (back == 1 and s["id"] == "fish-oil.d2") or (back == 0 and s["id"] == "magnesium.d1"):
                continue
            r = random.random()
            if back > 1 and r < 0.06:
                continue
            skipped = back > 1 and r < 0.09
            when = when + timedelta(minutes=random.randint(-10, 25))
            parts = None
            pills = s.get("pills", 1)
            if j["id"] == "adderall":
                parts = [{"bottleId": "adderall", "pills": 1}] if s.get("dose", 30) >= 30 else [{"bottleId": "adderall-10mg", "pills": 1}]
                pills = 1
            entry(j, s["id"], s.get("label") or "", when, pills, skipped=skipped, parts=parts)
        if j["id"] == "l-theanine" and day >= focus_start and not (back == 0 and at(day, "07:45") > now):
            entry(by_id["caffeine-pills"], "focus.d2", "", at(day, "07:15") + timedelta(minutes=random.randint(30, 50)), 1)
    if back > 0:
        for _ in range(random.choice([0, 0, 1, 2])):
            entry(by_id["ibuprofen"], "prn", "As Needed", day + timedelta(hours=random.randint(6, 17)), 2)
        if random.random() < 0.4:
            entry(by_id["cannabis"], "prn", "As Needed", day + timedelta(hours=random.randint(14, 18)), 1)
        if random.random() < 0.5:
            entry(by_id["caffeine-pills"], "prn", "As Needed", day + timedelta(hours=random.randint(10, 13)), 1)

# A dose taken an hour ago so Working Now and the Live Activity have something.
entry(by_id["adderall"], "", "Extra Dose", now - timedelta(minutes=55), 1, parts=[{"bottleId": "adderall-10mg", "pills": 1}],
      amount="10 mg")
# Check-ins on a few doses.
for e in entries[-40::7]:
    e["checkIn"] = {"focus": random.randint(2, 5), "mood": random.randint(2, 5), "sideEffects": ["Low appetite"], "note": "",
                    "at": e["takenAt"] + 7200}

planned = [
    {"id": "plan1", "jarId": "caffeine-pills", "at": ts((today + timedelta(days=1)).replace(hour=15, minute=0)), "pills": 1,
     "note": "Exam", "headsUpMinutes": 30},
    {"id": "plan2", "jarId": "ibuprofen", "at": ts((today + timedelta(days=3)).replace(hour=9, minute=30)), "pills": 2,
     "note": "Dentist", "headsUpMinutes": 60},
]
caffeine = [
    {"id": "c1", "mg": 95, "label": "Coffee", "at": ts(now - timedelta(hours=3))},
    {"id": "c2", "mg": 64, "label": "Espresso", "at": ts(now - timedelta(minutes=40))},
    {"id": "c3", "mg": 160, "label": "Energy Drink", "at": ts(now - timedelta(days=1, hours=2))},
]
wake_key = today.strftime("%Y%m%d")
settings = {"faceIDLock": False, "reminders": True, "groupReminders": True, "bedtime": BEDTIME, "usualWake": 7 * 60,
            "bedtimeByWeekday": {"6": 60}, "caffeineTracker": True}
data = {"version": 1, "jars": jars, "entries": sorted(entries, key=lambda e: -e["takenAt"]), "settings": settings,
        "caffeine": caffeine, "planned": planned, "wakeTimes": {wake_key: ts(today.replace(hour=6, minute=50))}, "stacks": stacks}
json.dump(data, open(sys.argv[1], "w"))
print(f"seed: {len(jars)} jars, {len(entries)} entries, now {now:%a %H:%M}")
