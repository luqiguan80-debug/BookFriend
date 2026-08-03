# BookFriend · 书友

> 一款不绑定任何书城的本地阅读器，接入你自己的 AI——边读边讲、边读边问，划过的每一笔都自动变成笔记。
>
> A local-first e-book reader tied to no bookstore, powered by *your own* AI — explain, translate, and chat while you read; every highlight becomes a note automatically.

**BYOB（Bring Your Own Book）× BYOK（Bring Your Own Key）。**
书和笔记全部存在本机，AI 请求直达你自己配置的接口，不经过任何第三方服务器。无账号、无统计、无订阅——你的书、你的 key、你的笔记。

**BYOB (Bring Your Own Book) × BYOK (Bring Your Own Key).**
Books and notes live entirely on your device. AI requests go straight to the endpoint *you* configure — no third-party server in between. No accounts, no analytics, no subscriptions.

---

## 中文

### 为什么是 BookFriend？

读非虚构类书籍时，我们常卡在三个地方：**读不懂、记不住、看不下去**。
BookFriend 把 AI 做成一个坐在你旁边的读书伙伴：

- **读不懂** → 选中任何一段话，让它结合上下文讲给你听
- **记不住** → 划线和问答自动沉淀为笔记卡片，读完一键导出
- **看不下去** → 不懂就问，追问到底，阅读从单向输入变成对话

### 功能

#### 📚 阅读器本体
- 导入 **EPUB / PDF / TXT**（MOBI 请先用 Calibre 转 EPUB）
- EPUB 精细排版：字号 / 主题 / 深色模式 / 目录跳转
- PDF 双模式：**原版渲染** + **重排阅读模式**（抽取文字、去页眉页脚、碎行合并回段落、识别标题层级，大多数文字版 PDF 可以像读书一样读）
- 扫描版 PDF 导入时自动 **Vision OCR** 加文字层，图片书也能选中、能问 AI
- TXT 自动识别 UTF-8 / GB18030 编码，启发式识别章节标题生成目录

#### 🤖 AI 伴读（产品灵魂）
- 选中文字 → **讲解** / **翻译** / **展开背景**，流式输出，随时可停
- **多轮对话**：对回答不满意就追问，面板里完整保留上下文
- 上下文自动携带：书名、章节、选段前后文，AI 知道你在读什么

#### 📝 自动笔记
- 划线 + AI 问答自动沉淀为**笔记卡片**，按书 → 章节归档
- 多轮对话结束后 AI 自动**提炼要点**更新卡片，而不是堆砌问答记录
- 一键导出 **Markdown**，直接导入 Obsidian / Notion

#### 🔑 BYOK · 隐私
- 支持任何 **OpenAI 兼容接口**（DeepSeek / 通义 / Kimi / 中转 / Ollama……）+ **Anthropic 官方接口**
- 自定义 base URL、模型名；key 只存本机 **Keychain**，绝不上传
- 没有账号体系，没有自有服务器，没有任何埋点统计

#### 🖥️📱 双平台
- **iOS / iPadOS** 与 **macOS** 双 target，SwiftUI + SwiftData 共享绝大部分代码
- iOS 用 sheet 弹 AI 面板，macOS 用侧边栏，各自贴合平台习惯

### 截图

_（待补充：书架 / AI 面板 / 笔记列表）_

### 构建

```bash
brew install xcodegen
xcodegen          # 生成 ShuYou.xcodeproj
open ShuYou.xcodeproj
```

