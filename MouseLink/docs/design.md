# MouseLink — Bluetooth direct mouse relay

Goal: iPad + iPhone + an already-connected mouse, with no runtime server, router, Mac or additional HID hardware. Send standard HID mouse reports directly from iPad to the iPhone AssistiveTouch input path.

New evidence: jqssun/darwin-bt-remote at ad7a76ce6132254fbd6085af87cea8d10aa8a82d supplies a published CoreBluetooth HOGP implementation with full UUIDs and direct hardware input. The prior assertion that no input path exists was overbroad.

Architecture: Japanese SwiftUI foreground iPad app; GCMouse capture and pointer lock; pinned AGPL-3.0-only HOGP stack with original GATT topology retained; targeted receiver selection and explicit session start; bounded FIFO for actual mouse reports; iPhone uses Bluetooth/AssistiveTouch, without a receiver app. An offline .swiftpm bundle runs in Swift Playground on iPad. Cloud build validation is not a runtime dependency and never touches the user's Mac.

Scope distinction: foreground direct relay, not a fake app-only cursor. No input capture while other iPad apps are foreground, automatic OS desktop edge crossing, iPhone mirroring or arbitrary software actions. Return to iPad with the middle button, visible Stop button, or foreground loss. Hardware validation remains a separate gate.

Safety: OS Bluetooth pairing; one explicitly selected central receives nonzero reports. No startup input, automatic resume, host-name identity claims, input logging, internet requests or advertising SDKs. Disconnect, foreground loss, queue age >500ms or overflow stops input and attempts an all-buttons-up report. No stale movement replay.

Deliverables: source, native build and Playground packaging, core/UI tests, full AGPL notice and upstream source in the generated distribution, verification logs. No signing with user credentials or store publication.
