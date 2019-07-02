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
    @IBOutlet weak var dateLabel: UILabel!
}

class TwitterViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var laneBreachIconView: UIView!
    @IBOutlet weak var communityIconView: UIView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!
    
    let cellReuseIdentifier = "TweetCell"
    var tweets : [JSON]?
    let swifter = Swifter(consumerKey: Keys.twitterConsumerKey,
                          consumerSecret: Keys.twitterConsumerSecret,
                          oauthToken: Keys.twitterOauthToken,
                          oauthTokenSecret: Keys.twitterOauthTokenSecret)
    let threeOneOneDateFormatter = DateFormatter()
    let friendlyDateFormatter = DateFormatter()
    var boldHelveticaFontDescriptor: UIFontDescriptor?
    var refreshingTweets = false
    var currentUserReports: Set<String> = []

    lazy var refreshControl: UIRefreshControl = {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(self.handleRefresh(_:)), for: UIControlEvents.valueChanged)
        refreshControl.tintColor = AppDelegate.brandColor(purpose: .lightMain)
        
        return refreshControl
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        threeOneOneDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"     // ex: 2019-04-19 07:21:53
        friendlyDateFormatter.dateFormat = "MMM d - h:mm a"               // ex: Apr 21 8:59 PM

        laneBreachIconView.backgroundColor = AppDelegate.brandColor(purpose: .main)
        communityIconView.backgroundColor = AppDelegate.brandColor(purpose: .communityFeedItems)
        
        tableView.addSubview(self.refreshControl)
        tableView.backgroundColor = AppDelegate.brandColor(purpose: .communityFeedItems)
        tableView.separatorStyle = .none
        
        // show on first load only
        activityIndicatorView.startAnimating()
        
        refreshTweets()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateUserReportsAndRefreshTweets(forceRefresh: false)
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
    
    func friendlyTimeFormat(duration: TimeInterval) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        
        return formatter.string(from: duration)
    }
    
    func refreshTweets() {
        guard !refreshingTweets else {
            return
        }
        
        refreshingTweets = true
        
        // extended mode is needed to get the full_text field (otherwise text is a truncated version of it)
        let parameters = ["tweet_mode": "extended"]
        swifter.getTimeline(for: "1010780550687100929" /* EverySF311Bike */, customParam: parameters, count:100, trimUser: true, success: { json in
            self.tweets = json.array
            self.tableView.reloadData()
            self.refreshControl.endRefreshing()
            self.activityIndicatorView.stopAnimating()
            self.activityIndicatorView.isHidden = true
            self.refreshingTweets = false
        }, failure: { error in
            print("error \(error)")
            self.activityIndicatorView.stopAnimating()
            self.activityIndicatorView.isHidden = true
            self.refreshingTweets = false
        })
    }

    func updateUserReportsAndRefreshTweets(forceRefresh: Bool) {
        // want to highlight the current user's reports - so we need to finalize them if we can
        ReportManager.shared.finalizeReportsIfNecessary {
            var needRefresh = forceRefresh
            if let reports = ReportManager.shared.getReports() {
                for report in reports {
                    if let serviceRequestId = report["serviceRequestId"] as? String {
                        if !self.currentUserReports.contains(serviceRequestId) {
                            self.currentUserReports.insert(serviceRequestId)
                            needRefresh = true
                        }
                    }
                }
            } // else user has no reports
            
            if needRefresh {
                self.refreshTweets()
            }
        }
    }
    
    @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
        updateUserReportsAndRefreshTweets(forceRefresh: true)
    }
    
    //MARK:- UITableViewDataSource/Delegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let tweets = tweets else {
            return 0
        }
        
        return tweets.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let tweets = tweets else {
            return 0
        }
        
        let text = tweets[indexPath.row]["full_text"].string
        
        if let text = text {
            // get the description text out of the report. It will start with "https://" if there is no description.
            let regex = try! NSRegularExpression(pattern: "\n\n.*\n")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: match.range.location + 2 /* exclude \n\n */)
                let end = text.index(text.startIndex, offsetBy: match.range.location + match.range.length - 1 /* exclude \n */)

                var description = decodeHtml(htmlEncodedString: String(text[start..<end]))
                if description!.starts(with: "https://") {
                    description = nil
                }
                
                // calculate height using a dummy label (exclude icon and 3 5pt spacers)
                let label: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.width - (60 + 5*3),
                                                           height: CGFloat.greatestFiniteMagnitude))
                label.numberOfLines = 0
                label.lineBreakMode = NSLineBreakMode.byWordWrapping
                label.font = UIFont(name: "Helvetica Neue", size: 15.0)
                label.text = description
                label.sizeToFit()
                
