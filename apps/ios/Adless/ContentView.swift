import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()

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

                Button {
                    if viewModel.hasSubscription {
                        Task { await viewModel.toggle() }
                    } else {
                        viewModel.isSubscriptionPresented = true
                    }
                } label: {
                    Image(systemName: viewModel.hasSubscription
                          ? (viewModel.isOn ? "shield.fill" : "shield")
                          : "lock.shield")
                        .font(.system(size: 56, weight: .medium))
                        .frame(width: 144, height: 144)
                        .foregroundStyle(viewModel.isOn ? .white : .primary)
                        .background(viewModel.isOn ? Color.green : Color.secondary.opacity(0.14))
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.hasSubscription
                                    ? (viewModel.isOn ? "Turn off blocking" : "Turn on blocking")
                                    : "Subscribe to turn on blocking")
                .accessibilityHint(viewModel.hasSubscription
                                   ? "Turns DNS blocking on or off"
                                   : "Opens subscription options")

                Text(viewModel.statusText)
                    .font(.headline)
                    .foregroundStyle(viewModel.isOn ? .green : Color.primary.opacity(0.58))

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
        }
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
        .onChange(of: viewModel.isSubscriptionPresented) { _, isPresented in
            guard isPresented else { return }
            subscriptionDetent = .medium
        }
        .sheet(isPresented: $viewModel.isSubscriptionPresented) {
            SubscriptionView(manager: viewModel.subscriptionManager)
                .interactiveDismissDisabled(false)
                .presentationDetents([.medium, .large], selection: $subscriptionDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    @State private var subscriptionDetent: PresentationDetent = .medium
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
