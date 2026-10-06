# MouseLink 0.4.2 / build 8 — input-boundary regression verification

This maintenance update retains the visible companion-pad workflow and adds no background capture, runtime server, receiver app or additional hardware.

## Reproduced defects and fixes
1. InputWindowState previously treated a view attached to an active window as visible even when its bounds were empty, outside the window, or fully clipped by a scroll/ancestor view. It now intersects the visible rectangle through clipping ancestors and window bounds. Partially visible content and unclipped overflow that remains on screen still work. This is rectangular visibility validation, not arbitrary overlapping-window or sibling occlusion detection.
2. A synchronous send callback could leave/re-enter or reauthorize the panel while the old pump still consumed the queue. PanelSession now checks the captured queue generation and live authorization after the send returns, before accepting the result.
3. A drained mouse queue accepted negative or backward event times. RelayBuffer now validates against the session's last enqueued event, including an empty pending queue. Production uses monotonic system uptime; these are injected clock anomalies, not wall-clock changes.

## Red evidence
- Native test-only commit c786ae9b5050ec40a9095ab7fd9816910156e7f0, GitHub Actions run37283607479: nine new test methods failed, with fourteen failed assertions. Existing Native67, normal UI18 and actual Safari Split View remained successful. This test used real UIKit windows and injected senders, not the user's physical devices.
- Core temporal regression tests failed on the old implementation: seven methods/nineteen assertions. The fixed implementation passes all ten temporal methods and the full Core suite locally.

## Expanded test matrix
Core144 covers 10 portrait/landscape/compact geometries, every pad exit and supported button combination, malformed coordinates/gain, all256 panel button masks, distinct mapping for all95 printable ASCII characters, Unicode/control rejection at draft positions, cancellation at all516 boundaries of the maximum text+Enter transaction, and20000 seeded queue-pressure operations. These are in-process state tests, not long-running radio tests.

Native adds15 tests covering actual UIKit geometry, clipping during a drag, callback reentry and bad clocks. CI also retains full iPad UI and real Safari Split View and adds three separate iPhone16-sized app UI checks: portrait, landscape and maximum accessibility text size. The receiver iPhone does not need this app; these extra UI tests do NOT validate receiver Bluetooth, IME or Enter behavior.

Local Core144 Debug/Release/AddressSanitizer and static package20 passed. ASan uses detect_leaks=0 and does not constitute a leak scan. Native/iPad/phone results are only established by the completed GitHub Actions result and logs recorded on PR2; do not infer their success from this source document.

## Remaining limits
Real Swift Playground execution, Bluetooth pairing, physical mouse movement/scroll, iPhone Japanese IME and app-specific Enter outcomes, iPadOS26 window events, overlap behavior and long radio sessions remain unverified. A generic iOS Release build is unsigned and not an installation test. The app is distributed as Swift Playground source, not an IPA. Upstream source and AGPL-3.0-only remain unchanged.
