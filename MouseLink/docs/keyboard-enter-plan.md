# Keyboard and Enter implementation plan (2026-10-05)

Goal: add on-screen text entry and actual HID Return/Enter to the existing Bluetooth-only app. No user's Mac access and no physical keyboard required.

The old code has HID keyboard descriptors but never sends keyboard reports from MouseLink. Keep that GATT layout unchanged; send only to the explicitly selected central and its subscribed keyboard characteristic.

1. Test then implement printable US-ASCII encoding, explicit special keys and ordered press/release plans. Reject unsupported text atomically, including pasted control characters. Japanese support is remote roman-input/IME plus an explicitly selected kana-reading conversion; never claim arbitrary kanji/emoji clipboard transfer.
2. Test then implement a bounded, rate-limited keyboard transaction that advances only when CoreBluetooth accepts a report. Stop on foreground loss, disconnect, target change, stalling or user cancellation; release keys and discard unsent Enter. Never automatically replay.
3. Add an unlocked typing sheet: draft, send text, send text+Enter, independent Enter, Shift+Enter, Backspace, Tab, Space/convert, arrows, input-source switch, on-screen QWERTY. Local IME composition stays local until explicit Send. No automatic double Enter or submission guarantee.
4. Package the vendor adapter reproducibly after the existing SHA-verified packaging, bump version to 0.2.0; run old/new core tests, iOS build and native UI tests; inspect real screenshots. Deliver updated source ZIP and record real-device limits.

Review focus: repeated identical characters need key-up; keyboard and mouse share a report UUID but not characteristic identity; do not send both boot/report forms; cancel must not retain Enter; app-local pointer must be unlocked for typing; no remote input until an explicit button action.
