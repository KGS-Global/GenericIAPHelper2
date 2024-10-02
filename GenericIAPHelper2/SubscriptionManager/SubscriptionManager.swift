import UIKit
import StoreKit


public class SubscriptionManager: NSObject {
    
    static let localDateFormatter: DateFormatter = {
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "MMM dd, yyyy HH:mm:ss"
        
        return dateFormatter
    }()
    
    
    public static let shared = SubscriptionManager()
    public let notificationHandler = SubManagerNotificationHandler.shared
    
    private var productIdentifiers: [String] = []
    private var subscriptionGroupId: String = ""
    private var allProducts = [String: Product]()
    private var reachability: Reachability?
    private var productsLoaded = false
    private var isProductLoading = false
    private var progressHudID = UUID().uuidString
    
    
    private var expiryCheckTimer: Timer?
    private var ignoreTimerChecks = false
    private var updateTask: Task<Void, Never>? = nil
    private var purchaseStatusChecked = false
    private var purchasedProducts = Set<String>()
    private var deepLinkProductPurchaseId: String?
    private var deepLinkProductState:SKPaymentTransactionState = .deferred
    
    private var isEligibleForIntro = true
    private var purchaseHistory = false
    private var isOnTrial = false
    private var subExpiryDate: Date?
    private var purchaseDate: Date?
    private var originalPurchaseDate: Date?
    private var autoRenewalOn = false
    
    private override init() {
        super.init()
        Task {
            await updateCurrentEntitlementStatus(shouldNotifyChange: false)
            let _ = await getLatestTransactionForSubscriptionGroup()
        }
        // Start listening for updates
        updateTask = observeTransactionUpdates()
        
        self.isEligibleForIntro = true
        self.checkSubscriptionExpiryPeriodically()
        
        // Required for AppStore initiated purchases & restore purchase.
        SKPaymentQueue.default().add(self)
    }
    
    deinit {
        updateTask?.cancel()
        self.expiryCheckTimer?.invalidate()
    }
    
    public func initWithProductIDS(productIds: [String], subscriptionGroupId: String) {
        self.productIdentifiers = productIds
        self.subscriptionGroupId = subscriptionGroupId
        self.setRequiredNotifications()
        
        Task {
            print("GenericIAPHelper2:: loadIAPProducts from initWithProductIDS!")
            await self.loadIAPProducts()
        }
    }
    
    //Called from App Side
    public func refreshPurchaseableProducts() {
        if (self.productsLoaded) {
            self.notificationHandler.notifyObserversForNotificationType(.ProductLoaded, nil)
        }
    }
    
    public func purchaseRequest(productID: String) {
        
        guard let productToPurchase = self.allProducts[productID] else { return }
        
        print("GenericIAPHelper2:: Initiating Purchase for product: ", productToPurchase.id)
        
        self.showProgressHud(text: "Please wait...")
        
        //Force dismiss progress after dealy of 15 seconds.
        let progressID = self.progressHudID
        self.dismissProgressHud(after: 15, progressId: progressID)
        
        
        Task {
            do {
                try await self.purchase(product: productToPurchase)
            } catch {
                print("GenericIAPHelper2:: Purchase error for product: \(productID) error: \(error.localizedDescription)")
            }
            
            self.dismissProgressHud(progressID: progressID)
        }
    }
    
