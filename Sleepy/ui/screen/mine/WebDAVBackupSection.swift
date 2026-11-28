import SwiftUI

@MainActor
struct WebDAVBackupSection: View {
    private enum Sheet: String, Identifiable {
        case setup, backups
        var id: String { rawValue }
    }

    @Environment(\.localWakeUpColors) private var colors
    @Binding var busy: Bool
    let localBusy: Bool
    let makeArchive: @Sendable () throws -> Data
    let onRestore: (MigrationPreparedArchive) -> Void

    private let client = WebDAVClient()
    private let store = WebDAVConnectionStore()
    @State private var connection: WebDAVConnection?
    @State private var draft = WebDAVConfig(serverURL: "", directory: "Sleepy")
    @State private var password = ""
    @State private var sheet: Sheet?
    @State private var backups: [WebDAVRemoteBackup] = []
    @State private var preparedRestore: MigrationPreparedArchive?
    @State private var uploadConfirmation = false
    @State private var forgetConfirmation = false
    @State private var operation: Task<Void, Never>?
    @State private var status: String?
    @State private var sheetError: String?

    private var unavailable: Bool { localBusy || busy || preparedRestore != nil }

    var body: some View {
        SettingsSection(title: L10n.t("webdav_section_title")) {
            VStack(alignment: .leading, spacing: 0) {
                Text(connection.map { L10n.format("webdav_configured_sub", $0.config.serverURL) }
                    ?? L10n.t("webdav_section_sub"))
                    .font(.footnote)
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(16)
                actionRow("webdav_config_title", id: "backup_webdav_setup", action: openSetup)
                    .disabled(unavailable)
                Divider().padding(.horizontal, 16)
                actionRow("webdav_upload", id: "backup_webdav_upload") { uploadConfirmation = true }
                    .disabled(unavailable || connection == nil)
                Divider().padding(.horizontal, 16)
                actionRow("webdav_restore", id: "backup_webdav_restore", action: listBackups)
                    .disabled(unavailable || connection == nil)
                if busy && sheet == nil {
                    ProgressView(L10n.t("webdav_working")).padding(16)
                }
                if let status = status {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(16)
                        .accessibilityIdentifier("backup_webdav_status")
                }
            }
            .background(colors.surfaceContainer, in: RoundedRectangle(cornerRadius: SleepyShapes.large))
        }
        .onAppear {
            do { connection = try store.load() }
            catch { status = L10n.t("webdav_error_generic") }
        }
        .onDisappear { operation?.cancel() }
        .sheet(item: $sheet, onDismiss: finishSheet) { route in
            switch route {
            case .setup: setupSheet
            case .backups: backupPicker
            }
        }
        .alert(L10n.t("webdav_upload_confirm_title"), isPresented: $uploadConfirmation) {
            Button(L10n.t("webdav_confirm_upload"), action: upload)
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            if let config = connection?.config {
                Text(L10n.format("webdav_upload_confirm_target", config.serverURL, config.directory))
            }
        }
    }

    private func actionRow(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(L10n.t(title)).foregroundColor(colors.onSurface)
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(colors.onSurfaceVariant)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(id)
    }

