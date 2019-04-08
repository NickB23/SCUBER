//
//  RoundedShadowButton.swift
//  SCUBER
//
//  Created by Nick Bruinsma on 01/04/2019.
//  Copyright © 2019 appeeme. All rights reserved.
//

import UIKit

class RoundedShadowButton: UIButton {
    
    var originalSize: CGRect?
    
    func setupView() {
        // Capture originalSize of button to animate back to
        originalSize = self.frame
        // Create rounded corners
        self.layer.cornerRadius = 5.0
        // Create shadow
        self.layer.shadowRadius = 10.0
        self.layer.shadowColor = UIColor.darkGray.cgColor
        self.layer.shadowOpacity = 0.3
        self.layer.shadowOffset = CGSize.zero
    }
    
    override func awakeFromNib() {
        setupView()
    }
    
    func animateButton(shouldLoad: Bool, withMessage message: String?) {
        // Create spinner
        let spinner = UIActivityIndicatorView()
        spinner.style = .whiteLarge
        spinner.color = UIColor.darkGray
        spinner.alpha = 0.0
        spinner.hidesWhenStopped = true
        // Set unique value so we can remove it later based on it's tag
        spinner.tag = 21
        
        if shouldLoad {
            // Add the spinner subview to the button
            self.addSubview(spinner)
            
            // Remove the text from the button
            self.setTitle("", for: .normal)
            UIView.animate(withDuration: 0.2, animations: {
                // Make the button square (equal width & height) and move it into the center x position of it's previous state
                self.frame = CGRect(x: self.frame.midX - (self.frame.height / 2), y: self.frame.origin.y, width: self.frame.height, height: self.frame.height)
                
                // Turn the square button into a circle by setting the cornerRadius
                self.layer.cornerRadius = self.frame.height / 2
                
            }, completion: { (finished) in
                if finished == true {
                    spinner.startAnimating()
                    
                    // Somehow it was off by one pixel. Which is why we add +1 for the y value
                    spinner.center = CGPoint(x: self.frame.width / 2 + 1, y: self.frame.height / 2 + 1 )
                    spinner.fadeTo(alphaValue: 1.0, withDuration: 0.2)
                }
            })
            self.isUserInteractionEnabled = false
        } else {
            self.isUserInteractionEnabled = true
            
            for subview in self.subviews {
                if subview.tag == 21 {
                    subview.removeFromSuperview()
                }
            }
            
            UIView.animate(withDuration: 0.2, animations: {
                self.layer.cornerRadius = 5.0
                self.frame = self.originalSize!
                self.setTitle(message, for: .normal)
            })
        }
        
    }
    
}


