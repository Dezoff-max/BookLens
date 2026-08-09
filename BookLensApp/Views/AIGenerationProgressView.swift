import AppKit
import BookLensDomain
import SwiftUI

struct AIGenerationProgressView: View {
    let state: GenerationState
    let status: String
    let progress: Double?
    let reduceMotionOverride: Bool?
    let animationPhaseOverride: Double?
    let startedAt: Date?
    let finishedAt: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var illustrationReveal = 0.08

    private let stages: [(String, String)] = [
        ("text.magnifyingglass", "Analysis"),
        ("wand.and.stars", "Creating"),
        ("checkmark.seal", "Validation"),
    ]

    init(
        state: GenerationState,
        status: String,
        progress: Double? = nil,
        reduceMotionOverride: Bool? = nil,
        animationPhaseOverride: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.state = state
        self.status = status
        self.progress = progress.map { min(max($0, 0), 1) }
        self.reduceMotionOverride = reduceMotionOverride
        self.animationPhaseOverride = animationPhaseOverride
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var body: some View {
        VStack(spacing: 22) {
            OpenBookGenerationView(
                stage: visualStage,
                progress: progress,
                illustrationReveal: illustrationReveal,
                reduceMotionOverride: reduceMotionOverride,
                animationPhaseOverride: animationPhaseOverride
            )
            .frame(width: 380, height: 330)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Creating an illustration from the book description")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("AI is analyzing the scene and creating an image. This usually takes a few minutes.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(verbatim: status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.1), in: Capsule())

                AIElapsedTimeView(startedAt: startedAt, finishedAt: finishedAt)
            }

            HStack(spacing: 8) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    stageView(index: index, icon: stage.0, title: stage.1)
                    if index < stages.count - 1 {
                        Capsule()
                            .fill(connectorColor(after: index))
                            .frame(width: 28, height: 3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
        }
        .padding(34)
        .onAppear { updateIllustrationReveal(animated: false) }
        .onChange(of: state) { _, _ in updateIllustrationReveal(animated: true) }
        .onChange(of: reduceMotion) { _, _ in updateIllustrationReveal(animated: false) }
    }

    private var visualStage: GenerationVisualStage {
        switch state {
        case .draft, .queued: .analyzing
        case .running: .creating
        case .saving: .validating
        case .succeeded: .completed
        case .cancelled, .failed: .failed
        }
    }

    private var activeStage: Int {
        switch state {
        case .draft, .queued: 0
        case .running: 1
        case .saving, .succeeded: 2
        case .cancelled, .failed: 1
        }
    }

    private var statusColor: Color {
        switch state {
        case .failed, .cancelled: .red
        case .succeeded: .green
        default: BookLensTheme.accent
        }
    }

    private func stageView(index: Int, icon: String, title: String) -> some View {
        let completed = state == .succeeded || index < activeStage
        let failed = [.failed, .cancelled].contains(state) && index == activeStage
        let active = index == activeStage && !completed

        return VStack(spacing: 5) {
            Image(systemName: failed ? "exclamationmark.circle.fill" : completed ? "checkmark.circle.fill" : icon)
                .font(.system(size: 16, weight: .semibold))
            Text(LocalizedStringKey(title))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(failed ? Color.red : active || completed ? BookLensTheme.accent : .secondary)
        .frame(minWidth: 58)
        .accessibilityElement(children: .combine)
    }

    private func connectorColor(after index: Int) -> Color {
        if state == .succeeded || index < activeStage {
            return BookLensTheme.accent
        }
        return Color.secondary.opacity(0.18)
    }

    private func updateIllustrationReveal(animated: Bool) {
        let target: Double
        switch visualStage {
        case .analyzing: target = 0.08
        case .creating: target = 0.82
        case .validating, .completed: target = 1
        case .failed: target = 0.12
        }

        guard animated, !motionReduced else {
            illustrationReveal = target
            return
        }
        withAnimation(.easeInOut(duration: visualStage == .creating ? 3.4 : 0.45)) {
            illustrationReveal = target
        }
    }

    private var motionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }
}

struct AIBookAnalysisProgressView: View {
    let status: String
    let animationPhaseOverride: Double?
    let startedAt: Date?
    let finishedAt: Date?

