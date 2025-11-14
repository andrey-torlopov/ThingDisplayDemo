import Metal
import MetalKit
import simd

enum CellType {
    case healthy
    case invader
}

enum AnimationState {
    case moving
    case merging
    case dividing
}

class Cell {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
    var type: CellType
    var scale: Float = 1.0
    var baseScale: Float = 1.0  // Store base scale for pulsation effects
    var rotation: Float = 0.0

    var animationState: AnimationState = .moving
    var mergeStartTime: Float = 0
    var divideStartTime: Float = 0

    // Store initial position for floating animation
    var initialPosition: SIMD3<Float>

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    init(position: SIMD3<Float>, color: SIMD4<Float>, type: CellType, device: MTLDevice) {
        self.position = position
        self.initialPosition = position
        self.color = color
        self.type = type

        createGeometry(device: device)
    }

    func createGeometry(device: MTLDevice) {
        switch type {
        case .healthy:
            createHealthyCellGeometry(device: device)
        case .invader:
            createInvaderCellGeometry(device: device)
        }
    }

    // Create organic-looking spherical cell
    func createHealthyCellGeometry(device: MTLDevice) {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt16] = []

        let segments = 20
        let rings = 20

        // Generate sphere with organic deformation
        for ring in 0...rings {
            let phi = Float(ring) / Float(rings) * .pi
            for segment in 0...segments {
                let theta = Float(segment) / Float(segments) * 2.0 * .pi

                // Add some noise for organic look
                let noiseScale: Float = 0.08
                let noise = sin(theta * 3.0) * cos(phi * 4.0) * noiseScale
                let radius: Float = 1.0 + noise

                let x = radius * sin(phi) * cos(theta)
                let y = radius * cos(phi)
                let z = radius * sin(phi) * sin(theta)

                let position = SIMD3<Float>(x, y, z)
                let normal = normalize(position)

                vertices.append(position)
                normals.append(normal)
            }
        }

        // Generate indices
        for ring in 0..<rings {
            for segment in 0..<segments {
                let current = UInt16(ring * (segments + 1) + segment)
                let next = UInt16(ring * (segments + 1) + segment + 1)
                let nextRing = UInt16((ring + 1) * (segments + 1) + segment)
                let nextRingNext = UInt16((ring + 1) * (segments + 1) + segment + 1)

                indices.append(current)
                indices.append(nextRing)
                indices.append(next)

                indices.append(next)
                indices.append(nextRing)
                indices.append(nextRingNext)
            }
        }

