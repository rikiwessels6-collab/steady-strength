"""Emily's workout: the 12-week, three-day gym program from the owner's workbook
(Resources/Source/12_Week_Gym_Weight_Tracker.xlsx, sheets A - Monday, B - Thursday, C - Saturday).

Unlike the Steady Strength templates, this program changes every week: each week has its own set
counts, rep range, reps in reserve (RIR) and phase. They are read straight from the workbook's week
headings and rows, never filled in by the importer. The workbook's "Alternative" column becomes each
exercise's preferred swap. Nothing is invented: an exercise or alternative the library doesn't have is
reported, not guessed.
"""
from __future__ import annotations

import re
from pathlib import Path

import openpyxl

from parsing import exercise_key, parse_effort, parse_reps, parse_rest, parse_sets

FILE = "12_Week_Gym_Weight_Tracker.xlsx"
PROGRAM_ID = "emily-workout"
PROGRAM_NAME = "Emily's workout"

# Workbook name -> library id, where the name isn't already a library name or alias.
NAME_TO_ID = {
    "cable biceps curl": "cable_curl",
    "hack squat machine": "hack_squat",
    "hip thrust machine": "machine_hip_thrust",
    "incline chest press machine": "machine_incline_press",
    "incline dumbbell chest press": "incline_db_press",
    "low step-up": "step_up",
    "rope triceps pushdown": "triceps_pushdown",
    "shoulder press machine": "machine_shoulder_press",
    "supported split squat": "split_squat",
}
# Planned exercises where the library's movement is close but not identical.
APPROX_NOTES = {
    "low step-up": "Use a low step.",
}

HEADING = re.compile(r"WEEK\s+(\d+)\s*•\s*([^•]+?)\s*•\s*RIR\s*([\d–\-]+)\s*•\s*Rest\s*(\d+)[–\-](\d+)\s*sec main lifts\s*/\s*(\d+)[–\-](\d+)\s*sec accessories")

PROGRAM_NOTES = [
    "Record weights in kg and reps as whole numbers.",
    "Only increase weight when all prescribed sets reach the top of the rep range with the planned reps in reserve and sound technique.",
    "If you are fatigued, repeat the load or reduce sets. Pilates and yoga count towards your weekly activity.",
    "Week 12 lowers volume to consolidate. No maximum-effort testing.",
    "This program has no dedicated core exercises.",
]
WEEK_NOTE = "Increase weight only when every set reaches the top of the rep range with the planned reps in reserve and sound technique."
LAST_WEEK_NOTE = "Lower volume and consolidate. No maximum-effort testing."


def _dash(text: str) -> str:
    return str(text).replace("–", "-").replace("—", "-").strip()


def _reps(text: str) -> str:
    t = _dash(text)
    return re.sub(r"\s*/\s*leg$", " each side", t)


def _rest(tier: str, pattern: str, main: tuple[int, int], acc: tuple[int, int]) -> dict:
    is_main = tier in ("main", "compound") and not pattern.startswith("core") and pattern != "carry"
    lo, hi = main if is_main else acc
    return parse_rest(f"{lo}-{hi}sec")


