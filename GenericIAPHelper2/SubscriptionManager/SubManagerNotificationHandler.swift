import UIKit

final class ObserverHolder {
    
    weak var observer : SubManagerNotificationObserver?
    init (observer: SubManagerNotificationObserver) {
        self.observer = observer
    }
}

public class SubManagerNotificationHandler: NSObject {
    
    private var arrayOfObserverHolders = [ObserverHolder]()
    
    @objc static public let shared:SubManagerNotificationHandler = {
        
        let shared = SubManagerNotificationHandler()
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
        
        for aObserverHolder in arrayOfObserverHolders {
            DispatchQueue.main.async {
                aObserverHolder.observer?.updateRequiredThingsFor(notificationType:notificationType, notification:notification)
            }
        }
    }
}
