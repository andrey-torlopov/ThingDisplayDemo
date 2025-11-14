import Metal
import MetalKit
import simd

struct Uniforms {
    var modelMatrix: float4x4
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
    var color: SIMD4<Float>
    var cameraPosition: SIMD3<Float>
}

class MetalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!

    var cells: [Cell] = []
    var time: Float = 0

    // Animation control
    var isAnimationRunning: Bool = false
    private var animationStartTime: Float = 0

    // For label positioning
    var onCellPositionsUpdated: (([CellLabelData]) -> Void)?
    var onAnimationComplete: (() -> Void)?
    private var viewSize: CGSize = .zero
    private var aspectRatio: Float = 1.0

    // Target cell for invader
    private var targetHealthyCellIndex: Int = 0

    // Cell size expressed in normalized world coordinates (0...1 range)
    private var cellRadius: Float = 0.1

    // Layout constants in screen-normalized coordinates (0...1)
    private let healthyCellNormalizedPositions: [SIMD2<Float>] = [
        SIMD2<Float>(0.28, 0.35),
        SIMD2<Float>(0.28, 0.65)
    ]
    private let invaderNormalizedStart = SIMD2<Float>(0.58, 0.5)
    private let divisionTargetsNormalized: [[SIMD2<Float>]] = [
        [SIMD2<Float>(0.22, 0.30), SIMD2<Float>(0.36, 0.42)],
        [SIMD2<Float>(0.22, 0.60), SIMD2<Float>(0.36, 0.72)]
    ]

    init?(metalView: MTKView) {
        print("🔧 MetalRenderer init started")

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ FAILED: Could not create Metal device")
            return nil
        }
        print("✅ Metal device created")

        guard let commandQueue = device.makeCommandQueue() else {
            print("❌ FAILED: Could not create command queue")
            return nil
        }
        print("✅ Command queue created")

        self.device = device
        self.commandQueue = commandQueue

        super.init()

        metalView.device = device
        metalView.delegate = self
        metalView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalView.depthStencilPixelFormat = .depth32Float
        print("✅ MTKView configured")

        buildPipeline(metalView: metalView)
        print("✅ Pipeline built")

        buildDepthStencilState()
        print("✅ Depth stencil state built")

        setupCells()
        print("✅ Cells setup complete")

        print("🎉 MetalRenderer initialization complete!")
    }

    func buildPipeline(metalView: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load Metal library")
        }

        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        // Vertex descriptor
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride * 2

        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
    }

    func buildDepthStencilState() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    func setupCells() {
        // Get initial aspect ratio estimate (will be updated in mtkView)
        // For iPhone portrait: aspect ≈ 0.46, for landscape ≈ 2.16
        // We'll use a safe default and update positions dynamically

        // Two healthy cells (blue) - positioned on the left side
        // These positions will be updated based on actual aspect ratio
        let healthyCell1 = Cell(
            position: SIMD3<Float>(0, 0, 0),
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        let healthyCell2 = Cell(
            position: SIMD3<Float>(0, 0, 0),
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        // Invader cell (red-orange, angular) - positioned on the right side
        let invaderCell = Cell(
            position: SIMD3<Float>(0, 0, 0),
            color: SIMD4<Float>(0.9, 0.3, 0.2, 0.9),
            type: .invader,
            device: device
        )

        cells = [healthyCell1, healthyCell2, invaderCell]

        applyBaseLayout()

        // Randomly choose target healthy cell (0 or 1)
        targetHealthyCellIndex = Int.random(in: 0...1)
    }

    private func worldPosition(normalizedX: Float, normalizedY: Float) -> SIMD3<Float> {
        return SIMD3<Float>(normalizedX * aspectRatio, normalizedY, 0)
    }

    private func worldPosition(for normalized: SIMD2<Float>) -> SIMD3<Float> {
        return worldPosition(normalizedX: normalized.x, normalizedY: normalized.y)
    }

    private func applyBaseLayout() {
        guard cells.count == 3 else { return }

        // Healthy cells - 20% smaller
        let healthyCellScale = cellRadius * 0.8
        for index in 0..<2 {
            let position = worldPosition(for: healthyCellNormalizedPositions[index])
            cells[index].position = position
            cells[index].initialPosition = position
            cells[index].scale = healthyCellScale
            cells[index].baseScale = healthyCellScale
        }

        // Invader cell - 30% larger
        let invaderScale = cellRadius * 1.3
        let invaderPosition = worldPosition(for: invaderNormalizedStart)
        cells[2].position = invaderPosition
        cells[2].initialPosition = invaderPosition
        cells[2].scale = invaderScale
        cells[2].baseScale = invaderScale
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = size

        guard size.height > 0 else { return }

        let previousAspect = aspectRatio
        let previousRadius = cellRadius

        aspectRatio = max(Float(size.width / size.height), 0.0001)

        let baseRadius: Float = 0.12
        let leftMargin = worldPosition(for: healthyCellNormalizedPositions[0]).x
        let rightMargin = aspectRatio - worldPosition(for: invaderNormalizedStart).x
        let safeHorizontalRadius = min(leftMargin, rightMargin) * 0.85
        cellRadius = max(0.075, min(baseRadius, safeHorizontalRadius))

        let aspectScale = previousAspect > 0 ? aspectRatio / previousAspect : 1.0
        let radiusScale = previousRadius > 0 ? cellRadius / previousRadius : 1.0

        for cell in cells {
            cell.position.x *= aspectScale
            cell.initialPosition.x *= aspectScale
            cell.scale *= radiusScale
            cell.baseScale *= radiusScale
        }
    }

    func draw(in view: MTKView) {
        // Only increment time if animation is running
        if isAnimationRunning {
            let oldTime = time
            time += 1.0 / 60.0

            // Log first few frames to verify animation starts
            if time < 0.5 {
                print("🎞️ Frame update. Time: \(String(format: "%.3f", oldTime)) → \(String(format: "%.3f", time)), isAnimationRunning: \(isAnimationRunning)")
            }
        } else {
            // Log when animation is NOT running
            if Int.random(in: 0..<120) == 0 {
                print("⏸️ Animation NOT running. isAnimationRunning: \(isAnimationRunning)")
            }
        }
        updateCells()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)

        // Use orthographic projection that maps 0...aspect in X and 0...1 in Y to the viewport
        let projectionMatrix = float4x4(
            orthographicWithLeft: 0,
            right: aspectRatio,
            bottom: 0,
            top: 1,
            near: -1,
            far: 1
        )

        // Camera looking straight down (2D view) with identity view matrix
        let cameraPosition = SIMD3<Float>(aspectRatio * 0.5, 0.5, 1.0)
        let viewMatrix = matrix_identity_float4x4

        // Render all cells
        for cell in cells {
            cell.render(encoder: renderEncoder,
                       projectionMatrix: projectionMatrix,
                       viewMatrix: viewMatrix,
                       cameraPosition: cameraPosition)
        }

        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()

        // Update label positions
        updateLabelPositions(projectionMatrix: projectionMatrix, viewMatrix: viewMatrix, viewSize: view.bounds.size)
    }

    func updateLabelPositions(projectionMatrix: float4x4, viewMatrix: float4x4, viewSize: CGSize) {
        var labelData: [CellLabelData] = []

        for (index, cell) in cells.enumerated() {
            // Convert 3D position to screen coordinates
            let worldPos = SIMD4<Float>(cell.position.x, cell.position.y, cell.position.z, 1.0)
            let viewPos = viewMatrix * worldPos
            let clipPos = projectionMatrix * viewPos

            // Perspective divide
            let ndcX = clipPos.x / clipPos.w
            let ndcY = clipPos.y / clipPos.w

            // Convert to screen coordinates
            let screenX = (ndcX + 1.0) * 0.5 * Float(viewSize.width)
            let screenY = (1.0 - (ndcY + 1.0) * 0.5) * Float(viewSize.height)

            // Create two-line labels
            let label: String
            if index < 2 {
                // Healthy cells (indices 0 and 1)
                label = ">CELL\n>DOG"
            } else {
                // Invader cell (index 2)
                label = cell.type == .invader ? ">CELL\n>INTRUDER" : ">CELL\n>DOG"
            }

            labelData.append(CellLabelData(label: label, screenPosition: CGPoint(x: CGFloat(screenX), y: CGFloat(screenY))))
        }

        onCellPositionsUpdated?(labelData)
    }

    func startAnimation() {
        print("🎬 startAnimation() called")
        isAnimationRunning = true
        resetCells()
        print("✅ Animation started. isAnimationRunning: \(isAnimationRunning), time: \(time)")
    }

    func resetCells() {
        print("🔄 resetCells() called")

        // Reset time FIRST before changing states
        time = 0

        // Reset all cells to initial state (normalized screen coordinates)
        cells[0].animationState = .moving
        cells[1].animationState = .moving
        cells[2].animationState = .moving

        applyBaseLayout()

        cells[0].color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)
        cells[0].rotation = 0

        cells[1].color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)
        cells[1].rotation = 0

        cells[2].color = SIMD4<Float>(0.9, 0.3, 0.2, 0.9)
        cells[2].type = .invader
        cells[2].createGeometry(device: device)
        // Rotate invader to show its angular shape better (30 degrees)
        cells[2].rotation = .pi / 6.0

        // Choose new random target
        targetHealthyCellIndex = Int.random(in: 0...1)

        print("📊 Reset complete. Target cell: \(targetHealthyCellIndex), cells states: \(cells.map { $0.animationState })")
        print("   Cell[0] pos: \(cells[0].position), state: \(cells[0].animationState)")
        print("   Cell[1] pos: \(cells[1].position), state: \(cells[1].animationState)")
        print("   Cell[2] pos: \(cells[2].position), state: \(cells[2].animationState)")
        print("   AspectRatio: \(aspectRatio), CellRadius: \(cellRadius)")
    }

    func updateCells() {
        guard cells.count >= 3 else { return }

        // Update all cells (for floating animation)
        for cell in cells {
            cell.update(time: time)
        }

        // Only process animation state machine if animation is running
        if !isAnimationRunning {
            return
        }

        let targetCell = cells[targetHealthyCellIndex]
        let invaderCell = cells[2]

        // Debug log - verbose for first 3 seconds, then every second
        if time < 3.0 || Int(time * 60.0).isMultiple(of: 60) {
            print("⏱️ Animation running. Time: \(String(format: "%.2f", time)), Target[\(targetHealthyCellIndex)] state: \(targetCell.animationState), Invader state: \(invaderCell.animationState)")
        }

        // Animation state machine
        if targetCell.animationState == .moving && invaderCell.animationState == .moving {
            // Move invader towards target healthy cell with acceleration
            let moveDuration: Float = 2.5
            let moveProgress = min(time / moveDuration, 1.0)

            // Apply easing for more dramatic approach
            let easedProgress = easeInOutCubic(moveProgress)

            // Invader moves to target from position (0.58, 0.5) in screen space
            let startPos = worldPosition(for: invaderNormalizedStart)
            let targetPos = targetCell.initialPosition  // Use initial position, not current (which has floating)
            invaderCell.position = mix(startPos, targetPos, t: easedProgress)

            // Scale invader slightly as it approaches (getting ready to attack)
            let approachScale = 1.0 + sin(moveProgress * .pi) * 0.15
            invaderCell.scale = cellRadius * approachScale
            invaderCell.baseScale = cellRadius * approachScale

            let distance = simd_distance(targetPos, invaderCell.position)

            // Log progress during movement
            if time < 3.0 && Int(time * 60.0) % 30 == 0 {
                print("   Moving phase: progress=\(String(format: "%.2f", moveProgress)), distance=\(String(format: "%.3f", distance))")
            }
            if distance < 0.05 || moveProgress >= 1.0 {
                print("🔄 TRANSITION: moving → merging. Distance: \(String(format: "%.3f", distance)), Progress: \(String(format: "%.2f", moveProgress))")
                targetCell.animationState = .merging
                invaderCell.animationState = .merging
                targetCell.mergeStartTime = time
                invaderCell.mergeStartTime = time
            }
        } else if targetCell.animationState == .merging && invaderCell.animationState == .merging {
            // Absorption animation - invader absorbs healthy cell
            let mergeDuration: Float = 2.0
            let mergeProgress = (time - targetCell.mergeStartTime) / mergeDuration
            let easedMerge = easeInOutCubic(mergeProgress)

            if mergeProgress < 1.0 {
                // Invader stays in place, healthy cell shrinks and is absorbed
                let mergePos = invaderCell.position
                targetCell.position = mix(targetCell.initialPosition, mergePos, t: easedMerge)

                // Healthy cell shrinks as it's absorbed (simple disappearance)
                targetCell.scale = cellRadius * (1.0 - easedMerge)
                targetCell.baseScale = cellRadius * (1.0 - easedMerge)

                // Gentle rotation during absorption (not too fast)
                targetCell.rotation += 0.02

                // Invader grows smoothly during absorption
                let pulsation = sin(mergeProgress * .pi * 4.0) * 0.03
                invaderCell.scale = cellRadius * (1.0 + 0.2 * mergeProgress + pulsation)
                invaderCell.baseScale = cellRadius * (1.0 + 0.2 * mergeProgress)

                // At halfway point, change invader form to sphere
                if mergeProgress > 0.5 && invaderCell.type == .invader {
                    invaderCell.type = .healthy  // Change geometry to sphere
                    invaderCell.color = SIMD4<Float>(0.9, 0.3, 0.2, 0.9)  // But keep red color
                    invaderCell.createGeometry(device: device)
                }

                // Rotate invader aggressively during absorption
                invaderCell.rotation += 0.08
            } else {
                // Absorption complete, start color change and then dividing
                print("🔄 TRANSITION: merging → dividing. Merge progress: 1.0")
                targetCell.animationState = .dividing
                invaderCell.animationState = .dividing
                targetCell.divideStartTime = time
                invaderCell.divideStartTime = time

                // Reset target cell to prepare for division
                targetCell.scale = cellRadius * 0.8  // Start slightly smaller
                targetCell.baseScale = cellRadius * 0.8
                targetCell.position = invaderCell.position
            }
        } else if targetCell.animationState == .dividing && invaderCell.animationState == .dividing {
            // Color change and division phase
            let colorChangeDuration: Float = 1.2
            let divideDuration: Float = 1.8
            let totalDuration = colorChangeDuration + divideDuration
            let totalProgress = (time - targetCell.divideStartTime) / totalDuration

            if totalProgress < colorChangeDuration / totalDuration {
                // Phase 1: Color change (red -> blue) while cells stay together
                let colorProgress = (time - targetCell.divideStartTime) / colorChangeDuration
                let easedColor = easeInOutCubic(colorProgress)

                // Smooth color transition
                invaderCell.color = mix(SIMD4<Float>(0.9, 0.3, 0.2, 0.9),
                                       SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
                                       t: easedColor)

                // Pulsate during color change
                let pulse = sin(colorProgress * .pi * 8.0) * 0.1
                invaderCell.scale = cellRadius * 0.8 * (1.0 + pulse)
                invaderCell.baseScale = cellRadius * 0.8
                targetCell.scale = cellRadius * 0.8 * (1.0 + pulse)
                targetCell.baseScale = cellRadius * 0.8

            } else if totalProgress < 1.0 {
                // Phase 2: Division after color change
                let divideProgress = (time - targetCell.divideStartTime - colorChangeDuration) / divideDuration
                let easedDivide = easeOutCubic(divideProgress)

                // Ensure color is fully blue
                invaderCell.color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)
                targetCell.color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)

                // Get initial positions
                let mergePos = (targetCell.position + invaderCell.position) * 0.5

                // Determine target positions based on which cell was targeted
                let targetPos1: SIMD3<Float>
                let targetPos2: SIMD3<Float>

                if targetHealthyCellIndex == 0 {
                    // Target was at (0.28, 0.35) - cells move apart
                    targetPos1 = worldPosition(for: divisionTargetsNormalized[0][0])   // Slightly left and down
                    targetPos2 = worldPosition(for: divisionTargetsNormalized[0][1])   // Slightly right and up
                } else {
                    // Target was at (0.28, 0.65) - cells move apart
                    targetPos1 = worldPosition(for: divisionTargetsNormalized[1][0])   // Slightly left and down
                    targetPos2 = worldPosition(for: divisionTargetsNormalized[1][1])   // Slightly right and up
                }

                targetCell.position = mix(mergePos, targetPos1, t: easedDivide)
                invaderCell.position = mix(mergePos, targetPos2, t: easedDivide)

                // Scale during division - return to normal size with bounce effect
                let bounceScale = 1.0 + sin(divideProgress * .pi) * 0.15
                let baseScale = cellRadius * (0.8 + 0.2 * easedDivide)
                let scale = baseScale * bounceScale
                targetCell.scale = scale
                targetCell.baseScale = baseScale
                invaderCell.scale = scale
                invaderCell.baseScale = baseScale

                // Add subtle rotation during division
                targetCell.rotation += 0.02
                invaderCell.rotation += 0.02

            } else {
                // Division complete, stop animation
                print("✅ ANIMATION COMPLETE! Total time: \(String(format: "%.2f", time))s")
                isAnimationRunning = false
                onAnimationComplete?()
            }
        }
    }
}

