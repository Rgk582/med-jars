# Test result tools

Run these on a results branch you pulled down (for example `git archive origin/ci-fulltest | tar -x -C out/`).

- `analyze.py out/` summarizes a full UI test run: steps, failed checks, slow steps, hangs, saves, memory, CPU, hot app code, warnings, crashes.
- `samples.py out/ [name]` sorts main-thread profiler time into idle, app code, SwiftUI, Core Animation, UIKit and the test tool. Pass part of a sample file name to look at one scenario.
- `heavy.py sample.txt [min]` prints the heaviest call paths in one profiler sample.
- `sheet.py out.jpg "shots/*Home*" "shots/*Schedule*"` puts screenshots side by side (needs `pip install pillow`).

Set `APP_NAME` when the app binary isn't called MedJars.
