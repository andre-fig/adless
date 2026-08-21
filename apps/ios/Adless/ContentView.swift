import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var subscriptionSheetHeight: CGFloat?

    private var subscriptionDetent: PresentationDetent {
        guard let subscriptionSheetHeight else { return .medium }
        return .height(subscriptionSheetHeight)
    }

    private var appBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.059, green: 0.078, blue: 0.102)
            : Color(.systemBackground)
    }

    private var inactiveButtonForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.67, green: 0.69, blue: 0.74)
            : Color(red: 0.40, green: 0.43, blue: 0.49)
    }

    private var inactiveButtonBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.145, green: 0.165, blue: 0.20)
            : Color(red: 0.92, green: 0.93, blue: 0.95)
    }

    private var inactiveButtonBorder: Color {
        colorScheme == .dark
            ? Color(red: 0.25, green: 0.27, blue: 0.31)
            : Color(red: 0.84, green: 0.86, blue: 0.89)
    }

    private var activeButtonBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.60, blue: 0.91)
            : Color(red: 0.20, green: 0.45, blue: 0.82)
    }

    private var activeButtonBorder: Color {
        colorScheme == .dark
            ? Color(red: 0.58, green: 0.76, blue: 0.98)
            : Color(red: 0.52, green: 0.70, blue: 0.94)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 20) {
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
                                         : inactiveButtonForeground)
                        .background(viewModel.isOn
                                    ? activeButtonBackground
                                    : inactiveButtonBackground)
                        .overlay {
                            Circle()
                                .stroke(
                                    viewModel.isOn
                                        ? activeButtonBorder
                                        : inactiveButtonBorder,
                                    lineWidth: 1
                                )
                        }
                        .clipShape(Circle())
                        .shadow(
                            color: viewModel.isOn
                                ? Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12)
                                : Color.black.opacity(colorScheme == .dark ? 0.30 : 0.14),
                            radius: viewModel.isOn && colorScheme == .dark ? 12 : 10,
                            x: 0,
                            y: viewModel.isOn && colorScheme == .dark ? 7 : 6
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
                    BlockingStatsView(
                        blockedTodayValue: viewModel.blockedTodayCount.formatted(.number),
                        allTimeValue: viewModel.allTimeBlockCount.formatted(.number)
                    )
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                if viewModel.hasSubscription {
                    VStack(spacing: 4) {
                        Text(viewModel.isOn
                             ? "Browse cleaner. Stay private."
                             : "Turn Adless back on to keep blocking.")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)

                        Text(viewModel.isOn
                             ? "Adless keeps working even after you close the app."
                             : "Your blocking history is saved while protection is paused.")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.58))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 2)
                } else {
                    Text("Start your free trial to turn on protection.")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }

                if !viewModel.hasSubscription {
                    BlockingStatsView(
                        blockedTodayValue: viewModel.blockedTodayCount.formatted(.number),
                        allTimeValue: viewModel.allTimeBlockCount.formatted(.number)
                    )
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .opacity(0)
                    .accessibilityHidden(true)
                }

                Spacer()
            }
            .padding()
            .offset(y: -52)

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

private struct BlockingStatsView: View {
    let blockedTodayValue: String
    let allTimeValue: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(blockedTodayValue)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text("ad & tracker requests blocked today")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()
                .padding(.horizontal, 20)

            HStack(spacing: 4) {
                Text(allTimeValue)
                    .monospacedDigit()

                Text("all-time blocks")
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary.opacity(0.58))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: AppViewModel())
    }
}
