
//
//  ContentView.swift
//  BFLabeler
//
//  Pixel-position mask labeling (true mask layer).
//
//  - Background shows BF preview (16-bit TIFF auto-BC -> 8-bit)
//  - One UInt16 mask per image (0..5 labels)
//  - All labels visible simultaneously as a 50% opacity overlay
//  - Painting in pixel coordinates (no vector strokes)
//  - Overlay rendered with NO interpolation (pixelated)
//  - Save writes ONLY the mask: <folder>/labels/<base>_mask.tif
//  - Reopening folder auto-loads existing masks
//

import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics

// MARK: - Main View

struct ContentView: View {
    private let labels: [UInt16] = [1, 2, 3, 4, 5]

    @State private var folderURL: URL?
    @State private var securityScopedFolderURL: URL?
    @State private var imageURLs: [URL] = []
    @State private var index: Int = 0

    // Current image preview (8-bit display)
    @State private var uiImage: UIImage?
    @State private var fluoroImage: UIImage?
    @State private var showFluoro: Bool = false
    @State private var bfOpacity: Double = 1.0
    @State private var fluoroOpacity: Double = 0.55
    @State private var maskOpacity: Double = 0.50
    @State private var imagePixelSize: CGSize = .zero

    // Current per-image mask (UInt16 labels, length = w*h)
    @State private var maskW: Int = 0
    @State private var maskH: Int = 0
    @State private var maskData: [UInt16] = []

    // Cache of masks across images
    private struct MaskCacheEntry {
        let w: Int
        let h: Int
        let data: [UInt16]
    }
    @State private var maskByImage: [String: MaskCacheEntry] = [:]

    // UI
    @State private var activeLabel: UInt16 = 1
    @State private var brushWidthPx: CGFloat = 6
    @State private var eraserMode: Bool = false
    @State private var pencilOnly: Bool = false
    @State private var autoFloodFill: Bool = false