    init(
        status: String,
        animationPhaseOverride: Double? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.status = status
        self.animationPhaseOverride = animationPhaseOverride
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    var body: some View {
        VStack(spacing: 14) {
            OpenBookGenerationView(
                stage: .analyzing,
                progress: nil,
                illustrationReveal: 0.14,
                reduceMotionOverride: nil,
                animationPhaseOverride: animationPhaseOverride
            )
            .frame(width: 320, height: 278)
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("AI is analyzing the book")
                    .font(.title2.bold())
                Text(verbatim: status)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                AIElapsedTimeView(startedAt: startedAt, finishedAt: finishedAt)
            }

            HStack(spacing: 8) {
                analysisStage("doc.text.magnifyingglass", "Text", completed: true)
                analysisConnector(active: true)
                analysisStage("person.3.fill", "Characters", active: true)
                analysisConnector(active: false)
                analysisStage("checkmark.seal", "Validation")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func analysisStage(
        _ icon: String,
        _ title: LocalizedStringKey,
        completed: Bool = false,
        active: Bool = false
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: completed ? "checkmark.circle.fill" : icon)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(completed || active ? BookLensTheme.accent : .secondary)
        .frame(minWidth: 58)
    }

    private func analysisConnector(active: Bool) -> some View {
        Capsule()
            .fill(active ? BookLensTheme.accent : Color.secondary.opacity(0.18))
            .frame(width: 28, height: 3)
    }
}

struct AIElapsedTimeView: View {
    let startedAt: Date?
    let finishedAt: Date?

    var body: some View {
        if let startedAt {
            if let finishedAt {
                timerLabel(at: finishedAt, startedAt: startedAt)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    timerLabel(at: timeline.date, startedAt: startedAt)
                }
            }
        }
    }

    @ViewBuilder
    private func timerLabel(at date: Date, startedAt: Date) -> some View {
        let duration = max(date.timeIntervalSince(startedAt), 0)
        Label {
            Text(verbatim: "\(BookLensLocalization.string("Elapsed")) \(Self.formattedDuration(seconds: duration))")
                .monospacedDigit()
        } icon: {
            Image(systemName: "timer")
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08)) }
        .accessibilityElement(children: .combine)
    }