    public func restorePurchase() {
        
        self.showProgressHud(text: "Please wait...")
        //Force Dismissal
        self.progressHudID = UUID().uuidString
        self.dismissProgressHud(after: 20, progressId: self.progressHudID)
        
        Task {
            await self.updateCurrentEntitlementStatus(shouldNotifyChange: false)
            let latestTransaction = await self.getLatestTransactionForSubscriptionGroup()
            
            if self.isSubscribedOrUnlockedAll() || latestTransaction != nil {
                
                self.restoreActionFinished(failedToRestore: false, delayInSeconds: 1.0)
                
            } else {
                //User might be logged out, or doesn't have any prior purchase
                //In either scenario, we want to call AppStore.sync() method.
                
                //AppStore.sync() will always asks for User Credential for Apple ID.
                //await self.restorePurchaseStoreKit2()
                
                //To prevent asking user for credential every time, falling back to StoreKit1 api.
                self.restorePurchaseStoreKit1()
            }
        }
    }
    
    
    private func purchase(product: Product) async throws {
        
        self.ignoreTimerChecks = true
        if InternetChecker.shared.isInternetConnected() == false {
            self.ignoreTimerChecks = false
            self.notificationHandler.notifyObserversForNotificationType(.PurchaseFailure, nil)
            return
        }
        
        let result = try await product.purchase()

        switch result {
        case let .success(.verified(transaction)):
            // Successful purhcase
            await transaction.finish()
            await updateCurrentEntitlementStatus(shouldNotifyChange: false)
            print("GenericIAPHelper2:: Notifying about a purchase success!")
            self.notificationHandler.notifyObserversForNotificationType(.PurchaseSuccessful, nil)
            
        case let .success(.unverified(_, error)):
            // Successful purchase but transaction/receipt can't be verified
            // Could be a jailbroken phone
            //TODO: Throw purchase fail notification unverified.
            print("GenericIAPHelper2:: Purchase unverified: error: \(error.localizedDescription)")
            self.notificationHandler.notifyObserversForNotificationType(.PurchaseUnverified, nil)
            break
        case .pending:
            // Transaction waiting on SCA (Strong Customer Authentication) or
            // approval from Ask to Buy
            self.notificationHandler.notifyObserversForNotificationType(.PurchasePending, nil)
            break
        case .userCancelled:
            // ^^^
            self.notificationHandler.notifyObserversForNotificationType(.PurchaseCanceled, nil)
            break
        @unknown default:
            break
        }
        
        self.ignoreTimerChecks = false
    }
    
    private func restorePurchaseStoreKit1() {
        //print("GenericIAPHelper2:: TRYING RESTORE PURCHASE WITH STOREKIT 1!!!")
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    //MARK: This method is not in use yet. But keep this method for future if required.
    private func restorePurchaseStoreKit2() async {
        //print("GenericIAPHelper2:: TRYING RESTORE PURCHASE WITH STOREKIT 2!!!")
        var failedToRestore = false
        do {
            try await AppStore.sync()
            await self.updateCurrentEntitlementStatus(shouldNotifyChange: true)
        } catch {
            print("GenericIAPHelper2:: Restore error: ", error.localizedDescription)
            failedToRestore = true
        }
        
        self.restoreActionFinished(failedToRestore: failedToRestore, delayInSeconds: 0)
    }
    
    private func restoreActionFinished(failedToRestore: Bool, delayInSeconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delayInSeconds, execute: {
            self.progressHudID = UUID().uuidString
            if (failedToRestore) {
                ProgressHUD.showError("Failed to restore.", interaction: false);
                self.notificationHandler.notifyObserversForNotificationType(.RestoreFailure, nil)
            } else {
                self.notificationHandler.notifyObserversForNotificationType(.RestoreSuccessful, nil)
                if self.isSubscribedOrUnlockedAll() {
                    ProgressHUD.showSucceed("Successfully Restored.", interaction: false)
                } else {
                    ProgressHUD.showError("Nothing to Restore.", interaction: false);
                }
            }
        })
    }
    
