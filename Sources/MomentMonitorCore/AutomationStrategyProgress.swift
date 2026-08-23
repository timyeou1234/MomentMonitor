import Foundation

public enum AutomationStrategyKind: String, Codable, Sendable {
  case reviewLoop
  case validationLoop
  case finalSolHigh
}

public enum AutomationStrategyStepKind: String, Codable, Sendable {
  case review
  case validation
  case correction
  case finalGoal
}

public enum AutomationStrategyStepState: String, Codable, Sendable {
  case completed
  case active
  case pending
  case halted

  public var title: String {
    switch self {
    case .completed: "completed"
    case .active: "active"
    case .pending: "pending"
    case .halted: "halted"
    }
  }
}

public struct AutomationStrategyStep: Codable, Equatable, Sendable {
  public let kind: AutomationStrategyStepKind
  public let number: Int?
  public let shortLabel: String
  public let title: String
  public let state: AutomationStrategyStepState
}

public struct AutomationStrategyProgress: Codable, Equatable, Sendable {
  public let kind: AutomationStrategyKind
  public let title: String
  public let currentStepTitle: String
  public let steps: [AutomationStrategyStep]

  public init?(observation: AutomationRuntimeObservation) {
    guard let status = observation.status else { return nil }
    let phase = status.lastActivePhase ?? status.phase
    let activeState: AutomationStrategyStepState =
      observation.availability == .live && status.outcome == .active ? .active : .halted

    switch phase {
    case .solReview, .lunaVerification:
      guard let round = status.roundNumber, let total = status.totalRounds,
        (1...4).contains(total), (1...total).contains(round)
      else { return nil }
      self = Self.loop(
        kind: .reviewLoop,
        title: "Review loop",
        currentStepTitle: "\(phase.title) \(round) of \(total)",
        primaryKind: .review,
        primaryPrefix: "R",
        primaryTitle: "Review",
        primaryCount: total,
        activeIndex: (round - 1) * 2,
        activeState: activeState
      )

    case .solReviewRepair,
      .lunaImplementation where status.repairAttempt != nil:
      guard let attempt = status.repairAttempt, let totalCorrections = status.totalRounds,
        (1...3).contains(totalCorrections), (1...totalCorrections).contains(attempt)
      else { return nil }
      let modelName = status.model?.displayName ?? "Review"
      self = Self.loop(
        kind: .reviewLoop,
        title: "Review loop",
        currentStepTitle: "\(modelName) correction \(attempt) of \(totalCorrections)",
        primaryKind: .review,
        primaryPrefix: "R",
        primaryTitle: "Review",
        primaryCount: totalCorrections + 1,
        activeIndex: (attempt - 1) * 2 + 1,
        activeState: activeState
      )

    case .prFast:
      guard let round = status.roundNumber, let total = status.totalRounds,
        (1...4).contains(total), (1...total).contains(round)
      else { return nil }
      self = Self.loop(
        kind: .validationLoop,
        title: "PR Fast loop",
        currentStepTitle: "Validation \(round) of \(total)",
        primaryKind: .validation,
        primaryPrefix: "V",
        primaryTitle: "Validation",
        primaryCount: total,
        activeIndex: (round - 1) * 2,
        activeState: activeState
      )

    case .solPRFastRepair:
      guard let attempt = status.repairAttempt, let totalCorrections = status.totalRounds,
        (1...3).contains(totalCorrections), (1...totalCorrections).contains(attempt)
      else { return nil }
      self = Self.loop(
        kind: .validationLoop,
        title: "PR Fast loop",
        currentStepTitle: "Sol correction \(attempt) of \(totalCorrections)",
        primaryKind: .validation,
        primaryPrefix: "V",
        primaryTitle: "Validation",
        primaryCount: totalCorrections + 1,
        activeIndex: (attempt - 1) * 2 + 1,
        activeState: activeState
      )

    case .solHighUnblock:
      self.init(
        kind: .finalSolHigh,
        title: "Final Sol High",
        currentStepTitle: "Until pass or a terminal boundary",
        steps: [
          AutomationStrategyStep(
            kind: .finalGoal,
            number: nil,
            shortLabel: "HIGH",
            title: "Durable final Sol High goal",
            state: activeState
          )
        ]
      )

    default:
      return nil
    }
  }

  public var accessibilitySummary: String {
    let stepSummary = self.steps
      .map { "\($0.title) \($0.state.title)" }
      .joined(separator: ", ")
    return "\(self.title), \(self.currentStepTitle), \(stepSummary)"
  }

  private init(
    kind: AutomationStrategyKind,
    title: String,
    currentStepTitle: String,
    steps: [AutomationStrategyStep]
  ) {
    self.kind = kind
    self.title = title
    self.currentStepTitle = currentStepTitle
    self.steps = steps
  }

  private static func loop(
    kind: AutomationStrategyKind,
    title: String,
    currentStepTitle: String,
    primaryKind: AutomationStrategyStepKind,
    primaryPrefix: String,
    primaryTitle: String,
    primaryCount: Int,
    activeIndex: Int,
    activeState: AutomationStrategyStepState
  ) -> Self {
    var steps: [AutomationStrategyStep] = []
    for number in 1...primaryCount {
      steps.append(
        Self.step(
          kind: primaryKind,
          number: number,
          shortLabel: "\(primaryPrefix)\(number)",
          title: "\(primaryTitle) \(number)",
          index: steps.count,
          activeIndex: activeIndex,
          activeState: activeState
        ))
      if number < primaryCount {
        steps.append(
          Self.step(
            kind: .correction,
            number: number,
            shortLabel: "C\(number)",
            title: "Correction \(number)",
            index: steps.count,
            activeIndex: activeIndex,
            activeState: activeState
          ))
      }
    }
    return Self(kind: kind, title: title, currentStepTitle: currentStepTitle, steps: steps)
  }

  private static func step(
    kind: AutomationStrategyStepKind,
    number: Int,
    shortLabel: String,
    title: String,
    index: Int,
    activeIndex: Int,
    activeState: AutomationStrategyStepState
  ) -> AutomationStrategyStep {
    let state: AutomationStrategyStepState
    if index < activeIndex {
      state = .completed
    } else if index == activeIndex {
      state = activeState
    } else {
      state = .pending
    }
    return AutomationStrategyStep(
      kind: kind,
      number: number,
      shortLabel: shortLabel,
      title: title,
      state: state
    )
  }
}
