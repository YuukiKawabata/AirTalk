import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    var isPlusActive: Bool {
        !purchasedProductIDs.isDisjoint(with: AirTalkPlus.productIDs)
    }

    var sortedProducts: [Product] {
        products.sorted { lhs, rhs in
            productSortOrder(lhs.id) < productSortOrder(rhs.id)
        }
    }

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func configure() async {
        await loadProducts()
        await refreshPurchasedProducts()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: Array(AirTalkPlus.productIDs))
            errorMessage = nil
        } catch {
            products = []
            errorMessage = "購入情報を読み込めませんでした。時間をおいてもう一度お試しください。"
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshPurchasedProducts()
                await transaction.finish()
                errorMessage = nil
            case .userCancelled:
                errorMessage = nil
            case .pending:
                errorMessage = "購入は承認待ちです。承認後にAirTalk Plusが自動で有効になります。"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入を完了できませんでした。"
        }
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshPurchasedProducts()
            errorMessage = isPlusActive ? nil : "復元できるAirTalk Plusの購入が見つかりませんでした。"
        } catch {
            errorMessage = "購入の復元に失敗しました。"
        }
    }

    func refreshPurchasedProducts() async {
        var activeProductIDs: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard AirTalkPlus.productIDs.contains(transaction.productID) else { continue }

            if transaction.revocationDate == nil {
                activeProductIDs.insert(transaction.productID)
            }
        }

        purchasedProductIDs = activeProductIDs
    }

    func title(for product: Product) -> String {
        switch product.id {
        case AirTalkPlus.monthlyProductID:
            return "AirTalk Plus 月額プラン"
        case AirTalkPlus.yearlyProductID:
            return "AirTalk Plus 年額プラン"
        default:
            return product.displayName
        }
    }

    func subtitle(for product: Product) -> String {
        if let introductoryOffer = product.subscription?.introductoryOffer,
           introductoryOffer.paymentMode == .freeTrial {
            return "\(periodDescription(introductoryOffer.period))の無料トライアル後、\(billingPeriodDescription(for: product))ごとに自動更新"
        }

        switch product.id {
        case AirTalkPlus.monthlyProductID:
            return "1か月ごとに自動更新"
        case AirTalkPlus.yearlyProductID:
            return "1年ごとに自動更新"
        default:
            return product.description
        }
    }

    func billingPeriodDescription(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            switch product.id {
            case AirTalkPlus.monthlyProductID:
                return "1か月"
            case AirTalkPlus.yearlyProductID:
                return "1年"
            default:
                return "期間"
            }
        }

        return periodDescription(period)
    }

    private func periodDescription(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return "\(period.value)日間"
        case .week:
            return "\(period.value)週間"
        case .month:
            return "\(period.value)か月間"
        case .year:
            return "\(period.value)年間"
        @unknown default:
            return ""
        }
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await refreshPurchasedProducts()
            await transaction.finish()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private func productSortOrder(_ productID: String) -> Int {
        switch productID {
        case AirTalkPlus.monthlyProductID:
            return 0
        case AirTalkPlus.yearlyProductID:
            return 1
        default:
            return 99
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
