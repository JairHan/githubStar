import SwiftUI

struct AccountView: View {
    @ObservedObject var account: GitHubAccountStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("GitHub 账号", systemImage: "person.crop.circle").font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let user = account.user {
                Label("已登录 @\(user.login)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Star 会同步到此账号。退出仅删除本机登录令牌；需要撤销授权时，请前往 GitHub 的应用授权设置。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("退出登录") { account.logout() }.disabled(account.isBusy)
                    Link("管理 GitHub 授权", destination: URL(string: "https://github.com/settings/applications")!)
                }
            }
            if let error = account.error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            Divider()
            if account.clientID.isEmpty {
                Label("此构建尚未启用 GitHub 登录", systemImage: "info.circle").foregroundStyle(.secondary)
                Text("请联系发行者获取已配置登录的版本。浏览热门仓库和搜索仍然可用。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("点击登录，在 GitHub 网页输入下方生成的验证码并允许授权，即可同步你的 Stars。").font(.callout).foregroundStyle(.secondary)
            }
            Text("授权请求 public_repo，用于公开仓库的 Star。GitHub 将此权限与公开仓库写权限合并；本应用只调用 Star 接口，不修改仓库内容。").font(.caption).foregroundStyle(.secondary)
            if let code = account.userCode {
                VStack(alignment: .leading, spacing: 12) {
                    Text("在 GitHub 网页中输入此验证码").font(.headline)
                    HStack {
                        Text(code).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                        Button("复制") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) }
                    }
                    Link("打开 GitHub 授权页面", destination: URL(string: "https://github.com/login/device")!)
                    HStack { ProgressView().controlSize(.small); Text("等待你在浏览器中完成授权…").font(.caption) }
                    if let date = account.expiresAt { Text("有效期至 " + date.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                if account.isBusy { Button("取消授权") { account.cancelLogin() } }
                else { Button(account.user == nil ? "在浏览器中授权登录" : "重新授权") { account.login() }.buttonStyle(.borderedProminent).disabled(account.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                Spacer()
            }
            Text("登录令牌仅保存至 macOS 钥匙串。客户端不会读取 GitHub 密码。").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
