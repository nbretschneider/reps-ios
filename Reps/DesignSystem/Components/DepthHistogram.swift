import SwiftUI
import RepsKit

/// How deep the reps were, as a distribution.
///
/// A mean says the set was 26 cm. This says whether that was twenty honest reps or ten good
/// ones and ten that stopped halfway, which is the difference the number cannot show and
/// the only part worth acting on.
///
/// Pure: bins in, bars out. It lives in the design system rather than a feature folder
/// because the session summary and the profile draw the same chart, and two copies would
/// drift apart the first time either was tuned.
///
/// Renders on the session gradient as well as on a card, so every colour comes in through
/// `tint` and `labelStyle` rather than being read off the theme here.
struct DepthHistogram: View {
    var bins: [DepthBin]
    var tint: Color = .rPrimary
    var labelColor: Color = .rMutedForeground
    /// Bar height for the tallest column. The summary screen has more room than a card.
    var height: CGFloat = 92

    /// The tallest column, floored at one so a single-rep session still draws a bar rather
    /// than dividing by zero.
    private var peak: Int { max(1, bins.map(\.count).max() ?? 1) }

    var body: some View {
        if bins.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: RTheme.Spacing.tight) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(bins) { bin in
                        VStack(spacing: 3) {
                            // Only labelled where there is something to count. A column of
                            // zeros printed above empty bars reads as data.
                            Text(bin.count > 0 ? "\(bin.count)" : " ")
                                .font(RTheme.font(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(labelColor)

                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(bin.count > 0 ? tint : tint.opacity(0.14))
                                // A measured bin is never thinner than a hairline, so an
                                // outlier rep is visible rather than rounding away.
                                .frame(height: barHeight(bin))
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityElement()
                        .accessibilityLabel("\(bin.lowerCm) to \(bin.upperCm) centimetres")
                        .accessibilityValue("\(bin.count) reps")
                    }
                }
                .frame(height: height + 16, alignment: .bottom)

                // Only the ends are labelled. Seven numbers under seven narrow columns is
                // unreadable at this width, and the range is what the axis has to say.
                HStack {
                    Text("\(bins.first?.lowerCm ?? 0) cm")
                    Spacer()
                    Text("\(bins.last?.upperCm ?? 0) cm")
                }
                .font(RTheme.font(size: 10))
                .monospacedDigit()
                .foregroundStyle(labelColor)
            }
        }
    }

    private func barHeight(_ bin: DepthBin) -> CGFloat {
        guard bin.count > 0 else { return 3 }
        return max(6, height * CGFloat(bin.count) / CGFloat(peak))
    }
}

/// The one-line verdict that goes above a histogram: how deep, and deeper or shallower than
/// before.
///
/// Centimetres first, because a person can picture 26 cm and cannot picture 82%. The
/// comparison is omitted rather than invented when there is nothing to compare against — a
/// first measured session has no baseline, and a baseline of zero would announce a
/// triumphant improvement every time.
struct DepthVerdict: View {
    var summary: DepthSummary
    var comparison: DepthComparison?
    var foreground: Color = .rForeground
    var dimmed: Color = .rMutedForeground

    private var medianCm: Int { Int((summary.median * 100).rounded()) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RTheme.Spacing.inline) {
            Text("\(medianCm)")
                .font(RTheme.font(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(foreground)
            Text("cm median")
                .font(RTheme.caption)
                .foregroundStyle(dimmed)

            Spacer(minLength: 0)

            if let comparison, comparison.deltaCm != 0 {
                Label(
                    "\(abs(comparison.deltaCm)) cm",
                    systemImage: comparison.isDeeper ? "arrow.up.right" : "arrow.down.right"
                )
                .font(RTheme.captionMedium)
                .foregroundStyle(comparison.isDeeper ? Color.rAccent : dimmed)
                .accessibilityLabel(
                    comparison.isDeeper
                        ? "\(abs(comparison.deltaCm)) centimetres deeper than the past week"
                        : "\(abs(comparison.deltaCm)) centimetres shallower than the past week"
                )
            }
        }
    }
}
