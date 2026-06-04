import SwiftUI

// ネイティブホーム画面。figma.com/files の代替として表示する。
// タブがゼロ、またはアクティブタブが「ホームURL」にいるときにContentViewが重ねて表示する。
struct NativeHomeView: View {
    @Environment(FigmaAPIManager.self) private var api
    // ファイルやURLが選択されたときにContentViewへ通知するコールバック
    let onOpen: (URL) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                recentSection
                if api.hasToken && !api.teamIDs.isEmpty {
                    projectSection
                }
                if !api.hasToken {
                    tokenPrompt
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))  // WebViewを隠すための不透明背景
        .onAppear { api.enrichThumbnailsIfNeeded() }
    }

    // MARK: - Recent Files

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "最近使ったファイル", symbol: "clock")

            if api.recentFiles.isEmpty {
                ContentUnavailableView(
                    "最近開いたファイルがありません",
                    systemImage: "clock",
                    description: Text("Figmaのファイルを開くと、ここに表示されます。")
                )
                .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 175, maximum: 230), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(api.recentFiles) { file in
                        FileThumbnailCard(file: file) { onOpen(file.openURL) }
                    }
                }
            }
        }
    }

    // MARK: - Project Browser

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionHeader(title: "プロジェクト", symbol: "folder")
            ForEach(api.teamIDs, id: \.self) { teamID in
                TeamProjectsSection(teamID: teamID, api: api, onOpen: onOpen)
            }
        }
    }

    // MARK: - Token Setup Prompt

    private var tokenPrompt: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("Figma APIトークンを設定するとさらに便利に")
                    .font(.subheadline).fontWeight(.semibold)
                Text("サムネイルの表示と、チームのプロジェクトブラウザが使えるようになります。\n設定 → Figma API で設定してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Section Header

private struct HomeSectionHeader: View {
    let title: LocalizedStringKey
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.title3.bold())
    }
}

// MARK: - File Thumbnail Card

struct FileThumbnailCard: View {
    let file: RecentFigmaFile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                thumbnailArea
                    .frame(height: 120)
                    .clipped()
                    .clipShape(.rect(topLeadingRadius: 10, topTrailingRadius: 10))
                infoArea
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressEffectButtonStyle(pressedScale: 0.97))
    }

    @ViewBuilder
    private var thumbnailArea: some View {
        if let urlStr = file.thumbnailUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholderView
                case .empty:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.secondary.opacity(0.08))
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: file.kind.symbol)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
        }
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(file.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
            Text(file.lastOpenedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Team Projects Section

private struct TeamProjectsSection: View {
    let teamID: String
    let api: FigmaAPIManager
    let onOpen: (URL) -> Void

    @State private var projects: [FigmaAPIProject] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoading {
                ProgressView()
                    .padding(.vertical, 8)
            } else if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ForEach(projects) { project in
                    ProjectFilesRow(project: project, api: api, onOpen: onOpen)
                }
            }
        }
        .task { await loadProjects() }
    }

    private func loadProjects() async {
        isLoading = true
        errorMessage = nil
        do {
            projects = try await api.fetchProjects(teamID: teamID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Project Files Row (collapsible)

private struct ProjectFilesRow: View {
    let project: FigmaAPIProject
    let api: FigmaAPIManager
    let onOpen: (URL) -> Void

    @State private var files: [FigmaAPIFile] = []
    @State private var isExpanded = false
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
                if isExpanded && files.isEmpty { Task { await loadFiles() } }
            } label: {
                HStack {
                    Label(project.name, systemImage: "folder.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 12)
                if isLoading {
                    ProgressView().padding(12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(files) { file in
                            Button {
                                onOpen(URL(string: "https://www.figma.com/design/\(file.key)")!)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "paintbrush.pointed")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    Text(file.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if file.id != files.last?.id { Divider().padding(.leading, 40) }
                        }
                    }
                }
            }
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
    }

    private func loadFiles() async {
        isLoading = true
        files = (try? await api.fetchFiles(projectID: project.id)) ?? []
        isLoading = false
    }
}
