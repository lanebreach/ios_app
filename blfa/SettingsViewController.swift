//
//  SettingsViewController.swift
//  blfa
//
//  Created by Dale Low on 11/14/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import UIKit

class SettingsViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var phoneTextField: UITextField!
    @IBOutlet weak var resetReportsLabel: UILabel!
    @IBOutlet weak var appVersionLabel: UILabel!
    
    //MARK:- Lifecycle
    override func viewDidLoad() {
        let tapper = UITapGestureRecognizer(target:self, action:#selector(self.resetReportsButtonPressed(sender:)))
        tapper.numberOfTouchesRequired = 1
        resetReportsLabel.isUserInteractionEnabled = true
        resetReportsLabel.addGestureRecognizer(tapper)
        
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
    @objc func resetReportsButtonPressed(sender: UITapGestureRecognizer?) {
        AppDelegate.showSimpleAlertWithOK(vc: self, "Touch Reset to clear your list of previously uploaded reports from the Reports screen. This does not affect reports uploaded to 311.",
                                          button2title: "Reset") { (_) in

                                            ReportManager.shared.clearReports()
                                            AppDelegate.showSimpleAlertWithOK(vc: self, "All reports removed from the map")
        }
    }
    
    //MARK:- UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        switch textField {
        case emailTextField:
            if let text = textField.text, text != "" {
                if !isValidEmail(testStr: text) {
                    AppDelegate.showSimpleAlertWithOK(vc: self, "Invalid email address")
                    return true
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
