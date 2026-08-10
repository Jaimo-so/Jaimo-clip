import ClipFlowKit
import Foundation

enum SelfTestError: Error {
    case failed(String)
}

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw SelfTestError.failed(message) }
}

func makeClip(_ text: String, date: Date = Date()) -> CapturedClip {
    CapturedClip(
        kind: .text,
        category: .text,
        sourceAppName: "SelfTest",
        sourceBundleID: "com.clipflow.selftest",
        copiedAt: date,
        title: text,
        fullText: text,
        meta: ClipClassifier.textMeta(text: text, kind: .text),
        contentHash: ClipClassifier.hash(Data(text.utf8))
    )
}

func withStore(_ body: (SQLiteClipStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipFlowSelfTest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(SQLiteClipStore(baseDirectory: directory))
}

do {
    let url = ClipClassifier.classify(text: "https://example.com/path?q={value}")
    try require(url.kind == .link && url.category == .link, "URL 必须优先判定为链接")

    let code = ClipClassifier.classify(text: "func greet() {\n  return \"你好\"\n}")
    try require(code.kind == .code && code.category == .text, "多行代码分类失败")

    try require(
        ClipClassifier.classify(text: "周四下午对接接口联调").kind == .text,
        "单行普通文字分类失败"
    )

    let longArticle = (0..<180)
        .map { "第\($0)段：渐进渲染需要保留每一段文字及其定义与意义。" }
        .joined(separator: "\n")
    let articleChunks = TextChunker.chunks(from: longArticle, targetLength: 120, maximumLength: 160)
    try require(articleChunks.count > 1, "长文章没有被分片")
    try require(
        articleChunks.map { $0.text + $0.trailingSeparator }.joined() == longArticle,
        "文章分片后没有完整保留原文"
    )
    try require(
        articleChunks.allSatisfy { $0.text.count <= 160 },
        "文章分片超过最大长度"
    )

    let unbrokenText = String(repeating: "🙂", count: 360)
    let unbrokenChunks = TextChunker.chunks(from: unbrokenText, targetLength: 90, maximumLength: 100)
    try require(
        unbrokenChunks.map { $0.text + $0.trailingSeparator }.joined() == unbrokenText,
        "无换行长文本分片损坏了 Unicode 字符"
    )

    try withStore { store in
        let clip = makeClip("same")
        try require(store.insert(clip) != nil, "首次插入失败")
        try require(store.insert(clip) == nil, "连续相同内容没有被去重")
        try require(store.itemCount() == 1, "去重后的记录数错误")
    }

    try withStore { store in
        guard let first = try store.insert(makeClip("first", date: Date(timeIntervalSince1970: 1))) else {
            throw SelfTestError.failed("无法插入首条记录")
        }
        _ = try store.insert(makeClip("second", date: Date(timeIntervalSince1970: 2)))
        try store.setFavorite(id: first.id, isFavorite: true)
        _ = try store.insert(makeClip("third", date: Date(timeIntervalSince1970: 3)), limit: 2)

        let items = try store.loadAll()
        try require(Set(items.map(\.title)) == Set(["first", "third"]), "数量上限没有淘汰最旧非收藏项")
        try require(items.first(where: { $0.id == first.id })?.isFavorite == true, "收藏项没有保留")
    }

    try require(
        AppVersion("v0.1.2")! > AppVersion("0.1.1")!,
        "更新版本比较失败"
    )
    try require(
        AppVersion("1.2.0")! == AppVersion("1.2")!,
        "版本号尾部零没有正确归一化"
    )

    let releaseJSON = """
    {
      "tag_name": "v0.1.2",
      "name": "Jaimo clip 0.1.2",
      "body": "修复与优化",
      "html_url": "https://github.com/Jaimo-so/Jaimo-clip/releases/tag/v0.1.2",
      "assets": [
        {
          "name": "Jaimo-clip-0.1.2-macOS-Apple-Silicon.dmg",
          "browser_download_url": "https://github.com/Jaimo-so/Jaimo-clip/releases/download/v0.1.2/Jaimo-clip-0.1.2-macOS-Apple-Silicon.dmg",
          "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        }
      ]
    }
    """
    let release = try JSONDecoder().decode(GitHubReleasePayload.self, from: Data(releaseJSON.utf8))
    let update = try release.availableUpdate(currentVersion: "0.1.1")
    try require(update?.version == "0.1.2", "GitHub Release 版本解析失败")
    try require(
        update?.expectedSHA256 == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "GitHub Release SHA-256 解析失败"
    )
    try require(
        try release.availableUpdate(currentVersion: "0.1.2") == nil,
        "相同版本不应提示更新"
    )

    print("Jaimo clip self-test passed: 14 checks")
} catch {
    fputs("Jaimo clip self-test failed: \(error)\n", stderr)
    exit(1)
}
