//
//  TwitterViewController.swift
//  blfa
//
//  Created by Dale Low on 4/10/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import Foundation
import Swifter
import UIKit

class TwitterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    
    let cellReuseIdentifier = "cell"
    
    override func viewDidLoad() {
        let swifter = Swifter(consumerKey: Keys.twitterConsumerKey,
                              consumerSecret: Keys.twitterConsumerSecret,
                              oauthToken: Keys.twitterOauthToken,
                              oauthTokenSecret: Keys.twitterOauthTokenSecret)

        swifter.getTimeline(for: "1010780550687100929" /* EverySF311Bike */, success: { json in
            print("json \(json)")
        }, failure: { error in
            print("error \(error)")
        })

        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell = self.tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier) as UITableViewCell!
        cell.textLabel?.text = "test"
        
        return cell
    }
}
