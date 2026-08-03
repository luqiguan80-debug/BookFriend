import SwiftUI

/// 启动欢迎页：苹果新品式极简花体，逐行淡入，停留片刻后自动淡出，点按可跳过
struct WelcomeView: View {
    var onFinish: () -> Void

    @State private var line1Visible = false
    @State private var line2Visible = false
    @State private var hairlineVisible = false
    @State private var captionVisible = false
    @State private var slowZoom = false
    @State private var finished = false

    /// 「BF」用 Snell Roundhand 花体，混排在同一基线上
    private var message: Text {
        var attr = AttributedString("你的 BF 永远都在")
        attr.font = Font.system(.title3, weight: .light)
        if let range = attr.range(of: "BF") {
            attr[range].font = .custom("SnellRoundhand", size: 36)
        }
        return Text(attr)
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            #else
            Color(.systemBackground).ignoresSafeArea()
            #endif
            // 极淡的纵向明暗，给纯白底加一点纵深，近看才察觉
            LinearGradient(colors: [Color.primary.opacity(0.035), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()

            // 整体缓慢推近（Ken Burns 式），静帧也有电影感
            VStack(spacing: 20) {
                Text("欢迎回来")
                    .font(.system(size: 56, weight: .ultraLight))
                    .tracking(1)
                    .opacity(line1Visible ? 1 : 0)
                    .scaleEffect(line1Visible ? 1 : 0.96)
                    .blur(radius: line1Visible ? 0 : 14)

                // 发丝线从中点向两端展开，Keynote 式的收束节拍
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(width: hairlineVisible ? 110 : 0, height: 0.5)

                message
                    .foregroundStyle(.secondary)
                    .opacity(line2Visible ? 1 : 0)
                    .offset(y: line2Visible ? 0 : 10)
                    .blur(radius: line2Visible ? 0 : 6)
            }
            .scaleEffect(slowZoom ? 1.025 : 1.0)

            VStack {
                Spacer()
                Text("B O O K F R I E N D")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(.tertiary)
                    .opacity(captionVisible ? 1 : 0)
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) { line1Visible = true }
            withAnimation(.easeInOut(duration: 0.9).delay(1.1)) { hairlineVisible = true }
            withAnimation(.easeOut(duration: 1.0).delay(1.3)) { line2Visible = true }
            withAnimation(.easeOut(duration: 0.8).delay(1.8)) { captionVisible = true }
            withAnimation(.linear(duration: 4.0)) { slowZoom = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                finish()
            }
        }
    }

    /// 点按跳过和计时结束都可能触发，只放行第一次
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
