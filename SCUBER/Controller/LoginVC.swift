//
//  LoginVC.swift
//  SCUBER
//
//  Created by Nick Bruinsma on 07/04/2019.
//  Copyright © 2019 appeeme. All rights reserved.
//

import UIKit
import Firebase

class LoginVC: UIViewController, UITextFieldDelegate, Alertable {
    
    @IBOutlet weak var emailField: RoundedCornerTextField!
    @IBOutlet weak var passwordField: RoundedCornerTextField!
    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var signupLoginBtn: RoundedShadowButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.bindToKeyboard()
        
        emailField.delegate = self
        passwordField.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleScreenTap(sender:)))
        self.view.addGestureRecognizer(tap)
        
    }
    
    func createFirebaseAccount(isDriver: Bool, user: Firebase.User) {
        if isDriver {
            let userData = ["provider": user.providerID, USER_IS_DRIVER: true, ACCOUNT_PICKUP_MODE_ENABLED: false, DRIVER_IS_ON_TRIP: false] as [String: Any]
            DataService.instance.createFirebaseDBUser(uid: user.uid, userData: userData, isDriver: true)
        } else {
            let userData = ["provider": user.providerID] as [String: Any]
            DataService.instance.createFirebaseDBUser(uid: user.uid, userData: userData, isDriver: false)
        }
    }
    
    func handleError(errorCode: AuthErrorCode, isSignupMode: Bool) {
        if isSignupMode {
            switch errorCode {
            case .emailAlreadyInUse:
                self.showAlert(ERROR_MSG_EMAIL_ALREADY_IN_USE)
            case .wrongPassword:
                self.showAlert("Password not allowed.")
            default:
                self.showAlert(ERROR_MSG_UNEXPECTED_ERROR)
            }
        } else {
            switch errorCode {
            case .invalidEmail:
                self.showAlert(ERROR_MSG_INVALID_EMAIL)
            case .wrongPassword:
                self.showAlert(ERROR_MSG_WRONG_PASSWORD)
            default:
                self.showAlert(ERROR_MSG_UNEXPECTED_ERROR)
            }
        }
    }
    
    @objc func handleScreenTap(sender: UITapGestureRecognizer) {
        self.view.endEditing(true)
    }
    
    @IBAction func cancelBtnPressed(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func signupLoginBtnPressed(_ sender: Any) {
        

        if emailField.text != nil && passwordField.text != nil {
            signupLoginBtn.animateButton(shouldLoad: true, withMessage: nil)
            self.view.endEditing(true)
            
            if let email = emailField.text, let password = passwordField.text {
                Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
                    if error == nil {
                        guard let result = result else {print("Error: No result from firebase"); return}
                        let user = result.user
                        if self?.segmentedControl.selectedSegmentIndex == 0 {
                            // if they login as passenger
                            self?.createFirebaseAccount(isDriver: false, user: user)
                        } else {
                            // it's a driver
                            self?.createFirebaseAccount(isDriver: true, user: user)
                        }
                        self?.dismiss(animated: true, completion: nil)
                    } else {
                        Auth.auth().createUser(withEmail: email, password: password, completion: { (result, error) in
                            if error != nil {
                                if let errorCode = AuthErrorCode(rawValue: error!._code) {
                                    self?.handleError(errorCode: errorCode, isSignupMode: true)
                                }
                            } else {
                                guard let result = result else {print("Error: No result from firebase"); return}
                                let user = result.user
                                if self?.segmentedControl.selectedSegmentIndex == 0 {
                                    // if they sign up as passenger
                                    self?.createFirebaseAccount(isDriver: false, user: user)
                                    self?.dismiss(animated: true, completion: nil)
                                } else {
                                    // they sign up as a driver
                                    
                                    self?.createFirebaseAccount(isDriver: true, user: user)
                                    self?.dismiss(animated: true, completion: nil)
                                }
                            }
                        })
                    }
                }
            }
        }
    }
}

