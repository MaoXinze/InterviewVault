# 面试复盘 App — PRD 与技术实现规格

文档版本: v1.0（2026-09-26 启动，末尾附「执行修订」）
文档类型: PRD + 技术实现规格（面向 AI Coding Agent）
产品代号: InterviewVault
核心原则: 本地优先 · 用户自持 AI · 数据自主 · 无后端依赖

---

## 第一部分：产品定义

### 1.1 一句话定位

一个以面试录音/模拟面试为输入，以问题卡片和复盘总结为输出的个人面试知识库工具。 用户导入真实面试录音或进行 AI 模拟面试，App 完成转写、标注、分类、卡片生成和总结导出。AI 能力由用户自行接入（自带 API Key），数据默认存储在本地。

### 1.2 产品本质

这不是一个"AI 面试工具"，而是一个面试场景下的知识管理工具。核心价值不是"帮你面试"，而是"帮你把每一次面试变成可复用的资产"。类比参考：面向求职者的 Obsidian / Notion + 录音转写 + 问题卡片系统。

### 1.3 目标用户

- 正在找实习/校招/跳槽的求职者
- 有多次面试经历，需要系统化复盘的人
- 对数据隐私敏感，不愿意把面试录音上传到第三方服务器的人
- 愿意自行配置 AI API Key 的轻度技术用户（初期核心用户）

### 1.4 竞品参考与差异化

- **AI Interviews (iOS)**：隐私优先，全程端侧处理，支持录音、转写、评分卡、候选人对比，无需账号，所有数据留在设备上。定价：终身 ¥328 / 月 ¥38 / 年 ¥148。差异化：InterviewVault 不面向招聘方，面向求职者；不内置 AI，由用户自持。
- **OfferLai**：本地优先 AI 求职工作台，整合投递管理、简历提取、分类面试复盘、AI 模拟面试、真实面试导入（录音/逐字稿）、长期能力画像。SQLite 本地存储，AI 模型和语音转写服务可自行配置。差异化：InterviewVault 聚焦"录音→卡片→导出"这条核心链路，不做投递管理和能力画像，更轻、更快。
- **开源 AI 面试复盘工具**：支持录音上传、AI 转写、结构化 Q&A 逐题评分、间隔重复（SM-2 算法）、知识库管理（Markdown 编辑）、简历模拟面试。差异化：InterviewVault 强调用户自持 AI 和本地数据，不做云端依赖。
- **Quala (macOS)**：端侧转写，录音永不离开设备，无按分钟转写费用，codebook 驱动的标注系统，带定义的标签，引用库（quote bank），审计追踪。InterviewVault 借鉴其"标注系统"和"引用库"思路，迁移到面试场景。

市场空缺验证（2026-09 检索）：市面上同类工具分三类——①录音转写复盘类（如听脑AI，只到转写+摘要）；②AI 模拟面试类（如练答、数字人面试，AI 内置收费）；③实时辅助类（面试副驾）。没有任何产品把"录音→转写→标注→卡片→回顾"做成闭环；BYOK+本地优先路线已被 Natively AI、RoleMule 等海外工具验证。

---

## 第二部分：功能规格（按优先级）

### P0 — MVP 必须实现

#### 2.1 账号与初始化
- ~~手机号/邮箱登录（可选，支持完全离线使用）~~（见执行修订 #3：MVP 完全无账号）
- 首次打开：选择身份（实习 / 校招 / 社招）、目标岗位方向（技术 / 产品 / 运营 / 设计 / 其他）
- 隐私政策展示与同意
- API Key 配置引导（首次进入模拟面试前触发）

#### 2.2 API Key 管理
- 支持的服务商：OpenAI、DeepSeek、Kimi (Moonshot)、通义千问、Claude (Anthropic)、自定义 OpenAI 兼容接口
- 配置项：服务商选择、API Key、模型名称、Base URL（自定义时）
- API Key 使用系统安全存储加密保存（iOS Keychain / Android Keystore）
- 连接测试功能，验证 Key 有效性
- 用量提示（不追踪，仅提示"AI 调用由你的账户扣费"）
- AI 请求直接从客户端发起，不经过任何中间服务器

