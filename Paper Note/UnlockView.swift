//
//  UnlockView.swift
//  Paper Note
//
//  Gate shown before a notebook opens. It tries Touch ID first; if biometrics
//  are unavailable or declined, the owner can type the passcode instead
//  ("paper note" by default).
//

import SwiftUI
import LocalAuthentication

struct UnlockView: View {
    var title: String
    /// The expected passcode (from Library.passcode).
    var passcode: String
    /// Whether Touch ID is offered. When false, only the passcode unlocks.
    var useBiometrics: Bool
    var onUnlock: () -> Void
    var onCancel: () -> Void

    @State private var entry = ""
    @State private var wrong = false
    @State private var shake: CGFloat = 0

    private var bookName: String { title.isEmpty ? "this notebook" : "“\(title)”" }

    /// Touch ID is only offered when the owner enabled it *and* the Mac has the
    /// hardware for it.
    private var biometricsReady: Bool {
        guard useBiometrics else { return false }
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.13, blue: 0.09),
                         Color(red: 0.10, green: 0.07, blue: 0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Locked")
                    .font(.custom(Ruling.fontName, size: 30).weight(.bold))
                    .foregroundStyle(.white.opacity(0.92))

                Text(biometricsReady
                     ? "Unlock \(bookName) with Touch ID or your passcode."
                     : "Unlock \(bookName) with your passcode.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    SecureField("Passcode", text: $entry)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                        .onSubmit(submitPasscode)
                        .modifier(Shake(animatableData: shake))

                    if wrong {
                        Text("Incorrect passcode")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Button(action: submitPasscode) {
                        Text("Unlock")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(entry.isEmpty)

                    if biometricsReady {
                        Button(action: authenticateBiometrics) {
                            Label("Use Touch ID", systemImage: "touchid")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 2)
                    }
                }

                Button(action: onCancel) {
                    Text("Back to Shelf")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(40)
        }
        .onAppear { if biometricsReady { authenticateBiometrics() } }
    }

    private func submitPasscode() {
        if entry == passcode {
            onUnlock()
        } else {
            wrong = true
            entry = ""
            withAnimation(.default) { shake += 1 }
        }
    }

    private func authenticateBiometrics() {
        guard useBiometrics else { return }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Unlock \(bookName)") { success, _ in
            if success { DispatchQueue.main.async(execute: onUnlock) }
        }
    }
}

/// Horizontal shake used to flag a wrong passcode.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = 8 * sin(animatableData * .pi * 4)
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
