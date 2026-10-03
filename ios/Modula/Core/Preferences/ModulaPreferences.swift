import Foundation
import Network
import SwiftUI
import UIKit

/// Typed, read-only access to the device preferences that Settings writes with
/// `@AppStorage("settings.<area>.<key>")`. Every consumer reads through here so a
/// key and its default live in exactly one place (`ModulaPreferences.Key`).
///
/// Values are read on demand (UserDefaults is thread-safe), so changing a toggle in
/// Settings takes effect the next time the consuming code path runs.
enum ModulaPreferences {
    nonisolated(unsafe) static var store: UserDefaults = .standard

    // MARK: Keys + defaults (must match the Settings `@AppStorage` declarations)

    enum Key {
        static let audioAutoplayPreviews = "settings.audio.autoplayPreviews"
        static let audioHapticOnPlay = "settings.audio.hapticOnPlay"
        static let audioRaiseToListen = "settings.audio.raiseToListen"
        static let audioVoicePlaybackSpeed = "settings.audio.voicePlaybackSpeed"
        static let batteryDataSaver = "settings.battery.dataSaver"
        static let batteryPauseAutoplayOnLowPower = "settings.battery.pauseAutoplayOnLowPower"
        static let batteryReduceMotionExtra = "settings.battery.reduceMotionExtra"
        static let cameraFormat = "settings.camera.format"
        static let cameraGrid = "settings.camera.grid"
        static let cameraMirrorFront = "settings.camera.mirrorFront"
        static let cameraSaveCapture = "settings.camera.saveCapture"
        static let chatsLinkPreviews = "settings.chats.linkPreviews"
        static let chatsPreviewMedia = "settings.chats.previewMedia"
        static let chatsReadReceiptsDisplay = "settings.chats.readReceiptsDisplay"
        static let creatorDefaultAudience = "settings.creator.defaultAudience"
        static let creatorShowInsightsHint = "settings.creator.showInsightsHint"
        static let digestsMorning = "settings.digests.morning"
        static let digestsWeekly = "settings.digests.weekly"
        static let feedDefaultMode = "settings.feed.defaultMode"
        static let feedHideModulePosts = "settings.feed.hideModulePosts"
        static let feedMediaOnly = "settings.feed.mediaOnly"
        static let feedShowReplies = "settings.feed.showReplies"
        static let finderIncludeModules = "settings.finder.includeModules"
        static let finderPeopleFirst = "settings.finder.peopleFirst"
        static let focusAllowMentions = "settings.focus.allowMentions"
        static let focusDimActivity = "settings.focus.dimActivity"
        static let focusHideBadges = "settings.focus.hideBadges"
        /// Written by the `ModulaFocusFilter` App Intent when an iOS Focus that has the
        /// Modula filter applied turns on or off. Not user-editable in Settings.
        static let focusFilterActive = "settings.focus.filterActive"
        static let gesturesDoubleTapLike = "settings.gestures.doubleTapLike"
        static let gesturesEdgeBack = "settings.gestures.edgeBack"
        static let gesturesShakeUndo = "settings.gestures.shakeUndo"
        static let gesturesSwipeReply = "settings.gestures.swipeReply"
        static let keyboardCapsLock = "settings.keyboard.capsLock"
        static let keyboardPeriodShortcut = "settings.keyboard.periodShortcut"
        static let keyboardSwipe = "settings.keyboard.swipe"
        static let labsDebugOverlays = "settings.labs.debugOverlays"
        static let labsExperimentalChrome = "settings.labs.experimentalChrome"
        static let labsVerboseLogging = "settings.labs.verboseLogging"
        static let languageTranslationHints = "settings.language.translationHints"
        static let mediaHighResUploads = "settings.media.highResUploads"
        static let mediaMuteStart = "settings.media.muteStart"
        static let mediaSaveOriginals = "settings.media.saveOriginals"
        static let mediaVideoQuality = "settings.media.videoQuality"
        static let networkPreferWiFiUploads = "settings.network.preferWiFiUploads"
        static let networkPreloadMedia = "settings.network.preloadMedia"
        static let personalisationCaptionSize = "settings.personalisation.captionSize"
        static let personalisationModuleSuggestions = "settings.personalisation.moduleSuggestions"
        static let personalisationSuggestedPeople = "settings.personalisation.suggestedPeople"
        static let photosAutoSaveStories = "settings.photos.autoSaveStories"
        static let photosLimitedLibraryHint = "settings.photos.limitedLibraryHint"
        static let sharingCopyAsLink = "settings.sharing.copyAsLink"
        static let sharingIncludeHandle = "settings.sharing.includeHandle"
        static let sharingPreferNativeSheet = "settings.sharing.preferNativeSheet"
        static let timeRelative = "settings.time.relative"
        static let timeUse24h = "settings.time.use24h"
        static let translateAutoDetect = "settings.translate.autoDetect"
        static let translateShowButton = "settings.translate.showButton"
        static let translateTarget = "settings.translate.target"
        static let unitsDistance = "settings.units.distance"
        static let unitsTemperature = "settings.units.temperature"
    }

    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? fallback
    }

    static func string(_ key: String, _ fallback: String) -> String {
        store.string(forKey: key) ?? fallback
    }

    static func double(_ key: String, _ fallback: Double) -> Double {
        store.object(forKey: key) as? Double ?? fallback
    }

    // MARK: Feed

    static var feedDefaultMode: HomeMode { HomeMode(rawValue: string(Key.feedDefaultMode, "following")) ?? .following }
    static var feedMediaOnlyByDefault: Bool { bool(Key.feedMediaOnly, false) }
    static var feedHideModulePostsByDefault: Bool { bool(Key.feedHideModulePosts, false) }
    static var feedShowReplyThreads: Bool { bool(Key.feedShowReplies, true) }

    // MARK: Media / audio / battery

    enum VideoQuality: String { case auto, saver, high }
    static var videoQuality: VideoQuality { VideoQuality(rawValue: string(Key.mediaVideoQuality, "auto")) ?? .auto }
    static var videoStartsMuted: Bool { bool(Key.mediaMuteStart, true) }
    static var highResolutionUploads: Bool { bool(Key.mediaHighResUploads, true) && !dataSaver }
    /// "Keep original file data": when off (default) photo uploads are re-encoded so
    /// location and camera metadata never leave the device.
    static var keepOriginalPhotoData: Bool { bool(Key.mediaSaveOriginals, false) }
    static var audioAutoplayPreviews: Bool { bool(Key.audioAutoplayPreviews, false) }
    static var hapticOnPlay: Bool { bool(Key.audioHapticOnPlay, true) }
    static var raiseToListen: Bool { bool(Key.audioRaiseToListen, false) }
    static var voicePlaybackSpeed: Float {
        Float(min(max(double(Key.audioVoicePlaybackSpeed, 1.0), 0.75), 2.0))
    }
    static var dataSaver: Bool { bool(Key.batteryDataSaver, false) }
    static var pauseAutoplayOnLowPower: Bool { bool(Key.batteryPauseAutoplayOnLowPower, true) }
    static var extraMotionReduction: Bool { bool(Key.batteryReduceMotionExtra, false) }
    static var preferWiFiForUploads: Bool { bool(Key.networkPreferWiFiUploads, true) }
    static var preloadMedia: Bool { bool(Key.networkPreloadMedia, true) }

    /// Feed video autoplay policy: Reduce Motion (system or Modula's extra reduction),
    /// Low Power Mode (when the user asked to pause), and Data saver on a metered
    /// network all stop autoplay. Tapping still plays.
    static func allowsVideoAutoplay(
        systemReduceMotion: Bool,
        lowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        expensiveNetwork: Bool = NetworkConditions.shared.isExpensive
    ) -> Bool {
        if systemReduceMotion || extraMotionReduction { return false }
        if lowPowerMode && pauseAutoplayOnLowPower { return false }
        if dataSaver && expensiveNetwork { return false }
        return true
    }

    /// Whether a feed video should be fetched before the user taps it.
    static func prefetchesVideo(expensiveNetwork: Bool = NetworkConditions.shared.isExpensive) -> Bool {
        if dataSaver { return false }
        switch videoQuality {
        case .high: return true
        case .saver: return false
        case .auto: return !expensiveNetwork && preloadMedia
        }
    }

    // MARK: Chats

    static var chatLinkPreviews: Bool { bool(Key.chatsLinkPreviews, true) && !dataSaver }
    static var chatInlineMedia: Bool { bool(Key.chatsPreviewMedia, true) }
    static var chatShowReadReceipts: Bool { bool(Key.chatsReadReceiptsDisplay, true) }

    // MARK: Creator

    static var creatorDefaultAudience: AudienceSelection {
        switch string(Key.creatorDefaultAudience, "public") {
        case "followers": .followers
        case "private", "close": .onlyMe
        default: .everyone
        }
    }
    static var creatorShowsInsightsHint: Bool { bool(Key.creatorShowInsightsHint, true) }

    // MARK: Search

    static var searchIncludesModules: Bool { bool(Key.finderIncludeModules, true) }
    static var searchPeopleFirst: Bool { bool(Key.finderPeopleFirst, false) }

    // MARK: Focus

    static var focusFilterActive: Bool { bool(Key.focusFilterActive, false) }
    static var hidesBadgesNow: Bool { focusFilterActive && bool(Key.focusHideBadges, false) }
    static var dimsActivityNow: Bool { focusFilterActive && bool(Key.focusDimActivity, true) }
    static var focusAllowsMentions: Bool { bool(Key.focusAllowMentions, true) }

    // MARK: Gestures / keyboard

    static var doubleTapToLike: Bool { bool(Key.gesturesDoubleTapLike, true) }
    static var edgeSwipeBack: Bool { bool(Key.gesturesEdgeBack, true) }
    static var shakeToUndo: Bool { bool(Key.gesturesShakeUndo, false) }
    static var swipeToReply: Bool { bool(Key.gesturesSwipeReply, true) }
    /// "Auto-capitalise" — sentence-case capitalisation in Modula's composers.
    static var composerAutoCapitalise: Bool { bool(Key.keyboardCapsLock, true) }
    /// "Autocorrect" in Modula's composers.
    static var composerAutocorrect: Bool { bool(Key.keyboardPeriodShortcut, true) }
    /// Swipe left/right on the composer tool strip to move between tools.
    static var composerToolSwipe: Bool { bool(Key.keyboardSwipe, true) }

    // MARK: Labs

    static var debugOverlays: Bool { bool(Key.labsDebugOverlays, false) }
    static var experimentalChrome: Bool { bool(Key.labsExperimentalChrome, false) }
    static var verboseLogging: Bool { bool(Key.labsVerboseLogging, false) }

    // MARK: Language / translation

    static var translationHints: Bool { bool(Key.languageTranslationHints, true) }
    /// "Keep original" as the target language turns post translation off.
    static var translateButton: Bool {
        bool(Key.translateShowButton, true) && string(Key.translateTarget, "system") != "original"
    }
    static var translateAutoDetect: Bool { bool(Key.translateAutoDetect, true) }
    /// `nil` = follow the system language.
    static var translateTargetLanguage: Locale.Language? {
        let raw = string(Key.translateTarget, "system")
        return raw == "system" || raw == "original" ? nil : Locale.Language(identifier: raw)
    }

    // MARK: Personalisation

    enum CaptionSize: String { case compact, standard, comfortable }
    static var captionSize: CaptionSize { CaptionSize(rawValue: string(Key.personalisationCaptionSize, "standard")) ?? .standard }
    static var showsModuleSuggestions: Bool { bool(Key.personalisationModuleSuggestions, true) }
    static var showsSuggestedPeople: Bool { bool(Key.personalisationSuggestedPeople, true) }

    // MARK: Photos / camera

    static var offerToSaveStories: Bool { bool(Key.photosAutoSaveStories, false) }
    static var explainLimitedLibrary: Bool { bool(Key.photosLimitedLibraryHint, true) }
    static var cameraGrid: Bool { bool(Key.cameraGrid, true) }
    static var cameraMirrorFront: Bool { bool(Key.cameraMirrorFront, true) }
    static var cameraSavesToPhotos: Bool { bool(Key.cameraSaveCapture, true) }
    static var cameraPrefersHEIC: Bool { string(Key.cameraFormat, "heic") == "heic" }

    // MARK: Sharing

    static var shareCopiesLink: Bool { bool(Key.sharingCopyAsLink, false) }
    static var shareIncludesHandle: Bool { bool(Key.sharingIncludeHandle, true) }
    static var sharePrefersSystemSheet: Bool { bool(Key.sharingPreferNativeSheet, true) }

    // MARK: Time & units

    static var relativeTimestamps: Bool { bool(Key.timeRelative, true) }
    static var uses24HourClock: Bool { bool(Key.timeUse24h, false) }
    static var metricDistance: Bool { string(Key.unitsDistance, "metric") == "metric" }
    static var celsius: Bool { string(Key.unitsTemperature, "c") == "c" }
}

