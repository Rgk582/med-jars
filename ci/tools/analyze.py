"""Summarizes a ci-fulltest results folder: steps, failures, hangs, persist timing, CPU, memory, hot main-thread frames."""
import collections, glob, os, re, sys
APP = os.environ.get("APP_NAME", "MedJars")  # the app binary name in profiler samples

R = sys.argv[1]
def read(p):
    try: return open(os.path.join(R, p), errors="replace").read()
    except FileNotFoundError: return ""

marks = read("marks.txt").splitlines()
print("== Status:", read("test-status.txt").strip(), "| build:", read("build-status.txt").strip())
steps = []
for m in marks:
    mm = re.match(r"MARK ([\d.]+) STEP END (\d+) (\d+)ms (OK|FAIL) :: (.*)", m)
    if mm: steps.append((float(mm.group(1)), mm.group(2), int(mm.group(3)), mm.group(4), mm.group(5)))
print(f"== Steps: {len(steps)} total, {sum(s[3]=='FAIL' for s in steps)} with failed checks")
fails = [m for m in marks if "CHECK FAIL" in m]
print(f"== Check failures: {len(fails)}")
for f in fails: print("  ", f.split("CHECK FAIL: ",1)[1])
print("== Slowest steps")
for s in sorted(steps, key=lambda s: -s[2])[:25]: print(f"   {s[2]:>7}ms {s[3]} {s[4]}")
print("== Responsive / launch / page marks")
for m in marks:
    if any(k in m for k in ("RESPONSIVE", "LAUNCHED", "PAGE ")): print("  ", m.split(" ", 2)[2])

perf = read("perf/perf.log") or read("perf/perf-documents.log")
lines = perf.splitlines()
print(f"== perf.log lines: {len(lines)}")
hangs = [l for l in lines if " HANG " in l]
vals = [int(re.search(r"HANG (\d+)ms", l).group(1)) for l in hangs]
print(f"== Main-thread hangs >=250ms: {len(hangs)}; worst: {sorted(vals)[-10:] if vals else []}")
persist = [float(re.search(r"total ([\d.]+)ms", l).group(1)) for l in lines if "PERSIST total" in l]
if persist:
    persist.sort()
    print(f"== persist(): n={len(persist)} median={persist[len(persist)//2]:.1f}ms p90={persist[int(len(persist)*.9)]:.1f}ms max={persist[-1]:.1f}ms")
times = collections.defaultdict(list)
for l in lines:
    mm = re.search(r"TIME (\S+).*? ([\d.]+)ms", l)
    if mm: times[mm.group(1)].append(float(mm.group(2)))
for k, v in sorted(times.items(), key=lambda kv: -max(kv[1])):
    v.sort(); print(f"   {k}: n={len(v)} median={v[len(v)//2]:.1f} max={v[-1]:.1f}")
for l in lines:
    if "SEED" in l: print("  ", l)
stats = [l for l in lines if " STATS " in l]
mem = [float(re.search(r"mem=([\d.]+)MB", l).group(1)) for l in stats if "mem=" in l]
rows = [int(re.search(r"rows/5s=(\d+)", l).group(1)) for l in stats]
bodies = [int(re.search(r"bodies/5s=(\d+)", l).group(1)) for l in stats]
if mem: print(f"== Memory: start {mem[0]:.0f}MB, max {max(mem):.0f}MB, end {mem[-1]:.0f}MB over {len(mem)} samples")
if rows: print(f"== Schedule rows computed per 5 s: max {max(rows)}, median {sorted(rows)[len(rows)//2]}")
if bodies: print(f"== View bodies per 5 s: max {max(bodies)}")
print("== Top body counts in busiest 5 s windows")
for l in sorted(stats, key=lambda l: -int(re.search(r"bodies/5s=(\d+)", l).group(1)))[:6]:
    print("  ", l.split("STATS ",1)[1][:300])

cpu = [l.split() for l in read("cpu.txt").splitlines() if len(l.split()) >= 4]
if cpu:
    c = [float(x[2]) for x in cpu]
    print(f"== CPU samples {len(c)}: median {sorted(c)[len(c)//2]:.0f}% max {max(c):.0f}%; RSS max {max(int(x[3]) for x in cpu)//1024}MB")
    def window(a, b):
        return [float(x[2]) for x in cpu if a <= int(x[0]) <= b]
    for tag in ("IDLE", "IDLE2"):
        b = [m for m in marks if f" {tag} BEGIN" in m]; e = [m for m in marks if f" {tag} END" in m]
        if b and e:
            w = window(float(b[0].split()[1]) + 3, float(e[0].split()[1]))
            if w: print(f"== CPU while idle ({tag}): avg {sum(w)/len(w):.1f}% max {max(w):.0f}% n={len(w)}")

# Hot app frames on the main thread across samples
hot = collections.Counter(); leaf = collections.Counter(); nfiles = 0
for f in glob.glob(os.path.join(R, "samples", "*.txt")):
    t = open(f, errors="replace").read()
    i = t.find("com.apple.main-thread")
    if i < 0: continue
    j = t.find("\n    ", i)
    nxt = re.search(r"\n    \d+ Thread_", t[i+10:])
    block = t[i: i + 10 + (nxt.start() if nxt else len(t))]
    nfiles += 1
    for line in block.splitlines():
        mm = re.match(r"\s*[+!:| ]*\s*(\d+)\s+(.+?)\s+\(in ([^)]+)\)", line)
        if mm and mm.group(3) in (APP, APP + ".debug.dylib"):
            name = re.sub(r"\s+\+ \d+.*$", "", mm.group(2))[:140]
            hot[name] += int(mm.group(1))
print(f"== Hot MedJars frames on the main thread ({nfiles} samples, inclusive counts)")
for k, v in hot.most_common(45): print(f"   {v:>6} {k}")
w = read("warnings.txt").splitlines()
print(f"== Runtime warnings: {len(w)} lines")
cnt = collections.Counter(re.sub(r"^.*?(MedJars\S*|SwiftUI|UIKit)[^:]*: ", "", l)[:160] for l in w)
for k, v in cnt.most_common(25): print(f"   {v:>5} {k}")
cr = glob.glob(os.path.join(R, "crashes", "*"))
print(f"== Crash reports: {len(cr)} {[os.path.basename(x) for x in cr]}")
print("== Metrics")
for l in read("results.txt").splitlines():
    if "measured [" in l: print("  ", re.sub(r"^.*?measured", "measured", l)[:220])
