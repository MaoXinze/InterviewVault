# InterviewVault — Agent 工作规则

本地优先的个人面试知识库 App。输入是面试录音/模拟面试，输出是问题卡片和复盘总结；AI 用用户自己的 API Key，数据全程本地、无后端。

**开工前必读**：[docs/PRD.md](docs/PRD.md)（需求/表结构/执行修订）、[docs/PLAN.md](docs/PLAN.md)（技术栈/路线图/当前周任务）。

---

## 三条铁律（所有设计决策的裁判）

1. **本地优先**：录音、转写稿、标注、卡片全存本地（SQLite + 文件系统），离线可用，无任何后端依赖
2. **用户自持 AI**：不内置 AI、不送额度；AI 请求从客户端直连用户配置的端点，App 只是遥控器
3. **数据自主**：全量 JSON + Markdown 随时导出带走，删除即真删

## 安全红线（API Key，每改相关代码必查）

- Key 只存 flutter_secure_storage（Android Keystore），**绝不**写入 SQLite、日志、异常堆栈、崩溃报告
- 网络拦截器仅当请求 host == 用户配置的 baseUrl 时注入 Authorization
- 日志拦截器必须脱敏全部 header
- 仓库中不得出现任何真实 Key；.gitignore 已挡 *.env / secrets/
- 用户可随时删除 Key

## 命名与文案

- 底部导航：首页 / 面试 / 中央⏺ / **回顾**（不得写"卡片库"）/ 我的
- 卡片复习叫"开始回顾"；首页提示"N 道题待回顾"
- 用户可见文案一律中文；代码标识符、commit message 用英文或中文均可，但需一致

## 工程纪律

1. **先写测试再写实现**，数据层（drift）优先：内存库跑 CRUD/筛选/级联删除/迁移
2. whisper.cpp、音频解码一律在 **Isolate/后台线程**，UI 永不阻塞
3. drift migrations 从 v1 起维护；改表必须走迁移 + 测试，禁止破坏性重建
4. Markdown 导出格式是**稳定性承诺**：改模板 = 破坏性变更，需快照测试 + 文档化
5. 完成定义：`flutter analyze` 0 issue + `flutter test` 全绿 + 分步 git 提交
6. 代码生成文件（*.g.dart/*.freezed.dart）不入库，改 schema 后跑 `dart run build_runner build --delete-conflicting-outputs`

## 范围护栏（明确不做，即使"顺手"也不实现）

登录/账号系统、云同步、社区、支付/会员、内置 AI 或免费额度、招聘端/企业端、视频面试、健康心理判定、课程内容、遥测上传。

## 当前阶段

MVP 仅 Android（iOS 延后用 Codemagic 补）；P0 支持锁屏后台录音。当前任务与周计划见 docs/PLAN.md 第 4-5 节。