/// Process-wide network path, so preferences can ask "is this a metered link?".
final class NetworkConditions: @unchecked Sendable {
    static let shared = NetworkConditions()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var expensive = false
    private var constrained = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.expensive = path.isExpensive
            self.constrained = path.isConstrained
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "digital.modula.network-conditions", qos: .utility))
    }

    /// Cellular / personal hotspot, or iOS Low Data Mode.
    var isExpensive: Bool {
        lock.lock(); defer { lock.unlock() }
        return expensive || constrained
    }
}

/// Timestamp + unit formatting that honours Settings → Time & Units.
enum ModulaTimeFormat {
    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Short timestamp for lists and cards.
    static func short(_ date: Date, now: Date = Date()) -> String {
        if ModulaPreferences.relativeTimestamps {
            if abs(now.timeIntervalSince(date)) < 45 { return String(localized: "now") }
            return relative.localizedString(for: min(date, now), relativeTo: now)
        }
        return absolute(date, now: now)
    }

    /// Absolute date/time in the chosen 12/24-hour clock.
    static func absolute(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let hour: Date.FormatStyle.Symbol.Hour = ModulaPreferences.uses24HourClock
            ? .twoDigits(amPM: .omitted)
            : .defaultDigits(amPM: .abbreviated)
        var style = Date.FormatStyle().hour(hour).minute(.twoDigits)
        if !calendar.isDate(date, inSameDayAs: now) {
            style = style.day().month(.abbreviated)
            if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        }
        return date.formatted(style)
    }

    static func distance(meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let unit: UnitLength = ModulaPreferences.metricDistance
            ? (meters >= 1_000 ? .kilometers : .meters)
            : (meters >= 1_609 ? .miles : .feet)
        return measurement.converted(to: unit).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func temperature(celsius value: Double) -> String {
        let measurement = Measurement(value: value, unit: UnitTemperature.celsius)
        let unit: UnitTemperature = ModulaPreferences.celsius ? .celsius : .fahrenheit
        return measurement.converted(to: unit).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}
