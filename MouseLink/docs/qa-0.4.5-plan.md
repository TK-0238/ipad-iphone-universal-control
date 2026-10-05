# MouseLink 0.4.5 input-contact QA plan

Goal: verify real LocalPadView event handlers, not just the report queue, across terminal movement samples and changes of input authorization.
Baseline: 2378fe2ebfe23794be368911011ea12417ba809f (0.4.4). Existing 144 Core tests re-executed successfully in isolated Linux Swift 6.2.1.

Scope: iPad/iPhone/mouse runtime only, no user's Mac, shared GUI, hardware pairing, actual application submissions, main merge or Release. Keep AGPL and pinned HID source. Synthetic UITouch objects in Native tests provide location/type to the actual UIKit view; they are not physical touch/mouse or Bluetooth tests.

- [ ] Add Native regression tests for final-only movement, final displacement after moves, old move/up/cancel after stop and re-enable, reconnect, disabled start, hidden surface and normal fresh contacts.
- [ ] Observe the test-only commit fail on actual iOS Native tests before changing product code.
- [ ] Bind one touch sequence to its input-authorization generation; consume the terminal position before deciding tap/release; reject stale sequences without disturbing new input.
- [ ] Re-run full Core Debug/Release, Native/UI and package checks on existing iOS18.5 and iOS26.2 CI lanes. Inspect actual screenshots. Do not equate simulation or build success with radio/hardware success.
- [ ] Review diff and package correspondence; report counts, limitations and warnings; retain Draft PR #2.

Additional review focus: rapid interruption between down and up; a hidden view retaining a held button; a late event releasing a new drag; inside/outside bounds at lift; touch cancellation must never synthesize Enter or a click.
