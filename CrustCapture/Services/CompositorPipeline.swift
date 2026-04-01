import CoreImage
import CoreGraphics
import AppKit

class CompositorPipeline {
    private let ciContext: CIContext

    init() {
        // Use Metal-backed context for GPU acceleration
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            ciContext = CIContext()
        }
    }

    /// Composites a single video frame with all effects applied.
    /// - Parameters:
    ///   - frame: The raw video frame as CIImage
    ///   - settings: Effect settings (background, corners, shadow, etc.)
    ///   - cursorPosition: Normalized cursor position (0-1), nil if not in frame
    ///   - isClick: Whether a click is happening at this frame
    ///   - clickIntensity: 0-1 intensity for click pulse animation
    ///   - zoom: Zoom state (centerX, centerY, scale)
    ///   - outputSize: The desired output frame size
    func composite(
        frame: CIImage,
        settings: EffectSettings,
        cursorPosition: CGPoint?,
        isClick: Bool,
        clickIntensity: CGFloat,
        zoom: (centerX: CGFloat, centerY: CGFloat, scale: CGFloat),
        outputSize: CGSize
    ) -> CIImage {
        let padding = settings.padding
        let cornerRadius = settings.cornerRadius
        let isCropped = settings.outputAspectRatio != .auto

        // For cropped ratios, use minimal padding so the recording fills the frame
        let effectivePadding = isCropped ? min(padding, 16) : padding

        // The recording fills the output minus padding
        let contentRect = CGRect(
            x: effectivePadding,
            y: effectivePadding,
            width: outputSize.width - effectivePadding * 2,
            height: outputSize.height - effectivePadding * 2
        )

        // Step 1: Apply zoom crop to the raw frame
        var processedFrame = frame
        if zoom.scale > 1.0 {
            processedFrame = applyZoom(
                to: processedFrame,
                centerX: zoom.centerX,
                centerY: zoom.centerY,
                scale: zoom.scale
            )
        }

        // Step 2: Scale frame to fill content rect
        let scaleX = contentRect.width / processedFrame.extent.width
        let scaleY = contentRect.height / processedFrame.extent.height
        // Auto: fit inside (letterbox). Cropped ratios: fill and overflow (cover)
        let scale = isCropped ? max(scaleX, scaleY) : min(scaleX, scaleY)
        processedFrame = processedFrame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center in content rect (overflowing parts get clipped at the end)
        let scaledWidth = processedFrame.extent.width
        let scaledHeight = processedFrame.extent.height
        let offsetX = contentRect.origin.x + (contentRect.width - scaledWidth) / 2
        let offsetY = contentRect.origin.y + (contentRect.height - scaledHeight) / 2
        processedFrame = processedFrame.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Step 3: Apply rounded corners (only if larger than native macOS window corners)
        let nativeCornerRadius: CGFloat = 10 * scale
        if cornerRadius > 0 && (cornerRadius * scale) > nativeCornerRadius {
            let roundedRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
            processedFrame = applyRoundedCorners(to: processedFrame, rect: roundedRect, radius: cornerRadius * scale)
        }

        // Step 4: Create background
        let background = createBackground(style: settings.background, size: outputSize)

        // Step 5: Add shadow (use a solid shape for shadow, not the frame with holes from native corners)
        var composited: CIImage
        if settings.shadowRadius > 0 {
            // Create a solid rounded rect for the shadow shape
            let shadowRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
            let shadowRadius = max(cornerRadius * scale, nativeCornerRadius)
            let shadowShape = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(settings.shadowOpacity)))
                .cropped(to: shadowRect)
                .applyingFilter("CIRoundedRectangleGenerator", parameters: [
                    "inputRadius": shadowRadius,
                    "inputExtent": CIVector(cgRect: shadowRect),
                    "inputColor": CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(settings.shadowOpacity))
                ])
                .cropped(to: shadowRect)
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: settings.shadowRadius
                ])
                .cropped(to: CGRect(origin: .zero, size: outputSize))

            composited = shadowShape.composited(over: background)
            composited = processedFrame.composited(over: composited)
        } else {
            composited = processedFrame.composited(over: background)
        }

        // Step 6: Draw cursor highlight
        if let pos = cursorPosition, settings.cursorStyle.highlightEnabled {
            composited = drawCursorHighlight(
                on: composited,
                position: pos,
                contentRect: CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight),
                style: settings.cursorStyle,
                isClick: isClick,
                clickIntensity: clickIntensity
            )
        }

        // Step 7: CRT effect
        if settings.crt.enabled {
            composited = applyCRT(
                to: composited,
                settings: settings.crt,
                contentRect: CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight),
                outputSize: outputSize
            )
        }

        return composited.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    // MARK: - Private

    private func applyZoom(to image: CIImage, centerX: CGFloat, centerY: CGFloat, scale: CGFloat) -> CIImage {
        let extent = image.extent
        let cropWidth = extent.width / scale
        let cropHeight = extent.height / scale

        // Center the crop on the zoom point, clamped to bounds
        var cropX = centerX * extent.width - cropWidth / 2
        var cropY = (1.0 - centerY) * extent.height - cropHeight / 2 // flip Y for CI coordinates

        cropX = max(0, min(cropX, extent.width - cropWidth))
        cropY = max(0, min(cropY, extent.height - cropHeight))

        let cropRect = CGRect(x: cropX + extent.origin.x, y: cropY + extent.origin.y, width: cropWidth, height: cropHeight)
        return image.cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
    }

    private func applyRoundedCorners(to image: CIImage, rect: CGRect, radius: CGFloat) -> CIImage {
        let roundedRect = CIImage(color: .white)
            .cropped(to: rect)
            .applyingFilter("CIRoundedRectangleGenerator", parameters: [
                "inputRadius": radius,
                "inputExtent": CIVector(cgRect: rect),
                "inputColor": CIColor.white
            ])
            .cropped(to: rect)

        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputMaskImageKey: roundedRect
        ])
    }

    private func createBackground(style: BackgroundStyle, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)

        switch style {
        case .solid(let color):
            let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
            let ciColor = CIColor(color: nsColor) ?? CIColor.black
            return CIImage(color: ciColor).cropped(to: rect)

        case .gradient(let startColor, let endColor, let angle):
            let nsStart = NSColor(startColor).usingColorSpace(.sRGB) ?? NSColor.black
            let nsEnd = NSColor(endColor).usingColorSpace(.sRGB) ?? NSColor.white
            let ciStart = CIColor(color: nsStart) ?? CIColor.black
            let ciEnd = CIColor(color: nsEnd) ?? CIColor.white

            let radians = angle * .pi / 180.0
            let dx = cos(radians) * Double(size.width)
            let dy = sin(radians) * Double(size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            return CIImage(color: ciStart).cropped(to: rect)
                .applyingFilter("CILinearGradient", parameters: [
                    "inputPoint0": CIVector(x: center.x - CGFloat(dx / 2), y: center.y - CGFloat(dy / 2)),
                    "inputPoint1": CIVector(x: center.x + CGFloat(dx / 2), y: center.y + CGFloat(dy / 2)),
                    "inputColor0": ciStart,
                    "inputColor1": ciEnd
                ])
                .cropped(to: rect)

        case .wallpaper(let name):
            if let nsImage = NSImage(named: name),
               let tiffData = nsImage.tiffRepresentation,
               let ciImage = CIImage(data: tiffData) {
                let scaleX = size.width / ciImage.extent.width
                let scaleY = size.height / ciImage.extent.height
                let scale = max(scaleX, scaleY)
                return ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        }
    }

    private func drawCursorHighlight(
        on image: CIImage,
        position: CGPoint,
        contentRect: CGRect,
        style: CursorStyle,
        isClick: Bool,
        clickIntensity: CGFloat
    ) -> CIImage {
        // Convert normalized position to pixel position within content rect
        let pixelX = contentRect.origin.x + position.x * contentRect.width
        let pixelY = contentRect.origin.y + (1.0 - position.y) * contentRect.height // flip Y

        var radius = style.highlightRadius
        var opacity = style.highlightOpacity

        // Pulse effect on click
        if isClick && style.clickPulseEnabled {
            radius += 15 * clickIntensity
            opacity = min(1.0, opacity + 0.3 * Double(clickIntensity))
        }

        let nsColor = NSColor(style.highlightColor).usingColorSpace(.sRGB) ?? NSColor.yellow
        let ciColor = CIColor(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            alpha: CGFloat(opacity)
        )

        let highlight = CIImage(color: ciColor)
            .cropped(to: CGRect(
                x: pixelX - radius,
                y: pixelY - radius,
                width: radius * 2,
                height: radius * 2
            ))
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: radius * 0.4
            ])

        return highlight.composited(over: image)
    }

    // MARK: - CRT Effect

    private func applyCRT(
        to image: CIImage,
        settings: CRTSettings,
        contentRect: CGRect,
        outputSize: CGSize
    ) -> CIImage {
        var result = image
        let rect = CGRect(origin: .zero, size: outputSize)

        // 1. Barrel distortion (screen curvature)
        if settings.curvature > 0 {
            let center = CIVector(x: outputSize.width / 2, y: outputSize.height / 2)
            result = result.applyingFilter("CIBumpDistortion", parameters: [
                kCIInputCenterKey: center,
                kCIInputRadiusKey: max(outputSize.width, outputSize.height) * 0.8,
                kCIInputScaleKey: -settings.curvature * 0.15
            ]).cropped(to: rect)
        }

        // 2. RGB chromatic aberration (offset R and B channels)
        if settings.rgbOffset > 0 {
            let offset = settings.rgbOffset

            // Shift red channel left, blue channel right
            let redShifted = result
                .transformed(by: CGAffineTransform(translationX: -offset, y: 0))
                .cropped(to: rect)
            let blueShifted = result
                .transformed(by: CGAffineTransform(translationX: offset, y: 0))
                .cropped(to: rect)

            // Extract channels using color matrix
            let redOnly = redShifted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            let greenOnly = result.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            let blueOnly = blueShifted.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])

            result = redOnly
                .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: greenOnly])
                .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blueOnly])
                .cropped(to: rect)
        }

        // 3. Scanlines
        if settings.scanlineIntensity > 0 {
            let lineHeight: CGFloat = 2.0
            let scanlines = CIFilter(name: "CIStripesGenerator", parameters: [
                "inputCenter": CIVector(x: 0, y: 0),
                "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: settings.scanlineIntensity),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
                "inputWidth": lineHeight,
                "inputSharpness": 1.0 as CGFloat
            ])!.outputImage!.cropped(to: rect)

            result = scanlines.composited(over: result).cropped(to: rect)
        }

        // 4. Vignette (darken edges)
        if settings.vignette > 0 {
            result = result.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: settings.vignette * 2.0,
                kCIInputRadiusKey: max(outputSize.width, outputSize.height) * 0.5
            ])
        }

        return result.cropped(to: rect)
    }

    /// Render a CIImage to a CVPixelBuffer for writing
    func render(_ image: CIImage, to pixelBuffer: CVPixelBuffer) {
        ciContext.render(image, to: pixelBuffer)
    }

    /// Render a CIImage to a CGImage for preview
    func renderToImage(_ image: CIImage) -> CGImage? {
        ciContext.createCGImage(image, from: image.extent)
    }
}
