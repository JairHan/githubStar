# GitHub Star

使用 Swift + SwiftUI 编写的 macOS 原生开源仓库发现应用。macOS 14 及以上，无第三方依赖。

## 功能

- 今日热门：GitHub Trending 日榜，显示今日新增 Star。
- 每周涨星：GitHub Trending 周榜，按本周新增 Star 排序。
- 总星榜：GitHub 搜索 API，按累计 Star 降序。
- 关键词搜索：支持 `swift`、`topic:ai`、`stars:>1000` 等 GitHub 查询语法。
- 语言筛选、分页、仓库详情、打开 GitHub、复制链接。
- 本地收藏及最近榜单缓存；请求失败时保留缓存并提示错误。
- 原生侧栏、菜单、设置窗口，自动适应系统浅色及深色外观。

## 运行

```bash
./script/build_and_run.sh
```

脚本构建并生成 `dist/GitHubStar.app`，然后打开应用。也可直接双击该应用。Codex 的 Run 按钮已配置。

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

快捷键：⌘F 搜索、⌘R 刷新、⌘O 打开仓库、⌘D 收藏。

## 数据口径与限制

周涨星是 GitHub Trending 周榜的新增 Star 数，只对入榜仓库排序，并非 GitHub 全站的周涨星完整排名。Trending 数据通过网页解析，GitHub 调整 HTML 结构时需要更新解析器；解析失败会提示，不会填入虚构数据。

总星榜和搜索采用 [GitHub REST Search API](https://docs.github.com/en/rest/search/search#search-repositories)。每页 30 条，API 限制最多浏览前 1,000 条。匿名 API 额度有限，限流时请稍后刷新。GitHub 没有保证榜单数据的实时性。

收藏仅保存在本机，不会执行 GitHub Star 操作。收藏中的数字为收藏时的快照。数据位于 `~/Library/Application Support/GitHubStar/`；榜单缓存和收藏为 JSON，不包含认证信息。

构建脚本使用本机临时签名，产物适合本机运行，尚未使用 Developer ID 签名和 Apple 公证，不是正式分发包。

## 工程结构

`App/` 应用入口与菜单，`Models/` 仓库模型，`Services/` API 和 Trending 解析，`Stores/` 状态及持久化，`Views/` 原生界面，`Tests/` 数据解析验证。
