import SwiftUI
import AppKit

/// Sign-in / sign-up surface. OAuth + email (create account with code + password, or sign in with password).
struct SignInView: View {
    let onClose: () -> Void

    @ObservedObject private var auth = AuthService.shared
    @State private var email: String = ""
    @State private var code: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var stage: Stage = .picker
    @State private var sending: Bool = false
    @State private var verifying: Bool = false
    @State private var submitting: Bool = false
    @State private var inlineError: String?
    @State private var resendTick = Date()
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    private let resendTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Stage {
        case picker
        case emailMode
        case emailEntryCreate
        case signInPassword
        case codeEntry
        case setPassword
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            background

            VStack(spacing: 0) {
                header
                content
                    .padding(.horizontal, 36)
                    .padding(.top, 8)
                Spacer(minLength: 16)
                footer
                    .padding(.bottom, 22)
            }

            closeButton
                .padding(.top, 14)
                .padding(.trailing, 14)
        }
        .frame(width: 460, height: 620)
        .onReceive(NotificationCenter.default.publisher(for: .mellotronAuthCompleted)) { _ in
            onClose()
        }
        .onChange(of: auth.lastError) { _, new in
            inlineError = new
            sending = false
        }
        .onReceive(resendTimer) { resendTick = $0 }
        .animation(.easeOut(duration: 0.22), value: stage)
        .mellotronThemed()
    }

    // MARK: - Pieces

    private var background: some View {
        Color.melloInk.ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 14) {
            BrandMark(size: 64)
                .padding(.top, 52)

            headline

            Text(subtitle)
                .font(.melloBody(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, -4)
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder private var headline: some View {
        switch stage {
        case .picker:
            DisplayHeadline("Welcome to ", size: 32, alignment: .center)
                .italic("Mellotron.")
        case .emailMode:
            DisplayHeadline("Continue with ", size: 30, alignment: .center)
                .italic("email.")
        case .emailEntryCreate:
            DisplayHeadline("Create your ", size: 30, alignment: .center)
                .italic("account.")
        case .signInPassword:
            DisplayHeadline("Sign in with ", size: 30, alignment: .center)
                .italic("password.")
        case .codeEntry:
            DisplayHeadline("Enter your ", size: 30, alignment: .center)
                .italic("code.")
        case .setPassword:
            DisplayHeadline("Set your ", size: 30, alignment: .center)
                .italic("password.")
        }
    }

    private var subtitle: String {
        switch stage {
        case .picker:
            return "Sign in to use the free transcription cloud and sync your settings."
        case .emailMode:
            return "Create a new account or sign in with your email and password."
        case .emailEntryCreate:
            return "We'll email you a 6-digit code to verify your address."
        case .signInPassword:
            return "Enter the email and password for your Mellotron account."
        case .codeEntry:
            return "We sent a 6-digit code to \(auth.pendingOTPEmail ?? email). Enter it below."
        case .setPassword:
            return "Choose a password (8+ characters). Stored securely by Supabase."
        }
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .picker:            pickerStage
        case .emailMode:         emailModeStage
        case .emailEntryCreate:  emailCreateStage
        case .signInPassword:    signInPasswordStage
        case .codeEntry:         codeStage
        case .setPassword:       setPasswordStage
        }
    }

    private var pickerStage: some View {
        VStack(spacing: 10) {
            ProviderButton(provider: .apple, title: "Apple", action: { auth.signInWithApple() })
            ProviderButton(provider: .google, title: "Google", action: { auth.signInWithProvider(.google) })
            ProviderButton(provider: .github, title: "GitHub", action: { auth.signInWithProvider(.github) })

            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                Text("or with email")
                    .font(.melloMono(10, weight: .medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            }
            .padding(.vertical, 10)

            Button {
                stage = .emailMode
                inlineError = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .font(.system(size: 13, weight: .medium))
                    Text("Continue with email")
                        .font(.melloBody(13.5, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 6)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var emailModeStage: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Create account", disabled: false) {
                stage = .emailEntryCreate
                inlineError = nil
            }
            Button {
                stage = .signInPassword
                inlineError = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .medium))
                    Text("Sign in with password")
                        .font(.melloBody(13.5, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button("Back") {
                stage = .picker
                inlineError = nil
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var emailCreateStage: some View {
        VStack(spacing: 14) {
            emailField
            PrimaryButton(
                title: sending ? "Sending…" : "Email me a code",
                disabled: sending || email.isEmpty,
                action: sendEmail
            )
            backToEmailModeButton
            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var signInPasswordStage: some View {
        VStack(spacing: 14) {
            emailField
            passwordField(placeholder: "Password", text: $password, visible: $showPassword, onSubmit: signInWithPassword)
            PrimaryButton(
                title: submitting ? "Signing in…" : "Sign in",
                disabled: submitting || email.isEmpty || password.isEmpty,
                action: signInWithPassword
            )
            backToEmailModeButton
            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var codeStage: some View {
        VStack(spacing: 16) {
            OTPDigitInput(code: $code) {
                verifyCode()
            }

            PrimaryButton(
                title: verifying ? "Verifying…" : "Verify code",
                disabled: verifying || code.count < 6,
                action: verifyCode
            )

            HStack(spacing: 16) {
                Button(resendLabel) {
                    code = ""
                    sendEmail()
                }
                .buttonStyle(.plain)
                .font(.melloBody(12, weight: .medium))
                .foregroundStyle(auth.canResendOTP && !sending ? .secondary : .tertiary)
                .disabled(!auth.canResendOTP || sending)

                Button("Use a different email") {
                    stage = .emailEntryCreate
                    code = ""
                    inlineError = nil
                }
                .buttonStyle(.plain)
                .font(.melloBody(12, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            if let inlineError {
                Text(inlineError)
                    .font(.melloBody(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var resendLabel: String {
        _ = resendTick
        if auth.canResendOTP { return sending ? "Sending…" : "Resend code" }
        return "Resend in \(auth.otpResendSecondsRemaining)s"
    }

    private var setPasswordStage: some View {
        VStack(spacing: 14) {
            passwordField(placeholder: "Password (8+ characters)", text: $password, visible: $showPassword, onSubmit: submitPassword)
            passwordField(placeholder: "Confirm password", text: $confirmPassword, visible: $showConfirmPassword, onSubmit: submitPassword)
            PrimaryButton(
                title: submitting ? "Saving…" : "Create account",
                disabled: submitting || password.count < 8 || password != confirmPassword,
                action: submitPassword
            )
            if password.count >= 1 {
                Text(passwordStrengthHint)
                    .font(.melloBody(11))
                    .foregroundStyle(password.count >= 8 ? .green : .secondary)
            }
            if !confirmPassword.isEmpty && password != confirmPassword {
                Text("Passwords don't match.")
                    .font(.melloBody(11))
                    .foregroundStyle(.red)
            }
            if let inlineError {
                Text(inlineError)
                    .font(.melloBody(12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var passwordStrengthHint: String {
        if password.count < 8 { return "At least 8 characters required." }
        if password.count < 12 { return "Good — 12+ characters is even stronger." }
        return "Strong password."
    }

    private var emailField: some View {
        HStack {
            Image(systemName: "envelope")
                .foregroundStyle(.secondary)
            TextField("you@example.com", text: $email)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(fieldBackground)
    }

    private func passwordField(
        placeholder: String,
        text: Binding<String>,
        visible: Binding<Bool>,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
            Group {
                if visible.wrappedValue {
                    TextField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit(onSubmit)
                } else {
                    SecureField(placeholder, text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit(onSubmit)
                }
            }
            Button {
                visible.wrappedValue.toggle()
            } label: {
                Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var backToEmailModeButton: some View {
        Button("Back") {
            stage = .emailMode
            inlineError = nil
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button("Continue without an account") {
                NSApp.activate(ignoringOtherApps: true)
                onClose()
            }
            .buttonStyle(.plain)
            .font(.melloBody(12, weight: .medium))
            .foregroundStyle(.secondary)

            Text("By continuing you agree to the Terms & Privacy Policy.")
                .font(.melloBody(10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func sendEmail() {
        guard !email.isEmpty else { return }
        inlineError = nil
        code = ""
        sending = true
        auth.signInWithEmail(email) { result in
            sending = false
            switch result {
            case .success:
                stage = .codeEntry
            case .failure(let err):
                inlineError = err.localizedDescription
            }
        }
    }

    private func verifyCode() {
        guard code.count == 6, !verifying else { return }
        inlineError = nil
        verifying = true
        auth.verifyEmailOTP(email: auth.pendingOTPEmail ?? email, code: code) { result in
            verifying = false
            switch result {
            case .success:
                password = ""
                confirmPassword = ""
                stage = .setPassword
            case .failure(let err):
                inlineError = err.localizedDescription
                code = ""
            }
        }
    }

    private func submitPassword() {
        guard password.count >= 8, password == confirmPassword, !submitting else { return }
        inlineError = nil
        submitting = true
        auth.setPassword(password) { result in
            submitting = false
            switch result {
            case .success:
                onClose()
            case .failure(let err):
                inlineError = err.localizedDescription
            }
        }
    }

    private func signInWithPassword() {
        guard !email.isEmpty, !password.isEmpty, !submitting else { return }
        inlineError = nil
        submitting = true
        auth.signInWithPassword(email: email, password: password) { result in
            submitting = false
            switch result {
            case .success:
                onClose()
            case .failure(let err):
                inlineError = err.localizedDescription
            }
        }
    }
}

// MARK: - OTP digit input

private struct OTPDigitInput: View {
    @Binding var code: String
    let onComplete: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Hidden field captures paste and keyboard input.
            TextField("", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .focused($focused)
                .onChange(of: code) { _, new in
                    let digits = new.filter(\.isNumber)
                    code = String(digits.prefix(6))
                    if code.count == 6 { onComplete() }
                }

            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let char = code.count > index
            ? String(code[code.index(code.startIndex, offsetBy: index)])
            : ""
        let isActive = code.count == index && focused

        Text(char)
            .font(.system(size: 22, weight: .semibold, design: .monospaced))
            .frame(width: 44, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? Color.mello.opacity(0.8) : Color.white.opacity(0.12), lineWidth: isActive ? 2 : 1)
                    )
            )
    }
}

// MARK: - Provider button

private struct ProviderButton: View {
    let provider: AuthService.OAuthProvider
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                providerIcon
                    .frame(width: 18, height: 18)
                Text(title)
                    .font(.melloBody(13.5, weight: .semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -6)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(stroke, lineWidth: 1)
                    )
            )
            .foregroundStyle(foreground)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var providerIcon: some View {
        switch provider {
        case .apple:
            Image(systemName: "apple.logo").font(.system(size: 16, weight: .medium))
        case .google:
            GoogleGlyph()
        case .github:
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
        }
    }

    private var background: Color {
        switch provider {
        case .apple:  return hovering ? .white : Color.white.opacity(0.95)
        case .google: return hovering ? Color.white.opacity(0.10) : Color.white.opacity(0.06)
        case .github: return hovering ? Color.white.opacity(0.12) : Color.white.opacity(0.07)
        }
    }
    private var stroke: Color {
        switch provider {
        case .apple:  return .black.opacity(0.08)
        case .google: return .white.opacity(0.12)
        case .github: return .white.opacity(0.10)
        }
    }
    private var foreground: Color {
        switch provider {
        case .apple:  return .black
        case .google: return .primary
        case .github: return .white
        }
    }
}

private struct GoogleGlyph: View {
    var body: some View {
        ZStack {
            Circle().trim(from: 0.0, to: 0.25)
                .stroke(Color(red: 0.96, green: 0.26, blue: 0.21), lineWidth: 2.6)
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0.25, to: 0.50)
                .stroke(Color(red: 0.99, green: 0.73, blue: 0.02), lineWidth: 2.6)
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0.50, to: 0.75)
                .stroke(Color(red: 0.20, green: 0.66, blue: 0.33), lineWidth: 2.6)
                .rotationEffect(.degrees(-90))
            Circle().trim(from: 0.75, to: 1.0)
                .stroke(Color(red: 0.26, green: 0.52, blue: 0.96), lineWidth: 2.6)
                .rotationEffect(.degrees(-90))
            Rectangle()
                .fill(Color(red: 0.26, green: 0.52, blue: 0.96))
                .frame(width: 7, height: 2.6)
                .offset(x: 4, y: 0)
        }
        .frame(width: 16, height: 16)
    }
}

private struct PrimaryButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.melloBody(13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(disabled ? Color.mello.opacity(0.35)
                                       : (hovering ? Color.mello.opacity(0.96) : Color.mello))
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
