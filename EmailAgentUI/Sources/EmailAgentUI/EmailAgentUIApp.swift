import SwiftUI

@main
struct EmailAgentUIApp: App {
    var body: some Scene {
        WindowGroup("Email Agent") {
            ContentView()
        }
        .defaultSize(width: 1180, height: 760)

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("serverBaseURL") private var serverBaseURL: String = "http://127.0.0.1:8000"
    @AppStorage("repoPath") private var repoPath: String = ""

    var body: some View {
        Form {
            TextField("Server URL", text: $serverBaseURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            HStack(alignment: .firstTextBaseline) {
                Text("Repo folder")
                Text(repoPath.isEmpty ? "not set — asked on first “Start Backend”" : repoPath)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("The repo folder is where start.command lives; the app uses it to boot the MLX + API servers for you.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 480)
    }
}