#### 2.3 录音导入与录制
- App 内录音：前台录音，支持暂停/继续，录音过程中显示波形（见执行修订 #2：P0 支持锁屏后台录音）
- 文件导入：支持 mp3、wav、m4a、aac、ogg
- 导入后处理：显示文件信息（时长、大小、格式），用户确认后进入转写流程
- 录音保存到本地存储，不上传任何服务器

#### 2.4 语音转文字
- 转写方案：用户可选本地 Whisper 模型或云端 ASR API
- 本地：集成 whisper.cpp，支持 base/small 模型，CPU 可运行
- 云端：支持 OpenAI Whisper API、DeepSeek ASR、用户自配
- 转写结果：带时间戳的逐字稿
- 转写文本可编辑、校正
- 说话人区分（面试官 / 我）标记（P0 为手动标记，P1 为自动区分）

#### 2.5 转写文本标注
- 时间点标注：点击文本任意位置添加标注
- 文本高亮：选中文本段落高亮
- 标签系统（预置）：问题（面试官提问）、回答（我的回答）、亮点（答得好的地方）、失误（答得不好的地方）、待改进（需要优化的地方）
- 自定义标签：用户可创建新标签
- 按标签筛选：快速定位所有"失误"或"待改进"
- 标注跳转：点击标注，播放器跳转到对应录音位置

#### 2.6 分类与整理
- 录音/面试记录分类维度：公司、岗位、轮次、时间
- 自定义文件夹
- 标签体系（与标注标签打通）
- 搜索：按公司、岗位、标签、关键词搜索
- 收藏

#### 2.7 问题卡片
- 从标注中提取问题卡片：
  - 卡片正面：问题文本
  - 卡片背面：我的回答（转写片段）、标注、自定义笔记、AI 生成的参考答案思路（如已配置 AI）
- 卡片来源标记：来自哪场面试、哪段录音、哪个时间点
- 卡片标签：与标注标签打通
- 翻卡复习模式
- 间隔重复（P1，MVP 先做简单复习列表）

#### 2.8 总结与复盘
- 单次面试总结页：包含所有问题卡片、标注统计、录音概要
- 按日汇总：当天所有面试/录音的摘要视图
- 导出 Markdown：将问题卡片、回答、标注导出为 .md 文件
- 导出格式：

```text
# 面试复盘 - [公司] [岗位] [日期]

## 面试信息
- 公司：
- 岗位：
- 轮次：
- 时长：

## 问题卡片

### 问题 1
**问题**：xxx
**我的回答**：（转写片段）
**标注**：⭐ 亮点 / ⚠️ 待改进
**复盘笔记**：xxx

---

### 问题 2
...
```

- 导出文件保存到本地文件系统，支持分享到其他 App

#### 2.9 模拟面试（P0 基础版）
- 配置：选岗位方向、上传简历（PDF/图片/粘贴文字）、粘贴 JD
- AI 出题：基于简历和 JD 生成 5 道面试题
- 文字回答 + 提交
- AI 逐题反馈：优点、不足、改进建议
- 模拟面试结果同样可生成问题卡片，与真实面试统一管理
- AI 调用通过用户自己的 API Key

#### 2.10 个人中心与数据管理
- 历史面试记录列表
- 我的问题卡片库（导航命名「回顾」）
- 数据导出（全部数据导出为 JSON + Markdown）
- 数据删除（单条/全部）
- 隐私政策、用户协议
- 账号注销（无账号版仅文案占位）

### P1 — 验证后添加
- 语音回答 + TTS 提问（模拟面试中用语音作答）
- 说话人自动区分（基于声纹或静音段检测）
- 间隔重复（SM-2 算法）
- 标签体系增强：多级标签、标签颜色
- 搜索增强：全文搜索转写内容（SQLite FTS5）
- 日历视图
- 弱项统计：高频"失误"标签统计、进步趋势
- 多 AI 提供商快捷切换
- 云端同步（可选，用户自持云盘如 iCloud / WebDAV）
- 分享单张问题卡片

