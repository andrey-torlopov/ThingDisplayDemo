//
//  ContentView.swift
//  ThingDisplay
//
//  Created by Andrey Torlopov on 14.11.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var showInfo = false
    @State private var tapCount = 0
    @State private var lastTapTime = Date()
    @State private var cellPositions: [CellLabelData] = []
    @State private var labelsOpacity: Double = 0.0
    @State private var renderer: MetalRenderer?
    @State private var hideLabelsTask: DispatchWorkItem?

    var body: some View {
        ZStack {
            // Metal rendering view
            MetalView(
                cellPositions: $cellPositions,
                onRendererReady: { metalRenderer in
                    renderer = metalRenderer
                }
            )
            .ignoresSafeArea()
            .onTapGesture {
                handleTap()
            }

            // Cell labels overlay
            CellLabelView(cellPositions: cellPositions)
                .opacity(labelsOpacity)
                .allowsHitTesting(false)

            // Info overlay
            if showInfo {
                InfoView(isPresented: $showInfo)
                    .transition(.opacity)
            }
        }
    }

    private func handleTap() {
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)

        // Detect double tap (within 0.3 seconds)
        if timeSinceLastTap < 0.3 {
            tapCount += 1
            if tapCount >= 2 {
                withAnimation {
                    showInfo = true
                }
                tapCount = 0
                return
            }
        } else {
            tapCount = 1
        }

        lastTapTime = now

        // Single tap - restart animation
        startAnimationSequence()
    }

    private func startAnimationSequence() {
        // Cancel previous hide task if exists
        hideLabelsTask?.cancel()

        // Show labels immediately
        withAnimation(.easeIn(duration: 0.3)) {
            labelsOpacity = 1.0
        }

        // Restart animation
        renderer?.startAnimation()

        // Schedule hiding labels and starting merge after 2 seconds
        let task = DispatchWorkItem { [self] in
            withAnimation(.easeOut(duration: 1.0)) {
                labelsOpacity = 0.0
            }
        }
        hideLabelsTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
    }
}

#Preview {
    ContentView()
}
