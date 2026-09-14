// 履歴パネルの中身（SwiftUI）。キー操作は HistoryPanelController が先に処理し、
// ここは表示と、マウスでのクリック選択・検索欄の入力を担当する。

import SwiftUI

struct HistoryPanelView: View {
    @ObservedObject var model: HistoryPanelModel
    @ObservedObject private var history = ClipboardHistory.shared
    let controller: HistoryPanelController
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("Search history"), text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onChange(of: model.query) { _, _ in model.selectedIndex = 0 }
                if !history.isEnabled {
                    Text(L("History is off"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            let items = model.filtered
            if items.isEmpty {
                Spacer()
                Text(history.isEnabled ? L("No items yet") : L("Turn on clipboard history in Settings to use this panel."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                                row(index: index, entry: entry)
                                    .id(entry.id)
                                    .onTapGesture { controller.confirm(index: index) }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selectedIndex) { _, newValue in
                        if items.indices.contains(newValue) {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(items[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 14) {
                hint("↩", L("type"))
                hint("⌘↩", L("copy"))
                hint("1–9", L("pick"))
                hint("esc", L("close"))
                Spacer()
                if PanelPosition.current == .custom {
                    Text(L("Drag to move"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: HistoryPanelController.panelWidth, height: HistoryPanelController.panelHeight)
        .background(.regularMaterial)
        .onAppear { searchFocused = true }
    }

    private func row(index: Int, entry: ClipEntry) -> some View {
        let selected = index == model.selectedIndex
        return HStack(alignment: .top, spacing: 10) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(selected ? .white.opacity(0.9) : .secondary)
                .frame(width: 14, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.preview)
                    .lineLimit(2)
                    .foregroundStyle(selected ? .white : .primary)
                Text(L("%d characters · %@", entry.characterCount,
                       entry.copiedAt.formatted(date: .omitted, time: .shortened)))
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
