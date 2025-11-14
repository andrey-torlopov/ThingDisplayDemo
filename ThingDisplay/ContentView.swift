//
//  ContentView.swift
//  ThingDisplay
//
//  Created by Andrey Torlopov on 14.11.2025.
//

import SwiftUI

struct ContentView: View {
    @State private var showInfo = false
    @State private var cellPositions: [CellLabelData] = []
    @State private var labelsOpacity: Double = 0.0
    @State private var renderer: MetalRenderer?
    @State private var hideLabelsTask: DispatchWorkItem?
    @State private var showStartButton = true

    init() {
        print("🏁 ContentView.init() called")
    }

    var body: some View {
        let _ = print("🎨 ContentView.body evaluated")
        return ZStack {
            // Metal rendering view
            MetalView(
                cellPositions: $cellPositions,
                onRendererReady: { metalRenderer in
                    print("✨ MetalRenderer initialized and ready")
                    // Use DispatchQueue to avoid "Modifying state during view update" warning
                    DispatchQueue.main.async {
                        renderer = metalRenderer
                        // Set up animation completion callback
                        metalRenderer.onAnimationComplete = {
                            DispatchQueue.main.async {
                                withAnimation(.easeIn(duration: 0.5)) {
                                    showStartButton = true
                                }
                            }
                        }
                    }
                }
            )
            .ignoresSafeArea()
            .onTapGesture {
                handleTap()
            }

            // Start button overlay
            if showStartButton {
                Button(action: {
                    showStartButton = false
                    startAnimationSequence()
                }) {
                    Text("Start")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(Color.blue.opacity(0.8))
                                .shadow(radius: 10)
                        )
                }
            }

            // Info button in top right corner
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showInfo = true
                        }
                    }) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(20)
                    }
                }
                Spacer()
            }
            .zIndex(50)

            // Cell labels overlay
            CellLabelView(cellPositions: cellPositions)
                .opacity(labelsOpacity)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $showInfo) {
            InfoView(isPresented: $showInfo)
                .presentationBackground(.black.opacity(0.85))
        }
    }

    private func handleTap() {
        // Tap restarts animation (only if start button was already pressed)
        if !showStartButton {
            startAnimationSequence()
        }
    }

    private func startAnimationSequence() {
        print("🚀 startAnimationSequence() called, renderer is: \(renderer == nil ? "nil" : "initialized")")

        // Cancel previous hide task if exists
        hideLabelsTask?.cancel()

        // Show labels immediately
        withAnimation(.easeIn(duration: 0.3)) {
            labelsOpacity = 1.0
        }

        // Restart animation
        if let renderer = renderer {
            print("🎯 Calling renderer.startAnimation()")
            renderer.startAnimation()
        } else {
            print("❌ ERROR: renderer is nil!")
        }

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
