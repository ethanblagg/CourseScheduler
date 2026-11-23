# Class Planner

`main` holds the iOS app (issue #1); `master` is the legacy C++ command-line version and must stay unchanged.

## iOS app

- `ClassPlanner.xcodeproj`: app target `ClassPlanner`, shown as "Class Planner", bundle ID `com.ethanblagg.ClassPlanner`, iPhone only, iOS 26 and newer. The `ClassPlanner/` folder is synced to the target, so new Swift files are picked up without editing the project.
- `ClassPlannerCore/`: Swift package with the SwiftData models, weekly-time validation, plan naming, and `Plan.readiness`, which hands the scheduling engine a value-type `PlanInput` only when every entry is complete. Keep scheduling logic here, independent of SwiftUI.
- SwiftData relationship arrays are unordered: every child has a `position`, and views use the `ordered…` accessors. Colors are stored apart from scheduling data and never affect `PlanInput` or starred schedules (`ScheduleKey`).

### Scheduling engine (`ScheduleSearch`)

- Input is `PlanInput` from `Plan.readiness`. A schedule picks exactly one section per course and includes every meeting of that section. It is valid only if no class meetings overlap each other or any unavailable time. Meetings overlap only on a shared weekday when `start < otherEnd && otherStart < end`, so back-to-back times fit.
- Outcomes are explicit: `.noCourses`, `.schedules`, `.noneFit` (smallest sets of courses that can't fit together, plus every meeting-level clash among them), or `.inconclusive` (the search budget ran out before finding any).
- Summaries count class meetings only; unavailable times never count as days on campus. Gaps are the idle minutes between classes on each campus day, summed over the week. Example: Mon 9–10 and 11–12 is 60 minutes; Wed 9–10, 10–10:30, 11–12 and 12–12:15 is 30 minutes.
- Two orderings: `fewestDays` (days, then gaps) and `shortestGaps` (gaps, then days); ties go to the earlier first class, then the earlier last class, then the key. Results keep the best 500 per ordering, with `totalCount` for all of them. `isExhaustive` is false if the 2,000,000-step budget stopped the search, in which case `totalCount` is a lower bound.
- Call `ScheduleSearch.outcome(for:)` from the UI. It runs off the main actor and stops when its task is cancelled. Results don't depend on input order.

### Calendar

- `CalendarLayout` (core) decides the visible days, hour range, and side-by-side lanes; the SwiftUI `WeekCalendar` only draws it. Event heights always match real durations: short meetings get thin blocks without text, and details come from tapping or VoiceOver.
- Settings live in `@AppStorage` (`CalendarSettings`): weekends on/off (a weekend column still shows if a class meets then) and week start (Mon/Sun). The editors' day toggles follow the week start.
- Event text inside calendar blocks is capped at the Large type size; the agenda, detail sheet, and everything else scale fully.

Commands (run from the repository root):

```sh
swift test --package-path ClassPlannerCore
(cd ClassPlannerCore && xcodebuild -scheme ClassPlannerCore -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ../.build/CoreDerivedData test)
xcodebuild -project ClassPlanner.xcodeproj -scheme ClassPlanner -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData build
```

The first is the fast macOS check; the second runs the same tests on iOS.

UI tests (`ClassPlannerUITests`, about two minutes) drive the entry flows in the simulator; set `TEST_RUNNER_SCREENSHOT_DIR` to save their screenshots:

```sh
TEST_RUNNER_SCREENSHOT_DIR=/tmp/class-planner-shots xcodebuild -project ClassPlanner.xcodeproj -scheme ClassPlanner -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData test
```

Debug launch arguments: `-ui-testing` uses an in-memory store and resets calendar settings, `-seed-sample` adds the Fall 2026 sample plan (CHEM 101 with three sections, MATH 120, Work, Weekend shift), and `-seed-display` adds a plan for checking the calendar (early and late classes, a 15-minute meeting, a Saturday lab, a Sunday shift, long names).

Deletes follow the Undo pattern: `remove…` returns a snapshot, the app saves and shows the Undo prompt (`UndoCenter`), and `restore(_:)` brings back the same IDs and values. If the simulator is missing, create it with `xcrun simctl create "iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0`.

## Design checkpoint (issue #2)

The `design/` folder is a dependency-free, clickable prototype. It computes schedules in the browser for review only; the production scheduling engine, persistence, and iOS app come in issues #3–#8, after design approval.

Design preferences from review:
- Keep text minimal: no explanatory copy, eyebrows, subtitles, or time zones. Labels only where needed.
- Everything autosaves. No Save or Cancel buttons; deletes offer Undo.
- Use "Section" (not "alternative section") and "Unavailable" for work and other fixed times.
- Colors are a tappable dot before the name; no explanation.
- The week view must not scroll horizontally. Weekends can be hidden, and the week can start on Monday or Sunday.
- When nothing fits, explain it on the schedules screen; don't add a separate page or force the user to choose what to edit.
- New plans default to the upcoming term name, with " (2)" and so on for duplicates.
- No sample data or extra decisions in the app. A first launch goes straight into an empty plan; the bottom button always names the next step.
- Schedules always reflect the current inputs. Starring marks schedules you like and puts them first; there are no saved copies. If an edit means a starred schedule no longer fits, it drops out.

v1 limits: meetings repeat weekly for the whole term (no alternating weeks, holidays, overnight classes, or TBA times). Back-to-back classes are allowed; there is no travel-time buffer.

Serve the prototype from the repository root with caching off, so reviewers never see stale files:

```sh
python3 -c 'import functools, http.server as h; H = type("H", (h.SimpleHTTPRequestHandler,), {"end_headers": lambda s: (s.send_header("Cache-Control", "no-store"), h.SimpleHTTPRequestHandler.end_headers(s))}); h.ThreadingHTTPServer(("127.0.0.1", 4173), functools.partial(H, directory="design")).serve_forever()'
```

The prototype starts as a new user (empty, straight into a first plan). "Returning user" in the left rail loads existing plans and course history.

Check JavaScript syntax with the system JavaScriptCore runtime:

```sh
swift -e 'import Foundation; import JavaScriptCore; let source = try! String(contentsOfFile: "design/prototype.js", encoding: .utf8); let data = try! JSONSerialization.data(withJSONObject: [source], options: .fragmentsAllowed); let json = String(data: data, encoding: .utf8)!; let context = JSContext()!; _ = context.evaluateScript("new Function(\(json.dropFirst().dropLast()))"); if context.exception != nil { fatalError("JavaScript syntax error: \(context.exception!)") }; print("JavaScript syntax OK")'
```
