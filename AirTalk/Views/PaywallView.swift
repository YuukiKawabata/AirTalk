import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackgroundView(themeColor: .purple)

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        features
                        products
                        restoreAndLinks
                    }
                    .padding(24)
                }
            }
            .navigationTitle("AirTalk Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await purchaseManager.loadProducts()
        }
        .onChange(of: purchaseManager.isPlusActive) { _, isActive in
            if isActive {
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.primary)

            Text("その場で、もっと見つけてもらう")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)

            Text("基本の発見・招待・1対1チャットは無料のまま。Plusではイベントや場づくりに便利なプロフィール機能を解放します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureRow(icon: "person.crop.circle.badge.checkmark", title: "Hostバッジ", detail: "イベントや場の主催者として見つけてもらいやすくする")
            FeatureRow(icon: "circle.hexagongrid.circle", title: "プレミアムフレーム", detail: "レーダーとチャットでプロフィールを少し目立たせる")
            FeatureRow(icon: "rectangle.stack.badge.person.crop", title: "プロフィールプリセット", detail: "イベント用、作業用、旅先用などをすぐ切り替える")
            FeatureRow(icon: "text.bubble", title: "アイスブレイク", detail: "最初の一言に使える定型文と追加リアクション")
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var products: some View {
        if purchaseManager.isLoadingProducts {
            HStack(spacing: 12) {
                ProgressView()
                Text("プランを読み込んでいます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else if purchaseManager.sortedProducts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("プランを表示できません")
                    .font(.headline)
                Text("App Storeの購入情報を取得できませんでした。ネットワーク接続を確認してもう一度お試しください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("もう一度読み込む") {
                    Task {
                        await purchaseManager.loadProducts()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(spacing: 12) {
                ForEach(purchaseManager.sortedProducts, id: \.id) { product in
                    Button {
                        Task {
                            await purchaseManager.purchase(product)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(purchaseManager.title(for: product))
                                    .font(.headline)
                                Text(purchaseManager.subtitle(for: product))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(product.displayPrice) / \(purchaseManager.billingPeriodDescription(for: product))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(product.displayPrice)
                                .font(.headline)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(purchaseManager.isPurchasing)
                }
            }
        }
    }

    private var restoreAndLinks: some View {
        VStack(spacing: 14) {
            if purchaseManager.isPurchasing || purchaseManager.isRestoring {
                ProgressView()
            }

            if let errorMessage = purchaseManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await purchaseManager.restorePurchases()
                }
            } label: {
                Text("購入を復元")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(purchaseManager.isRestoring)

            Text("サブスクリプションは自動更新されます。解約はApp Storeのアカウント設定からいつでも行えます。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Link("利用規約", destination: SafetyPolicy.termsURL)
                Link("プライバシーポリシー", destination: SafetyPolicy.privacyURL)
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
