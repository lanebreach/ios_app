//
//  TwitterViewController.swift
//  blfa
//
//  Created by Dale Low on 4/10/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import Foundation
import SafariServices
import SDWebImage
import Swifter
import UIKit

class TweetCell: UITableViewCell {
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var label1: UILabel!
    @IBOutlet weak var label2: UILabel!
}

class TwitterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    
    let cellReuseIdentifier = "TweetCell"
    var tweets : [JSON]?
    let swifter = Swifter(consumerKey: Keys.twitterConsumerKey,
                          consumerSecret: Keys.twitterConsumerSecret,
                          oauthToken: Keys.twitterOauthToken,
                          oauthTokenSecret: Keys.twitterOauthTokenSecret)

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(self.handleRefresh(_:)), for: UIControlEvents.valueChanged)
        refreshControl.tintColor = AppDelegate.brandColor(purpose: .common)
        
        return refreshControl
    }()
    
    override func viewDidLoad() {
        tableView.addSubview(self.refreshControl)
        refreshTweets()
    }
    
    //MARK:- Internal methods
    func decodeHtml(htmlEncodedString: String) -> String? {
        guard let data = htmlEncodedString.data(using: .utf8) else {
            return nil
        }
        
        guard let attributedString = try? NSAttributedString(data: data,
                                                             options: [.documentType: NSAttributedString.DocumentType.html,
                                                                       .characterEncoding: String.Encoding.utf8.rawValue],
                                                             documentAttributes: nil) else {
                                                                return nil
        }
        
        return attributedString.string
    }
    
    func refreshTweets() {
        // extended mode is needed to get the full_text field (otherwise text is a truncated version of it)
        let parameters = ["tweet_mode": "extended"]
        swifter.getTimeline(for: "1010780550687100929" /* EverySF311Bike */, customParam: parameters, count:100, trimUser: true, success: { json in
            self.tweets = json.array
            self.tableView.reloadData()
            self.refreshControl.endRefreshing()
        }, failure: { error in
            print("error \(error)")
        })
    }
    
    @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
        refreshTweets()
    }
    
    //MARK:- UITableViewDataSource/Delegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tweets = tweets else {
            return 0
        }
        
        return tweets.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let tweets = tweets, let cell = self.tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier) as? TweetCell else {
            return UITableViewCell()
        }

        let text = tweets[indexPath.row]["full_text"].string
        
        // text ex: "37 2ND ST\n\nUber or Lyft driver ran a person on a bicycle into the curb as he pul…\n"
        var location: String?
        var description: String?
        var date: String?
        var laneBreachSubmission: Bool = false
        if let text = text {
            // get the location text out of the report
            var regex = try! NSRegularExpression(pattern: ".*\n\n")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: 0)
                let end = text.index(text.startIndex, offsetBy: match.range.length - 2 /* exclude \n\n */)
                
                location = decodeHtml(htmlEncodedString: String(text[start..<end]))
            }
            
            // get the description text out of the report. It will start with "https://" if there is no description.
            regex = try! NSRegularExpression(pattern: "\n\n.*\n")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: match.range.location + 2 /* exclude \n\n */)
                let end = text.index(text.startIndex, offsetBy: match.range.location + match.range.length - 1 /* exclude \n */)
                
                description = decodeHtml(htmlEncodedString: String(text[start..<end]))
                if description != nil {
                    if description!.starts(with: "https://") {
                        description = nil
                    } else {
                        // now check for lane breach description
                        if description == "Blocked bicycle lane" {
                            laneBreachSubmission = true
                        } else {
                            regex = try! NSRegularExpression(pattern: "^\\[[A-Z].*\\]")
                            if regex.firstMatch(in: description!, options: [], range: NSRange(location: 0, length: description!.utf16.count)) != nil {
                                laneBreachSubmission = true
                            }
                        }
                    }
                }
            }
            
            // get the date (ex: "2019-04-19 07:21:53")
            regex = try! NSRegularExpression(pattern: "\\d\\d\\d\\d\\-\\d\\d\\-\\d\\d\\ \\d\\d:\\d\\d:\\d\\d")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: match.range.location)
                let end = text.index(text.startIndex, offsetBy: match.range.location + match.range.length)
                
                date = String(text[start..<end])
            }
        }

//        print("\n-------------------------")
//        print(">>>text: '\(text!)'")
//        print(">>>url: '\(cell.label2.text ?? "nil")'")
//        print(">>>location: '\(location ?? "nil")'")
//        print(">>>description: '\(description ?? "nil")'")
//        print(">>>date: '\(date ?? "nil")'")

        cell.label1.text = (date ?? "Unknown date") + "\n" + (location ?? "Unknown Location")
        cell.label2.text = description ?? ""
        if laneBreachSubmission {
            cell.backgroundColor = AppDelegate.brandColor(purpose: .feedItems)
        } else {
            cell.backgroundColor = UIColor.white
        }

        if let mediaUrl = tweets[indexPath.row]["entities"]["media"][0]["media_url_https"].string {
            cell.iconView.sd_setImage(with: URL(string: mediaUrl), placeholderImage: UIImage(named: "no_bike_icon"), completed: nil)
            cell.iconView.contentMode = .scaleAspectFill
        } else {
            cell.iconView.image = nil
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let tweets = tweets else {
            return
        }

        if let threeOneOneUrl = tweets[indexPath.row]["entities"]["urls"][0]["expanded_url"].string {
            let url = URL(string: threeOneOneUrl)!
            let safariView = SFSafariViewController(url: url)
            self.present(safariView, animated: true, completion: nil)
        }
    }
}