    private func loadIAPProducts() async {
        
        if self.isProductLoading == true {
            return
        }
        self.isProductLoading = true
        
        print("GenericIAPHelper2:: Trying to load IAP Products!")
        
        if self.productIdentifiers.isEmpty {
            self.isProductLoading = false
            return
        }
        
        if InternetChecker.shared.isInternetConnected() == false {
            self.isProductLoading = false
            return
        }

        do {
            let fetchedProducts = try await Product.products(for: productIdentifiers)
            if let transaction = await self.getLatestTransactionForSubscriptionGroup() {
                await self.updateRenewalInfo(transaction: transaction)
            }
            
            
            await MainActor.run {
                for product in fetchedProducts {
                    self.allProducts[product.id] = product
                }
                
                self.productsLoaded = true
                print("GenericIAPHelper2:: Products loaded!!!")
            }
            
        } catch {
            print("GenericIAPHelper2:: Failed to fetch products: \(error.localizedDescription). Will retry when network is reachable. !!")
        }
        
        if (self.productsLoaded) {
            self.notificationHandler.notifyObserversForNotificationType(.ProductLoaded, nil)
        }
        
        self.isProductLoading = false
    }
    
}

// MARK: Helper Methods
extension SubscriptionManager {
    
    private func checkSubscriptionExpiryPeriodically() {
        self.expiryCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { timer in
            self.checkLocalSubscriptionExpiry()
        }
    }
    
    private func checkLocalSubscriptionExpiry() {
        
        if self.ignoreTimerChecks {
            return
        }
        
        print("GenericIAPHelper2:: Checking subscription expiry with local time!")
        guard let expiryDate = self.subExpiryDate else { return }
        
        if expiryDate < Date() {
            Task {
                await updateCurrentEntitlementStatus(shouldNotifyChange: true)
            }
        }
    }
    
    private func showProgressHud(text: String) {
        self.progressHudID = UUID().uuidString
        ProgressHUD.show(text, interaction: false)
    }
    
    private func dismissProgressHud(progressID: String) {
        if progressID == self.progressHudID {
            self.progressHudID = UUID().uuidString
            ProgressHUD.dismiss()
        }
    }
    
    private func dismissProgressHud(after seconds: Double, progressId: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: {
            if progressId == self.progressHudID {
                self.progressHudID = UUID().uuidString
                ProgressHUD.dismiss()
            }
        })
    }
}




// MARK: Current Entitlement & Transaction Updates Handler
extension SubscriptionManager {
    
    func updateCurrentEntitlementStatus(shouldNotifyChange: Bool) async {
        
        var purchasedProducts = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            if transaction.revocationDate == nil {
                purchasedProducts.insert(transaction.productID)
            }
            
            Task {
                await self.updateRenewalInfo(transaction: transaction)
            }
        }
        
        //Was subscribed, but now subscription expired.
        var subscriptionExpired = false
        if purchasedProducts.isEmpty && self.purchasedProducts.isEmpty == false {
            subscriptionExpired = true
        }
        
        var newProductPurchased = false
        if (purchasedProducts.count > self.purchasedProducts.count) {
            newProductPurchased = true
        }
        
        
        self.purchasedProducts = purchasedProducts
        
        if (shouldNotifyChange) {
            if (subscriptionExpired) {
                self.notificationHandler.notifyObserversForNotificationType(.SubscriptionExpire, nil)
            } else if (newProductPurchased) {
                self.notificationHandler.notifyObserversForNotificationType(.RestoreSuccessful, nil)
            }
            
            if let productId = self.deepLinkProductPurchaseId, self.deepLinkProductState == .purchasing {
                if (self.purchasedProducts.contains(productId)) {
                    self.deepLinkProductState = .deferred
                    self.deepLinkProductPurchaseId = nil
                    print("GenericIAPHelper2:: Notifying about a purchase success!")
                    self.notificationHandler.notifyObserversForNotificationType(.PurchaseSuccessful, nil)
                }
            }
        }
        
        purchaseStatusChecked = true
    }
    
    func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [unowned self] in
            for await result in Transaction.updates {
                
                guard case .verified(let transaction) = result else {
                    continue
                }
                
                print("GenericIAPHelper2:: StoreKit2: New Transaction update for: ", transaction.productID)
                
                await transaction.finish()
                await updateCurrentEntitlementStatus(shouldNotifyChange: true)
            }
        }
    }
}