    private var setupSheet: some View {
        NavigationView {
            Form {
                Section {
                    TextField(L10n.t("webdav_server_url"), text: $draft.serverURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("backup_webdav_server")
                    TextField(L10n.t("webdav_directory"), text: $draft.directory)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("backup_webdav_directory")
                    TextField(L10n.t("webdav_username"), text: $draft.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("backup_webdav_username")
                    SecureField(L10n.t("webdav_password"), text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("backup_webdav_password")
                } footer: {
                    let canReuse = !WebDAVConnection.draft(config: draft, enteredPassword: "", saved: connection).password.isEmpty
                    Text(L10n.t(canReuse ? "webdav_password_keep_hint" : "webdav_password_optional_hint"))
                }
                .disabled(busy)
                Section {
                    Button(L10n.t("webdav_test_and_save"), action: testAndSave)
                        .disabled(unavailable)
                        .accessibilityIdentifier("backup_webdav_test")
                    if busy { ProgressView(L10n.t("webdav_testing")) }
                    if let error = sheetError { Text(error).foregroundColor(colors.error) }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("webdav_directory_create_notice"))
                        Text(L10n.t("webdav_privacy_notice"))
                    }
                }
                if connection != nil {
                    Button(L10n.t("webdav_forget_configuration"), role: .destructive) { forgetConfirmation = true }
                        .disabled(unavailable)
                }
            }
            .navigationTitle(L10n.t("webdav_config_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelToolbar }
            .alert(L10n.t("webdav_forget_title"), isPresented: $forgetConfirmation) {
                Button(L10n.t("webdav_forget_configuration"), role: .destructive, action: forget)
                Button(L10n.t("cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("webdav_forget_warning"))
            }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(busy)
    }

    private var backupPicker: some View {
        NavigationView {
            List {
                if busy { ProgressView(L10n.t("webdav_working")) }
                if let error = sheetError { Text(error).foregroundColor(colors.error) }
                if backups.isEmpty {
                    Text(L10n.t("webdav_remote_empty")).foregroundColor(.secondary)
                }
                ForEach(backups) { backup in
                    Button { download(backup) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.fileName).foregroundColor(.primary)
                            Text(L10n.format("webdav_remote_file_detail",
                                backup.modifiedAt?.formatted(date: .abbreviated, time: .shortened)
                                    ?? L10n.t("webdav_date_unknown"),
                                ByteCountFormatter.string(fromByteCount: backup.sizeBytes, countStyle: .file)))
                                .font(.footnote).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .disabled(unavailable)
                    .accessibilityIdentifier("backup_webdav_remote_file")
                }
            }
            .navigationTitle(L10n.t("webdav_remote_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelToolbar }
        }
        .navigationViewStyle(.stack)
        .interactiveDismissDisabled(busy)
    }

    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.t("cancel")) {
                operation?.cancel()
                preparedRestore = nil
                sheet = nil
            }
            .accessibilityIdentifier("backup_webdav_cancel")
        }
    }

    private func openSetup() {
        draft = connection?.config ?? WebDAVConfig(serverURL: "", directory: "Sleepy")
        password = ""
        sheetError = nil
        sheet = .setup
    }

    private func finishSheet() {
        password = ""
        if let archive = preparedRestore {
            preparedRestore = nil
            onRestore(archive)
        }
    }

    private func testAndSave() {
        let candidate = WebDAVConnection.draft(config: draft, enteredPassword: password, saved: connection)
        run {
            try await client.testConnection(config: candidate.config, password: candidate.password)
            try Task.checkCancellation()
            try store.save(candidate)
            connection = candidate
            status = L10n.t("webdav_config_saved")
            sheet = nil
        }
    }

    private func forget() {
        run {
            try store.forget()
            connection = nil
            status = L10n.t("webdav_config_forgotten")
            sheet = nil
        }
    }

    /// Reaching this function requires the explicit confirmation on the backup page.
    private func upload() {
        guard let connection = connection else { return }
        run {
            let bytes = try await Self.background(makeArchive)
            try Task.checkCancellation()
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: Date())
            let name = "sleepy-backup-\(stamp)-\(UUID().uuidString.lowercased()).sleepybackup"
            try await client.upload(config: connection.config, password: connection.password, fileName: name, bytes: bytes)
            try Task.checkCancellation()
            status = L10n.format("webdav_upload_done", name)
        }
    }

    private func listBackups() {
        guard let connection = connection else { return }
        run {
            let result = try await client.listBackups(config: connection.config, password: connection.password)
            try Task.checkCancellation()
            backups = result
            sheet = .backups
        }
    }

    private func download(_ backup: WebDAVRemoteBackup) {
        guard let connection = connection else { return }
        run {
            let bytes = try await client.download(config: connection.config, password: connection.password, fileName: backup.fileName)
            let archive: MigrationPreparedArchive
            do {
                archive = try await Self.background { try MigrationPreparedArchive.decodeRemote(bytes) }
            } catch is CancellationError {
                throw CancellationError()
            } catch is MigrationPackageCodec.ReadLimitError {
                throw RestoreError.tooLarge
            } catch {
                throw RestoreError.invalidArchive
            }
            try Task.checkCancellation()
            // Deliver after this sheet has disappeared, so the parent presents the same
            // Merge/Overwrite/Cancel dialog it uses for a local file.
            preparedRestore = archive
            sheet = nil
        }
    }

    private enum RestoreError: Error { case invalidArchive, tooLarge }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !unavailable else { return }
        status = nil
        sheetError = nil
        busy = true
        operation = Task { @MainActor in
            defer { busy = false; operation = nil }
            do {
                try Task.checkCancellation()
                try await action()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let message = Self.message(for: error)
                if sheet == nil { status = message } else { sheetError = message }
            }
        }
    }

    private nonisolated static func background<T: Sendable>(_ action: @escaping @Sendable () throws -> T) async throws -> T {
        let worker = Task.detached(priority: .userInitiated, operation: action)
        return try await withTaskCancellationHandler(operation: { try await worker.value },
                                                     onCancel: { worker.cancel() })
    }

    private static func message(for error: Error) -> String {
        if let restore = error as? RestoreError {
            switch restore {
            case .invalidArchive: return L10n.t("settings_migration_import_fail")
            case .tooLarge: return L10n.t("webdav_error_archive_size")
            }
        }
        guard let failure = error as? WebDAVError else { return L10n.t("webdav_error_generic") }
        switch failure {
        case .invalidConfiguration: return L10n.t("webdav_error_configuration")
        case .httpsRequired: return L10n.t("webdav_error_https")
        case .authentication: return L10n.t("webdav_error_authentication")
        case .forbidden: return L10n.t("webdav_error_forbidden")
        case .redirectRefused: return L10n.t("webdav_error_redirect")
        case .alreadyExists: return L10n.t("webdav_error_exists")
        case .httpStatus(let status): return L10n.format("webdav_error_http_status", status)
        case .fileTooLarge: return L10n.t("webdav_error_too_large")
        case .invalidResponse: return L10n.t("webdav_error_response")
        case .network: return L10n.t("webdav_error_network")
        }
    }
}
