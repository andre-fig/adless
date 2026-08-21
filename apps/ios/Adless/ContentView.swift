import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var subscriptionSheetHeight: CGFloat?

    private var subscriptionDetent: PresentationDetent {
        guard let subscriptionSheetHeight else { return .medium }
        return .height(subscriptionSheetHeight)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 14) {
                    AdlessLogoView(size: 56)

                    VStack(spacing: 6) {
                        Text(viewModel.isOn ? "Protection Active" : "Protection Off")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(!viewModel.hasSubscription
                             ? "Block ads and trackers across your iPhone."
                             : (viewModel.isOn
                                ? "Adless is working quietly in the background."
                                : "Your protection is paused."))
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.58))
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: viewModel.hasSubscription ? 24 : 16) {
                Button {
                    if viewModel.hasSubscription {
                        Task { await viewModel.toggle() }
                    } else {
                        viewModel.isSubscriptionPresented = true
                    }
                } label: {
                    Image(systemName: viewModel.isOn ? "shield.fill" : "power")
                        .font(.system(size: 56, weight: .medium))
                        .frame(width: 144, height: 144)
                        .foregroundStyle(viewModel.isOn
                                         ? Color.white
                                         : Color(red: 0.40, green: 0.43, blue: 0.49))
                        .background(viewModel.isOn
                                    ? Color.green
                                    : Color(red: 0.92, green: 0.93, blue: 0.95))
                        .overlay {
                            Circle()
                                .stroke(
                                    viewModel.isOn
                                        ? Color.clear
                                        : Color(red: 0.84, green: 0.86, blue: 0.89),
                                    lineWidth: 1
                                )
                        }
                        .clipShape(Circle())
                        .shadow(
                            color: viewModel.isOn ? Color.clear : Color.black.opacity(0.14),
                            radius: 10,
                            x: 0,
                            y: 6
                        )
                }
                .accessibilityLabel(viewModel.hasSubscription
                                    ? (viewModel.isOn ? "Turn off blocking" : "Turn on blocking")
                                    : "Subscribe to turn on blocking")
                .accessibilityHint(viewModel.hasSubscription
                                   ? "Turns DNS blocking on or off"
                                   : "Opens subscription options")

                if !viewModel.hasSubscription {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.medium))

                        Text("Premium access required")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.12, green: 0.43, blue: 0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(AdlessTheme.selectedPlanBackground)
                    .clipShape(Capsule())
                }
                }

                if viewModel.hasSubscription {
                    VStack(spacing: 0) {
                        BlockingStatRow(
                            value: viewModel.blockedTodayCount.formatted(.number),
                            label: "ad & tracker requests blocked today"
                        )

                        Divider()
                            .padding(.horizontal, 20)

                        BlockingStatRow(
                            value: viewModel.allTimeBlockCount.formatted(.number),
                            label: "all-time blocks"
                        )
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                Text(!viewModel.hasSubscription
                     ? "Start your free trial to turn on protection."
                     : (viewModel.isOn
                        ? "Browse cleaner. Stay private."
                        : "Turn Adless back on to keep blocking."))
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)

                if !viewModel.hasSubscription {
                    VStack(spacing: 0) {
                        BlockingStatRow(
                            value: viewModel.blockedTodayCount.formatted(.number),
                            label: "ad & tracker requests blocked today"
                        )

                        Divider()
                            .padding(.horizontal, 20)

                        BlockingStatRow(
                            value: viewModel.allTimeBlockCount.formatted(.number),
                            label: "all-time blocks"
                        )
                    }
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(0)
                    .accessibilityHidden(true)
                }

                Spacer()
            }
            .padding()
            .offset(y: -24)

            if viewModel.isSubscriptionPresented {
                Color.black
                    .opacity(0.24)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSubscriptionPresented)
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.isSubscriptionPresented else { return }
            viewModel.isSubscriptionPresented = false
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.applicationDidBecomeActive() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await MainActor.run {
                    viewModel.refreshBlockingStats()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .sheet(isPresented: $viewModel.isSubscriptionPresented) {
            SubscriptionView(
                manager: viewModel.subscriptionManager,
                onContentHeightChange: { contentHeight in
                    let proposedHeight = contentHeight + 2
                    guard proposedHeight.isFinite, proposedHeight > 0 else { return }

                    if subscriptionSheetHeight == nil || abs(subscriptionSheetHeight! - proposedHeight) > 1 {
                        subscriptionSheetHeight = proposedHeight
                    }
                }
            )
                .interactiveDismissDisabled(false)
                .presentationDetents([subscriptionDetent])
                .presentationDragIndicator(.hidden)
                .presentationBackground(AdlessTheme.subscriptionDrawerBackground)
                .presentationBackgroundInteraction(.enabled)
        }
    }
}

private struct BlockingStatRow: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.primary.opacity(0.58))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}
