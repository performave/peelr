import CoreML
import Foundation

/// Downloads and caches the BiRefNet/RMBG-2 Core ML model on demand.
///
/// The model is ~233 MB, so we don't bundle it (that would bloat every app update, which
/// Homebrew casks redownload in full). Instead we fetch it once, on first photo-mode use,
/// into Application Support, compile it, and reuse it across launches and app updates.
/// The cache is keyed by `revision`, so bumping the model re-downloads exactly once.
@available(macOS 14.0, *)
final class ModelStore {
    static let shared = ModelStore()

    // Pinned to a known-good revision of the (CC BY-NC 4.0) community conversion. See AGENTS.md.
    private let repoPath = "VincentGOURBIN/RMBG-2-CoreML"
    private let revision = "0da071b52c402b293c8b13af9148bac21b4a8456"
    private let packageName = "RMBG-2-native-int8.mlpackage"
    private let relativeFiles = [
        "Manifest.json",
        "Data/com.apple.CoreML/model.mlmodel",
        "Data/com.apple.CoreML/weights/weight.bin",
    ]

    private var inFlight: Task<URL, Error>?

    private var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Peelr/Models", isDirectory: true)
    }

    /// Where the compiled model lives once ready. Name carries the revision so an updated
    /// pin invalidates the old cache automatically.
    var compiledModelURL: URL {
        supportDir.appendingPathComponent("BiRefNet-\(revision).mlmodelc", isDirectory: true)
    }

    /// Non-nil once the model is downloaded, compiled, and ready to load.
    var readyModelURL: URL? {
        FileManager.default.fileExists(atPath: compiledModelURL.path) ? compiledModelURL : nil
    }

    /// The cache directory, for "Show in Finder".
    var modelsDirectory: URL { supportDir }

    /// Total on-disk size of the cached model, if present.
    var cachedByteCount: Int64? {
        guard let url = readyModelURL,
              let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// Remove the cached model from disk.
    func deleteCache() throws {
        if FileManager.default.fileExists(atPath: compiledModelURL.path) {
            try FileManager.default.removeItem(at: compiledModelURL)
        }
    }

    /// Ensure the model is present, downloading + compiling once. Concurrent callers share
    /// the same in-flight work. `progress` reports the download fraction (0…1).
    @MainActor
    @discardableResult
    func ensureAvailable(progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let ready = readyModelURL { return ready }
        if let inFlight { return try await inFlight.value }
        let task = Task.detached { try await self.downloadAndCompile(progress: progress) }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    private func downloadAndCompile(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let fm = FileManager.default
        let tmpPackage = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(packageName, isDirectory: true)
        try? fm.removeItem(at: tmpPackage)

        let base = "https://huggingface.co/\(repoPath)/resolve/\(revision)/\(packageName)/"
        for rel in relativeFiles {
            guard let src = URL(string: base + rel) else { throw ModelStoreError.downloadFailed(rel) }
            let dst = tmpPackage.appendingPathComponent(rel)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            let isWeights = rel.hasSuffix("weight.bin") // the only file large enough to track
            try await download(from: src, to: dst) { frac in if isWeights { progress(frac) } }
        }

        // Compile the downloaded package and move it into the persistent cache.
        let compiled = try await MLModel.compileModel(at: tmpPackage)
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dest = compiledModelURL
        try? fm.removeItem(at: dest)
        try fm.moveItem(at: compiled, to: dest)
        try? fm.removeItem(at: tmpPackage.deletingLastPathComponent())
        return dest
    }

    /// Download a single file to `dest`, reporting fractional progress via KVO on the task.
    private func download(from url: URL, to dest: URL,
                          progress: @escaping @Sendable (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var observation: NSKeyValueObservation?
            let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
                observation?.invalidate()
                if let error { cont.resume(throwing: error); return }
                guard let tempURL,
                      let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    cont.resume(throwing: ModelStoreError.downloadFailed(url.lastPathComponent)); return
                }
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: tempURL, to: dest)
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in progress(p.fractionCompleted) }
            task.resume()
        }
    }

    enum ModelStoreError: LocalizedError {
        case downloadFailed(String)
        var errorDescription: String? {
            switch self {
            case .downloadFailed(let file):
                return "Couldn't download the background model (\(file)). Check your connection and try again."
            }
        }
    }
}
