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
    private var viewSize: CGSize = .zero

    // Target cell for invader
    private var targetHealthyCellIndex: Int = 0

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
        // Two healthy cells (blue) - positioned in different depths
        let healthyCell1 = Cell(
            position: SIMD3<Float>(-2.5, 0.8, -1.0),  // Top left, back
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        let healthyCell2 = Cell(
            position: SIMD3<Float>(-2.5, -0.8, 1.0),  // Bottom left, front
            color: SIMD4<Float>(0.3, 0.5, 0.9, 0.9),
            type: .healthy,
            device: device
        )

        // Invader cell (red-orange, angular)
        let invaderCell = Cell(
            position: SIMD3<Float>(2.5, 0, 0),
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
    }

    func draw(in view: MTKView) {
        time += 1.0 / 60.0
        updateCells()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)

        let aspect = Float(view.bounds.width / view.bounds.height)
        let projectionMatrix = float4x4(perspectiveWithAspect: aspect, fovy: 60.0, near: 0.1, far: 100.0)

        // Camera positioned at an angle to see depth (like microscope view)
        let cameraPosition = SIMD3<Float>(0, 3, 8)
        let viewMatrix = float4x4(lookAt: cameraPosition,
                                   target: SIMD3<Float>(0, 0, 0),
                                   up: SIMD3<Float>(0, 1, 0))

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
        // Reset all cells to initial state
        cells[0].animationState = .moving
        cells[1].animationState = .moving
        cells[2].animationState = .moving

        cells[0].scale = 1.0
        cells[1].scale = 1.0
        cells[2].scale = 1.0

        cells[0].position = SIMD3<Float>(-2.5, 0.8, -1.0)
        cells[1].position = SIMD3<Float>(-2.5, -0.8, 1.0)
        cells[2].position = SIMD3<Float>(2.5, 0, 0)

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

        // Only update if animation is running
        if !isAnimationRunning {
            return
        }

        // Update all cells
        for cell in cells {
            cell.update(time: time)
        }

        let targetCell = cells[targetHealthyCellIndex]
        let invaderCell = cells[2]

        // Animation state machine
        if targetCell.animationState == .moving && invaderCell.animationState == .moving {
            // Move invader towards target healthy cell
            let moveDuration: Float = 3.0
            let moveProgress = min(time / moveDuration, 1.0)

            // Invader moves to target
            let startPos = SIMD3<Float>(2.5, 0, 0)
            invaderCell.position = mix(startPos, targetCell.position, t: moveProgress)

            let distance = simd_distance(targetCell.position, invaderCell.position)
            if distance < 0.5 || moveProgress >= 1.0 {
                targetCell.animationState = .merging
                invaderCell.animationState = .merging
                targetCell.mergeStartTime = time
                invaderCell.mergeStartTime = time
            }
        } else if targetCell.animationState == .merging && invaderCell.animationState == .merging {
            // Merge cells - invader changes form to sphere but stays red
            let mergeDuration: Float = 2.0
            let mergeProgress = (time - targetCell.mergeStartTime) / mergeDuration

            if mergeProgress < 1.0 {
                // Interpolate positions
                let mergePos = (targetCell.position + invaderCell.position) * 0.5
                targetCell.position = mix(targetCell.position, mergePos, t: mergeProgress)
                invaderCell.position = mix(invaderCell.position, mergePos, t: mergeProgress)

                // At halfway point, change invader form to sphere but keep red
                if mergeProgress > 0.5 && invaderCell.type == .invader {
                    invaderCell.type = .healthy  // Change geometry to sphere
                    invaderCell.color = SIMD4<Float>(0.9, 0.3, 0.2, 0.9)  // But keep red color
                    invaderCell.createGeometry(device: device)
                }
            } else {
                // Merge complete, start color change and then dividing
                targetCell.animationState = .dividing
                invaderCell.animationState = .dividing
                targetCell.divideStartTime = time
                invaderCell.divideStartTime = time
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
                    // Cells move apart in different directions
                    targetPos1 = SIMD3<Float>(-2.5, 0.8, -1.0)   // Top left, back
                    targetPos2 = SIMD3<Float>(-1.5, -1.2, 0.5)   // Bottom, slightly right, front
                } else {
                    // Cells move apart in different directions
                    targetPos1 = SIMD3<Float>(-1.5, 1.2, 0.5)    // Top, slightly right, front
                    targetPos2 = SIMD3<Float>(-2.5, -0.8, -1.0)  // Bottom left, back
                }

                targetCell.position = mix(mergePos, targetPos1, t: divideProgress)
                invaderCell.position = mix(mergePos, targetPos2, t: divideProgress)

                // Scale during division
                let scale = 0.6 + 0.4 * divideProgress
                targetCell.scale = scale
                invaderCell.scale = scale
            } else {
                // Division complete, stop animation
                isAnimationRunning = false
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