在 Xcode 中选择你的 Development Team 即可运行（iOS 17+ / macOS 14+）。
依赖：[ZIPFoundation](https://github.com/weichsel/ZIPFoundation)（SwiftPM 自动拉取）。

命令行构建（免签名）：

```bash
# macOS
xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS 模拟器
xcodebuild -project ShuYou.xcodeproj -scheme ShuYou \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### 架构

```
Sources/
├── App/         iOS 入口
├── Mac/         macOS 入口与 Mac 版阅读器
├── Models/      Book / NoteCard（SwiftData）、主题
├── Services/    AIService（SSE 流式，OpenAI 兼容 + Anthropic）
│                AISettings（BYOK，key 存 Keychain）
│                PDF 重排 / 字体扫描 / Vision OCR / TXT 章节识别
│                EPUB 导入 / Markdown 导出 / 本地存储约定
├── EPUB/        EPUB 解析（container.xml → OPF → spine → NCX/Nav 目录）
├── Reader/      三个阅读器 + 选段中枢（SelectionCenter）
│                EPUB：WKWebView 渲染，注入 JS 实现选段定位与划线
│                PDF：PDFKit，选段 → AI；划线 = PDF 高亮批注
│                TXT：TextView，选段 → AI
├── Shared/      跨平台补丁、Markdown 渲染、选中动作条
└── Views/       书架 / AI 面板（流式多轮）/ 笔记列表 / 设置 / 目录侧栏
```

#### 关键设计

- **选段链路**：三种阅读器统一经 `SelectionCenter` 取选段，每次新选段 = 新 `AIRequest` = 新面板实例 = 干净会话，无需手动清状态
- **划线定位**：EPUB 用「文本 + 章节内偏移」锚定，重开章节后 JS 重新上色
- **笔记提炼**：仅 1 轮对话存 AI 原始回答；≥2 轮结束后由 AI 提炼要点就地更新卡片，提取失败兜底存问答转录

### 路线图

下一步：断档续接（重开书时 AI 回顾上次进度）、章节钩子（带着问题读）、全书问答。

---

## English

### Why BookFriend?

When reading non-fiction, we usually get stuck in three places: **can't understand, can't remember, can't keep going**.
BookFriend turns AI into a reading companion sitting next to you:

- **Can't understand** → select any passage and get it explained in the context of the book
- **Can't remember** → highlights and Q&A automatically become note cards; export everything when you finish
- **Can't keep going** → ask questions and follow up until it's clear — reading becomes a conversation, not a one-way intake

### Features

#### 📚 The Reader
- Import **EPUB / PDF / TXT** (convert MOBI to EPUB with Calibre first)
- Refined EPUB typography: font size / themes / dark mode / table of contents
- Dual PDF modes: **original rendering** + **reflow reading mode** (text extraction, header/footer removal, broken-line merging, heading detection — most text-based PDFs read like real books)
- Scanned PDFs get an automatic **Vision OCR** text layer on import — image-only books become selectable and askable
- TXT auto-detects UTF-8 / GB18030 encodings and heuristically builds a chapter outline

#### 🤖 AI Companion (the soul of the product)
- Select text → **Explain** / **Translate** / **Expand background**, streamed, stoppable anytime
- **Multi-turn chat**: not satisfied? Follow up — the panel keeps full context
- Context comes for free: book title, chapter, and surrounding text, so the AI knows what you're reading

#### 📝 Automatic Notes
- Highlights + AI Q&A settle into **note cards**, filed by book → chapter
- After multi-turn chats, the AI **distills key points** into the card instead of dumping raw transcripts
- One-tap **Markdown export**, ready for Obsidian / Notion

#### 🔑 BYOK & Privacy
- Works with any **OpenAI-compatible endpoint** (DeepSeek / Qwen / Kimi / relays / Ollama…) plus the official **Anthropic API**
- Custom base URL and model name; keys live only in the local **Keychain**, never uploaded
- No account system, no first-party server, no analytics of any kind

#### 🖥️📱 Two Platforms
- Dual targets for **iOS / iPadOS** and **macOS**; SwiftUI + SwiftData share most of the code
- AI panel shows as a sheet on iOS and a sidebar on macOS — native to each platform

### Screenshots

_(Coming soon: bookshelf / AI panel / notes list)_

### Build

```bash
brew install xcodegen
xcodegen          # generates ShuYou.xcodeproj
open ShuYou.xcodeproj
```

Pick your Development Team in Xcode and run (iOS 17+ / macOS 14+).
Dependency: [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (fetched automatically via SwiftPM).

Command-line builds (no signing):

```bash
# macOS
xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# iOS Simulator
xcodebuild -project ShuYou.xcodeproj -scheme ShuYou \
  -destination 'generic/platform=iOS Simulator' build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Architecture

```
Sources/
├── App/         iOS entry point
├── Mac/         macOS entry point and Mac readers
├── Models/      Book / NoteCard (SwiftData), themes
├── Services/    AIService (SSE streaming, OpenAI-compatible + Anthropic)
│                AISettings (BYOK, keys in Keychain)
│                PDF reflow / font scanning / Vision OCR / TXT chapter detection
│                EPUB import / Markdown export / local storage conventions
├── EPUB/        EPUB parsing (container.xml → OPF → spine → NCX/Nav TOC)
├── Reader/      Three readers + selection hub (SelectionCenter)
│                EPUB: WKWebView rendering, injected JS for selection & highlights
│                PDF: PDFKit, selection → AI; highlights = PDF annotations
│                TXT: TextView, selection → AI
├── Shared/      Cross-platform shims, Markdown rendering, selection action bar
└── Views/       Bookshelf / AI panel (streaming, multi-turn) / notes / settings / TOC sidebar
```

#### Key Designs

- **Selection pipeline**: all three readers go through `SelectionCenter`; each new selection = new `AIRequest` = fresh panel instance = clean session, no manual state clearing
- **Highlight anchoring**: EPUB highlights anchor by "text + offset within chapter"; JS re-applies them when the chapter reopens
- **Note distillation**: single-turn chats save the raw AI answer; after 2+ turns the AI distills key points and updates the card in place, falling back to a Q&A transcript if extraction fails

### Roadmap

Next up: resume-with-recap (AI reviews your last progress when you reopen a book), chapter hooks (questions to read with), whole-book Q&A.

---

## License

[MIT](LICENSE) © 2026 luqiguan80-debug — 可自由使用、修改、商用，保留版权声明即可。
Free to use, modify, and distribute, commercially or otherwise, with attribution.
