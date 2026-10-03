import Foundation
import Observation

@MainActor
@Observable
final class AnalyticsDashboardViewModel {
    var analytics: PostAnalytics?
    var creatorOverview: CreatorOverview?
    var isLoading = false
    var errorMessage: String?
    var hasAttemptedLoad = false
    var chartMetric: AnalyticsChartMetric = .views

    let postID: String?
    private let analyticsUseCase: PostAnalyticsUseCase

    init(postID: String? = nil, analyticsUseCase: PostAnalyticsUseCase) {
        self.postID = postID
        self.analyticsUseCase = analyticsUseCase
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasAttemptedLoad = true
        }

        if let postID {
            // Post insights: don't fail the whole screen if creator overview errors.
            do {
                analytics = try await analyticsUseCase.fetchAnalytics(postID: postID)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            creatorOverview = try? await analyticsUseCase.fetchCreatorOverview()
            return
        }

        do {
            creatorOverview = try await analyticsUseCase.fetchCreatorOverview()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
