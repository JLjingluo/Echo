import SwiftUI

struct Suggestion: Hashable {
    let icon: String
    let text: String
}

let echoSuggestions: [Suggestion] = [
    Suggestion(icon: "doc.viewfinder", text: "拍张发票，识别成能直接交的报销表"),
    Suggestion(icon: "mic", text: "这段会议录音，转成谁该干什么的清单"),
    Suggestion(icon: "curlybraces.squiggle", text: "写个 js 跑一下，算我这半年的日均花销"),
    Suggestion(icon: "qrcode", text: "生成一张名片二维码，电话和邮箱都塞进去"),
    Suggestion(icon: "text.quote", text: "这篇长文压成 5 条，保留原来的说法"),
    Suggestion(icon: "envelope", text: "回这封英文邮件，客气但把时间咬死"),
    Suggestion(icon: "hand.writing", text: "把相册那张手写便签变成能搜的文字"),
    Suggestion(icon: "calendar", text: "排一份七天大阪行程，每天不超过三个地方"),
    Suggestion(icon: "cup.and.saucer", text: "给这款挂耳写三条文案，别像广告"),
    Suggestion(icon: "function", text: "首付还差 40 万，倒推每月要存多少"),
    Suggestion(icon: "tablecells", text: "这份接口的 JSON，整理成字段说明表"),
    Suggestion(icon: "bell.badge", text: "20 分钟后提醒我关火，别让我忘了"),
    Suggestion(icon: "link", text: "打开这个链接，只告诉我作者的结论"),
    Suggestion(icon: "person.crop.circle", text: "面试自我介绍 120 字，投的是增长岗"),
    Suggestion(icon: "doc.on.doc", text: "这份简历改成投数据岗的版本，砍掉没用的"),
    Suggestion(icon: "chevron.left.forwardslash.chevron.right", text: "这段 Python 换成 JavaScript，逻辑别动"),
    Suggestion(icon: "cart", text: "语音里报的菜谱，汇成一张购物清单"),
    Suggestion(icon: "book", text: "这个开头，给三个走向完全不同的结尾"),
    Suggestion(icon: "scalemass", text: "对比两台洗地机，直接给我一个买哪个"),
    Suggestion(icon: "leaf", text: "做一份自然观察作业单，给幼儿园大班"),
    Suggestion(icon: "receipt", text: "把这堆账单按类别合计，找出涨得最凶的"),
    Suggestion(icon: "moon.z", text: "把这段改委婉点，明天要发给甲方"),
    Suggestion(icon: "lightbulb", text: "列 10 个周末一个人待着能做的事"),
    Suggestion(icon: "qrcode.viewfinder", text: "扫一下这张图里的二维码，看指向哪"),
    Suggestion(icon: "chart.bar", text: "这几组数字，用文字画成能看懂的对比"),
    Suggestion(icon: "phone", text: "教我爸妈清手机内存，写成他们能照做的步骤"),
    Suggestion(icon: "music.note", text: "把这段歌词改成毕业版，押韵别丢"),
    Suggestion(icon: "house", text: "给山里的民宿起 5 个名字，各配一句标语"),
    Suggestion(icon: "graduationcap", text: "这些错题抄成一张练习卷，答案放最后"),
    Suggestion(icon: "checklist", text: "这段微信记录，理成今天要办的事"),
    Suggestion(icon: "text.viewfinder", text: "截图里的收货地址提取出来，存成文件"),
    Suggestion(icon: "figure.walk", text: "膝盖不太好，排一周三练的计划"),
    Suggestion(icon: "questionmark.diamond", text: "跳槽还是留下，帮我把利弊摆平"),
    Suggestion(icon: "timer", text: "写个喝水提醒脚本，工作日每小时一次"),
    Suggestion(icon: "list.bullet.rectangle", text: "说明书太啰嗦，精简成 8 条注意事项"),
    Suggestion(icon: "sparkles", text: "把这个想法拆成能今晚就动手的小步骤"),
    Suggestion(icon: "globe", text: "抓一下这个网页，只留作者的核心结论"),
    Suggestion(icon: "square.and.arrow.down", text: "做一个能离线打开的 HTML 小工具页"),
]

enum EchoWheel {
    private static let bagKey = "echo.wheel.bag"
    private static let prevKey = "echo.wheel.prev"
    private static let greetKey = "echo.wheel.greet"
    private static let greets = ["今天想做点什么？", "从一个任务开始。", "说吧，我在听。",
                                 "想先搞定哪件事？"]

    static func picks(_ count: Int = 4) -> [Suggestion] {
        let d = UserDefaults.standard
        var bag = (d.array(forKey: bagKey) as? [Int]) ?? []
        if bag.count < count {
            var fresh = Array(0..<echoSuggestions.count).shuffled()
            let prev = Set((d.array(forKey: prevKey) as? [Int]) ?? [])
            var guardCount = 0
            while Set(fresh.prefix(count)).isSubset(of: prev) && guardCount < 6 {
                fresh.shuffle()
                guardCount += 1
            }
            bag = fresh
        }
        let ids = Array(bag.prefix(count))
        bag.removeFirst(ids.count)
        d.set(bag, forKey: bagKey)
        d.set(ids, forKey: prevKey)
        return ids.map { echoSuggestions[$0] }
    }

    static func greeting() -> String {
        let d = UserDefaults.standard
        let i = d.integer(forKey: greetKey) % greets.count
        d.set((i + 1) % greets.count, forKey: greetKey)
        return greets[i]
    }
}

struct EmptyState: View {
    @Environment(AppState.self) private var app
    var sendPrompt: (String) -> Void
    var openModel: () -> Void = {}

    @State private var greeting = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                BrandFace(size: 76)
                    .padding(.bottom, 6)

                Text(greeting)
                    .font(Hand.display(36))
                    .foregroundStyle(Ink.line)
                    .fixedSize(horizontal: false, vertical: true)

                Text("你的文件、记录、Key 都留在这台手机上。")
                    .font(Hand.body(16))
                    .foregroundStyle(Ink.gray)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: openModel) {
                    HStack(spacing: 6) {
                        Text(app.apiKey.isEmpty ? "\(app.vendorName) · 还没填 Key" : app.vendorName)
                            .font(Hand.body(14))
                            .foregroundStyle(app.apiKey.isEmpty ? Ink.accent : Ink.gray)
                        TechLabel(text: app.settings.model.isEmpty ? "选择模型" : app.settings.model)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Gutter.edge)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper)
        .onAppear { greeting = EchoWheel.greeting() }
    }
}

extension Color {
    static let gray4Custom = Color(light: Color(rgba: 0xd0d0_d3ff), dark: Color(rgba: 0x4244_4eff))
    static let gray5Custom = Color(light: Color(rgba: 0xf7f7_f9ff), dark: Color(rgba: 0x2526_2aff))
    static let labelCustom = Color(light: Color(rgba: 0x0606_06ff), dark: Color(rgba: 0xfbfb_fcff))
    static let gray3Custom = Color(light: Color(rgba: 0x6b6e_7bff), dark: Color(rgba: 0x9294_a0ff))
}
