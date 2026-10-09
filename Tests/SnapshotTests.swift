import XCTest
import AppKit

/// Renders the editor to PNG for eyeballing (set WRITEMD_SNAPSHOT_DIR); also asserts drawing does not crash.
final class SnapshotTests: XCTestCase {
    func testRenderSample() throws {
        let path = ProcessInfo.processInfo.environment["WRITEMD_SAMPLE"] ?? "/tmp/wmd/sample.md"
        guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { throw XCTSkip("no sample") }
        let dir = ProcessInfo.processInfo.environment["WRITEMD_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let (_, tv) = makeEditor(src, width: 900)
            tv.window?.appearance = NSAppearance(named: appearance)
            tv.appearance = NSAppearance(named: appearance)
            tv.layoutManager!.ensureLayout(for: tv.textContainer!)
            let used = tv.layoutManager!.usedRect(for: tv.textContainer!)
            tv.setFrameSize(NSSize(width: 900, height: used.height + 80))
            tv.layoutSubtreeIfNeeded()
            let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds)!
            tv.cacheDisplay(in: tv.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("writemd-\(name).png"))
        }
    }
}
