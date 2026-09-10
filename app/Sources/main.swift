// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import AppKit

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
// .accessory keeps it out of the Dock and the app switcher: it lives in the
// menu bar only.
application.setActivationPolicy(.accessory)
application.run()
