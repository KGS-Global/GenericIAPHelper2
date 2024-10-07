#
#  Be sure to run `pod spec lint GenericIAPHelper.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  spec.name         = "GenericIAPHelper2"
  spec.version      = "0.0.2"
  spec.summary      = "A short description of GenericIAPHelper 2."

  spec.description  = <<-DESC 
                    IOS In App Purchase Helper Framework to complete In App Purchases.
		    This is using the new StoreKit2 API for managing purchases and subscriptions.
                   DESC

  spec.homepage     = "https://github.com/KGS-Global/GenericIAPHelper2"
  
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "KGS-Global" => "kgs.bitbucket.manager@gmail.com" }
  
  spec.platform     = :ios, "15.0"
  spec.source       = { :git => "https://github.com/KGS-Global/GenericIAPHelper2.git", :tag => "#{spec.version}" }

  spec.source_files  = "GenericIAPHelper2", "GenericIAPHelper2/**/*.{h,m,swift}"
  #spec.resources     = "GenericIAPHelper2/**/*.{png,xib,plist,xcassets}"

  spec.swift_version = "5.0"

end
