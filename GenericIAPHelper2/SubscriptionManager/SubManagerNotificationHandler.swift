import UIKit

final class ObserverHolder {
    
    weak var observer : SubManagerNotificationObserver?
    init (observer: SubManagerNotificationObserver) {
        self.observer = observer
    }
}

public class SubManagerNotificationHandler: NSObject {
    
    internal static let restoreSuccessfulNotification = Notification.Name("SubscriptionServiceRestoreSuccessfulNotification")
    internal static let restoreFailureNotification = Notification.Name("SubscriptionServiceRestoreFailureNotification")
    internal static let purchaseSuccessfulNotification = Notification.Name("SubscriptionServicePurchaseSuccessfulNotification")
    internal static let purchaseFailureNotification = Notification.Name("SubscriptionServicePurchaseFailureNotification")
    internal static let purchaseCancelledNotification = Notification.Name("SubscriptionServicePurchaseCancelledNotification")
    internal static let duplicatePurchasedNotification = Notification.Name("SubscriptionDuplicatePurchasedNotification")
    internal static let promotionPurchaseStartNotification = Notification.Name("PromotionPurchaseStartNotification")
    
    private var arrayOfObserverHolders = [ObserverHolder]()
    
    @objc static public let shared:SubManagerNotificationHandler = {
        
        let shared = SubManagerNotificationHandler()
        shared.setRequiredNotifications()
        return shared
    }()
}

//MARK: Observer Handler
extension SubManagerNotificationHandler {
    
    public func addObserver(_ observerToAdd:SubManagerNotificationObserver) {
        
        var tempArrayObserverHolders = [ObserverHolder]()
        for aObserverHolder in arrayOfObserverHolders {
            if aObserverHolder.observer != nil {
                tempArrayObserverHolders.append(aObserverHolder)
            }
        }
        arrayOfObserverHolders.removeAll()
        for aTempHolder in tempArrayObserverHolders {
            arrayOfObserverHolders.append(aTempHolder)
        }
        arrayOfObserverHolders.append(ObserverHolder(observer: observerToAdd))
        print("Currently Hold: observer: \(arrayOfObserverHolders.count) \(type(of: arrayOfObserverHolders.first?.observer.self))")
    }
    
    public func removeObserver(_ observerToRemove:SubManagerNotificationObserver) {
        
        for index in 0..<arrayOfObserverHolders.count {
            
            let currentObserver = arrayOfObserverHolders[index].observer
            if currentObserver === observerToRemove {
                
                arrayOfObserverHolders.remove(at: index)
                break
            }
        }
    }
    
    func notifyObserversForNotificationType(_ notificationType:IAPurchaseState, _ notification:Notification?) {
        
//        if notificationType == .SubscriptionExpire {
//            try! SubscriptionManager.shared.refreshReceiptWhenExpired()
//        }
        
        for aObserverHolder in arrayOfObserverHolders {
            DispatchQueue.main.async {
                aObserverHolder.observer?.updateRequiredThingsFor(notificationType:notificationType, notification:notification)
            }
        }
    }
}

//MARK: Receive Notifications for IAPurchaseHelper
extension SubManagerNotificationHandler {
    
    private func setRequiredNotifications() {
        
        NotificationCenter.default.addObserver(self, selector: #selector(purchaseSuccess(_:)), name: SubManagerNotificationHandler.purchaseSuccessfulNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(restoreSuccess(_:)), name: SubManagerNotificationHandler.restoreSuccessfulNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(purchaseFailed(_:)), name: SubManagerNotificationHandler.purchaseFailureNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(restoreFailed(_:)), name: SubManagerNotificationHandler.restoreFailureNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(promotionPurchaseStart(_:)), name: SubManagerNotificationHandler.promotionPurchaseStartNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(duplicatePurchase(_:)), name: SubManagerNotificationHandler.duplicatePurchasedNotification, object: nil)

    }
    @objc private func duplicatePurchase(_ notification:Notification) {
        
        self.notifyObserversForNotificationType(.DuplicatePurchase, notification)
    }
    
    @objc private func purchaseSuccess(_ notification:Notification) {
        
        self.notifyObserversForNotificationType(.PurchaseSuccessful, notification)
    }
    
    @objc private func purchaseFailed(_ notification:Notification) {
        
        self.notifyObserversForNotificationType(.PurchaseFailure, notification)
    }
    
    @objc private func restoreSuccess(_ notification:Notification) {
        
        //TODO: IMPLEMENT LATER
//        if (SubscriptionManager.shared.boolShouldShowSuccessAlert) {
//            
//            if SubscriptionManager.shared.isSubscribedOrUnlockedAll() {
//                ProgressHUD.showSucceed("Successfully Restored.", interaction: false)
//            } else {
//                ProgressHUD.showError("Nothing to Restore.", interaction: false);
//            }
//        }
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.10) {
//             ProgressHUD.dismiss()
//        }
        
        self.notifyObserversForNotificationType(.RestoreSuccessful, notification)
    }
    
    @objc private func restoreFailed(_ notification:Notification) {
        
//        if (SubscriptionManager.shared.boolShouldShowSuccessAlert) {
//            
//            ProgressHUD.showFailed("Failed to Restore. Please try again!", interaction: false)
//            
//        }
//        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2.10) {
//             ProgressHUD.dismiss()
//        }
        
        self.notifyObserversForNotificationType(.RestoreFailure, notification)
    }
    
    @objc private func promotionPurchaseStart(_ notification:Notification) {
        self.notifyObserversForNotificationType(.PromotionPurchaseStart, notification)
    }
}
