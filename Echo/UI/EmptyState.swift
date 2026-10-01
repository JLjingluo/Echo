import SwiftUI

struct EmptyState: View {
    var onPick: (String) -> Void

    private let cards: [(String, String, String)] = [
        ("square.and.pencil", "写一个贪吃蛇网页小游戏", "html"),
        ("doc.text.magnifyingglass", "把这段英文摘要翻成中文并存成 md", "text"),
        ("qrcode", "生成一个含指定链接的二维码", "tool"),
        ("tablecells", "整理一份北京周末两日游行程表，导出 CSV", "csv"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("今天想做点什么？")
                    .font(.system(size: 30, weight: .bold, design: .default))
                Text("所有执行都在手机本地，产出文件可直接导出到「文件」App")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 10) {
                ForEach(cards, id: \.1) { card in
                    Button {
                        onPick(card.1)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: card.0)
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            Text(card.1)
                                .font(.system(size: 16))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glass(.rect(20), interactive: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