        createBuffers(vertices: vertices, normals: normals, indices: indices, device: device)
    }

    // Create angular invader cell (three-pointed star like Mercedes logo / spaceship)
    func createInvaderCellGeometry(device: MTLDevice) {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt16] = []

        // Create three sharp spikes (like Mercedes logo / spaceship)
        let spikeCount = 3
        let centerRadius: Float = 0.25
        let spikeLength: Float = 1.3
        let spikeHeight: Float = 0.25  // More pronounced 3D shape

        // Center point
        let center = SIMD3<Float>(0, 0, 0)

        // Create spikes at 120 degree intervals
        for spike in 0..<spikeCount {
            let angle = Float(spike) * 2.0 * .pi / Float(spikeCount) - .pi / 2.0  // Rotate to point one spike forward

            // Spike tip - sharper and longer
            let tipX = spikeLength * cos(angle)
            let tipZ = spikeLength * sin(angle)
            let tip = SIMD3<Float>(tipX, 0, tipZ)

            // Base corners of spike - narrower for more angular look
            let leftAngle = angle - .pi / 8.0  // Narrower angle
            let rightAngle = angle + .pi / 8.0

            let leftX = centerRadius * cos(leftAngle)
            let leftZ = centerRadius * sin(leftAngle)
            let left = SIMD3<Float>(leftX, 0, leftZ)

            let rightX = centerRadius * cos(rightAngle)
            let rightZ = centerRadius * sin(rightAngle)
            let right = SIMD3<Float>(rightX, 0, rightZ)

            // Create top and bottom faces for each spike with more height
            for yOffset in [-spikeHeight, spikeHeight] as [Float] {
                let baseIndex = UInt16(vertices.count)

                // Add vertices with Y offset
                let centerY = SIMD3<Float>(center.x, yOffset, center.z)
                let tipY = SIMD3<Float>(tip.x, yOffset * 0.5, tip.z)  // Tips less tall for sleeker look
                let leftY = SIMD3<Float>(left.x, yOffset, left.z)
                let rightY = SIMD3<Float>(right.x, yOffset, right.z)

                vertices.append(centerY)
                vertices.append(leftY)
                vertices.append(tipY)
                vertices.append(rightY)

                // Calculate normal (pointing up or down)
                let normal = SIMD3<Float>(0, yOffset > 0 ? 1 : -1, 0)
                normals.append(normal)
                normals.append(normal)
                normals.append(normal)
                normals.append(normal)

                // Add indices for triangle fan
                if yOffset > 0 {
                    // Top face (counter-clockwise)
                    indices.append(baseIndex)
                    indices.append(baseIndex + 1)
                    indices.append(baseIndex + 2)

                    indices.append(baseIndex)
                    indices.append(baseIndex + 2)
                    indices.append(baseIndex + 3)
                } else {
                    // Bottom face (clockwise)
                    indices.append(baseIndex)
                    indices.append(baseIndex + 2)
                    indices.append(baseIndex + 1)

                    indices.append(baseIndex)
                    indices.append(baseIndex + 3)
                    indices.append(baseIndex + 2)
                }
            }

            // Add side faces with proper normals
            let topBaseIndex = UInt16(vertices.count - 8)
            let bottomBaseIndex = UInt16(vertices.count - 4)

            // Left edge
            indices.append(topBaseIndex + 1)
            indices.append(bottomBaseIndex + 1)
            indices.append(topBaseIndex + 2)

            indices.append(topBaseIndex + 2)
            indices.append(bottomBaseIndex + 1)
            indices.append(bottomBaseIndex + 2)

            // Right edge
            indices.append(topBaseIndex + 2)
            indices.append(bottomBaseIndex + 2)
            indices.append(topBaseIndex + 3)

            indices.append(topBaseIndex + 3)
            indices.append(bottomBaseIndex + 2)
            indices.append(bottomBaseIndex + 3)
        }

        createBuffers(vertices: vertices, normals: normals, indices: indices, device: device)
    }

    func createBuffers(vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt16], device: MTLDevice) {
        // Interleave vertices and normals
        var vertexData: [SIMD3<Float>] = []
        for i in 0..<vertices.count {
            vertexData.append(vertices[i])
            vertexData.append(normals[i])
        }

        vertexBuffer = device.makeBuffer(bytes: vertexData,
                                        length: vertexData.count * MemoryLayout<SIMD3<Float>>.stride,
                                        options: [])

        indexBuffer = device.makeBuffer(bytes: indices,
                                       length: indices.count * MemoryLayout<UInt16>.stride,
                                       options: [])

        indexCount = indices.count
    }

    func update(time: Float) {
        // Animation effects based on cell type and state
        if type == .invader && animationState == .moving {
            // Aggressive rotation for invader
            rotation += 0.03

            // Pulsing effect - invader breathes menacingly
            let pulseSpeed: Float = 4.0
            let pulseAmount: Float = 0.08
            let pulse = sin(time * pulseSpeed) * pulseAmount
            scale = baseScale * (1.0 + pulse)  // Apply pulse to base scale, not current scale

            // Subtle hover movement
            let floatOffset = sin(time * 2.0) * 0.015
            position.y = initialPosition.y + floatOffset
        } else if type == .healthy && animationState == .moving {
            // Gentle floating animation for healthy cells
            rotation += 0.01
            // Add subtle floating effect relative to initial position
            let floatOffset = sin(time * 0.5 + initialPosition.y * 3.0) * 0.02
            position.y = initialPosition.y + floatOffset
        }
    }

    func render(encoder: MTLRenderCommandEncoder,
               projectionMatrix: float4x4,
               viewMatrix: float4x4,
               cameraPosition: SIMD3<Float>) {
        guard let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer else {
            return
        }

        // Build model matrix
        let translationMatrix = float4x4(translation: position)
        let scaleMatrix = float4x4(scale: SIMD3<Float>(repeating: scale))

        // Rotation - invader rotates around Z axis (perpendicular to view), healthy around Y
        let c = cos(rotation)
        let s = sin(rotation)
        let rotationMatrix: float4x4

        if type == .invader {
            // Rotate around Z axis (flat rotation in screen plane)
            rotationMatrix = float4x4(
                SIMD4<Float>(c, -s, 0, 0),
                SIMD4<Float>(s, c, 0, 0),
                SIMD4<Float>(0, 0, 1, 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
        } else {
            // Rotate around Y axis
            rotationMatrix = float4x4(
                SIMD4<Float>(c, 0, s, 0),
                SIMD4<Float>(0, 1, 0, 0),
                SIMD4<Float>(-s, 0, c, 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
        }

        let modelMatrix = translationMatrix * rotationMatrix * scaleMatrix

        var uniforms = Uniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            color: color,
            cameraPosition: cameraPosition
        )

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        encoder.drawIndexedPrimitives(type: .triangle,
                                     indexCount: indexCount,
                                     indexType: .uint16,
                                     indexBuffer: indexBuffer,
                                     indexBufferOffset: 0)
    }
}
