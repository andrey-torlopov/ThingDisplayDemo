import SwiftUI
import MetalKit

struct MetalView: UIViewRepresentable {
    @Binding var cellPositions: [CellLabelData]
    var onRendererReady: ((MetalRenderer) -> Void)?

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        if let renderer = MetalRenderer(metalView: mtkView) {
            context.coordinator.renderer = renderer
            renderer.onCellPositionsUpdated = { positions in
                DispatchQueue.main.async {
                    context.coordinator.updateCellPositions(positions)
                }
            }
            onRendererReady?(renderer)
        }

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(cellPositions: $cellPositions)
    }

    class Coordinator {
        var renderer: MetalRenderer?
        var cellPositions: Binding<[CellLabelData]>

        init(cellPositions: Binding<[CellLabelData]>) {
            self.cellPositions = cellPositions
        }

        func updateCellPositions(_ positions: [CellLabelData]) {
            cellPositions.wrappedValue = positions
        }
    }
}