def build(src: Path, index: dict, by_id: dict, issues) -> dict:
    wb = openpyxl.load_workbook(src, data_only=True)
    sheets = [ws for ws in wb.worksheets if re.match(r"^[ABC] - ", ws.title)]
    if len(sheets) != 3:
        raise ValueError(f"{FILE}: expected sheets A, B and C, found {[w.title for w in wb.worksheets]}")

    def lookup(name: str) -> str | None:
        key = exercise_key(name)
        return NAME_TO_ID.get(key) or index.get(key)

    weeks = {n: {"number": n, "label": f"Week {n}", "workouts": []} for n in range(1, 13)}
    unmatched_alts = set()

    for pos, ws in enumerate(sheets, start=1):
        letter, _, day = ws.title.partition(" - ")
        workout_name = f"Workout {letter} ({day})"
        current = None   # (week, phase, rir, rest_main, rest_acc)
        slots_by_week: dict[int, list] = {}
        for row in ws.iter_rows(min_row=1):
            first = row[0].value
            if isinstance(first, str) and first.strip().upper().startswith("WEEK") and "•" in first:
                m = HEADING.match(first.strip())
                if not m:
                    raise ValueError(f"{ws.title} row {row[0].row}: can't read the week heading {first!r}")
                n = int(m.group(1))
                current = (n, m.group(2).strip(), _dash(m.group(3)), (int(m.group(4)), int(m.group(5))), (int(m.group(6)), int(m.group(7))))
                slots_by_week[n] = []
                weeks[n]["phase"] = current[1]
                weeks[n]["rir"] = current[2]
                continue
            if current and isinstance(first, int) and first == current[0] and row[1].value:
                n, phase, rir, rest_main, rest_acc = current
                planned, alt, sets, reps = row[1].value, row[2].value, row[4].value, row[5].value
                eid = lookup(planned)
                if eid is None or eid not in by_id:
                    raise ValueError(f"{PROGRAM_ID}: '{planned}' is not in the exercise catalogue")
                alt_id = lookup(alt) if alt else None
                if alt and alt_id is None:
                    unmatched_alts.add(str(alt))
                ex = by_id[eid]
                order = len(slots_by_week[n]) + 1
                notes = APPROX_NOTES.get(exercise_key(planned))
                if alt and alt_id is None:
                    notes = (notes + " " if notes else "") + f"Your sheet's alternative: {alt}."
                slots_by_week[n].append({
                    "exercise": ex["name"], "exerciseKey": exercise_key(ex["name"]), "label": str(planned),
                    "sets": parse_sets(int(sets)), "reps": parse_reps(_reps(reps)),
                    "effort": parse_effort(rir, "rir"), "rest": _rest(ex["tier"], ex["pattern"], rest_main, rest_acc),
                    "notes": notes,
                    "source": {"sheet": ws.title, "row": row[0].row},
                    "exerciseId": eid, "alternativeIds": [alt_id] if alt_id else [],
                    "order": order,
                })
        for n in range(1, 13):
            if n not in slots_by_week or not slots_by_week[n]:
                raise ValueError(f"{ws.title}: no exercises found for week {n}")
            weeks[n]["workouts"].append({"rawName": ws.title, "name": workout_name, "position": pos, "optional": False,
                                         "slots": slots_by_week[n]})

    week_list = []
    for n in range(1, 13):
        w = weeks[n]
        note = f"Reps in reserve: {w['rir']}. " + (LAST_WEEK_NOTE if n == 12 else WEEK_NOTE)
        week_list.append({"number": n, "label": w["label"], "phase": w["phase"], "isDeload": n == 12,
                          "lowFatigueOptional": False, "phaseNote": note, "workouts": w["workouts"]})
    for alt in sorted(unmatched_alts):
        issues.add("warning", "alt-unknown", PROGRAM_ID, "alternatives",
                   f"Alternative '{alt}' is not in the exercise library; it is shown as a note instead")

    return {
        "id": PROGRAM_ID, "name": PROGRAM_NAME, "masterName": PROGRAM_NAME,
        "author": "Supplied by the app owner", "family": "personal",
        "intensityType": "rir", "unit": "kg", "weeks": week_list, "status": "complete",
        "experienceLevel": None, "defaultDaysPerWeek": 3, "split": "Full body, three gym days (Mon, Thu, Sat)",
        "goalTags": ["muscle", "strength"],
        "description": "Three gym days a week (Monday, Thursday, Saturday) to build muscle and strength and support fat loss. "
                       "Pilates on Tuesday and yoga on Wednesday count as other activity; Friday is walking or rest.",
        "durationWeeks": 12, "maxSwapDifficulty": 2,
        "programNotes": PROGRAM_NOTES,
        "progression": "double progression: reach the top of the rep range on every set at the planned reps in reserve, "
                       "then add the smallest practical load",
        "source": {"file": FILE, "sheet": "A - Monday, B - Thursday, C - Saturday"},
    }
