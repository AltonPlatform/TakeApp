import SwiftUI
import Charts

struct AnalyticsDashboardView: View {
    @Bindable var viewModel: AnalyticsDashboardViewModel
    /// When embedded in a bottom sheet, hide the navigation title (chrome provides it).
    var embeddedInSheet: Bool = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.analytics == nil && viewModel.creatorOverview == nil {
                ProgressView("Loading analytics...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage,
                      viewModel.analytics == nil,
                      viewModel.creatorOverview == nil {
                ContentUnavailableView(
                    "Unable to load analytics",
                    systemImage: "chart.bar.xaxis",
                    description: Text(error)
                )
            } else if viewModel.postID != nil,
                      viewModel.analytics == nil,
                      viewModel.hasAttemptedLoad {
                ContentUnavailableView(
                    "No insights yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text(viewModel.errorMessage ?? "Stats will appear after people view this post.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if let analytics = viewModel.analytics {
                            summarySection(analytics)
                            dynamicsSection(analytics)
                            engagementRatesSection(analytics)
                            sourceSection(analytics)
                            audienceSection(analytics)
                            earningsSection(analytics)
                        }
                        if let overview = viewModel.creatorOverview, viewModel.postID == nil {
                            creatorOverviewSection(overview)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle(embeddedInSheet ? "" : (viewModel.postID == nil ? "Creator Analytics" : "Post insights"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(embeddedInSheet ? .hidden : .automatic, for: .navigationBar)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    // MARK: - Summary (Takes-style grid)

    private func summarySection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Overview")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summaryCard(
                    title: "Views",
                    value: formatCount(analytics.totalViews),
                    comparison: comparison(forAbsolute: analytics.totalViews)
                )
                summaryCard(
                    title: "Viewers",
                    value: formatCount(analytics.uniqueVisitors),
                    comparison: comparison(forAbsolute: analytics.uniqueVisitors)
                )
                summaryCard(
                    title: "Profile visits",
                    value: formatCount(analytics.profileViews),
                    comparison: .typical
                )
                summaryCard(
                    title: "Followers",
                    value: formatCount(analytics.followersGained),
                    comparison: .typical
                )
            }
        }
    }

    private func summaryCard(title: String, value: String, comparison: MetricComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
            Text(comparison.label)
                .font(.caption)
                .foregroundStyle(comparison.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Dynamics chart

    private func dynamicsSection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Dynamics")
                Spacer()
                Picker("Metric", selection: $viewModel.chartMetric) {
                    ForEach(AnalyticsChartMetric.allCases) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if analytics.daily.isEmpty {
                Text("No daily data yet")
                    .foregroundStyle(.secondary)
            } else {
                let points = cumulativeDaily(analytics.daily, metric: viewModel.chartMetric)
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value(viewModel.chartMetric.title, point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.primary)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value(viewModel.chartMetric.title, point.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.primary.opacity(0.08))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.day().month(.abbreviated))
                            }
                        }
                    }
                }
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.25), value: viewModel.chartMetric)
            }
        }
    }

    // MARK: - Engagement rates

    private func engagementRatesSection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("What drives views")
            Text("Rates are based on unique viewers")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                rateRow(
                    icon: "heart.fill",
                    title: "Like rate",
                    rate: analytics.likeRate,
                    comparison: comparison(forRate: analytics.likeRate)
                )
                Divider().padding(.leading, 52)
                rateRow(
                    icon: "bubble.right.fill",
                    title: "Reply rate",
                    rate: analytics.replyRate,
                    comparison: comparison(forRate: analytics.replyRate)
                )
                Divider().padding(.leading, 52)
                rateRow(
                    icon: "paperplane.fill",
                    title: "Share rate",
                    rate: analytics.shareRate,
                    comparison: comparison(forRate: analytics.shareRate)
                )
                Divider().padding(.leading, 52)
                rateRow(
                    icon: "arrow.2.squarepath",
                    title: "Repost rate",
                    rate: analytics.repostRate,
                    comparison: comparison(forRate: analytics.repostRate)
                )
            }
        }
    }

    private func rateRow(
        icon: String,
        title: String,
        rate: Double,
        comparison: MetricComparison
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())

            Text(title)
                .font(.body)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatPercent(rate))
                    .font(.body.weight(.semibold))
                Text(comparison.label)
                    .font(.caption)
                    .foregroundStyle(comparison.color)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Sources

    private func sourceSection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Top sources of views")

            if analytics.sourceBreakdown.isEmpty {
                Text("No view data yet")
                    .foregroundStyle(.secondary)
            } else {
                let total = max(analytics.sourceBreakdown.reduce(0) { $0 + $1.count }, 1)
                VStack(spacing: 10) {
                    ForEach(analytics.sourceBreakdown, id: \.source) { item in
                        HStack {
                            Text(friendlySource(item.source))
                                .font(.subheadline)
                            Spacer()
                            Text(formatPercent(Double(item.count) / Double(total)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(item.count), total: Double(total))
                            .tint(.primary)
                    }
                }
            }
        }
    }

    // MARK: - Audience

    private func audienceSection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Audience")

            if analytics.ageBreakdown.isEmpty && analytics.genderBreakdown.isEmpty {
                Text("Audience details appear as more people with profile data view this post.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !analytics.ageBreakdown.isEmpty {
                    Text("Age")
                        .font(.subheadline.weight(.semibold))
                    audienceBars(analytics.ageBreakdown)
                }
                if !analytics.genderBreakdown.isEmpty {
                    Text("Gender")
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 8)
                    audienceBars(analytics.genderBreakdown)
                } else {
                    Text("Gender breakdown isn’t available yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func audienceBars(_ buckets: [AudienceBucket]) -> some View {
        let total = max(buckets.reduce(0) { $0 + $1.count }, 1)
        return VStack(spacing: 8) {
            ForEach(buckets) { bucket in
                HStack {
                    Text(bucket.label)
                        .font(.subheadline)
                        .frame(width: 52, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: geo.size.width * CGFloat(bucket.count) / CGFloat(total), height: 10)
                    }
                    .frame(height: 10)
                    Text(formatPercent(Double(bucket.count) / Double(total)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Earnings / creator overview (unchanged intent)

    private func earningsSection(_ analytics: PostAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Earnings")
                Spacer()
                Text("\(Int(analytics.creatorSharePct))% share")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Monetizable views", value: formatCount(analytics.monetizableViews), icon: "dollarsign.circle")
                metricCard(
                    title: "Est. earnings",
                    value: String(format: "$%.2f", analytics.estimatedEarningsUsd),
                    icon: "banknote"
                )
            }
        }
    }

    private func creatorOverviewSection(_ overview: CreatorOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Creator overview")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricCard(title: "Views (30d)", value: formatCount(overview.totalViews30d), icon: "eye")
                metricCard(title: "Monetizable", value: formatCount(overview.monetizableViews), icon: "dollarsign.circle")
                metricCard(
                    title: "Est. earnings",
                    value: String(format: "$%.2f", overview.estimatedEarningsUsd),
                    icon: "banknote"
                )
                metricCard(title: "Profile views", value: formatCount(overview.profileViews), icon: "person.crop.circle")
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func metricCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func formatPercent(_ rate: Double) -> String {
        String(format: "%.2f%%", rate * 100)
    }

    private func friendlySource(_ raw: String) -> String {
        switch raw {
        case "feed": return "Feed"
        case "profile": return "Profile"
        case "search": return "Search"
        case "recommendation": return "Recommendations"
        case "hashtag": return "Hashtag"
        case "mention": return "Mention"
        case "internal_link": return "In-app link"
        case "direct": return "Direct"
        case "ad_adjacent": return "Near ads"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func cumulativeDaily(
        _ daily: [DailyViews],
        metric: AnalyticsChartMetric
    ) -> [(date: Date, value: Int)] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var running = 0
        return daily.compactMap { day in
            guard let date = formatter.date(from: day.date) else { return nil }
            running += day.value(for: metric)
            return (date, running)
        }
    }

    private func comparison(forRate rate: Double) -> MetricComparison {
        if rate >= 0.02 { return .higher }
        if rate > 0, rate < 0.005 { return .lower }
        return .typical
    }

    private func comparison(forAbsolute value: Int) -> MetricComparison {
        if value == 0 { return .typical }
        return .typical
    }
}

private enum MetricComparison {
    case lower, typical, higher

    var label: String {
        switch self {
        case .lower: return "Lower"
        case .typical: return "Typical"
        case .higher: return "Higher"
        }
    }

    var color: Color {
        switch self {
        case .higher: return .green
        case .lower, .typical: return .secondary
        }
    }
}
