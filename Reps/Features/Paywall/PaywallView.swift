import SwiftUI
import StoreKit
import RepsKit

/// Reps Pro.
///
/// Dismissible, always. Counting is free forever and so is the daily-goal plan, so a user
/// who says no here still has a working app — which is the point. A push-up app earns a
/// subscription by being used every day for a month, not by holding the first set hostage.
struct PaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var selection: String = PurchaseStore.annualID
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.rBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: RTheme.Spacing.card) {
                        header
                        features
                        options
                        footer
                    }
                    .padding(RTheme.Spacing.page)
                }
            }
            .safeAreaInset(edge: .bottom) { purchaseBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .tint(.rMutedForeground)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await purchases.restore() } }
                        .font(RTheme.caption)
                        .tint(.rMutedForeground)
                }
            }
            .task { if purchases.products.isEmpty { await purchases.loadProducts() } }
            .onChange(of: purchases.isPro) { _, isPro in if isPro { dismiss() } }
        }
    }

    private var header: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            ZStack {
                Circle().fill(RTheme.sessionGradient).frame(width: 76, height: 76)
                Text("r")
                    .font(RTheme.font(size: 40, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Reps Pro")
                .font(RTheme.title)
                .foregroundStyle(Color.rForeground)
            Text("The published programs, every number you've ever put in, and depth on every rep.")
                .font(RTheme.body)
                .foregroundStyle(Color.rMutedForeground)
                .multilineTextAlignment(.center)
        }
        .padding(.top, RTheme.Spacing.card)
    }

    private var features: some View {
        RCard {
            VStack(alignment: .leading, spacing: RTheme.Spacing.stack) {
                feature("list.bullet.rectangle", "The classic programs",
                        "100 Push-Ups and the Prison Ladder, reproduced as published.")
                // Precision mode used to be the headline Pro feature. It is now the free
                // default, because it is the engine that actually counts reliably and a
                // paywall in front of the counter is a paywall in front of the app.
                //
                // Replaced with export rather than a depth-history claim: the only real
                // gates in the app are the published programs, the month/year chart
                // scopes, Health sync and export. Naming anything else would be selling
                // something that is not behind the wall.
                feature("square.and.arrow.up", "Export your data",
                        "Every session as a spreadsheet, whenever you want it.")
                feature("clock.arrow.circlepath", "Your whole history",
                        "Every month and year, not just the last 30 days.")
                feature("square.grid.2x2", "Widgets and Health",
                        "Home and Lock Screen widgets, and sessions written to Apple Health.")
            }
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: RTheme.Spacing.stack) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(Color.rPrimary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RTheme.bodyMedium)
                    .foregroundStyle(Color.rForeground)
                Text(detail)
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var options: some View {
        if purchases.products.isEmpty {
            if purchases.isLoading {
                ProgressView().tint(.rPrimary).frame(maxWidth: .infinity).padding()
            } else {
                Text("Pricing is unavailable right now. Check your connection and try again.")
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rMutedForeground)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: RTheme.Spacing.inline) {
                ForEach(purchases.products, id: \.id) { product in
                    optionRow(product)
                }
            }
        }
    }

    private func optionRow(_ product: Product) -> some View {
        let isSelected = selection == product.id
        return Button {
            selection = product.id
            Haptics.select()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(RTheme.bodyMedium)
                        .foregroundStyle(Color.rForeground)
                    Text(purchases.priceLine(for: product))
                        .font(RTheme.caption)
                        .foregroundStyle(Color.rMutedForeground)
                }
                Spacer()
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.rPrimary : Color.rCardBorder)
            }
            .padding(RTheme.Spacing.card)
            .background(
                isSelected ? Color.rPrimary.opacity(0.10) : Color.rCard,
                in: RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: RTheme.Radius.control, style: .continuous)
                    .stroke(isSelected ? Color.rPrimary : Color.rCardBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.pressable)
    }

    private var footer: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            if let error = purchases.lastError {
                Text(error)
                    .font(RTheme.caption)
                    .foregroundStyle(Color.rDestructive)
                    .multilineTextAlignment(.center)
            }
            Text("Counting, your adaptive plan, open sets, your streak and the last 30 days stay free forever. Cancel any time in Settings.")
                .font(RTheme.caption)
                .foregroundStyle(Color.rMutedForeground)
                .multilineTextAlignment(.center)
        }
    }

    private var purchaseBar: some View {
        VStack(spacing: RTheme.Spacing.inline) {
            PrimaryButton(
                title: isPurchasing ? "…" : "CONTINUE",
                isEnabled: !isPurchasing && !purchases.products.isEmpty
            ) {
                guard let product = purchases.products.first(where: { $0.id == selection }) else { return }
                Task {
                    isPurchasing = true
                    await purchases.purchase(product)
                    isPurchasing = false
                }
            }
            Button("Not now") { dismiss() }
                .font(RTheme.caption)
                .tint(.rMutedForeground)
        }
        .padding(RTheme.Spacing.page)
        .background(.regularMaterial)
    }
}
