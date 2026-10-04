# GitHub Star

使用 Swift + SwiftUI 编写的 macOS 原生开源仓库发现应用。macOS 14 及以上，无第三方依赖。

## 功能

- GitHub 动态：原生事件列表与仓库详情，复用应用登录，支持类型筛选、关键词过滤、分页和直接 Star。
- 今日热门：GitHub Trending 日榜，显示今日新增 Star。
- 每周涨星：GitHub Trending 周榜，按本周新增 Star 排序。
- 总星榜：GitHub 搜索 API，按累计 Star 降序。
- 关键词搜索：支持 `swift`、`topic:ai`、`stars:>1000` 等 GitHub 查询语法。
- 语言筛选、分页、仓库详情、打开 GitHub、复制链接。
- GitHub 设备授权登录、Star / 取消 Star、分页读取我的 Stars。
- 公开榜单离线缓存；登录令牌保存至 macOS 钥匙串。
- 原生侧栏、菜单、设置窗口，自动适应系统浅色及深色外观。

## 运行

```bash
./script/build_and_run.sh
```

每次构建同时生成 `dist/GitHubStar.app` 和压缩安装镜像 `dist/GitHubStar.dmg`。默认构建后打开应用；Codex 的 Run 按钮已配置。打开 DMG 后，将 GitHubStar 拖入镜像中的 Applications 快捷入口即可安装。

使用 Xcode 时打开 `Package.swift`。构建只需要 Apple Command Line Tools 中的 Swift 工具链。

```bash
./script/test.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --build-only
```

测试脚本直接编译生产数据层并运行断言，不需要 XCTest 或 Swift Testing 宏插件。运行在线检查：

```bash
GITHUBSTAR_LIVE_TEST=1 ./script/test.sh
```

快捷键：⌘F 搜索、⌘R 刷新、⌘O 打开仓库、⌘D Star / 取消 Star。

## GitHub 动态

