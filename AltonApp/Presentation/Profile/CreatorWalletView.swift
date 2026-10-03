import SwiftUI

struct CreatorWalletView: View {
    let earningsRepository: EarningsRepository

    @State private var balance: CreatorBalance?
    @State private var isLoading = false
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        Group {
            if isLoading && balance == nil {
                ProgressView("Loading wallet...")
            } else if let errorMessage, balance == nil {
                ContentUnavailableView(
                    "Unable to load wallet",
                    systemImage: "creditcard",
                    description: Text(errorMessage)
                )
            } else if let balance {
                List {
                    Section {
                        Text("Wallet integration coming soon")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        metricRow("Available", value: formatUSD(balance.availableUsd))
                        metricRow("Pending", value: formatUSD(balance.pendingUsd))
                        metricRow("Lifetime", value: formatUSD(balance.lifetimeEarnedUsd))
                    }

                    Section {
                        HStack {
                            Text("Creator share")
                            Spacer()
                            Text("\(Int(balance.creatorSharePct))%")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        Text("Minimum payout \(formatUSD(balance.minPayoutUsd))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            Task { await requestPayout(available: balance.availableUsd, min: balance.minPayoutUsd) }
                        } label: {
                            if isRequesting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Request payout")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isRequesting || balance.availableUsd < balance.minPayoutUsd)

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Wallet")
        .task { await load() }
        .refreshable { await load() }
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }

    private func formatUSD(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            balance = try await earningsRepository.fetchCreatorBalance()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestPayout(available: Double, min: Double) async {
        guard available >= min else { return }
        isRequesting = true
        statusMessage = nil
        defer { isRequesting = false }
        do {
            let payout = try await earningsRepository.requestPayout(amountUsd: available)
            // Stub payouts use sui_tx_hash = "stub-…"; hide chain details until real SUI transfers.
            statusMessage = payout.status == "pending" || payout.status == "completed"
                ? "Payout \(payout.status)."
                : "Payout requested (\(payout.status))."
            await load()
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
