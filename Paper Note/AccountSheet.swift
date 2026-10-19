//
//  AccountSheet.swift
//  Paper Note
//
//  Sign in to the Paper Note sync server so the same notebooks show up on
//  every device (Mac, Android phone, …).
//

import SwiftUI

struct AccountSheet: View {
    @Bindable var library: Library
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    private var account: SyncAccount { library.account }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.title2.weight(.semibold))

            Text("Sign in with the same email on each device and your notebooks stay in sync through Google Firebase.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if account.isSignedIn {
                signedIn
            } else {
                signInForm
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear { email = account.email }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Signed in as", value: account.email)
            LabeledContent("Last sync") {
                if let t = account.lastSync {
                    Text(t, style: .relative) + Text(" ago")
                } else {
                    Text("Not yet")
                }
            }
            if !account.status.isEmpty {
                Text(account.status).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(account.syncing ? "Syncing…" : "Sync now") {
                    Task { await library.syncNow() }
                }
                .disabled(account.syncing)
                Button("Sign out", role: .destructive) { account.signOut() }
            }
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .onSubmit { submit(create: false) }

            HStack {
                Button("Sign in") { submit(create: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
                Button("Create account") { submit(create: true) }
                    .disabled(busy)
                if busy { ProgressView().controlSize(.small) }
            }
        }
    }

    private func submit(create: Bool) {
        error = nil
        busy = true
        Task {
            do {
                try await account.signIn(email: email, password: password, create: create)
                password = ""
                await library.syncNow()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
