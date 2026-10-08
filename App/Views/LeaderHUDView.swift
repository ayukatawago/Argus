import ArgusConfigKit
import SwiftUI

/// Which-key overlay shown while leader mode is pending: every bound second key and what it does,
/// generated from `LeaderActionCatalog` so it always matches what the dispatcher will do.
struct LeaderHUDView: View {
    @ObservedObject private var state = LeaderModeState.shared
    @EnvironmentObject var configStore: ArgusConfigStore

    var body: some View {
        if state.showHUD {
            let entries = LeaderActionCatalog.entries(config: configStore.config)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(configStore.config.leaderKey) then…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                let columns = [GridItem(.adaptive(minimum: 190), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(entries, id: \.key) { entry in
                        HStack(spacing: 8) {
                            Text(entry.key)
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .frame(minWidth: 22)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12)))
                            Text(entry.title)
                                .font(.callout)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 720)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 12)
            .padding(.bottom, 24)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