### P2 — 产品化阶段
- 真人互练匹配
- 团队/班级空间
- 企业合作
- 课程内容
- 会员体系
- 桌面端（macOS / Windows）
- 浏览器插件（录制在线面试）

### 明确不做
- 不做 AI 内置（不提供免费 AI 额度）
- 不做健康/心理状态判定
- 不做招聘平台/企业端
- 不做陌生人社交/社区
- 不做视频面试模拟（P2 前）
- 不做课程售卖（P2 前）

---

## 第三部分：技术架构

### 3.1 整体架构

```text
┌─────────────────────────────────────┐
│          客户端 App                  │
│  ┌─────────┐  ┌─────────┐          │
│  │ 录音模块 │  │ 转写模块 │          │
│  └────┬────┘  └────┬────┘          │
│       │            │                │
│  ┌────▼────────────▼────┐          │
│  │    本地数据层         │          │
│  │  SQLite / 文件系统    │          │
│  └──────────┬───────────┘          │
│             │                       │
│  ┌──────────▼───────────┐          │
│  │   AI 调用层（直连）   │          │
│  │  用户 API Key → LLM  │          │
│  └──────────────────────┘          │
└─────────────────────────────────────┘
```

无后端服务器（MVP 阶段）。所有数据存储在本地，AI 请求从客户端直连用户配置的 API 端点。

### 3.2 技术栈（定稿版见 docs/PLAN.md）

跨平台框架 Flutter；本地数据库 SQLite（drift）；安全存储 flutter_secure_storage；录音 record；播放 just_audio；本地转写 whisper.cpp（FFI）；状态管理 Riverpod。

### 3.3 数据模型（SQLite 表结构，v1）

```sql
-- 面试记录
CREATE TABLE interviews (
    id TEXT PRIMARY KEY,
    company TEXT,
    position TEXT,
    round TEXT,               -- 一面/二面/HR面
    interview_date TEXT,
    duration_seconds INTEGER,
    audio_file_path TEXT,
    transcript_text TEXT,
    status TEXT DEFAULT 'draft',  -- draft/transcribed/annotated/summarized
    created_at TEXT,
    updated_at TEXT
);

-- 转写片段
CREATE TABLE transcript_segments (
    id TEXT PRIMARY KEY,
    interview_id TEXT,
    start_time REAL,
    end_time REAL,
    text TEXT,
    speaker TEXT,             -- interviewer/candidate/unknown
    FOREIGN KEY (interview_id) REFERENCES interviews(id)
);

-- 标注
CREATE TABLE annotations (
    id TEXT PRIMARY KEY,
    interview_id TEXT,
    segment_id TEXT,
    start_offset INTEGER,
    end_offset INTEGER,
    tag TEXT,                 -- question/answer/highlight/mistake/improvement/custom
    custom_tag_name TEXT,
    note TEXT,
    created_at TEXT,
    FOREIGN KEY (interview_id) REFERENCES interviews(id)
);

-- 问题卡片
CREATE TABLE flashcards (
    id TEXT PRIMARY KEY,
    interview_id TEXT,
    question TEXT,
    my_answer TEXT,
    ai_reference TEXT,
    tags TEXT,                -- JSON array
    source_start_time REAL,
    source_end_time REAL,
    review_count INTEGER DEFAULT 0,
    last_reviewed_at TEXT,
    created_at TEXT,
    FOREIGN KEY (interview_id) REFERENCES interviews(id)
);

-- AI 配置（执行修订 #5：不存 API Key 本体）
CREATE TABLE ai_configs (
    id TEXT PRIMARY KEY,
    provider TEXT,            -- openai/deepseek/kimi/qwen/anthropic/custom
    model_name TEXT,
    base_url TEXT,
    is_active INTEGER DEFAULT 0,
    created_at TEXT
);

-- 标签
CREATE TABLE tags (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE,
    color TEXT,
    is_system INTEGER DEFAULT 0,
    created_at TEXT
);
```