    static func formattedDuration(seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private enum GenerationVisualStage {
    case analyzing
    case creating
    case validating
    case completed
    case failed

    var scansContinuously: Bool {
        self == .analyzing || self == .creating
    }
}

private struct BookAnimationSnapshot {
    let scanPosition: Double
    let pageTurn: Double
    let pageIndex: Int
    let particlePhase: Double
}

private struct OpenBookGenerationView: View {
    let stage: GenerationVisualStage
    let progress: Double?
    let illustrationReveal: Double
    let reduceMotionOverride: Bool?
    let animationPhaseOverride: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let scanAmber = Color(red: 0.94, green: 0.66, blue: 0.27)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !runsDecorativeLoop)) { timeline in
            let snapshot = animationSnapshot(at: timeline.date)
            openBook(
                scanPosition: snapshot.scanPosition,
                pageTurn: snapshot.pageTurn,
                pageIndex: snapshot.pageIndex,
                particlePhase: snapshot.particlePhase
            )
        }
    }

    private var runsDecorativeLoop: Bool {
        stage.scansContinuously && progress == nil && animationPhaseOverride == nil && !motionReduced
    }

    private func animationSnapshot(at date: Date) -> BookAnimationSnapshot {
        if let progress {
            return BookAnimationSnapshot(
                scanPosition: progress,
                pageTurn: progress >= 1 && !motionReduced ? 1 : 0,
                pageIndex: 0,
                particlePhase: progress
            )
        }
        guard stage.scansContinuously, !motionReduced else {
            return BookAnimationSnapshot(
                scanPosition: staticScanPosition,
                pageTurn: 0,
                pageIndex: 0,
                particlePhase: 0
            )
        }

        let cycleDuration = 4.2
        let elapsed = max(date.timeIntervalSinceReferenceDate, 0)
        let phase = animationPhaseOverride.map { min(max($0, 0), 1) }
            ?? elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        let pageIndex = animationPhaseOverride == nil ? Int(elapsed / cycleDuration) % 4 : 0
        let scanPosition = min(phase / 0.72, 1)
        let rawTurn = min(max((phase - 0.76) / 0.2, 0), 1)
        let easedTurn = rawTurn * rawTurn * (3 - 2 * rawTurn)
        return BookAnimationSnapshot(
            scanPosition: scanPosition,
            pageTurn: easedTurn,
            pageIndex: pageIndex,
            particlePhase: phase
        )
    }

    private var staticScanPosition: Double {
        switch stage {
        case .analyzing: 0.28
        case .creating: 0.66
        case .validating, .completed: 0.94
        case .failed: 0.42
        }
    }

    private func openBook(
        scanPosition: Double,
        pageTurn: Double,
        pageIndex: Int,
        particlePhase: Double
    ) -> some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, 380)
            let height = min(proxy.size.height, 330)
            let bookWidth = width * 0.82
            let bookHeight = height * 0.68
            let top = height * 0.16
            let pageTop = (height - bookHeight) / 2 + top
            let scanY = pageTop + 8 + (bookHeight - 20) * scanPosition
            let turnLift = CGFloat(sin(.pi * pageTurn))

            ZStack {
                Ellipse()
                    .fill(BookLensTheme.accent.opacity(stage == .failed ? 0.03 : 0.1))
                    .frame(width: bookWidth * 1.08, height: bookHeight * 0.38)
                    .blur(radius: 12)
                    .offset(y: bookHeight * 0.42)

                AnalysisCornerMarkers()
                    .stroke(
                        stage == .failed ? Color.red.opacity(0.55) : BookLensTheme.accent.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: bookWidth + 36, height: bookHeight + 32)
                    .offset(y: top - 12)

                HStack(spacing: 0) {
                    bookPage(side: .left, width: bookWidth / 2, height: bookHeight, variant: pageIndex)
                    bookPage(side: .right, width: bookWidth / 2, height: bookHeight, variant: pageIndex + 2)
                }
                .frame(width: bookWidth, height: bookHeight)
                .offset(y: top)
                .shadow(color: .black.opacity(0.24), radius: 8, y: 7)

                bookPage(
                    side: .right,
                    width: bookWidth / 2,
                    height: bookHeight,
                    variant: pageIndex + 1
                )
                .rotation3DEffect(
                    .degrees(-178 * pageTurn),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.62
                )
                .offset(x: bookWidth / 4, y: top)
                .shadow(
                    color: .black.opacity(0.18 + 0.24 * Double(turnLift)),
                    radius: 5 + 9 * turnLift,
                    x: -5 * turnLift,
                    y: 5
                )

                LinearGradient(
                    colors: [.clear, .black.opacity(0.34), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 18, height: bookHeight - 5)
                .offset(y: top + 2)

                if stage.scansContinuously {
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, scanAmber, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: bookWidth - 18, height: 2)
                            .shadow(color: scanAmber.opacity(0.82), radius: 7)
                        LinearGradient(
                            colors: [scanAmber.opacity(0.24), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: bookWidth - 22, height: 32)
                    }
                    .offset(y: scanY - height / 2)
                }

                if stage == .creating && !motionReduced {
                    lightParticles(width: width, height: height, phase: particlePhase)
                }

                stateBadge
                    .offset(x: bookWidth * 0.27, y: top + bookHeight * 0.26)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var motionReduced: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private func bookPage(
        side: OpenBookPageShape.Side,
        width: CGFloat,
        height: CGFloat,
        variant: Int
    ) -> some View {
        let normalizedVariant = abs(variant) % 4
        let leftPatterns: [[CGFloat]] = [
            [0.68, 0.82, 0.58, 0.76, 0.48, 0.62],
            [0.78, 0.56, 0.86, 0.7, 0.61, 0.48],
            [0.6, 0.84, 0.72, 0.52, 0.8, 0.57],
            [0.82, 0.66, 0.74, 0.55, 0.7, 0.64],
        ]
        let rightPatterns: [[CGFloat]] = [
            [0.72, 0.55, 0.78],
            [0.62, 0.82, 0.5],
            [0.8, 0.64, 0.74],
            [0.56, 0.76, 0.84],
        ]

        return ZStack {
            OpenBookPageShape(side: side)
                .fill(Color(nsColor: .textBackgroundColor))
            OpenBookPageShape(side: side)
                .fill(Color.primary.opacity(0.035))
            OpenBookPageShape(side: side)
                .stroke(Color.primary.opacity(0.28), lineWidth: 1)

            if side == .left {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(leftPatterns[normalizedVariant].dropLast().enumerated()), id: \.offset) { _, lineWidth in
                        decorativeLine(width: lineWidth)
                    }
                    Spacer()
                    decorativeLine(width: leftPatterns[normalizedVariant].last ?? 0.62)
                }
                .padding(.leading, 24)
                .padding(.trailing, 18)
                .padding(.vertical, 28)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    illustrationPanel(variant: normalizedVariant)
                        .frame(height: height * 0.43)
                    ForEach(Array(rightPatterns[normalizedVariant].enumerated()), id: \.offset) { _, lineWidth in
                        decorativeLine(width: lineWidth)
                    }
                    Spacer()
                }
                .padding(.leading, 18)
                .padding(.trailing, 24)
                .padding(.vertical, 24)
            }
        }
        .frame(width: width, height: height)
    }

    private func decorativeLine(width: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.primary.opacity(0.2))
                .frame(width: proxy.size.width * width, height: 3)
        }
        .frame(height: 3)
    }

    private func illustrationPanel(variant: Int) -> some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.24))
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)

                ZStack {
                    LinearGradient(
                        colors: [BookLensTheme.accent.opacity(0.52), Color.gray.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Circle()
                        .fill(Color.primary.opacity(0.34))
                        .frame(width: proxy.size.height * 0.28)
                        .offset(
                            x: proxy.size.width * (variant.isMultiple(of: 2) ? 0.2 : -0.18),
                            y: -proxy.size.height * 0.18
                        )
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.22)
                        .rotationEffect(.degrees(variant.isMultiple(of: 2) ? -13 : 11))
                        .offset(
                            x: proxy.size.width * (variant.isMultiple(of: 2) ? -0.08 : 0.08),
                            y: proxy.size.height * 0.2
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .opacity(illustrationReveal)
            }
        }
    }

    private func lightParticles(width: CGFloat, height: CGFloat, phase: Double) -> some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let shifted = (phase + Double(index) * 0.23).truncatingRemainder(dividingBy: 1)
                Circle()
                    .fill(scanAmber.opacity(0.22 + 0.36 * (1 - shifted)))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3)
                    .offset(
                        x: width * (0.12 + CGFloat(index) * 0.07),
                        y: height * (0.25 - CGFloat(shifted) * 0.23)
                    )
            }
        }
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch stage {
        case .validating:
            Image(systemName: "checkmark.shield")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BookLensTheme.accent)
                .padding(7)
                .background(.regularMaterial, in: Circle())
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)
                .padding(5)
                .background(.regularMaterial, in: Circle())
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        case .analyzing, .creating:
            EmptyView()
        }
    }
}

