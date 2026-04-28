import CoreGraphics
import CoreVideo
import Vision

/// 一页扫描得到的文字区块（Vision 坐标系：归一化、原点在左下）。
struct ScannedTextBlock: Identifiable, Equatable {
    let id: UUID
    let text: String
    let boundingBox: CGRect

    init(text: String, boundingBox: CGRect) {
        self.id = UUID()
        self.text = text
        self.boundingBox = boundingBox
    }
}

enum PageTextScanService {
    /// 对当前帧做文字检测；相邻行会在版式上合并为「段落」区块（便于整段点读）。
    static func recognizeBlocks(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) throws -> [ScannedTextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = [
            "zh-Hans", "zh-Hant", "en-US",
        ]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        var lines: [(text: String, box: CGRect)] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let t = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            lines.append((t, observation.boundingBox))
        }
        // 自上而下（Vision：midY 大在上）
        lines.sort { $0.box.midY > $1.box.midY }

        let merged = mergeLinesIntoParagraphBlocks(lines)
        return resolveNonOverlappingBlocks(merged, separation: 0.0045)
    }

    // MARK: - 区块不相交（避免热区叠在一起无法点选）

    /// 阅读顺序优先：靠前的区块保留面积，靠后的在与前者相交时裁掉重叠部分，保证框两两不相交（留间隙）。
    private static func resolveNonOverlappingBlocks(_ blocks: [ScannedTextBlock], separation: CGFloat) -> [ScannedTextBlock] {
        guard blocks.count > 1 else { return blocks }

        let ordered = blocks.sorted { a, b in
            let ra = a.boundingBox
            let rb = b.boundingBox
            if abs(ra.midY - rb.midY) > 0.012 {
                return ra.midY > rb.midY
            }
            return ra.minX < rb.minX
        }

        var placed: [CGRect] = []
        var result: [ScannedTextBlock] = []

        let minW: CGFloat = 0.014
        let minH: CGFloat = 0.012

        for block in ordered {
            var rect = block.boundingBox
            for _ in 0..<16 {
                var progressed = false
                for p in placed where rect.intersects(p) {
                    guard let clipped = largestAxisAlignedSubrect(of: rect, avoiding: p, gap: separation) else {
                        rect = .zero
                        progressed = true
                        break
                    }
                    rect = clipped
                    progressed = true
                }
                if rect.width < minW || rect.height < minH { break }
                if !progressed { break }
            }

            guard rect.width >= minW, rect.height >= minH else { continue }

            placed.append(rect)
            result.append(ScannedTextBlock(text: block.text, boundingBox: rect))
        }

        return result
    }

    /// 在 `container` 内取与 `obstacle`（外扩 gap）不相交的最大轴对齐子矩形，优先保留更大面积（四向条带）。
    private static func largestAxisAlignedSubrect(
        of container: CGRect,
        avoiding obstacle: CGRect,
        gap: CGFloat
    ) -> CGRect? {
        let f = obstacle.insetBy(dx: -gap, dy: -gap)
        if !container.intersects(f) {
            return container
        }

        var best: CGRect?
        var bestArea: CGFloat = 0
        let r = container

        let bottomTop = min(r.maxY, f.minY - gap)
        let hBottom = bottomTop - r.minY
        if hBottom >= 0.008 {
            let c = CGRect(x: r.minX, y: r.minY, width: r.width, height: hBottom)
            pushIfLarger(&best, &bestArea, c)
        }

        let topY = max(r.minY, f.maxY + gap)
        let hTop = r.maxY - topY
        if hTop >= 0.008 {
            let c = CGRect(x: r.minX, y: topY, width: r.width, height: hTop)
            pushIfLarger(&best, &bestArea, c)
        }

        let rightOfLeft = min(r.maxX, f.minX - gap)
        let wLeft = rightOfLeft - r.minX
        if wLeft >= 0.008 {
            let c = CGRect(x: r.minX, y: r.minY, width: wLeft, height: r.height)
            pushIfLarger(&best, &bestArea, c)
        }

        let leftOfRight = max(r.minX, f.maxX + gap)
        let wRight = r.maxX - leftOfRight
        if wRight >= 0.008 {
            let c = CGRect(x: leftOfRight, y: r.minY, width: wRight, height: r.height)
            pushIfLarger(&best, &bestArea, c)
        }

        return best
    }

    private static func pushIfLarger(_ best: inout CGRect?, _ bestArea: inout CGFloat, _ candidate: CGRect) {
        let a = candidate.width * candidate.height
        if a > bestArea {
            best = candidate.standardized
            bestArea = a
        }
    }

    /// 将行距很小、左右对齐相近的相邻行并为一段；标题与正文之间因行距大不会合并。
    private static func mergeLinesIntoParagraphBlocks(_ lines: [(text: String, box: CGRect)]) -> [ScannedTextBlock] {
        guard !lines.isEmpty else { return [] }

        var result: [ScannedTextBlock] = []
        var group: [(text: String, box: CGRect)] = [lines[0]]

        for i in 1..<lines.count {
            let prev = group.last!
            let curr = lines[i]
            if shouldMergeLineIntoParagraph(upper: prev, lower: curr) {
                group.append(curr)
            } else {
                result.append(makeBlock(from: group))
                group = [curr]
            }
        }
        result.append(makeBlock(from: group))
        return result
    }

    /// `upper` 在画面上方（midY 更大），`lower` 为下一行。
    private static func shouldMergeLineIntoParagraph(
        upper: (text: String, box: CGRect),
        lower: (text: String, box: CGRect)
    ) -> Bool {
        let a = upper.box
        let b = lower.box
        let verticalGap = a.minY - b.maxY
        let lineH = max(min(a.height, b.height), 0.001)
        let lineHMax = max(a.height, b.height)

        // 歌词/教材：行间距有时较大（插图、行距），上限放宽到约 1.5～2 行高
        let maxGapGenerous = max(0.018, 1.55 * lineH)

        guard verticalGap <= maxGapGenerous else { return false }

        // --- 主路径：左缘对齐 + 行高同一量级（适合英文各行宽度差很大的情况）---
        let leftEdgeDelta = abs(a.minX - b.minX)
        let heightRatio = lineHMax / lineH
        let leftAlignedBody = leftEdgeDelta <= 0.065 && heightRatio <= 2.35
        if leftAlignedBody, verticalGap <= maxGapGenerous {
            return true
        }

        // --- 备选：横向重叠仍较高（标题区、居中句）---
        let maxGapTight = max(0.012, 1.05 * lineH)
        guard verticalGap <= maxGapTight else { return false }

        let overlap = horizontalOverlapRatio(a, b)
        guard overlap >= 0.07 else { return false }

        let cx = abs(a.midX - b.midX)
        guard cx <= max(a.width, b.width) * 0.52 else { return false }

        return true
    }

    private static func horizontalOverlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let left = max(a.minX, b.minX)
        let right = min(a.maxX, b.maxX)
        let w = right - left
        guard w > 0 else { return 0 }
        let m = min(a.width, b.width)
        return m > 0 ? w / m : 0
    }

    private static func makeBlock(from group: [(text: String, box: CGRect)]) -> ScannedTextBlock {
        let boxes = group.map(\.box)
        let union = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
        let text = group.map(\.text).joined(separator: "\n")
        return ScannedTextBlock(text: text, boundingBox: union)
    }
}

enum PixelBufferCopy {
    static func deepCopy(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(src)
        let h = CVPixelBufferGetHeight(src)
        let format = CVPixelBufferGetPixelFormatType(src)
        var dst: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, format, nil, &dst)
        guard status == kCVReturnSuccess, let dst else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
        }

        guard let sb = CVPixelBufferGetBaseAddress(src), let db = CVPixelBufferGetBaseAddress(dst) else { return nil }
        let size = CVPixelBufferGetDataSize(src)
        memcpy(db, sb, size)
        return dst
    }
}