// MARK: Handle Notifications
extension SubscriptionManager {
    
    private func setRequiredNotifications() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(reachabilityChanged), name: Notification.Name.reachabilityChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
        
    }
    
    @objc private func reachabilityChanged(_ notification:Notification) {
        
        print("GenericIAPHelper2:: Reachability Changed!")
        if InternetChecker.shared.isInternetConnected() {
            Task {
                await self.loadIAPProducts()
                await self.updateCurrentEntitlementStatus(shouldNotifyChange: true)
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        Task {
            await self.loadIAPProducts()
            if (InternetChecker.shared.isInternetConnected()) {
                await self.updateCurrentEntitlementStatus(shouldNotifyChange: false)
            }
        }
    }
    
    @objc private func appWillTerminate() {
        NotificationCenter.default.removeObserver(self)
    }
}


//MARK: Request From App Side
extension SubscriptionManager {
    
    public func requestPrice(for productID: String) -> String? {
        
        guard let product = self.allProducts[productID] else {
            return nil
        }
        return product.displayPrice
    }
    
    public func requestPriceInDecimal(for productID: String) -> Decimal? {
         
        guard let product = self.allProducts[productID] else {
             return nil
         }
        return product.price
     }
    
    public func requestIntroductoryPrice(for productID: String) -> String? {
        
        guard let product = self.allProducts[productID] else {
            return nil
        }
        
        return product.subscription?.introductoryOffer?.displayPrice
    }
    
    public func requestIntroductoryPriceInDecimal(for productID: String) -> Decimal? {
         
        guard let product = self.allProducts[productID] else {
            return nil
        }
        return product.subscription?.introductoryOffer?.price
     }
    
    public func isSubscribedOrUnlockedAll() -> Bool {
        return self.purchasedProducts.isEmpty == false
    }
    
}


extension SubscriptionManager {
    
    private func updateRenewalInfo(transaction: Transaction) async {
        
        //HAS PURCHASE HISTORY
        self.purchaseHistory = true
        if transaction.productType != .autoRenewable {
            return
        }
        
        //UPDATE IS_ON_TRIAL
        if let offerType = transaction.offerType, offerType == .introductory {
            self.isOnTrial = true
        } else {
            self.isOnTrial = false
        }
        
        if let expiryDate = transaction.expirationDate {
            self.subExpiryDate = expiryDate
        }
        
        
        self.purchaseDate = transaction.purchaseDate
        self.originalPurchaseDate = transaction.purchaseDate
        
        if (InternetChecker.shared.isInternetConnected()) {
            self.isEligibleForIntro = await Product.SubscriptionInfo.isEligibleForIntroOffer(for: self.subscriptionGroupId)
            
            do {
                var willAutoRenew = false
                
                let statuses = try await Product.SubscriptionInfo.status(for: subscriptionGroupId)
                for status in statuses {
                    guard case .verified(let renewalInfo) = status.renewalInfo else { continue }
                    if status.state != .subscribed {
                        continue
                    }
                    if renewalInfo.willAutoRenew {
                        willAutoRenew = true
                    }
                }
                self.autoRenewalOn = willAutoRenew

            } catch {
                print("GenericIAPHelper2::  Error: ", error.localizedDescription)
            }
            
        }
        
        print("GenericIAPHelper2::  Eligible for intro: ", self.isEligibleForIntro)
        print("GenericIAPHelper2::  User on trial: ", self.isOnTrial)
        print("GenericIAPHelper2::  Auto Renew On: ", self.autoRenewalOn)
        print("GenericIAPHelper2::  expiry date: ", self.subExpiryDate ?? "No Expiry Date Found")
        print("GenericIAPHelper2::  purchase date: ", transaction.purchaseDate)
        print("GenericIAPHelper2::  original purchase date: ", transaction.originalPurchaseDate)
    }
    
    private func getLatestTransactionForSubscriptionGroup() async -> Transaction? {
        
        var latestTransaction: Transaction? = nil
        for productID in self.productIdentifiers {
            if let result = await Transaction.latest(for: productID) {
                guard case .verified(let transaction) = result else {
                    continue
                }
                
                self.purchaseHistory = true
                if let latest = latestTransaction {
                    if transaction.purchaseDate > latest.purchaseDate {
                        latestTransaction = transaction
                    }
                } else {
                    latestTransaction = transaction
                }
            }
        }
        
        //TODO: USE LATEST TRANSACTION FOR TRANSACTION HISTORY UPDATE.
//        if let transaction = latestTransaction {
//            Task {
//                await self.updateRenewalInfo(transaction: transaction)
//            }
//        }
        
        return latestTransaction
    }
    
    public func isTrialPeriodOngoing() -> Bool {
        return self.isOnTrial
    }

    public func hasPurchasesHistory() -> Bool {
        return self.purchaseHistory
    }
    
    public func currentSubscribedProductID() -> String? {
        if (self.purchasedProducts.isEmpty) {
            return nil
        }
        
    
        for productId in self.purchasedProducts {
            return productId
        }
        
        return nil
    }
    
    @objc public func getExpirationDateString() -> String?{
        if let expirationDate = self.subExpiryDate {
            return SubscriptionManager.localDateFormatter.string(from: expirationDate)
        }
        
        return nil
    }
    
    public func getPurchaseDateString() -> String?{
        if let purchaseDate = self.originalPurchaseDate {
            return SubscriptionManager.localDateFormatter.string(from: purchaseDate)
        }
        
        return nil
    }
    
    public func isAutoRenewalOn() -> Bool{
        return self.autoRenewalOn
    }
    
    public func isEligibleForIntroOffer() -> Bool {
        return self.isEligibleForIntro
    }
    
    public func getFreeTrialPeriod(for productID: String, inDays: Bool = true) -> String? {
        
        
        guard let product = self.allProducts[productID] else { return nil }
        guard let subscription = product.subscription else { return nil }
        guard let introductoryOffer = subscription.introductoryOffer else { return "0-days"}
        
        
        let totalUnits = introductoryOffer.period.value
        let periodUnit = introductoryOffer.period.unit
        
        var freeTrialPeriod: String?
        
        if inDays {
            freeTrialPeriod = convertTrialPeriodInDays(for: totalUnits, periodUnit: periodUnit)
            
        } else {
            freeTrialPeriod = trialPeriodAsGiven(for: totalUnits, periodUnit: periodUnit)
        }
        
        return freeTrialPeriod
    }
    
    public func getFreeTrialPeriodInDaysInteger(for productID: String?) -> Int {
        
        guard let productID = productID else { return 0 }
        guard let product = self.allProducts[productID] else { return 0 }
        guard let subscription = product.subscription else { return 0 }
        guard let introductoryOffer = subscription.introductoryOffer else { return 0}
        
        var freeTrialPeriod: Int
        let totalUnits = introductoryOffer.period.value
        let periodUnit = introductoryOffer.period.unit
        
        freeTrialPeriod = convertTrialPeriodInDaysInteger(for: totalUnits, periodUnit: periodUnit)
        
        return freeTrialPeriod
    }
    
    private func convertTrialPeriodInDaysInteger(for numberOfUnit: Int, periodUnit: Product.SubscriptionPeriod.Unit) -> Int {
        
        var numberOfDays: Int = 0;
        
        switch periodUnit {
            
        case .day:
            numberOfDays = numberOfUnit
        case .week:
            numberOfDays = numberOfUnit * 7
        case .month:
            numberOfDays = numberOfUnit * 30
        case .year:
            numberOfDays = numberOfUnit * 365
        default:
            break
        }
        return numberOfDays
    }
    
    private func convertTrialPeriodInDays(for numberOfUnit: Int, periodUnit: Product.SubscriptionPeriod.Unit) -> String {
        
        var numberOfDays: Int = 0;
        
        switch periodUnit {
            
        case .day:
            numberOfDays = numberOfUnit
        case .week:
            numberOfDays = numberOfUnit * 7
        case .month:
            numberOfDays = numberOfUnit * 30
        case .year:
            numberOfDays = numberOfUnit * 365
        default:
            break
        }
        
        var freeTrialPeriod = String(format: "%ld Day", numberOfDays)
        if numberOfDays >= 2 {
            freeTrialPeriod += "s"
        }
        return freeTrialPeriod
    }
    
    private func trialPeriodAsGiven(for numberOfUnit: Int, periodUnit: Product.SubscriptionPeriod.Unit) -> String {
        
        var freeTrialPeriod = "";
        
        switch periodUnit {
            
        case .day:
            freeTrialPeriod = String(format: "%ld Day", numberOfUnit)
        case .week:
            freeTrialPeriod = String(format: "%ld Week", numberOfUnit)
        case .month:
            freeTrialPeriod = String(format: "%ld Month", numberOfUnit)
        case .year:
            freeTrialPeriod = String(format: "%ld Year", numberOfUnit)
        default:
            break
        }
        
        if numberOfUnit >= 2 {
            freeTrialPeriod += "s"
        }
        return freeTrialPeriod
    }
}


extension SubscriptionManager: SKPaymentTransactionObserver {
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        
        if transactions.isEmpty {
            return
        }

        for transaction in transactions {
            
            print("GenericIAPHelper2:: StoreKit1: updatedTransactions:: productID: \(transaction.payment.productIdentifier) state: \(transaction.transactionState.rawValue)")
            
            if transaction.payment.productIdentifier == self.deepLinkProductPurchaseId {
                self.deepLinkProductState = transaction.transactionState
                
                if transaction.transactionState == .purchasing {
                    self.showProgressHud(text: "Please wait...")
                    self.dismissProgressHud(after: 10, progressId: self.progressHudID)
                    
                } else if transaction.transactionState == .failed {
                    self.dismissProgressHud(progressID: self.progressHudID)
                }
            }
            
            if transaction.transactionState != .purchasing {
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        }
        
        //Not purchasing...
        if (self.deepLinkProductPurchaseId != nil && self.deepLinkProductState != .purchasing) {
            
            if self.deepLinkProductState == .purchased {
                print("GenericIAPHelper2:: Notifying about a purchase success!")
                self.notificationHandler.notifyObserversForNotificationType(.PurchaseSuccessful, nil)
            }
            
            self.deepLinkProductPurchaseId = nil
            self.deepLinkProductState = .deferred
        }
        
        Task {
            await self.updateCurrentEntitlementStatus(shouldNotifyChange: true)
            
            if self.isSubscribedOrUnlockedAll() {
                self.dismissProgressHud(after: 1, progressId: self.progressHudID)
            }
        }
    }
    
    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        print("GenericIAPHelper2::  All restore transactions finished.")
        self.restoreActionFinished(failedToRestore: false, delayInSeconds: 0)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("GenericIAPHelper2::  All restore transaction failed with error: ", error.localizedDescription)
        self.restoreActionFinished(failedToRestore: true, delayInSeconds: 0)
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        print("GenericIAPHelper2::  Storekit1: shouldAddStorePayment:: productId: ", product.productIdentifier)
        
        self.deepLinkProductPurchaseId = product.productIdentifier
        self.deepLinkProductState = .deferred
        
        self.showProgressHud(text: "Please wait...")
        self.dismissProgressHud(after: 30, progressId: self.progressHudID)
//        self.notificationHandler.notifyObserversForNotificationType(.PromotionPurchaseStart, nil)
        
        return false
    }
}

