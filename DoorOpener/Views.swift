import SwiftUI

// MARK: - 根视图（根据登录状态切换）
struct RootView: View {
    @EnvironmentObject var api: DoorAPI
    @State private var checking = true

    var body: some View {
        Group {
            if checking {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在恢复会话…").font(.subheadline).foregroundStyle(.secondary)
                }
            } else {
                switch api.loginState {
                case .loggedIn:
                    MainView()
                default:
                    LoginView()
                }
            }
        }
        .animation(.default, value: api.loginState)
        .task {
            // 等待 init 中发起的会话检测完成
            try? await Task.sleep(nanoseconds: 600_000_000)
            checking = false
        }
    }
}

// MARK: - 登录页
struct LoginView: View {
    @EnvironmentObject var api: DoorAPI
    @State private var code = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("门禁远程开门")
                    .font(.title.bold())

                Text("北京中学门禁系统")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    LabeledContent("账号") {
                        Text("gzb1").foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        TextField("输入验证码", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 140)

                        Group {
                            if let img = api.captchaImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 40)
                                    .background(Color.gray.opacity(0.15))
                                    .cornerRadius(6)
                                    .onTapGesture { Task { await api.fetchCaptcha() } }
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.15))
                                    .frame(width: 100, height: 40)
                                    .cornerRadius(6)
                                    .overlay(ProgressView())
                            }
                        }
                    }

                    if case .failed(let msg) = api.loginState {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await api.login(code: code) }
                    } label: {
                        if api.isBusy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("登录").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.isEmpty || api.isBusy)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)

                Spacer()

                Text("点击验证码图片可更换")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .navigationTitle("门禁开门")
            .task {
                if api.captchaImage == nil { await api.fetchCaptcha() }
            }
        }
    }
}

// MARK: - 主界面
struct MainView: View {
    @EnvironmentObject var api: DoorAPI
    @State private var keyword = ""
    @State private var selected: Set<Door> = []
    @State private var showResult = false

    private var matches: [Door] {
        api.searchDoors(keyword: keyword)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("输入楼栋或房间号，如 勇岳107", text: $keyword)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !keyword.isEmpty {
                        Button { keyword = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .padding()

                // 门列表
                if matches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: keyword.isEmpty ? "magnifyingglass" : "questionmark.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text(keyword.isEmpty ? "输入门牌号开始搜索" : "未找到匹配的门")
                            .font(.headline)
                        Text(keyword.isEmpty ? "支持楼栋名、房间号，如 智渊楼205 / 107" : "请核对门牌名称或换个关键词")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(matches) { door in
                                DoorRow(door: door, isSelected: selected.contains(door)) {
                                    if selected.contains(door) {
                                        selected.remove(door)
                                    } else {
                                        selected.insert(door)
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("找到 \(matches.count) 个门")
                                Spacer()
                                if !matches.isEmpty {
                                    Button(selected.count == matches.count ? "取消全选" : "全选") {
                                        if selected.count == matches.count {
                                            selected.removeAll()
                                        } else {
                                            selected = Set(matches)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                // 底部操作栏
                VStack(spacing: 8) {
                    if !selected.isEmpty {
                        Text("已选 \(selected.count) 个门：\(selected.map(\.name).prefix(2).joined(separator: "、"))\(selected.count > 2 ? "…" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        let targets = selected.isEmpty ? matches : Array(selected)
                        Task {
                            await api.openDoors(targets)
                            showResult = true
                        }
                    } label: {
                        if api.isBusy {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label(selected.isEmpty ? "开首个门" : "开门（\(selected.count) 个）", systemImage: "door.left.hand.open")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(api.isBusy || matches.isEmpty)

                    if let err = api.lastError {
                        Text(err).font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(.bar)
            }
            .navigationTitle("门禁开门")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task { await api.refreshOnlineStatus() }
                        } label: {
                            Label("刷新设备状态", systemImage: "arrow.clockwise")
                        }
                        Button("退出登录", role: .destructive) {
                            api.logout()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showResult) {
                ResultView()
            }
        }
    }
}

// MARK: - 门列表行
struct DoorRow: View {
    let door: Door
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(door.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(door.full)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(door.online ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(door.online ? "联机" : "脱机")
                        .font(.caption)
                        .foregroundStyle(door.online ? .green : .red)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 结果记录
struct ResultView: View {
    @EnvironmentObject var api: DoorAPI
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if api.results.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("暂无操作记录").font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(api.results) { r in
                            HStack(alignment: .top) {
                                Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(r.success ? .green : .red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.doorName).font(.headline)
                                    Text(r.message).font(.subheadline).foregroundStyle(.secondary)
                                    Text(r.time).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("开门记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
