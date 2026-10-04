import Foundation

struct GitHubEvent: Decodable, Identifiable {
    let id: String
    let type: String
    let actor: Actor
    let repo: EventRepository
    let payload: Payload?
    let created_at: Date

    struct Actor: Decodable { let login: String }
    struct EventRepository: Decodable { let name: String }
    struct Subject: Decodable {
        let title: String?
        let name: String?
        let tag_name: String?
        let html_url: URL?
    }
    struct Commit: Decodable { let message: String? }
    struct Payload: Decodable {
        let action: String?
        let ref: String?
        let ref_type: String?
        let size: Int?
        let commits: [Commit]?
        let release: Subject?
        let issue: Subject?
        let pull_request: Subject?
        let comment: Subject?
        let forkee: Subject?
    }

    var category: ActivityCategory {
        switch type {
        case "WatchEvent": .stars
        case "ForkEvent": .forks
        case "ReleaseEvent": .releases
        default: .development
        }
    }
    var icon: String {
        switch type {
        case "WatchEvent": "star"
        case "ForkEvent": "arrow.triangle.branch"
        case "ReleaseEvent": "tag"
        case "PushEvent": "arrow.up.right"
        case "IssuesEvent": "exclamationmark.circle"
        case "PullRequestEvent", "PullRequestReviewEvent": "arrow.triangle.merge"
        case "IssueCommentEvent", "CommitCommentEvent", "PullRequestReviewCommentEvent": "text.bubble"
        case "CreateEvent": "plus.circle"
        case "DeleteEvent": "minus.circle"
        default: "bolt"
        }
    }
    var summary: String {
        switch type {
        case "WatchEvent": return "Star 了仓库"
        case "ForkEvent": return "Fork 了仓库"
        case "ReleaseEvent": return "发布了版本"
        case "PushEvent": return "推送了代码"
        case "IssuesEvent": return "\(actionText) Issue"
        case "PullRequestEvent": return "\(actionText) Pull Request"
        case "PullRequestReviewEvent": return "评审了 Pull Request"
        case "IssueCommentEvent": return "评论了 Issue / Pull Request"
        case "CommitCommentEvent": return "评论了提交"
        case "PullRequestReviewCommentEvent": return "评论了代码评审"
        case "CreateEvent": return "创建了\(refTypeText)"
        case "DeleteEvent": return "删除了\(refTypeText)"
        case "PublicEvent": return "公开了仓库"
        case "MemberEvent": return "更新了仓库成员"
        case "GollumEvent": return "更新了 Wiki"
        default: return "更新了仓库动态"
        }
    }
    private var actionText: String {
        switch payload?.action {
        case "opened": "创建了"
        case "closed": "关闭了"
        case "reopened": "重新打开了"
        default: "更新了"
        }
    }
    private var refTypeText: String {
        switch payload?.ref_type { case "branch": "分支"; case "tag": "标签"; default: "仓库" }
    }
    var detail: String? {
        if let subject = payload?.release { return subject.name ?? subject.tag_name }
        if let subject = payload?.issue ?? payload?.pull_request { return subject.title }
        if let message = payload?.commits?.first?.message { return message }
        return payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "")
    }
    var repositoryURL: URL {
        var components = URLComponents(string: "https://github.com")!
        components.path = "/" + repo.name
        return components.url!
    }
    var url: URL {
        let candidate = payload?.comment?.html_url ?? payload?.issue?.html_url
            ?? payload?.pull_request?.html_url ?? payload?.release?.html_url ?? payload?.forkee?.html_url
        if let candidate, candidate.scheme == "https", candidate.host == "github.com",
           candidate.user == nil, candidate.password == nil, candidate.port == nil || candidate.port == 443 {
            return candidate
        }
        return repositoryURL
    }
}

enum ActivityCategory: String, CaseIterable, Identifiable {
    case all = "全部", stars = "Star", forks = "Fork", releases = "发布", development = "开发动态"
    var id: Self { self }
}

struct ActivityPage {
    let items: [GitHubEvent]
    let hasMore: Bool
}
