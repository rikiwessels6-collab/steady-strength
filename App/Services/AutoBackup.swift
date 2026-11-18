import Foundation
import SwiftData
import SteadyCore

/// Weekly backup file saved to a folder the user picks in Files (iCloud Drive, On My iPhone, ...).
/// Runs when the app opens and a week has passed. The folder is remembered as a bookmark on this
/// phone only; it is not part of backups.
@MainActor
enum AutoBackup {
    private static let bookmarkKey = "autoBackupFolder"
    private static let lastKey = "autoBackupLastAt"
    private static let errorKey = "autoBackupLastError"
    private static var defaults: UserDefaults { .standard }

    static var isOn: Bool { defaults.data(forKey: bookmarkKey) != nil }
    static var lastAt: Date? { defaults.object(forKey: lastKey) as? Date }
    static var lastError: String? { defaults.string(forKey: errorKey) }

    /// The chosen folder's name, for Settings.
    static var folderName: String? { resolve()?.lastPathComponent }

    /// Remembers a folder from the folder picker, then makes the first backup straight away.
    static func choose(_ url: URL, context: ModelContext) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
        defaults.removeObject(forKey: lastKey)
        defaults.removeObject(forKey: errorKey)
        run(context)
    }

    static func stop() {
        for key in [bookmarkKey, lastKey, errorKey] { defaults.removeObject(forKey: key) }
    }

    static func runIfDue(_ context: ModelContext) {
        guard isOn, AutoBackupPlan.isDue(last: lastAt) else { return }
        run(context)
    }

    @discardableResult
    static func run(_ context: ModelContext) -> Bool {
        guard let folder = resolve() else {
            defaults.set("The backup folder can't be found. Choose it again.", forKey: errorKey)
            return false
        }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        do {
            let data = try DataExport.encoded(context)
            let dest = folder.appendingPathComponent(AutoBackupPlan.fileName(.now))
            var coordinatorError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: dest, options: .forReplacing, error: &coordinatorError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let e = coordinatorError { throw e }
            if let e = writeError { throw e }
            prune(folder)
            defaults.set(Date.now, forKey: lastKey)
            defaults.removeObject(forKey: errorKey)
            if let s = try? context.fetch(FetchDescriptor<AppSettings>()).first {
                s.lastBackupAt = .now
                try? context.save()
            }
            return true
        } catch {
            defaults.set("The last weekly backup couldn't be saved: \(error.localizedDescription)", forKey: errorKey)
            return false
        }
    }

    private static func resolve() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    private static func prune(_ folder: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for name in AutoBackupPlan.toRemove(urls.map(\.lastPathComponent)) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
