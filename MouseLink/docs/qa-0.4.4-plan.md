# MouseLink 0.4.4 QA plan

Goal: verify replacement/removal of the visible local pad without replaying old input or cancelling its replacement.
Architecture: retain the current HID, core queues, typing and full-screen modes. Bind each UIKit pad's authority to a unique view owner only when attached to a window. Stale view cleanup and events must not mutate the new surface's session.
Spec: companion-panel.md (one visible, explicitly enabled local surface; no background capture).

Constraints: existing Draft PR2 branch only; no main merge, Release, user Mac/GUI, pairing or real-app input. Preserve AGPL and pinned upstream. Existing full suite and both OS lanes must be rerun; passing simulator tests are not radio validation.

- [x] Reproduce with real UIKit Native tests: constructing an unattached view; attaching a replacement during a drag; old remove/dismantle/layout/cancel; current dismantle before removal; same-view reattachment; blocked release.
- [x] Bind/unbind PanelSession ownership; ignore stale view events; no automatic authorization for a new view.
- [x] Inspect adjacent event boundaries, retain explicit enable/disable and one receiver.
- [ ] Run Core Debug/Release, existing Native/UI/Split View/phone tests, package checks, iOS26 compatibility and warning checks.
- [ ] Inspect CI screenshots visually, export exact successful app archive, record verified counts and remaining limitations.

## Reproduction evidence
Test-only HEAD 061020fa08698fadaf04febf8b3dfeb1e3f6c61b, iOS26 run37383121222, artifact11376203435: 8 of the 10 new methods failed (22 assertions); previous104 methods passed. This is native UIKit with an injected sender, not wireless input.

The patch scopes pad callbacks to the currently bound view, binds on actual attachment rather than initialization, and terminally revokes dismantled views. Synchronous button release is retained. Only redraw notifications produced inside UIKit lifecycle methods are deferred; ordinary input notifications stay synchronous. Two additional tests verify deferred redraw actually arrives without restoring input, and a dismantled view cannot reclaim a replacement's ownership.

Local Swift syntax parsing and offline fixture packaging are preliminary only. Fresh CI, full native regression, UI and screenshot verification remain the completion gate.
