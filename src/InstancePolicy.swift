// mac-24ghz-battery — part of https://github.com/usamarashid94/mac-24ghz-battery
// Copyright (C) 2026 usamarashid94. Licensed under GPL-3.0; see LICENSE.

import Foundation

/// Decides what a starting instance should do about copies already running.
///
/// macOS only prevents relaunching the *same bundle path*. A copy in
/// /Applications, a copy built from source, and a Gatekeeper-translocated copy
/// running from a read-only shadow of a .dmg are three different paths sharing
/// one bundle identifier, so all three can run at once and each adds its own
/// menu bar item.
///
/// The rule is "newest wins", which makes opening a freshly installed version
/// replace the running one. Deciding that needs care: if every instance simply
/// terminated every other, two launched at the same moment would kill each
/// other and leave no menu bar item at all. So an instance only replaces copies
/// that started *before* it, and defers to any that started after.
///
/// Kept free of AppKit so it can be tested without a running app.
enum InstancePolicy {
    struct Instance: Equatable {
        var pid: Int32
        /// Nil when the system won't say; treated as "started long ago".
        var launched: Date?
    }

    enum Decision: Equatable {
        /// Take the menu bar, ending these older copies first.
        case proceed(terminating: [Int32])
        /// A newer instance is starting or already running; leave it to that one.
        case standDown
    }

    static func decide(me: Instance, others: [Instance]) -> Decision {
        guard !others.isEmpty else { return .proceed(terminating: []) }

        // A missing launch date sorts as oldest, so it never wins a tie.
        let mine = me.launched ?? .distantPast

        for other in others {
            let theirs = other.launched ?? .distantPast
            if theirs > mine { return .standDown }
            // Same instant: fall back to pid so exactly one side yields.
            if theirs == mine && other.pid > me.pid { return .standDown }
        }

        return .proceed(terminating: others.map(\.pid))
    }
}