// Helper functions
func mix(_ a: Float, _ b: Float, t: Float) -> Float {
    return a * (1.0 - t) + b * t
}

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a * (1.0 - t) + b * t
}

func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, t: Float) -> SIMD4<Float> {
    return a * (1.0 - t) + b * t
}

// Easing functions for smooth animations
func easeInOut(_ t: Float) -> Float {
    return t < 0.5 ? 2.0 * t * t : 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
}

func easeInCubic(_ t: Float) -> Float {
    return t * t * t
}

func easeOutCubic(_ t: Float) -> Float {
    let t1 = 1.0 - t
    return 1.0 - t1 * t1 * t1
}

func easeInOutCubic(_ t: Float) -> Float {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
}

// Matrix helpers
extension float4x4 {
    init(perspectiveWithAspect aspect: Float, fovy: Float, near: Float, far: Float) {
        let yScale = 1.0 / tanf(fovy * .pi / 180.0 * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near
        let zScale = -(far + near) / zRange
        let wzScale = -2.0 * far * near / zRange

        self.init(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }

    init(orthographicWithLeft left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let width = right - left
        let height = top - bottom
        let depth = far - near

        self.init(
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, 2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, -2.0 / depth, 0),
            SIMD4<Float>(-(right + left) / width, -(top + bottom) / height, -(far + near) / depth, 1)
        )
    }

    init(lookAt eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - target)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        self.init(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        )
    }

    init(translation: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        )
    }

    init(scale: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(scale.x, 0, 0, 0),
            SIMD4<Float>(0, scale.y, 0, 0),
            SIMD4<Float>(0, 0, scale.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}
