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
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.emailTextField.text = UserDefaults.standard.string(forKey: "com.blfa.email") ?? ""
        self.emailTextField.delegate = self
    }
    
    //MARK:- Internal methods
    func isValidEmail(testStr:String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        
        let emailTest = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailTest.evaluate(with: testStr)
    }
    
    //MARK:- UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        if let text = textField.text, text != "" {
            if !isValidEmail(testStr: text) {
                AppDelegate.showSimpleAlertWithOK(vc: self, "Invalid email address")
                return true
            }
        }
        
        UserDefaults.standard.set(textField.text, forKey: "com.blfa.email")
        return true
    }
}
