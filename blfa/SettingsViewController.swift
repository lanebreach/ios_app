//
//  SettingsViewController.swift
//  blfa
//
//  Created by Dale Low on 11/14/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import Crashlytics
import Fabric
import SafariServices
import UIKit

class SettingsViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var phoneTextField: UITextField!
    @IBOutlet weak var showHelpLabel: UILabel!
    @IBOutlet weak var resetReportsLabel: UILabel!
    @IBOutlet weak var resetTipsLabel: UILabel!
    @IBOutlet weak var appVersionLabel: UILabel!
    @IBOutlet weak var changeServerHiddenView: UIView!
    
    //MARK:- Lifecycle
    override func viewDidLoad() {
        #if false
        // crash tester
        let button = UIButton(type: .roundedRect)
        button.frame = CGRect(x: 20, y: 50, width: 100, height: 30)
        button.setTitle("Crash", for: [])
        button.addTarget(self, action: #selector(self.crashButtonTapped(_:)), for: .touchUpInside)
        view.addSubview(button)
        #endif

        var tapper = UITapGestureRecognizer(target:self, action:#selector(self.showHelpAction(sender:)))
        tapper.numberOfTouchesRequired = 1
        showHelpLabel.isUserInteractionEnabled = true
        showHelpLabel.addGestureRecognizer(tapper)

        tapper = UITapGestureRecognizer(target:self, action:#selector(self.resetReportsAction(sender:)))
        tapper.numberOfTouchesRequired = 1
        resetReportsLabel.isUserInteractionEnabled = true
        resetReportsLabel.addGestureRecognizer(tapper)
        
        tapper = UITapGestureRecognizer(target:self, action:#selector(self.resetTipsAction(sender:)))
        tapper.numberOfTouchesRequired = 1
        resetTipsLabel.isUserInteractionEnabled = true
        resetTipsLabel.addGestureRecognizer(tapper)

        let longTapper = UILongPressGestureRecognizer(target:self, action:#selector(self.changeServerAction(sender:)))
        longTapper.numberOfTouchesRequired = 1
        changeServerHiddenView.isUserInteractionEnabled = true
        changeServerHiddenView.addGestureRecognizer(longTapper)

        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            let appBundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            
            appVersionLabel.text = "App Version \(appVersion) (\(appBundleVersion))"
        } else {
            appVersionLabel.text = ""
        }
        
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.emailTextField.text = UserDefaults.standard.string(forKey: kUserDefaultsEmailKey)
        self.emailTextField.delegate = self
        
        self.nameTextField.text = UserDefaults.standard.string(forKey: kUserDefaultsNameKey)
        self.nameTextField.delegate = self
        
        self.phoneTextField.text = UserDefaults.standard.string(forKey: kUserDefaultsPhoneKey)
        self.phoneTextField.delegate = self
    }
    
    //MARK:- Internal methods
    func isValidEmail(testStr:String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailTest.evaluate(with: testStr)
    }
    
    //MARK:- Event Handlers
    #if false
    @objc func crashButtonTapped(_ sender: AnyObject) {
        Crashlytics.sharedInstance().crash()
    }
    #endif

    @objc func showHelpAction(sender: UITapGestureRecognizer?) {
        if let url = URL(string: "https://www.lanebreach.org/mobilehelp") {
            let vc = SFSafariViewController(url: url, entersReaderIfAvailable: true)
            present(vc, animated: true)
        }
    }
    
    @objc func resetReportsAction(sender: UITapGestureRecognizer?) {
        AppDelegate.showSimpleAlertWithOK(vc: self, "Touch Reset to clear your list of previously uploaded reports from the Reports screen. This does not affect reports uploaded to 311.",
                                          button2title: "Reset") { (_) in

                                            ReportManager.shared.clearReports()
                                            AppDelegate.showSimpleAlertWithOK(vc: self, "All reports removed from the map")
        }
    }
    
    @objc func resetTipsAction(sender: UITapGestureRecognizer?) {
        AppDelegate.restoreAllTips()
        
        AppDelegate.showSimpleAlertWithOK(vc: self, "All hints restored")
    }
    
    @objc func changeServerAction(sender: UILongPressGestureRecognizer?) {
        guard sender?.state == .ended else {
            return
        }
        
        let alertController = UIAlertController(title: nil, message: "Change server?", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "Password"
            textField.isSecureTextEntry = true
        }
        
        let productionAction = UIAlertAction(title: "311 Prod", style: .default) { [weak alertController] _ in
            guard let alertController = alertController, let textField = alertController.textFields?.first else { return }
            if let password = textField.text, password == Keys.apiServerPassword {
                AppDelegate.showSimpleAlertWithOK(vc: self, "Server changed to 311 production")
                UserDefaults.standard.set(false, forKey: kUserDefaultsUsingDevServerKey)
                NetworkManager.shared.updateTabBarStyleForCurrentServer(vc: self)
            }
        }
        alertController.addAction(productionAction)

        let devAction = UIAlertAction(title: "311 Dev", style: .default) { [weak alertController] _ in
            guard let alertController = alertController, let textField = alertController.textFields?.first else { return }
            if let password = textField.text, password == Keys.apiServerPassword {
                AppDelegate.showSimpleAlertWithOK(vc: self, "Server changed to 311 development")
                UserDefaults.standard.set(true, forKey: kUserDefaultsUsingDevServerKey)
                NetworkManager.shared.updateTabBarStyleForCurrentServer(vc: self)
            }
        }
        alertController.addAction(devAction)

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        present(alertController, animated: true, completion: nil)
    }
    
    //MARK:- UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        switch textField {
        case emailTextField:
            if let text = textField.text, text != "" {
                if !isValidEmail(testStr: text) {
                    AppDelegate.showSimpleAlertWithOK(vc: self, "Invalid email address")
                    return false
                }
            }
            
            UserDefaults.standard.set(textField.text, forKey: kUserDefaultsEmailKey)
        case nameTextField:
            UserDefaults.standard.set(textField.text, forKey: kUserDefaultsNameKey)
        case phoneTextField:
            UserDefaults.standard.set(textField.text, forKey: kUserDefaultsPhoneKey)
        default:
            assert(false)
        }
        
        return true
    }
}
