//
//  GradientView.swift
//  SCUBER
//
//  Created by Nick Bruinsma on 01/04/2019.
//  Copyright © 2019 appeeme. All rights reserved.
//

import UIKit

class GradientView: UIView {
    
    let gradient = CAGradientLayer()
    
    override func awakeFromNib() {
        setupGradientView()
    }
    
    func setupGradientView() {
        gradient.frame = self.bounds
        gradient.colors = [UIColor.white.cgColor, UIColor.init(white: 1.0, alpha: 0.0).cgColor]
        gradient.startPoint = CGPoint.zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        gradient.locations = [0.8, 1.0]
        self.layer.addSublayer(gradient)
    }
}
