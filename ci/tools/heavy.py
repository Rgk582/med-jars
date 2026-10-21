"""Prints the heaviest path through the main thread's call tree, with counts, following the biggest child each step."""
import re, sys
txt = open(sys.argv[1], errors="replace").read().splitlines()
start = next((i for i, l in enumerate(txt) if "com.apple.main-thread" in l), None)
if start is None: start = next(i for i, l in enumerate(txt) if "Thread_" in l and "Main Thread" in l)
rx = re.compile(r"^(\s*[+!:| ]*)(\d+) (.*)$")
nodes = []
for l in txt[start + 1:]:
    if re.match(r"^    \d+ Thread_", l) or not l.strip(): break
    m = rx.match(l)
    if m: nodes.append((len(m.group(1)), int(m.group(2)), m.group(3)))
# children lists
children = {i: [] for i in range(len(nodes))}
st = []
roots = []
for i, (d, c, f) in enumerate(nodes):
    while st and nodes[st[-1]][0] >= d: st.pop()
    if st: children[st[-1]].append(i)
    else: roots.append(i)
    st.append(i)
minc = int(sys.argv[2]) if len(sys.argv) > 2 else 200
def walk(i, depth):
    d, c, f = nodes[i]
    f = re.sub(r"\s+\(in ([^)]+)\).*$", r"  [\1]", f)
    print(f"{'  '*min(depth,40)}{c} {f[:160]}")
    for k in sorted(children[i], key=lambda k: -nodes[k][1]):
        if nodes[k][1] >= minc: walk(k, depth + 1)
for r in roots: walk(r, 0)
