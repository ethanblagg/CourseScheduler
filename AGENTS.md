# Class Planner

`main` holds the iOS app (issue #1); `master` is the legacy C++ command-line version and must stay unchanged.

## iOS app

- `ClassPlanner.xcodeproj`: app target `ClassPlanner`, shown as "Class Planner", bundle ID `com.ethanblagg.ClassPlanner`, iPhone only, iOS 26 and newer. The `ClassPlanner/` folder is synced to the target, so new Swift files are picked up without editing the project.
- `ClassPlannerCore/`: Swift package with the SwiftData models, weekly-time validation, plan naming, and `Plan.readiness`, which hands the scheduling engine a value-type `PlanInput` only when every entry is complete. Keep scheduling logic here, independent of SwiftUI.
- SwiftData relationship arrays are unordered: every child has a `position`, and views use the `ordered…` accessors. Colors are stored apart from scheduling data and never affect `PlanInput` or starred schedules (`ScheduleKey`).

Commands (run from the repository root):

```sh
swift test --package-path ClassPlannerCore
(cd ClassPlannerCore && xcodebuild -scheme ClassPlannerCore -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath ../.build/CoreDerivedData test)
xcodebuild -project ClassPlanner.xcodeproj -scheme ClassPlanner -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath .build/DerivedData build
```

The first is the fast macOS check; the second runs the same tests on iOS. If the simulator is missing, create it with `xcrun simctl create "iPhone 17" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0`.

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