//                print("text: \(label.text), height: \(label.frame.height)")
                // these magic numbers are the min height of the cell with just the image and
                // the height of the cell with the top label and spacers + the height of the description
                return max(70, 55 + label.frame.height)
            }
        }
        
        return 70
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
        var dateDelta: TimeInterval?
        var laneBreachSubmission: Bool = false
        
        if let text = text {
            // get the location text out of the report
            var regex = try! NSRegularExpression(pattern: ".*\n\n")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: 0)
                let end = text.index(text.startIndex, offsetBy: match.range.length - 2 /* exclude \n\n */)
                
                // note: we remove "Intersection of" to make the string shorter to fit better on smaller phones
                location = decodeHtml(htmlEncodedString: String(text[start..<end]))?.replacingOccurrences(of: "Intersection of ", with: "")
            }
            
            // get the description text out of the report.
            // It will start with "https://", "Make/Model:", "License Plate:", or "Color:" if there is no description.
            regex = try! NSRegularExpression(pattern: "\n\n.*\n")
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) {
                let start = text.index(text.startIndex, offsetBy: match.range.location + 2 /* exclude \n\n */)
                let end = text.index(text.startIndex, offsetBy: match.range.location + match.range.length - 1 /* exclude \n */)
                
                description = decodeHtml(htmlEncodedString: String(text[start..<end]))
                if description != nil {
                    if description!.starts(with: "https://") || description!.starts(with: "Make/Model:") ||
                        description!.starts(with: "License Plate:") || description!.starts(with: "Color:") {
                        
                        description = nil
                    } else {
                        // now check for lane breach description: "Blocked bicycle lane" or "[Category] ..."
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
                if date != nil {
                    if let dateObject = threeOneOneDateFormatter.date(from: date!) {
                        // get time delta
                        dateDelta = dateObject.timeIntervalSinceNow
                        
                        // reformat date
                        date = friendlyDateFormatter.string(from: dateObject)
                    }
                }
            }
        }

//        print("\n-------------------------")
//        print(">>>text: '\(text!)'")
//        print(">>>url: '\(cell.label2.text ?? "nil")'")
//        print(">>>location: '\(location ?? "nil")'")
//        print(">>>description: '\(description ?? "nil")'")
//        print(">>>date: '\(date ?? "nil")'")

        // make the location bold
        let dateAndLocation = (date ?? "Unknown date") + "\n" + (location ?? "Unknown Location")
        let range = (dateAndLocation as NSString).range(of: location ?? "Unknown Location")
        let dateAndLocationAttributedString = NSMutableAttributedString(string: dateAndLocation)
        
        if boldHelveticaFontDescriptor == nil {
            // cache bold descriptor for location
            boldHelveticaFontDescriptor = cell.label1.font?.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits.traitBold)
        }
        
        if let boldHelveticaFontDescriptor = boldHelveticaFontDescriptor  {
            dateAndLocationAttributedString.addAttribute(NSAttributedStringKey.font,
                                                         value: UIFont(descriptor: boldHelveticaFontDescriptor, size: cell.label1.font.pointSize),
                                                         range: range)
        }
        
        cell.label1.attributedText = dateAndLocationAttributedString
        
        // figure out if this report belongs to the current user
        // the last part of the url is the serviceRequestId (https://mobile311.sfgov.org/reports/10774119)
        var currentUserReport = false
        if let threeOneOneUrl = tweets[indexPath.row]["entities"]["urls"][0]["expanded_url"].string {
            let urlComponentsArray = threeOneOneUrl.components(separatedBy: "/")
            if let serviceRequestId = urlComponentsArray.last {
                if self.currentUserReports.contains(serviceRequestId) {
                    currentUserReport = true
                }
            }
        }
        
        if let description = description {
            cell.label2.text = currentUserReport ? "⭐ \(description)" : description
        } else {
            cell.label2.text = ""
        }
        
        if laneBreachSubmission {
            cell.backgroundColor = AppDelegate.brandColor(purpose: .main)
        } else {
            cell.backgroundColor = AppDelegate.brandColor(purpose: .communityFeedItems)
        }
        
        if let dateDelta = dateDelta, dateDelta < 0, let friendlyTimeDelta = friendlyTimeFormat(duration: -dateDelta) {
            cell.dateLabel.text = friendlyTimeDelta
        } else {
            cell.dateLabel.text = ""
        }

        if let mediaUrl = tweets[indexPath.row]["entities"]["media"][0]["media_url_https"].string {
            cell.iconView.sd_setImage(with: URL(string: mediaUrl), placeholderImage: UIImage(named: "no_bike_icon"), completed: nil)
            cell.iconView.contentMode = .scaleAspectFill
        } else {
            cell.iconView.image = UIImage(named: "no_bike_icon")
        }
        
        cell.iconView.layer.cornerRadius = 10

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