    @State private var statusText: String = ""
    @State private var showPicker = false
    @State private var jumpFrameText: String = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button("Choose Folder") { showPicker = true }
                if let folderURL {
                    Text(folderURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !imageURLs.isEmpty {
                    Text("\(index+1)/\(imageURLs.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Frame", text: $jumpFrameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
#if canImport(UIKit)
                        .keyboardType(.numberPad)
#endif

                    Button("Jump") { jumpToFrame() }
                }
            }

            HStack(spacing: 12) {
                Text("Label:")
                Picker("", selection: $activeLabel) {
                    ForEach(labels, id: \.self) { v in
                        Text("\(v)").tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .disabled(eraserMode)

                Text("Brush (px)")
                Slider(value: $brushWidthPx, in: 1...15, step: 1)
                    .frame(width: 200)

                Spacer()

                Button(eraserMode ? "Eraser ✓" : "Eraser") { eraserMode.toggle() }

                Button(pencilOnly ? "Pencil Only ✓" : "Pencil Only") { pencilOnly.toggle() }

                Button(showFluoro ? "Fluoro ✓" : "Fluoro") { showFluoro.toggle() }

                Button(autoFloodFill ? "Auto Fill ✓" : "Auto Fill") { autoFloodFill.toggle() }

                VStack(alignment: .leading, spacing: 2) {
                    Text("BF \(Int(round(bfOpacity * 100)))%")
                        .font(.caption2)
                    Slider(value: $bfOpacity, in: 0...1)
                        .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fluoro \(Int(round(fluoroOpacity * 100)))%")
                        .font(.caption2)
                    Slider(value: $fluoroOpacity, in: 0...1)
                        .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mask \(Int(round(maskOpacity * 100)))%")
                        .font(.caption2)
                    Slider(value: $maskOpacity, in: 0...1)
                        .frame(width: 110)
                }

                Button("Prev") { prev() }.disabled(index == 0)
                Button("Next") { saveAndNext() }.disabled(index >= imageURLs.count - 1)
            }

            ZStack {
                if let uiImage {
                    GeometryReader { geo in
                        let fitted = aspectFitRect(imageSize: uiImage.size, in: geo.size)

                        // BF background preview
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .opacity(bfOpacity)

                        // Optional fluorescent layer (same fitted rect as BF)
                        if showFluoro, let fluoroImage {
                            Image(uiImage: fluoroImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .opacity(fluoroOpacity)
                        }

                        // Mask overlay + painter (only on fitted rect)
                        PixelMaskPainterRepresentable(
                            maskW: maskW,
                            maskH: maskH,
                            maskData: $maskData,
                            activeLabel: $activeLabel,
                            brushWidthPx: $brushWidthPx,
                            eraserMode: $eraserMode,
                            pencilOnly: $pencilOnly,
                            overlayOpacity: $maskOpacity
                        )
                        .frame(width: fitted.width, height: fitted.height)
                        .position(x: fitted.midX, y: fitted.midY)
                    }
                } else {
                    Text(folderURL == nil ? "Choose a folder with BF*.tif" : "Loading image…")
                        .foregroundStyle(.secondary)
                }
            }
            .background(Color(white: 0.96))
            .cornerRadius(12)
            .padding(.vertical, 6)

            HStack {
                Button("Clear Mask") { clearCurrentMask() }
                Spacer()
                Button("Save Mask TIFF") { saveMaskTiff() }
                    .disabled(uiImage == nil || folderURL == nil)
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .onAppear {
            if let url = folderURL {
                // Ensure access remains open during the session
                _ = beginSecurityScopedAccess(to: url)
            }
        }
        .onDisappear {
            endSecurityScopedAccess()
        }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in
                if let url {
                    // IMPORTANT: needed on real device for folder access
                    if beginSecurityScopedAccess(to: url) {
                        folderURL = url
                        loadFolder(url)
                    } else {
                        statusText = "Failed to access folder (permission). Try picking again."
                    }
                }
                showPicker = false
            }
        }
    }

    // MARK: - Security-scoped access (required on physical devices)

    private func beginSecurityScopedAccess(to url: URL) -> Bool {
        // If we already have an open security-scoped URL, close it first.
        if let existing = securityScopedFolderURL {
            existing.stopAccessingSecurityScopedResource()
            securityScopedFolderURL = nil
        }

        // Start access for this session
        let ok = url.startAccessingSecurityScopedResource()
        if ok {
            securityScopedFolderURL = url
        }
        return ok
    }

    private func endSecurityScopedAccess() {
        if let existing = securityScopedFolderURL {
            existing.stopAccessingSecurityScopedResource()
            securityScopedFolderURL = nil
        }
    }

    // MARK: - Navigation

    // Try common mask locations/names for a given image base name.
    private func candidateMaskURLs(folder: URL, imageBase: String) -> [URL] {
        // Current expected location
        let labelsDir = folder.appendingPathComponent("labels", isDirectory: true)

        // Also accept older/common alternatives without changing the save path
        let maskDir1 = folder.appendingPathComponent("mask", isDirectory: true)
        let maskDir2 = folder.appendingPathComponent("masks", isDirectory: true)

        return [
            // Canonical expected location/name
            labelsDir.appendingPathComponent("\(imageBase)_mask.tif"),
            labelsDir.appendingPathComponent("\(imageBase)_mask.tiff"),

            // Backward-compatible alternatives
            labelsDir.appendingPathComponent("\(imageBase)_label.tif"),
            labelsDir.appendingPathComponent("\(imageBase)_label.tiff"),
            labelsDir.appendingPathComponent("\(imageBase).tif"),
            labelsDir.appendingPathComponent("\(imageBase).tiff"),

            maskDir1.appendingPathComponent("\(imageBase)_mask.tif"),
            maskDir1.appendingPathComponent("\(imageBase)_mask.tiff"),
            maskDir1.appendingPathComponent("\(imageBase)_label.tif"),
            maskDir1.appendingPathComponent("\(imageBase)_label.tiff"),
            maskDir1.appendingPathComponent("\(imageBase).tif"),
            maskDir1.appendingPathComponent("\(imageBase).tiff"),

            maskDir2.appendingPathComponent("\(imageBase)_mask.tif"),
            maskDir2.appendingPathComponent("\(imageBase)_mask.tiff"),
            maskDir2.appendingPathComponent("\(imageBase)_label.tif"),
            maskDir2.appendingPathComponent("\(imageBase)_label.tiff"),
            maskDir2.appendingPathComponent("\(imageBase).tif"),
            maskDir2.appendingPathComponent("\(imageBase).tiff"),

            // Same-folder fallback
            folder.appendingPathComponent("\(imageBase)_mask.tif"),
            folder.appendingPathComponent("\(imageBase)_mask.tiff"),
            folder.appendingPathComponent("\(imageBase)_label.tif"),
            folder.appendingPathComponent("\(imageBase)_label.tiff"),
        ]
    }

    private func tryLoadMaskFromDisk(folder: URL, imageBase: String) -> MaskCacheEntry? {
        let fm = FileManager.default
        for url in candidateMaskURLs(folder: folder, imageBase: imageBase) {
            if fm.fileExists(atPath: url.path), let loaded = readUInt16LabelTiff(from: url) {
                return MaskCacheEntry(w: loaded.w, h: loaded.h, data: loaded.data)
            }
        }
        return nil
    }

    private func currentImageKey() -> String {
        guard !imageURLs.isEmpty else { return "" }
        return imageURLs[index].deletingPathExtension().lastPathComponent
    }

    private func stashCurrentMask() {
        guard !imageURLs.isEmpty else { return }
        let key = currentImageKey()
        if maskW > 0, maskH > 0, maskData.count == maskW*maskH {
            maskByImage[key] = MaskCacheEntry(w: maskW, h: maskH, data: maskData)
        }
    }

    private func prev() {
        guard index > 0 else { return }
        stashCurrentMask()
        index -= 1
        loadCurrentImage()
    }

    private func next() {
        guard index < imageURLs.count - 1 else { return }
        stashCurrentMask()
        index += 1
        loadCurrentImage()
    }

    private func saveAndNext() {
        guard index < imageURLs.count - 1 else { return }
        if autoFloodFill {
            maskData = floodFillEnclosures(in: maskData, width: maskW, height: maskH)
            stashCurrentMask()
        }
        saveMaskTiff()
        next()
    }
    // Fill enclosed holes independently for each nonzero label.
    private func floodFillEnclosures(in data: [UInt16], width: Int, height: Int) -> [UInt16] {
        guard width > 0, height > 0, data.count == width * height else { return data }
        var out = data
        for label in labels {
            out = fillHoles(for: label, in: out, width: width, height: height)
        }
        return out
    }

    // For one label, treat pixels == label as foreground. Any background region not connected
    // to the image border is an enclosed hole and gets filled with this label.
    private func fillHoles(for label: UInt16, in data: [UInt16], width: Int, height: Int) -> [UInt16] {
        guard width > 0, height > 0, data.count == width * height else { return data }

        let count = width * height
        var visited = Array(repeating: false, count: count)
        var result = data
        var queue: [Int] = []
        queue.reserveCapacity(max(width * 2 + height * 2, 16))
        var head = 0

        @inline(__always)
        func idx(_ x: Int, _ y: Int) -> Int { y * width + x }

        // Seed BFS with all border pixels that are NOT this label.
        if height > 0 {
            for x in 0..<width {
                let iTop = idx(x, 0)
                if !visited[iTop] && data[iTop] != label {
                    visited[iTop] = true
                    queue.append(iTop)
                }
                let iBot = idx(x, height - 1)
                if !visited[iBot] && data[iBot] != label {
                    visited[iBot] = true
                    queue.append(iBot)
                }
            }
        }
        if width > 0 && height > 2 {
            for y in 1..<(height - 1) {
                let iLeft = idx(0, y)
                if !visited[iLeft] && data[iLeft] != label {
                    visited[iLeft] = true
                    queue.append(iLeft)
                }
                let iRight = idx(width - 1, y)
                if !visited[iRight] && data[iRight] != label {
                    visited[iRight] = true
                    queue.append(iRight)
                }
            }
        }

        // 4-connected flood over non-label pixels reachable from border.
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % width
            let y = i / width

            if x > 0 {
                let j = i - 1
                if !visited[j] && data[j] != label {
                    visited[j] = true
                    queue.append(j)
                }
            }
            if x + 1 < width {
                let j = i + 1
                if !visited[j] && data[j] != label {
                    visited[j] = true
                    queue.append(j)
                }
            }
            if y > 0 {
                let j = i - width
                if !visited[j] && data[j] != label {
                    visited[j] = true
                    queue.append(j)
                }
            }
            if y + 1 < height {
                let j = i + width
                if !visited[j] && data[j] != label {
                    visited[j] = true
                    queue.append(j)
                }
            }
        }

        // Any non-label pixel not reached from the border is enclosed by this label.
        for i in 0..<count {
            if data[i] != label && !visited[i] {
                result[i] = label
            }
        }
        return result
    }

    private func jumpToFrame() {
        guard !imageURLs.isEmpty else { return }
        guard let oneBased = Int(jumpFrameText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusText = "Enter a valid frame number."
            return
        }

        let newIndex = oneBased - 1
        guard newIndex >= 0 && newIndex < imageURLs.count else {
            statusText = "Frame out of range. Enter 1–\(imageURLs.count)."
            return
        }

        stashCurrentMask()
        index = newIndex
        loadCurrentImage()
        statusText = "Jumped to frame \(oneBased)."
    }

    // MARK: - Folder / Image loading

    private func loadFolder(_ url: URL) {
        // On physical devices, folder reads require security-scoped access.
        if securityScopedFolderURL?.standardizedFileURL != url.standardizedFileURL {
            _ = beginSecurityScopedAccess(to: url)
        }
        statusText = "Scanning folder…"
        imageURLs = []
        index = 0
        uiImage = nil
        fluoroImage = nil

        maskW = 0
        maskH = 0
        maskData = []
        maskByImage.removeAll()

        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            statusText = "Failed to read folder."
            return
        }

        let tiffs = items.filter { u in
            let ext = u.pathExtension.lowercased()
            return ext == "tif" || ext == "tiff"
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        imageURLs = tiffs

        // Preload existing masks if present; otherwise create a blank cache entry for every BF image.
        for imgURL in imageURLs {
            let base = imgURL.deletingPathExtension().lastPathComponent

            if let entry = tryLoadMaskFromDisk(folder: url, imageBase: base) {
                maskByImage[base] = entry
                continue
            }

            // No matching mask on disk: create a blank one now so later navigation does not re-check disk.
            if let preview = readTiffPreview8bitAutoBC(from: imgURL) {
                let w = Int(preview.pixelSize.width)
                let h = Int(preview.pixelSize.height)
                if w > 0, h > 0 {
                    maskByImage[base] = MaskCacheEntry(
                        w: w,
                        h: h,
                        data: Array(repeating: 0, count: w * h)
                    )
                }
            }
        }

        statusText = "Found \(tiffs.count) TIFFs."
        loadCurrentImage()
    }

    private func loadCurrentImage() {
        guard !imageURLs.isEmpty else { return }
        let url = imageURLs[index]
        let key = url.deletingPathExtension().lastPathComponent

        if let preview = readTiffPreview8bitAutoBC(from: url) {
            uiImage = preview.image
            fluoroImage = loadMatchingFluoroPreview(for: url)
            imagePixelSize = preview.pixelSize

            let w = Int(preview.pixelSize.width)
            let h = Int(preview.pixelSize.height)

            if let cached = maskByImage[key], cached.w == w, cached.h == h {
                maskW = cached.w
                maskH = cached.h
                maskData = cached.data
            } else {
                maskW = w
                maskH = h
                maskData = Array(repeating: 0, count: w*h)
                maskByImage[key] = MaskCacheEntry(w: w, h: h, data: maskData)
            }

            statusText = "Loaded \(url.lastPathComponent) (\(w)x\(h))"
        } else {
            uiImage = nil
            fluoroImage = nil
            maskW = 0
            maskH = 0
            maskData = []
            statusText = "Failed to load \(url.lastPathComponent)"
        }
    }

    private func matchingFluoroURL(for bfURL: URL) -> URL? {
        let folder = bfURL.deletingLastPathComponent()
        let name = bfURL.deletingPathExtension().lastPathComponent

        // Match BF8 -> Fluoro8, BF08 -> Fluoro08, etc.
        if let m = name.range(of: #"^BF(\d+)$"#, options: .regularExpression) {
            let digits = String(name[m]).replacingOccurrences(of: "BF", with: "")
            let candidates = [
                folder.appendingPathComponent("Fluoro\(digits).tif"),
                folder.appendingPathComponent("Fluoro\(digits).tiff")
            ]
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // Fallback: try replacing a leading BF with Fluoro in the filename stem.
        if name.hasPrefix("BF") {
            let replaced = "Fluoro" + name.dropFirst(2)
            let candidates = [
                folder.appendingPathComponent("\(replaced).tif"),
                folder.appendingPathComponent("\(replaced).tiff")
            ]
            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func loadMatchingFluoroPreview(for bfURL: URL) -> UIImage? {
        guard let fluoroURL = matchingFluoroURL(for: bfURL) else { return nil }
        return readTiffPreview8bitAutoBC(from: fluoroURL)?.image
    }

    // MARK: - Mask ops

    private func clearCurrentMask() {
        guard maskW > 0, maskH > 0 else { return }
        maskData = Array(repeating: 0, count: maskW*maskH)
        stashCurrentMask()
    }

    private func saveMaskTiff() {
        guard let folderURL, !imageURLs.isEmpty else { return }
        let key = currentImageKey()

        if autoFloodFill {
            maskData = floodFillEnclosures(in: maskData, width: maskW, height: maskH)
        }
        stashCurrentMask()

        let outDir = folderURL.appendingPathComponent("labels", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let outURL = outDir.appendingPathComponent("\(key)_mask.tif")

        guard maskW > 0, maskH > 0, maskData.count == maskW*maskH else {
            statusText = "Invalid mask size."
            return
        }

        do {
            try writeUInt16TiffGray(label: maskData, width: maskW, height: maskH, to: outURL)
            statusText = "Saved mask: labels/\(outURL.lastPathComponent)"
        } catch {
            statusText = "Save failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Pixel Mask Painter (overlay + touch painting)

struct PixelMaskPainterRepresentable: UIViewRepresentable {
    let maskW: Int
    let maskH: Int
    @Binding var maskData: [UInt16]
    @Binding var activeLabel: UInt16
    @Binding var brushWidthPx: CGFloat
    @Binding var eraserMode: Bool
    @Binding var pencilOnly: Bool
    @Binding var overlayOpacity: Double

    func makeUIView(context: Context) -> PixelMaskPainterView {
        let v = PixelMaskPainterView()
        v.isOpaque = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: PixelMaskPainterView, context: Context) {
        uiView.pencilOnly = pencilOnly
        // Refresh the paint closure every update so it always uses current bindings/state.
        uiView.onPaint = { point in
            paint(at: point, viewSize: uiView.bounds.size)
            uiView.overlayImage = makeMaskOverlayImage(maskW: maskW, maskH: maskH, maskData: maskData, overlayOpacity: overlayOpacity)
            uiView.setNeedsDisplay()
        }

        uiView.overlayImage = makeMaskOverlayImage(maskW: maskW, maskH: maskH, maskData: maskData, overlayOpacity: overlayOpacity)
        uiView.setNeedsDisplay()
    }

    private func paint(at point: CGPoint, viewSize: CGSize) {
        guard maskW > 0, maskH > 0, maskData.count == maskW*maskH else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let px = Int((point.x / viewSize.width) * CGFloat(maskW))
        let py = Int((point.y / viewSize.height) * CGFloat(maskH))
        if px < 0 || px >= maskW || py < 0 || py >= maskH { return }

        let r = max(0, Int(round((brushWidthPx - 1) / 2.0)))
        let r2 = r*r
        let value: UInt16 = eraserMode ? 0 : activeLabel

        var newData = maskData

        if r == 0 {
            newData[py*maskW + px] = value
            maskData = newData
            return
        }

        let x0 = max(0, px - r)
        let x1 = min(maskW - 1, px + r)
        let y0 = max(0, py - r)
        let y1 = min(maskH - 1, py + r)

        for y in y0...y1 {
            let dy = y - py
            let dy2 = dy*dy
            for x in x0...x1 {
                let dx = x - px
                if dx*dx + dy2 <= r2 {
                    newData[y*maskW + x] = value
                }
            }
        }

        maskData = newData
    }
}

final class PixelMaskPainterView: UIView {
    var overlayImage: UIImage?
    var onPaint: ((CGPoint) -> Void)?
    var pencilOnly: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = true
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let overlayImage else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            overlayImage.draw(in: rect)
            return
        }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        overlayImage.draw(in: rect)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        if pencilOnly && t.type != .pencil { return }
        onPaint?(t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        if pencilOnly && t.type != .pencil { return }
        onPaint?(t.location(in: self))
    }
}

private func makeMaskOverlayImage(maskW: Int, maskH: Int, maskData: [UInt16], overlayOpacity: Double) -> UIImage? {
    guard maskW > 0, maskH > 0, maskData.count == maskW*maskH else { return nil }
    let n = maskW * maskH

    var rgba = Data(count: n * 4)
    rgba.withUnsafeMutableBytes { raw in
        let p = raw.bindMemory(to: UInt8.self)
        for i in 0..<n {
            let rawV = maskData[i]
            // Normalize: keep 0..5; recover byte-swapped 16-bit labels (256,512,...) -> 1..5;
            // otherwise treat any nonzero as label 1 (binary masks like 0/255).
            let v: UInt16
            if rawV <= 5 {
                v = rawV
            } else if (rawV & 0x00FF) == 0 {
                let hi = rawV >> 8
                v = (hi <= 5) ? hi : 1
            } else {
                v = (rawV == 0) ? 0 : 1
            }
            let base = i * 4
            let (r,g,b,a) = labelRGBA(v)
            let scaledAlpha = UInt8(max(0, min(255, Int(round(Double(a) * overlayOpacity)))))
            p[base+0] = r
            p[base+1] = g
            p[base+2] = b
            p[base+3] = scaledAlpha
        }
    }

    guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let cg = CGImage(
        width: maskW,
        height: maskH,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: maskW * 4,
        space: cs,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else { return nil }

    return UIImage(cgImage: cg)
}

// MARK: - Folder Picker

struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

// MARK: - Helpers

private struct TiffPreview {
    let image: UIImage
    let pixelSize: CGSize
}

// Read a 16-bit TIFF and produce an 8-bit grayscale preview by mapping the full image min/max to 0..255
private func readTiffPreview8bitAutoBC(from url: URL) -> TiffPreview? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

    let w = cg.width
    let h = cg.height
    let pixelSize = CGSize(width: w, height: h)

    if cg.bitsPerComponent <= 8 {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    if cg.colorSpace?.model != .monochrome || cg.bitsPerPixel < 16 {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    guard let dataProvider = cg.dataProvider, let cfData = dataProvider.data else {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    let data = cfData as Data
    let expectedBytes = w * h * 2
    if data.count < expectedBytes {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    // Fiji "Reset" brightness/contrast behavior: use full image min/max.
    var lo: UInt16 = 65535
    var hi: UInt16 = 0

    data.withUnsafeBytes { raw in
        let p = raw.bindMemory(to: UInt16.self)
        let n = w * h
        for i in 0..<n {
            let v = p[i]
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
    }

    if hi <= lo {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    var out = Data(count: w * h)
    out.withUnsafeMutableBytes { outRaw in
        let dst = outRaw.bindMemory(to: UInt8.self)
        data.withUnsafeBytes { inRaw in
            let src16 = inRaw.bindMemory(to: UInt16.self)
            let n = w * h
            let loF = Double(lo)
            let hiF = Double(hi)
            let scale = 255.0 / (hiF - loF)
            for i in 0..<n {
                let v = Double(src16[i])
                let cl = min(max(v, loF), hiF)
                let u8 = UInt8(min(max(Int((cl - loF) * scale + 0.5), 0), 255))
                dst[i] = u8
            }
        }
    }

    guard let provider = CGDataProvider(data: out as CFData) else {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    let cs = CGColorSpaceCreateDeviceGray()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

    guard let outCG = CGImage(
        width: w,
        height: h,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: w,
        space: cs,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        return TiffPreview(image: UIImage(cgImage: cg), pixelSize: pixelSize)
    }

    return TiffPreview(image: UIImage(cgImage: outCG), pixelSize: pixelSize)
}

private func writeUInt16TiffGray(label: [UInt16], width: Int, height: Int, to url: URL) throws {
    guard label.count == width * height else { throw NSError(domain: "LabelSize", code: 1) }

    let bytesPerRow = width * MemoryLayout<UInt16>.size
    let data = Data(bytes: label, count: label.count * 2)

    guard let provider = CGDataProvider(data: data as CFData) else {
        throw NSError(domain: "CGDataProvider", code: 2)
    }

    let cs = CGColorSpaceCreateDeviceGray()
    let bitmapInfo: CGBitmapInfo = [
        .byteOrder16Little,
        CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    ]

    guard let cg = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 16,
        bitsPerPixel: 16,
        bytesPerRow: bytesPerRow,
        space: cs,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw NSError(domain: "CGImageCreate", code: 3)
    }

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
        throw NSError(domain: "CGImageDestination", code: 4)
    }

    let props: [CFString: Any] = [
        kCGImagePropertyTIFFCompression: 1
    ]

    CGImageDestinationAddImage(dest, cg, props as CFDictionary)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "CGImageDestinationFinalize", code: 5)
    }
}

private func readUInt16LabelTiff(from url: URL) -> (w: Int, h: Int, data: [UInt16])? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }

    let w = cg.width
    let h = cg.height
    guard w > 0, h > 0 else { return nil }

    // Decode by drawing into a known pixel format to avoid TIFF compression/byte-order surprises.
    let cs = CGColorSpaceCreateDeviceGray()

    // 16-bit grayscale destination buffer
    let bytesPerRow16 = w * 2
    var buf16 = [UInt16](repeating: 0, count: w * h)

    let bitmapInfo16: CGBitmapInfo = [
        CGBitmapInfo.byteOrder16Little,
        CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    ]

    let ok16: Bool = buf16.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(
            data: base,
            width: w,
            height: h,
            bitsPerComponent: 16,
            bytesPerRow: bytesPerRow16,
            space: cs,
            bitmapInfo: bitmapInfo16.rawValue
        ) else { return false }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }

    if ok16 {
        var out = buf16
        // Normalize: keep 0..5; recover byte-swapped 16-bit labels (256,512,...) -> 1..5;
        // otherwise treat any nonzero as label 1 (binary masks like 0/255).
        for i in 0..<(w*h) {
            let v = out[i]
            if v <= 5 { continue }
            if (v & 0x00FF) == 0 {
                let hi = v >> 8
                out[i] = (hi <= 5) ? hi : 1
            } else {
                out[i] = (v == 0) ? 0 : 1
            }
        }
        return (w, h, out)
    }

    // Fallback: decode as 8-bit gray
    let bytesPerRow8 = w
    var buf8 = [UInt8](repeating: 0, count: w * h)
    let bitmapInfo8: CGBitmapInfo = [
        CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    ]

    let ok8: Bool = buf8.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return false }
        guard let ctx = CGContext(
            data: base,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow8,
            space: cs,
            bitmapInfo: bitmapInfo8.rawValue
        ) else { return false }

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }

    if ok8 {
        var out = [UInt16](repeating: 0, count: w * h)
        for i in 0..<(w*h) {
            let v = buf8[i]
            if v <= 5 { out[i] = UInt16(v) }
            else { out[i] = (v == 0) ? 0 : 1 }
        }
        return (w, h, out)
    }

    return nil
}

private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let w = imageSize.width * scale
    let h = imageSize.height * scale
    let x = (container.width - w) / 2
    let y = (container.height - h) / 2
    return CGRect(x: x, y: y, width: w, height: h)
}

private func labelRGBA(_ v: UInt16) -> (UInt8, UInt8, UInt8, UInt8) {
    switch v {
    case 1: return (255, 59, 48, 127)
    case 2: return (52, 199, 89, 127)
    case 3: return (0, 122, 255, 127)
    case 4: return (255, 149, 0, 127)
    case 5: return (175, 82, 222, 127)
    default: return (0, 0, 0, 0)
    }
}
