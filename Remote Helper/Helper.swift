//
//  Helper.swift
//  Video Player
//
//  Created by Venj Chu on 15/11/2.
//  Copyright © 2015 Home. All rights reserved.
//

import UIKit
import Alamofire
import PKHUD
import Reachability
import SafariServices
import TOWebViewController

@objc
open class Helper : NSObject {
    open static let shared = Helper()

    fileprivate var sessionHeader: String = ""
    fileprivate var downloadPath: String = ""
    var reachability: Reachability? = {
        let reach = Reachability()
        try? reach?.startNotifier()
        return reach!
    }()

    // AD black list.
    var kittenBlackList: [String] = ["正品香烟", "中铧", "稥湮", "威信", "试抽"]

    func kittenSearchPath(withKeyword keyword: String, page: Int = 1) -> String {
        let kw = keyword.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics)
        let escapedKeyword = kw == nil ? "" : kw!
        let pageString = page == 1 ? "" : "\(page)"
        return "https://www.torrentkitty.tv/search/\(escapedKeyword)/\(pageString)"
    }

    //MARK: - Local Files and ImageCache Helpers
    func documentsDirectory() -> String {
        return NSSearchPathForDirectoriesInDomains(.documentationDirectory, .userDomainMask, true).first!
    }
    
    func freeDiskSpace() -> Int {
        guard let dictionary = try? FileManager.default.attributesOfFileSystem(forPath: self.documentsDirectory()) else { return 0 }
        let freeFileSystemSizeInBytes = dictionary[FileAttributeKey.systemFreeSize] as! Int
        return freeFileSystemSizeInBytes
    }

    func localFileSize() -> Int {
        var size = 0
        let documentsDirectory = self.documentsDirectory()
        guard let fileEnumerator = FileManager.default.enumerator(atPath: documentsDirectory) else { return 0 }
        for fileName in fileEnumerator {
            let filePath = documentsDirectory.vc_stringByAppendingPathComponent(fileName as! String)
            guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: filePath) else { continue }
            size += (attrs[FileAttributeKey.size] as! Int)
        }
        return size
    }

    func fileToDownload(withPath path: String) -> String {
        return self.documentsDirectory().vc_stringByAppendingPathComponent(path.vc_lastPathComponent())
    }

    func fileSizeString(withInteger integer: Int) -> String {
        return integer.fileSizeString
    }

    //MARK: - UserDefaults Helpers

    func appVersionString() -> String {
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(versionString)(\(buildString))"
    }

    //MARK: - UI Related Helpers
    func mainThemeColor() -> UIColor {
        return UIColor(red:0.94, green:0.44, blue:0.19, alpha:1)
    }
    
    func showCellularHUD() -> Bool {
        guard let reachability = self.reachability else { return false }
        if !Configuration.shared.userCellularNetwork && reachability.connection != .wifi {
            DispatchQueue.main.async(execute: { () -> Void in
                PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("Cellular data is turned off.", comment: "Cellular data is turned off."))
            })
            return true
        }
        return false
    }

    @objc func dismissMe(_ sender: UIBarButtonItem) {
        AppDelegate.shared.window?.rootViewController?.dismiss(animated: true, completion: nil)
    }

    // Nasty method naming, just for minimum code change
    func showTorrentSearchAlertInViewController(_ viewController:UIViewController?) {
        guard let viewController = viewController else { return } // Just do nothing...
        if (self.showCellularHUD()) { return }
        let title = NSLocalizedString("Search Torrent Kitten", comment: "Search Torrent Kitten")
        let message = NSLocalizedString("Please enter video serial (or anything):", comment: "Please enter video serial (or anything):")
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.keyboardType = .default
            textField.becomeFirstResponder()
        }
        let searchAction = UIAlertAction(title: NSLocalizedString("Search", comment: "Search"), style: .default) { _ in
            let keyword = alertController.textFields![0].text!
            let hud = PKHUD.sharedHUD.showHUD()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let `self` = self else { return }
                let url = URL(string: self.kittenSearchPath(withKeyword: keyword))!
                if let data = try? Data(contentsOf: url) {
                    let torrents = KittenTorrent.parse(data: data)
                    if torrents.count == 0 {
                        DispatchQueue.main.async {
                            PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("No torrent found", comment: "No torrent found"))
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        if let tabControl =  UIApplication.shared.keyWindow?.rootViewController as? UITabBarController, let navControl = tabControl.selectedViewController as? UINavigationController, let searchControl = navControl.topViewController as? VPSearchResultController {
                            searchControl.torrents = torrents
                            searchControl.keyword = keyword
                            searchControl.tableView.reloadData()
                            hud.hide()
                            return
                        }
                        let searchResultController = VPSearchResultController()
                        searchResultController.torrents = torrents
                        searchResultController.keyword = keyword
                        if let navigationController = viewController as? UINavigationController {
                            navigationController.pushViewController(searchResultController, animated: true)
                        }
                        else if let tabbarController = (UIApplication.shared.delegate as! AppDelegate).window?.rootViewController as? UITabBarController, let navigationController = tabbarController.selectedViewController as? UINavigationController {
                            navigationController.pushViewController(searchResultController, animated: true)
                        }
                        else {
                            let searchResultNavigationController = UINavigationController(rootViewController: searchResultController)
                            searchResultController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target:self, action: #selector(Helper.dismissMe(_:)))
                            viewController.present(searchResultNavigationController, animated: true, completion: nil)
                        }
                        hud.hide()
                    }
                }
                else {
                    DispatchQueue.main.async {
                        PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("Connection failed.", comment: "Connection failed."))
                    }
                }
            }
        }
        alertController.addAction(searchAction)
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        alertController.view.tintColor = Helper.shared.mainThemeColor()
        viewController.present(alertController, animated: true, completion: nil)
    }

    //MARK: - Transmission Remote Download Helpers
    func downloadTask(_ magnet:String, toDir dir: String, completionHandler:(() -> Void)? = nil,  errorHandler:(() -> Void)? = nil) {
        let params = ["method" : "torrent-add", "arguments": ["paused" : false, "download-dir" : dir, "filename" : magnet]] as [String : Any]
        let HTTPHeaders = ["X-Transmission-Session-Id" : sessionHeader]
        //, parameters: params, encoding: .JSON, headers: HTTPHeaders
        let request = Alamofire.request(Configuration.shared.transmissionRPCAddress(), method: .post, parameters: params, encoding: JSONEncoding(options: []),headers: HTTPHeaders)
        request.authenticate(user: Configuration.shared.transmissionUsername, password: Configuration.shared.transmissionPassword).responseJSON { response in
            if response.result.isSuccess {
                let responseObject = response.result.value as! [String: Any]
                let result = responseObject["result"] as! String
                if result == "success" {
                    completionHandler?()
                }
            }
            else {
                errorHandler?()
            }
        }
    }

    func parseSessionAndAddTask(_ magnet:String, completionHandler:(() -> Void)? = nil, errorHandler:(() -> Void)? = nil) {
        let params = ["method" : "session-get"]
        let HTTPHeaders = ["X-Transmission-Session-Id" : sessionHeader]
        let request = Alamofire.request(Configuration.shared.transmissionRPCAddress(), method: .post, parameters: params, encoding: JSONEncoding(options: []),headers: HTTPHeaders)
        request.authenticate(user: Configuration.shared.transmissionUsername, password: Configuration.shared.transmissionPassword).responseJSON { [weak self] response in
            guard let `self` = self else { return }
            if response.result.isSuccess {
                let responseObject = response.result.value as! [String:Any]
                let result = responseObject["result"] as! String
                if result == "success" {
                    self.downloadPath = (responseObject["arguments"] as! [String: Any])["download-dir"] as! String
                    self.downloadTask(magnet, toDir: self.downloadPath, completionHandler: completionHandler, errorHandler: errorHandler)
                }
                else {
                    errorHandler?()
                }
            }
            else {
                if response.response?.statusCode == 409 {
                    self.sessionHeader = response.response!.allHeaderFields["X-Transmission-Session-Id"] as! String
                    let params = ["method" : "session-get"]
                    let HTTPHeaders = ["X-Transmission-Session-Id" : self.sessionHeader]
                    let request = Alamofire.request(Configuration.shared.transmissionRPCAddress(), method: .post, parameters: params, encoding: JSONEncoding(options: []),headers: HTTPHeaders)
                    request.authenticate(user: Configuration.shared.transmissionUsername, password: Configuration.shared.transmissionPassword).responseJSON { [weak self] response in
                        guard let `self` = self else { return }
                        if response.result.isSuccess {
                            let responseObject = response.result.value as! [String:Any]
                            let result = responseObject["result"] as! String
                            if result == "success" {
                                self.downloadPath = (responseObject["arguments"] as! [String: Any])["download-dir"] as! String
                                self.downloadTask(magnet, toDir: self.downloadPath, completionHandler: completionHandler, errorHandler: errorHandler)
                            }
                            else {
                                errorHandler?()
                            }
                        }
                        else {
                            let alertController = UIAlertController(title: NSLocalizedString("Error", comment:"Error"), message: NSLocalizedString("Unkown error.", comment: "Unknow error."), preferredStyle: .alert)
                            let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: .cancel, handler: nil)
                            alertController.addAction(cancelAction)
                            alertController.view.tintColor = Helper.shared.mainThemeColor()
                            AppDelegate.shared.window?.rootViewController?.present(alertController, animated: true, completion: nil)
                        }
                    }
                }
                else {
                    errorHandler?()
                }
            }
        }
    }

    func showMiDownload(for link: String, inViewController viewController: UIViewController) {
        guard let miURL = URL(string:(link)) else { return }
        if #available(iOS 9.0, *) {
            let sfVC = SFSafariViewController(url: miURL)
            sfVC.title = NSLocalizedString("Mi Remote", comment: "Mi Remote")
            sfVC.modalPresentationStyle = .formSheet
            sfVC.modalTransitionStyle = .coverVertical
            viewController.navigationController?.present(sfVC, animated: true, completion: nil)
        } else {
            // Fallback on earlier versions
            let webView = TOWebViewController(url: miURL)!
            webView.title = NSLocalizedString("Mi Remote", comment: "Mi Remote")
            webView.modalPresentationStyle = .formSheet
            webView.modalTransitionStyle = .coverVertical
            viewController.navigationController?.present(webView, animated: true, completion: nil)
        }
    }

    func transmissionDownload(for link: String) {
        PKHUD.sharedHUD.showHUD()
        parseSessionAndAddTask(link, completionHandler: {
            PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("Task added.", comment: "Task added."))
        }, errorHandler: {
            PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("Transmission server error.", comment: "Transmission server error."))
        })
    }

    var canStartMiDownload: Bool {
        return !(Configuration.shared.miAccountUsername.isEmpty || Configuration.shared.miAccountPassword.isEmpty)
    }

    func miDownloadForLink(_ link: String, fallbackIn viewController: UIViewController) {
        miDownloadForLinks([link], fallbackIn: viewController)
    }

    func miDownloadForLinks(_ links: [String], fallbackIn viewController: UIViewController) {
        guard canStartMiDownload else {
            PKHUD.sharedHUD.showHudWithMessage(NSLocalizedString("Mi account not set.", comment: "Mi account not set."))
            return
        }
        let hud = PKHUD.sharedHUD.showHUD()
        MiDownloader(withUsername:Configuration.shared.miAccountUsername, password: Configuration.shared.miAccountPassword, links: links).loginAndFetchDeviceList(progress: { (progress) in
            switch progress {
            case .prepare:
                hud.setMessage(NSLocalizedString("Preparing...", comment: "Preparing..."))
            case .login:
                hud.setMessage(NSLocalizedString("Loging in...", comment: "Loging in..."))
            case .fetchDevice:
                hud.setMessage(NSLocalizedString("Loading Device...", comment: "Loading Device..."))
            case .download:
                hud.setMessage(NSLocalizedString("Add download...", comment: "Add download..."))
            }
        }, success: { (success) in
            switch success {
            case .added:
                hud.setMessage(NSLocalizedString("Added!", comment: "Added!"))
            case .duplicate:
                hud.setMessage(NSLocalizedString("Duplicated!", comment: "Duplicated!"))
            case .other(let code):
                hud.setMessage(NSLocalizedString("Added! Code: ", comment: "Added! Code: ") + "\(code)")
            }
            hud.hide(afterDelay: 1.0)
        }, error: { (error) in
            hud.hide()
            switch error {
            case .capchaError(let link):
                PKHUD.sharedHUD.hide()
                DispatchQueue.main.after(0.5, execute: {
                    self.showMiDownload(for: link, inViewController: viewController)
                })
            default:
                let reason = error.localizedDescription
                PKHUD.sharedHUD.showHudWithMessage(reason)
            }
        })
    }
}


