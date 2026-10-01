import UIKit
import Vision

enum ImageOps {
    static func qr(_ text: String, size: Int) throws -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw ToolFailure("这台设备生成不了二维码")
        }
        let data = text.data(using: .utf8) ?? Data()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = filter.outputImage else { throw ToolFailure("二维码生成失败") }
        let side = CGFloat(max(120, min(size, 1200)))
        let scaled = out.transformed(by: CGAffineTransform(scaleX: side / out.extent.width,
                                                           y: side / out.extent.height))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else {
            throw ToolFailure("二维码渲染失败")
        }
        let img = UIImage(cgImage: cg)
        guard let d = img.pngData() else { throw ToolFailure("二维码存成 PNG 失败") }
        return d
    }

    @MainActor
    static func ocr(path: String) async throws -> String {
        let url = try FileStore.shared.url(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ToolFailure("找不到图片：\(path)")
        }
        guard let img = UIImage(contentsOfFile: url.path), let cg = img.cgImage else {
            throw ToolFailure("这个文件不是能识别的图片")
        }
        return try await withCheckedThrowingContinuation { cont in
            let req = VNRecognizeTextRequest { r, e in
                if let e { cont.resume(throwing: ToolFailure("识图失败：\(e.localizedDescription)")); return }
                let obs = (r.results as? [VNRecognizedTextObservation]) ?? []
                let lines = obs.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                cont.resume(returning: text.isEmpty ? "图上没识别出文字" : text)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["zh-Hans", "en-US", "zh-Hant", "ja", "ko"]
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                do { try handler.perform([req]) } catch { cont.resume(throwing: ToolFailure("识图失败：\(error.localizedDescription)")) }
            }
        }
    }

    static func jpegDownscale(_ image: UIImage, maxSide: CGFloat = 1280, quality: CGFloat = 0.72) -> Data {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: fmt)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var q = quality
        var data = resized.jpegData(compressionQuality: q) ?? Data()
        while data.count > 900_000, q > 0.3 {
            q -= 0.1
            data = resized.jpegData(compressionQuality: q) ?? data
        }
        return data
    }
}