### 3.4 API Key 安全方案
- 使用 flutter_secure_storage 将 API Key 存入 iOS Keychain / Android Keystore（数据表内不存 Key）
- 运行时仅在内存中解密，不写入日志
- 不在任何网络请求中携带 Key 到非用户指定的端点
- 用户可随时删除本地 Key

---

## 第四部分：开发计划（4 周 MVP）

- **第 1 周**：基础框架 + 数据层 + 导航骨架（详见 docs/PLAN.md W1 六步）
- **第 2 周**：录音（含锁屏后台）+ 导入 + whisper.cpp 本地转写 + 逐字稿编辑
- **第 3 周**：标注 + 问题卡片 + 翻卡回顾 + 模拟面试基础流程
- **第 4 周**：总结页 + 按日汇总 + Markdown/JSON 导出 + 数据管理 + 隐私文档 + UI 打磨 + 全链路测试 + 提交 Google Play

---

## 第五部分：关键决策记录

| 决策点 | 选择 | 理由 |
|---|---|---|
| 数据存储 | 本地优先（SQLite） | 隐私、无服务器成本、离线可用 |
| AI 接入 | 用户自持 API Key | 无 AI 成本、隐私、用户自主 |
| 语音转写 | 本地 Whisper 优先 | 录音不出设备，隐私最大化 |
| 平台 | Flutter 跨平台 | 一套代码双端，个人开发效率高 |
| 核心链路 | 录音→转写→标注→卡片→导出 | 聚焦，不贪多 |
| 模拟面试 | 作为录音的辅助功能 | 录音是核心，模拟是补充 |

---

## 第六部分：Agent 执行注意事项

1. 每次实现一个模块，先写测试再写代码。优先保证数据层正确性。
2. API Key 相关代码必须审查：确保 Key 不出现在日志、网络请求头（除非目标就是用户配置的 API 端点）、崩溃报告中。
3. 录音和转写是性能敏感路径：whisper.cpp 调用需放在 Isolate / 后台线程，避免阻塞 UI。
4. SQLite 迁移策略：从 v1 开始就写迁移脚本，后续版本加字段不破坏已有数据。
5. Markdown 导出格式需稳定：用户可能依赖该格式进行二次处理，导出模板需文档化。
6. UI 参考方向：简洁、深色模式优先、卡片式布局。参考 Obsidian 的文件列表 + Notion 的块编辑感 + 音乐 App 的播放器控制条（用于录音回放）。
7. 不做的事情不实现：不要在没有需求的情况下添加登录、云同步、社区、支付等功能。

---

## 执行修订（2026-09-26 确认，与上文冲突时以本节为准）

1. **平台**：MVP 仅 Android（开发机为 Windows，无法构建 iOS）。代码保持双端兼容；W4 后用 Codemagic 云构建补 iOS 上架。
2. **录音**：2.3 的"前台录音"修订为"P0 支持锁屏后台录音"——Android 使用前台服务（`foregroundServiceType="microphone"` + 常驻通知）；iOS Background Audio mode 权限配置先行、真机验证延后。
3. **账号**：2.1 的"手机号/邮箱登录"在 MVP 中完全跳过（与"无后端"矛盾），首次进入仅做身份选择与隐私同意；「我的」保留隐私政策、数据导出/删除；账号注销仅文案占位。
4. **命名**：底部导航为 4 Tab + 中央录音按钮：首页 / 面试 / ⏺ / **回顾**（原"卡片库"）/ 我的。首页提示"N 道题待回顾"，翻卡模式叫"开始回顾"。
5. **安全修正**：3.3 的 `ai_configs` 表**取消 api_key_encrypted 字段**——表内仅存 provider/model_name/base_url；API Key 本体仅存 flutter_secure_storage。
6. **文档结构**：简简历（PDF 提取）走纯 Dart 方案（无 GMS 依赖）；图片简历 OCR 依赖 GMS，国内安卓不可靠，P0 引导用户"粘贴文字"。
