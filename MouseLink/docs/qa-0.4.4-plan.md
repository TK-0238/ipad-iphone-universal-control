# MouseLink 0.4.4 QA plan

Goal: verify replacement/removal of the visible local pad without replaying old input or cancelling its replacement.
Architecture: retain the current HID, core queues, typing and full-screen modes. Bind each UIKit pad's authority to a unique view owner only when attached to a window. Stale view cleanup and events must not mutate the new surface's session.
Spec: companion-panel.md (one visible, explicitly enabled local surface; no background capture).

Constraints: existing Draft PR2 branch only; no main merge, Release, user Mac/GUI, pairing or real-app input. Preserve AGPL and pinned upstream. Existing full suite and both OS lanes must be rerun; passing simulator tests are not radio validation.

- [ ] Reproduce with real UIKit Native tests: constructing an unattached view; attaching a replacement during a drag; old remove/dismantle/layout/cancel; current dismantle before removal; same-view reattachment; blocked release.
- [ ] Bind/unbind PanelSession ownership; ignore stale view events; no automatic authorization for a new view.
- [ ] Inspect adjacent event boundaries, retain explicit enable/disable and one receiver.
- [ ] Run Core Debug/Release, existing Native/UI/Split View/phone tests, package checks, iOS26 compatibility and warning checks.
- [ ] Inspect CI screenshots visually, export exact successful app archive, record verified counts and remaining limitations.
