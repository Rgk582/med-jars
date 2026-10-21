"""Attributes main-thread busy time in `sample` outputs: XCTest snapshots, SwiftUI updates, CA commits, app code."""
import collections, glob, os, re, sys, bisect
APP = os.environ.get("APP_NAME", "MedJars")  # the app binary name in profiler samples

R = sys.argv[1]
only = sys.argv[2] if len(sys.argv) > 2 else None
line_re = re.compile(r"^(\s*[+!:| ]*)(\d+) (.*)$")

def parse_main(text):
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if "com.apple.main-thread" in l), None)
    if start is None:
        start = next((i for i, l in enumerate(lines) if "Thread_" in l and "Main Thread" in l), None)
    if start is None: return None
    out = []
    for l in lines[start + 1:]:
        if re.match(r"^    \d+ Thread_", l) or not l.strip(): break
        m = line_re.match(l)
        if not m: continue
        depth = len(m.group(1))
        out.append((depth, int(m.group(2)), m.group(3)))
    return int(re.search(r"(\d+) Thread_", lines[start]).group(1)), out

def name(frame):
    f = re.sub(r"\s+\(in [^)]+\).*$", "", frame)
    return f[:150]

def lib(frame):
    m = re.search(r"\(in ([^)]+)\)", frame)
    return m.group(1) if m else ""

cats = collections.Counter(); app = collections.Counter(); appleaf = collections.Counter(); total = 0; busy_total = 0
per_file = []
files = sorted(glob.glob(os.path.join(R, "samples", "*.txt")))
for f in files:
    if only and only not in f: continue
    p = parse_main(open(f, errors="replace").read())
    if not p: continue
    tot, nodes = p
    total += tot
    kids = [0] * len(nodes)
    st = []
    for i2, (d, c, fr) in enumerate(nodes):
        while st and nodes[st[-1]][0] >= d: st.pop()
        if st: kids[st[-1]] += c
        st.append(i2)
    stack = []
    fbusy = 0
    for i2, (d, c, fr) in enumerate(nodes):
        while stack and stack[-1][0] >= d: stack.pop()
        stack.append((d, c, fr))
        selfc = c - kids[i2]
        if selfc <= 0: continue
        path = [s[2] for s in stack]
        leaf = path[-1]
        if "mach_msg2_trap" in leaf or "__semwait" in leaf or "__psynch_cvwait" in leaf:
            cats["idle (waiting)"] += selfc
            continue
        fbusy += selfc
        joined = " | ".join(path)
        if "XCTAutomationSupport" in joined or "AXRuntime" in joined or "AccessibilityUtilities" in joined or "UIAccessibility" in joined:
            cat = "XCTest accessibility snapshots"
        elif any(lib(x) in (APP + ".debug.dylib", APP) and "DebugHarness" not in x for x in path[6:]):
            cat = "app code (MedJars)"
        elif "CA::Transaction::commit" in joined or "CA::Layer" in joined or "CA::Render" in joined:
            cat = "Core Animation commit/render"
        elif "AttributeGraph" in joined or "AG::" in joined:
            cat = "SwiftUI graph update/layout"
        elif "UIKitCore" in joined:
            cat = "UIKit"
        else:
            cat = "other"
        cats[cat] += selfc
        appframes = [name(x) for x in path[6:] if lib(x) in (APP + ".debug.dylib", APP)]
        if appframes:
            for a in set(appframes): app[a] += selfc
            appleaf[appframes[-1]] += selfc
    busy_total += fbusy
    per_file.append((os.path.basename(f), tot, fbusy))

print(f"files={len(per_file)} main-thread samples={total} busy={busy_total}")
for k, v in cats.most_common(): print(f"  {v:>7} {100*v/max(total,1):5.1f}%  {k}")
print("Deepest app frame (self time attributed):")
for k, v in appleaf.most_common(40): print(f"  {v:>6} {k}")
print("App frames inclusive:")
for k, v in app.most_common(60): print(f"  {v:>6} {k}")
