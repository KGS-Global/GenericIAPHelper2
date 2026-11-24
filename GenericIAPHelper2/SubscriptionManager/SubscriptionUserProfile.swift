import Foundation

public enum SubscriptionSegment: Equatable {
    case neverSubscribed

    case freeTrialActive(renewEnabled: Bool)
    case paidIntroActive(renewEnabled: Bool)
    case regularPaidActive(renewEnabled: Bool)

    case freeTrialExpired
    case paidIntroExpired
    case regularPaidExpired
    case previouslySubscribed

    case gracePeriod
    case billingRetry
    case revoked
    case unknown
}

public enum IntroductoryOfferKind: Equatable {
    case freeTrial
    case payUpFront
    case payAsYouGo
    case none
    case unknown
}

public struct SubscriptionUserProfile {

    public let subscriptionGroupID: String
    public let segment: SubscriptionSegment

    public let productID: String?
    public let expirationDate: Date?
    public let willAutoRenew: Bool?

    public let hasSubscriptionHistory: Bool
    public let hasUsedIntroOffer: Bool
    public let hasRecordedPaidTransaction: Bool

    public let latestIntroductoryOffer: IntroductoryOfferKind
    public let latestTransactionID: String?

    public var isActive: Bool {
        switch segment {
        case .freeTrialActive,
             .paidIntroActive,
             .regularPaidActive,
             .gracePeriod:
            return true
        default:
            return false
        }
    }

    public var isTrialActive: Bool {
        if case .freeTrialActive = segment {
            return true
        }
        return false
    }

    public var isRenewalDisabled: Bool {
        willAutoRenew == false && isActive
    }
}
