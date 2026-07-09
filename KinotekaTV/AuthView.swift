import SwiftUI

// ===========================================================
// Экран входа: логин + пароль → cookie-сессия воркера.
// Liquid Glass карточка на тёмном фоне.
// ===========================================================

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @State private var login = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case login, password }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            LinearGradient(
                colors: [Theme.accent.opacity(0.18), .clear, .clear],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Кинотека")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("Фильмы и сериалы")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField("Логин", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .login)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))

                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .padding(.horizontal, 16)
                        .frame(height: 50)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        Group {
                            if busy { ProgressView().tint(.black) }
                            else { Text("Войти").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(busy || login.isEmpty || password.isEmpty)
                }
                .padding(24)
                .frame(maxWidth: 420)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private func submit() {
        guard !busy, !login.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        Task {
            let ok = await Backend.login(login.trimmingCharacters(in: .whitespaces).lowercased(), password: password)
            if ok {
                await appState.didLogin()
            } else {
                error = "Неверный логин или пароль"
            }
            busy = false
        }
    }
}