侧栏选择“GitHub 动态”即可查看当前账号收到的事件。使用与其他模块一致的 SwiftUI 三栏界面，通过 [GitHub Events API](https://docs.github.com/en/rest/activity/events#list-events-received-by-the-authenticated-user)读取数据，复用钥匙串中的现有 OAuth 授权，无需额外网页登录。

列表包含 Star、Fork、发布、推送、Issue 和 Pull Request 等事件，可按类型或关键词筛选已加载项目。选择事件后显示事件摘要和真实仓库详情，支持 Star / 取消 Star、打开事件和仓库；⌘R 刷新，⌘O 打开选中仓库，⌘D Star。每页 100 条，最多加载 300 条，仅涵盖最近 30 天。Events API 可能有 30 秒至 6 小时的延迟，并不保证实时更新。

这里展示的是 API 提供的事件流，与网页 Feed 的推荐流存在差异，不包含网页的全部推荐内容。现有授权仍只申请 `public_repo`，不新增私有仓库权限。动态与仓库详情仅保存在内存，退出或切换账号时清空。

## 数据口径与限制

周涨星是 GitHub Trending 周榜的新增 Star 数，只对入榜仓库排序，并非 GitHub 全站的周涨星完整排名。Trending 数据通过网页解析，GitHub 调整 HTML 结构时需要更新解析器；解析失败会提示，不会填入虚构数据。

总星榜和搜索采用 [GitHub REST Search API](https://docs.github.com/en/rest/search/search#search-repositories)。每页 30 条，API 限制最多浏览前 1,000 条。匿名 API 额度有限，限流时请稍后刷新。GitHub 没有保证榜单数据的实时性。

登录后 Star / 取消 Star 会直接更新 GitHub 账号；操作成功后才更新界面状态。我的 Stars 每页 100 条，可继续加载；语言和关键词只筛选已加载的项目。Star 操作后会刷新列表以保持分页与服务器一致。

登录令牌保存在 macOS 钥匙串，不写入项目、JSON、UserDefaults 或日志。账号数据只保存在内存中，切换账号或退出后清空；授权后的搜索结果不写入离线缓存。旧版 `favorites.json` 会保留，但不再作为 Stars 列表，也不会自动批量 Star。

## 发行者：一次性配置 GitHub 登录

本项目已注册 OAuth App **Star Explorer for macOS**，并将公开 Client ID 放入 `Config/GitHubOAuthClientID.txt`。使用本项目发行构建的用户无需另行配置。维护者可在 [OAuth App 设置](https://github.com/settings/applications/3904132)管理 Device Flow 和授权设置。

1. 打开 [GitHub OAuth App 注册页](https://github.com/settings/applications/new)。Application name 填 `Star Explorer for macOS`（GitHub 不允许名称以 GitHub 或 Gist 开头）。
2. Homepage URL 可填本项目地址 `https://github.com/JairHan/githubStar`；Authorization callback URL 可填 `http://127.0.0.1/callback`。设备授权流程不使用这个回调地址。
3. 创建后在 OAuth App 设置中勾选 **Enable Device Flow**。
4. 复制公开的 **Client ID**，写入 `Config/GitHubOAuthClientID.txt`（仅写 ID 一行），或使用构建环境变量 `GITHUBSTAR_OAUTH_CLIENT_ID`。不要填写 Client Secret。
5. 运行 `./script/build_and_run.sh --release`，同时生成优化构建的 `.app` 与 `.dmg`，不自动启动应用。Client ID 会内置在包的 Info.plist 中；缺少 Client ID 时脚本拒绝生成发行构建。

也可以临时指定 Client ID 打包：

```bash
GITHUBSTAR_OAUTH_CLIENT_ID=你的公开ClientID ./script/build_and_run.sh --release
```

注册 OAuth App 和配置 Client ID 只由发行者做一次。普通用户下载已配置的应用后，只需点击“登录 GitHub”、在 GitHub 网页输入应用生成的八位验证码并允许授权，无需注册 OAuth App 或填写 Client ID。

开发构建仍可在“设置 → 高级：开发者 OAuth 配置”填写本机 Client ID。内置的发行配置始终优先，本机旧配置不会覆盖它。普通登录面板不展示开发者注册流程；未配置的构建会说明登录尚未启用。

依据 [GitHub Device Flow 文档](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow)实现验证码轮询、取消、拒绝及过期处理，无需服务器或内置 Client Secret。申请 `public_repo` scope 以管理公开仓库的 Star；GitHub OAuth 将其与公开仓库写权限合并，应用仅调用 Star 接口。若 OAuth App 配置了令牌过期，则过期后需要重新授权；当前不自动刷新令牌。

退出登录会删除本机钥匙串令牌；若要撤销 GitHub 授权，可到 [GitHub 应用授权设置](https://github.com/settings/applications)操作。该功能不复用本机 `gh` 的登录凭据。

测试通过 URLProtocol 模拟授权等待、拒绝、取消、过期、Star/Unstar 成功及失败、账号失效和 Stars 分页，不会对真实账号执行 Star。完整的真人授权流程需发行者先内置有效 Client ID，再由账号持有人在 GitHub 完成授权。

构建脚本在本机临时目录中签名并校验应用，再创建和验证 DMG，避免 Desktop 文件提供程序附加的元数据影响镜像内的签名。安装镜像包含应用与指向 `/Applications` 的快捷入口；生成的应用包和镜像均位于已被 Git 忽略的 `dist/`。

当前仍使用本机临时签名，尚未使用 Developer ID 签名和 Apple 公证。DMG 可作为发行附件，但打包不会解决 Gatekeeper 信任问题；正式面向其他用户发行前需完成 Developer ID 签名与公证。

## 软件图标

图标采用靛紫色 macOS 圆角底板、金色 Star 和青色代码连线。源图为带透明通道的 `Assets/AppIcon.png`，macOS 图标为 `Assets/AppIcon.icns`。打包脚本会自动将图标加入应用包。

修改源图后运行 `./script/generate_icon.sh` 重新生成 ICNS，再构建应用。生成提示词记录在 `Assets/AppIcon-prompt.md`。

## 工程结构

`App/` 应用入口与菜单，`Models/` 仓库模型，`Services/` API 和 Trending 解析，`Stores/` 状态及持久化，`Views/` 原生界面，`Tests/` 数据解析验证。
