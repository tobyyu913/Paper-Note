//
//  PasscodeSheet.swift
//  Paper Note
//
//  Lets the owner change the passcode that unlocks notebooks. The current
//  passcode (or Touch ID) must be confirmed before a new one is set.
//

import SwiftUI
import LocalAuthentication

struct PasscodeSheet: View {
    @Bindable var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPass = ""
    @State private var confirm = ""
    @State private var authed = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security")
                .font(.system(size: 18, weight: .semibold))

            if library.biometricsAvailable {
                Toggle("Unlock with Touch ID", isOn: $library.useBiometrics)
                    .toggleStyle(.switch)
                Text("When off, notebooks open with the passcode only.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Divider().padding(.vertical, 2)
            }

            Text("Passcode")
                .font(.system(size: 14, weight: .medium))

            if authed {
                Text("Verified. Choose a new passcode.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                SecureField("New passcode", text: $newPass)
                SecureField("Confirm new passcode", text: $confirm)
            } else {
                Text("Confirm your current passcode, or use Touch ID.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                SecureField("Current passcode", text: $current)
                    .onSubmit(verifyCurrent)
                if library.useBiometrics && library.biometricsAvailable {
                    Button {
                        authenticateBiometrics()
                    } label: {
                        Label("Use Touch ID", systemImage: "touchid")
                    }
                    .buttonStyle(.link)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                if authed {
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(newPass.isEmpty)
                } else {
                    Button("Continue", action: verifyCurrent)
                        .buttonStyle(.borderedProminent)
                        .disabled(current.isEmpty)
                }
            }
            .padding(.top, 4)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 320)
    }

    private func verifyCurrent() {
        if current == library.passcode {
            authed = true
            error = nil
        } else {
            error = "Incorrect passcode"
        }
    }

    private func save() {
        guard newPass == confirm else { error = "Passcodes don’t match"; return }
        library.passcode = newPass
        dismiss()
    }

    private func authenticateBiometrics() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            error = "Touch ID isn’t available"
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                           localizedReason: "Change your notebook passcode") { success, _ in
            if success { DispatchQueue.main.async { authed = true; error = nil } }
        }
    }
}
