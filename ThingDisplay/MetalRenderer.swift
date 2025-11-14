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

    // Target cell for invader
    private var targetHealthyCellIndex: Int = 0

    // Cell size expressed in normalized world coordinates (0...1 range)
    private var cellRadius: Float = 0.1

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue

        super.init()

        metalView.device = device
        metalView.delegate = self
        metalView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0)
        metalView.depthStencilPixelFormat = .depth32Float

        buildPipeline(metalView: metalView)
        buildDepthStencilState()
        setupCells()
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
            position: SIMD3<Float>(0.15, 0.35, 0),
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        let healthyCell2 = Cell(
            position: SIMD3<Float>(0.15, 0.65, 0),
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        // Invader cell (red-orange, angular) - positioned on the right side
        let invaderCell = Cell(
            position: SIMD3<Float>(0.35, 0.5, 0),
            color: SIMD4<Float>(0.9, 0.3, 0.2, 0.9),
            type: .invader,
            device: device
        )

        cells = [healthyCell1, healthyCell2, invaderCell]

        // Randomly choose target healthy cell (0 or 1)
        targetHealthyCellIndex = Int.random(in: 0...1)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewSize = size

        // In normalized 0...1 world coordinates we keep a constant radius
        cellRadius = 0.1

        // Update all cells scale
        for cell in cells {
            cell.scale = cellRadius
        }
    }

    func draw(in view: MTKView) {
        // Only increment time if animation is running
        if isAnimationRunning {
            time += 1.0 / 60.0
        }
        updateCells()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)

        // Use orthographic projection that maps 0...1 in both X and Y to the viewport
        let projectionMatrix = float4x4(
            orthographicWithLeft: 0,
            right: 1,
            bottom: 0,
            top: 1,
            near: -1,
            far: 1
        )

        // Camera looking straight down (2D view) with identity view matrix
        let cameraPosition = SIMD3<Float>(0.5, 0.5, 1.0)
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
        isAnimationRunning = true
        resetCells()
    }

    func resetCells() {
        // Reset all cells to initial state (normalized screen coordinates)
        cells[0].animationState = .moving
        cells[1].animationState = .moving
        cells[2].animationState = .moving

        cells[0].scale = cellRadius
        cells[1].scale = cellRadius
        cells[2].scale = cellRadius

        cells[0].position = SIMD3<Float>(0.15, 0.35, 0)
        cells[1].position = SIMD3<Float>(0.15, 0.65, 0)
        cells[2].position = SIMD3<Float>(0.35, 0.5, 0)

        cells[0].initialPosition = SIMD3<Float>(0.15, 0.35, 0)
        cells[1].initialPosition = SIMD3<Float>(0.15, 0.65, 0)
        cells[2].initialPosition = SIMD3<Float>(0.35, 0.5, 0)

        cells[0].color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)
        cells[1].color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)
        cells[2].color = SIMD4<Float>(0.9, 0.3, 0.2, 0.9)

        cells[2].type = .invader
        cells[2].createGeometry(device: device)

        // Choose new random target
        targetHealthyCellIndex = Int.random(in: 0...1)

        // Reset time for animation restart
        time = 0
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

        // Animation state machine
        if targetCell.animationState == .moving && invaderCell.animationState == .moving {
            // Move invader towards target healthy cell
            let moveDuration: Float = 3.0
            let moveProgress = min(time / moveDuration, 1.0)

            // Invader moves to target from position (0.35, 0.5)
            let startPos = SIMD3<Float>(0.35, 0.5, 0)
            invaderCell.position = mix(startPos, targetCell.position, t: moveProgress)

            let distance = simd_distance(targetCell.position, invaderCell.position)
            if distance < 0.05 || moveProgress >= 1.0 {
                targetCell.animationState = .merging
                invaderCell.animationState = .merging
                targetCell.mergeStartTime = time
                invaderCell.mergeStartTime = time
            }
        } else if targetCell.animationState == .merging && invaderCell.animationState == .merging {
            // Absorption animation - invader absorbs healthy cell
            let mergeDuration: Float = 2.5
            let mergeProgress = (time - targetCell.mergeStartTime) / mergeDuration

            if mergeProgress < 1.0 {
                // Invader stays in place, healthy cell shrinks and moves into invader
                let mergePos = invaderCell.position
                targetCell.position = mix(targetCell.position, mergePos, t: mergeProgress)

                // Healthy cell shrinks as it's absorbed
                targetCell.scale = cellRadius * (1.0 - mergeProgress)

                // Invader grows slightly during absorption
                invaderCell.scale = cellRadius * (1.0 + 0.2 * mergeProgress)

                // At halfway point, change invader form to sphere
                if mergeProgress > 0.5 && invaderCell.type == .invader {
                    invaderCell.type = .healthy  // Change geometry to sphere
                    invaderCell.color = SIMD4<Float>(0.9, 0.3, 0.2, 0.9)  // But keep red color
                    invaderCell.createGeometry(device: device)
                }

                // Rotate invader during absorption
                invaderCell.rotation += 0.05
            } else {
                // Absorption complete, start color change and then dividing
                targetCell.animationState = .dividing
                invaderCell.animationState = .dividing
                targetCell.divideStartTime = time
                invaderCell.divideStartTime = time

                // Reset target cell to prepare for division
                targetCell.scale = cellRadius
                targetCell.position = invaderCell.position
            }
        } else if targetCell.animationState == .dividing && invaderCell.animationState == .dividing {
            // Color change and division phase
            let colorChangeDuration: Float = 1.5
            let divideDuration: Float = 2.0
            let totalDuration = colorChangeDuration + divideDuration
            let totalProgress = (time - targetCell.divideStartTime) / totalDuration

            if totalProgress < colorChangeDuration / totalDuration {
                // Phase 1: Color change (red -> blue) while cells stay together
                let colorProgress = (time - targetCell.divideStartTime) / colorChangeDuration
                invaderCell.color = mix(SIMD4<Float>(0.9, 0.3, 0.2, 0.9),
                                       SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
                                       t: colorProgress)
            } else if totalProgress < 1.0 {
                // Phase 2: Division after color change
                let divideProgress = (time - targetCell.divideStartTime - colorChangeDuration) / divideDuration

                // Ensure color is fully blue
                invaderCell.color = SIMD4<Float>(0.3, 0.5, 0.9, 0.9)

                // Get initial positions
                let mergePos = (targetCell.position + invaderCell.position) * 0.5

                // Determine target positions based on which cell was targeted
                let targetPos1: SIMD3<Float>
                let targetPos2: SIMD3<Float>

                if targetHealthyCellIndex == 0 {
                    // Target was at (0.15, 0.35) - cells move apart
                    targetPos1 = SIMD3<Float>(0.10, 0.30, 0)   // Slightly left and down
                    targetPos2 = SIMD3<Float>(0.20, 0.40, 0)   // Slightly right and up
                } else {
                    // Target was at (0.15, 0.65) - cells move apart
                    targetPos1 = SIMD3<Float>(0.10, 0.60, 0)   // Slightly left and down
                    targetPos2 = SIMD3<Float>(0.20, 0.70, 0)   // Slightly right and up
                }

                targetCell.position = mix(mergePos, targetPos1, t: divideProgress)
                invaderCell.position = mix(mergePos, targetPos2, t: divideProgress)

                // Scale during division - return to normal size
                let scale = cellRadius * (0.6 + 0.4 * divideProgress)  // Scale from 0.6 to 1.0 of cellRadius
                targetCell.scale = scale
                invaderCell.scale = scale
            } else {
                // Division complete, stop animation
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
