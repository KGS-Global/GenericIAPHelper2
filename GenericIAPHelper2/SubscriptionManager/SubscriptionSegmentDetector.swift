import Foundation
import StoreKit

public final class SubscriptionSegmentDetector {

    public init() {}

    public func detect(
        subscriptionGroupID: String
    ) async throws -> SubscriptionUserProfile {

        // Collect verified subscription history for this group.
        var history: [Transaction] = []
        var hasUnverifiedHistory = false

        for await result in Transaction.all {
            switch result {
            case .verified(let transaction):
                guard transaction.productType == .autoRenewable,
                      transaction.subscriptionGroupID ==
                        subscriptionGroupID else {
                    continue
                }
                history.append(transaction)

            case .unverified(let transaction, _):
                if transaction.productType == .autoRenewable,
                   transaction.subscriptionGroupID ==
                     subscriptionGroupID {
                    hasUnverifiedHistory = true
                }
            }
        }

        history.sort {
            $0.purchaseDate < $1.purchaseDate
        }

        let latest = history.last

        let introHistory = history.filter {
            $0.offerType == .introductory
        }

        let latestIntro = introHistory.last
        let introKind = latestIntro.map {
            offerKind($0)
        } ?? .none

        // Transaction.price may be unavailable. A false
        // result here is not proof the user never paid.
        let hasPaid = history.contains {
            guard let price = $0.price else {
                return false
            }
            return price > 0
        }

        func makeProfile(
            _ segment: SubscriptionSegment,
            transaction: Transaction? = nil,
            renew: Bool? = nil
        ) -> SubscriptionUserProfile {

            let selected = transaction ?? latest

            return SubscriptionUserProfile(
                subscriptionGroupID: subscriptionGroupID,
                segment: segment,
                productID: selected?.productID,
                expirationDate: selected?.expirationDate,
                willAutoRenew: renew,
                hasSubscriptionHistory: !history.isEmpty,
                hasUsedIntroOffer: !introHistory.isEmpty,
                hasRecordedPaidTransaction: hasPaid,
                latestIntroductoryOffer: introKind,
                latestTransactionID: selected.map {
                    String($0.id)
                }
            )
        }

        // Current subscription state is authoritative.
        let statuses = try await Product.SubscriptionInfo.status(
            for: subscriptionGroupID
        )

        // Do not silently classify unverified status as free.
        let subscribed = statuses.filter {
            $0.state == .subscribed
        }

        if !subscribed.isEmpty {
            let verified = subscribed.compactMap { status
                -> (Transaction,
                    Product.SubscriptionInfo.RenewalInfo)? in

                guard case .verified(let transaction) =
                        status.transaction,
                      case .verified(let renewal) =
                        status.renewalInfo else {
                    return nil
                }

                return (transaction, renewal)
            }

            guard !verified.isEmpty else {
                return makeProfile(.unknown)
            }

            // Prefer the latest-ending verified entitlement.
            // Apps with subscription tiers or Family Sharing
            // may need a more specific selection policy.
            let selected = verified.max {
                ($0.0.expirationDate ?? .distantPast) <
                ($1.0.expirationDate ?? .distantPast)
            }!

            let transaction = selected.0
            let renewEnabled = selected.1.willAutoRenew

            let segment: SubscriptionSegment

            if transaction.offerType == .introductory {
                switch offerKind(transaction) {
                case .freeTrial:
                    segment = .freeTrialActive(
                        renewEnabled: renewEnabled
                    )
                case .payUpFront, .payAsYouGo:
                    segment = .paidIntroActive(
                        renewEnabled: renewEnabled
                    )
                default:
                    segment = .unknown
                }
            } else {
                segment = .regularPaidActive(
                    renewEnabled: renewEnabled
                )
            }

            return makeProfile(
                segment,
                transaction: transaction,
                renew: renewEnabled
            )
        }

        if statuses.contains(where: {
            $0.state == .inGracePeriod
        }) {
            return makeProfile(.gracePeriod)
        }

        if statuses.contains(where: {
            $0.state == .inBillingRetryPeriod
        }) {
            return makeProfile(.billingRetry)
        }

        if statuses.contains(where: {
            $0.state == .revoked
        }) {
            return makeProfile(.revoked)
        }

        if history.isEmpty {
            return makeProfile(
                hasUnverifiedHistory || !statuses.isEmpty
                    ? .unknown
                    : .neverSubscribed
            )
        }

        // Classify the latest verified, non-revoked period.
        let validHistory = history.filter {
            $0.revocationDate == nil
        }

        guard let lastValid = validHistory.last else {
            return makeProfile(.revoked)
        }

        // Important: do not classify an expired user
        // solely from any introductory offer in history.
        // Use the most recent subscription period.
        if lastValid.offerType == .introductory {
            switch offerKind(lastValid) {
            case .freeTrial:
                return makeProfile(.freeTrialExpired)
            case .payUpFront:
                return makeProfile(.paidIntroExpired)
            default:
                return makeProfile(.previouslySubscribed)
            }
        }

        if hasPaid {
            return makeProfile(.regularPaidExpired)
        }

        return makeProfile(.previouslySubscribed)
    }

    private func offerKind(
        _ transaction: Transaction
    ) -> IntroductoryOfferKind {

        guard transaction.offerType == .introductory else {
            return .none
        }

        if #available(iOS 17.2, *) {
            if let mode = transaction.offer?.paymentMode {
                switch mode {
                case .freeTrial:
                    return .freeTrial
                case .payUpFront:
                    return .payUpFront
                case .payAsYouGo:
                    return .payAsYouGo
                default:
                    return .unknown
                }
            }
        }

        guard let raw =
            transaction.offerPaymentModeStringRepresentation
        else {
            return .unknown
        }

        let value = raw.lowercased()
            .filter { $0.isLetter }

        if value == "freetrial" {
            return .freeTrial
        }
        if value == "payupfront" {
            return .payUpFront
        }
        if value == "payasyougo" {
            return .payAsYouGo
        }

        return .unknown
    }
}
