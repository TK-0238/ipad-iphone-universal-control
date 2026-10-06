# MouseLink input-boundary QA plan

Goal: Find and repair reproducible failures in the approved visible panel and typing workflow.
Architecture: Keep the current HID implementation; exercise real Core/UIKit models with injected senders. Do not substitute a mock UI or radio test for hardware validation.
Tech stack: Swift/XCTest, UIKit/Combine, Python packaging, GitHub Actions.
Spec: ../../companion-panel.md

Constraints: iPad+iPhone+mouse at runtime; one visible MouseLink window; no user's Mac/GUI, pairing, external input, merge or Release. Preserve AGPL and pinned source. Baseline e744596.

Review focus: clipped/off-window surfaces; cancellation/reentry during a send; negative/backward clocks after an empty queue; release at every transaction offset; portrait/landscape compact layouts.

- [x] Recheck PR head and independently run Core123 baseline.
- [x] Add test-only Native cases for actual UIKit clipping, queue reentry and clocks; verify failures in CI before product changes. Run37283607479 reproduced nine failing methods/fourteen failed assertions.
- [x] Write and run failing Core temporal tests. Add last-event time validation without changing valid FIFO semantics. Seven methods/nineteen assertions failed before the fix; all ten new methods passed after it.
- [x] Fix proven geometry/queue defects, keeping releases bound to the original connection. Core144 and static20 are green locally; Native verification must finish in CI.
- [x] Add generated-input/boundary regression tests and iPhone portrait/landscape UI coverage. Preserve existing Debug/Release builds and real Safari Split View test.
- [ ] Inspect the new CI's real screenshots, compare source/ZIP hashes and record actual results and limitations in PR2. Do not count pending Native/phone checks as passed.