private struct OpenBookPageShape: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if side == .left {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 8))
            path.addCurve(
                to: CGPoint(x: rect.minX + 6, y: rect.minY + 2),
                control1: CGPoint(x: rect.width * 0.68, y: rect.minY + 1),
                control2: CGPoint(x: rect.width * 0.28, y: rect.minY - 1)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + 3, y: rect.maxY - 7),
                control: CGPoint(x: rect.minX, y: rect.midY)
            )
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - 1),
                control1: CGPoint(x: rect.width * 0.38, y: rect.maxY - 10),
                control2: CGPoint(x: rect.width * 0.72, y: rect.maxY - 3)
            )
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + 8))
            path.addCurve(
                to: CGPoint(x: rect.maxX - 6, y: rect.minY + 2),
                control1: CGPoint(x: rect.width * 0.32, y: rect.minY + 1),
                control2: CGPoint(x: rect.width * 0.72, y: rect.minY - 1)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - 3, y: rect.maxY - 7),
                control: CGPoint(x: rect.maxX, y: rect.midY)
            )
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - 1),
                control1: CGPoint(x: rect.width * 0.62, y: rect.maxY - 10),
                control2: CGPoint(x: rect.width * 0.28, y: rect.maxY - 3)
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct AnalysisCornerMarkers: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.12
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

#Preview("Analysis · Dark") {
    AIGenerationProgressView(state: .queued, status: "Checking Codex and account")
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Creation · Dark") {
    AIGenerationProgressView(state: .running, status: "Codex is creating the image")
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Validation · Dark") {
    AIGenerationProgressView(state: .saving, status: "Validating the image and SHA-256")
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Complete · Dark") {
    AIGenerationProgressView(state: .succeeded, status: "Image validated and saved")
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Error · Dark") {
    AIGenerationProgressView(state: .failed, status: "Generation failed")
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Reduce Motion · Dark") {
    AIGenerationProgressView(
        state: .running,
        status: "Codex is creating the image",
        progress: 0.62,
        reduceMotionOverride: true
    )
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Page turn · Dark") {
    AIGenerationProgressView(
        state: .running,
        status: "Codex is creating the image",
        animationPhaseOverride: 0.86
    )
        .preferredColorScheme(.dark)
        .frame(width: 720, height: 680)
}

#Preview("Creation · Light") {
    AIGenerationProgressView(
        state: .running,
        status: "Codex is creating the image",
        animationPhaseOverride: 0.52
    )
        .preferredColorScheme(.light)
        .frame(width: 720, height: 680)
}

#Preview("Book analysis · Light") {
    AIBookAnalysisProgressView(
        status: "AI is understanding the story and separating characters from incidental names…",
        animationPhaseOverride: 0.48
    )
        .preferredColorScheme(.light)
        .frame(width: 720, height: 680)
}
