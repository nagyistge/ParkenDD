//
//  ViewController.swift
//  ParkenDD
//
//  Created by Kilian Koeltzsch on 18/01/15.
//  Copyright (c) 2015 Kilian Koeltzsch. All rights reserved.
//

import UIKit
import CoreLocation
//import MCSwipeTableViewCell
import TSMessages
import SwiftyTimer
import MWFeedParser

// Removing MCSwipeTableViewCellDelegate here temporarily
class LotlistViewController: UITableViewController, CLLocationManagerDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating, MWFeedParserDelegate {

	let locationManager = CLLocationManager()

	var searchController: UISearchController!

	var parkinglots: [Parkinglot] = []
	var defaultSortedParkinglots: [Parkinglot] = []
	var filteredParkinglots: [Parkinglot] = []

	var timeUpdated: NSDate?
	var timeDownloaded: NSDate?
	var dataSource: String?

	var feedItems = [MWFeedItem]()

	override func viewDidLoad() {
		super.viewDidLoad()

		// Set up the UISearchController
		searchController = UISearchController(searchResultsController: nil)
		searchController.searchResultsUpdater = self
		searchController.searchBar.delegate = self
		searchController.dimsBackgroundDuringPresentation = false
//		searchController.hidesNavigationBarDuringPresentation = false
//		searchController.searchBar.searchBarStyle = UISearchBarStyle.Minimal

		searchController.searchBar.frame = CGRectMake(searchController.searchBar.frame.origin.x, searchController.searchBar.frame.origin.y, searchController.searchBar.frame.size.width, 44.0)

//		tableView.tableHeaderView = searchController.searchBar
		self.definesPresentationContext = true

		// set CLLocationManager delegate
		locationManager.delegate = self

		// display the standard reload button
		showReloadButton()

		// pretty navbar with black buttons
		let navBar = self.navigationController?.navigationBar
		navBar!.translucent = false
		navBar!.tintColor = UIColor.blackColor()

		// pretty title
		let font = UIFont(name: "AvenirNext-Medium", size: 18.0)
		var attrsDict = [NSObject: AnyObject]()
		attrsDict[NSFontAttributeName] = font
		navBar!.titleTextAttributes = attrsDict

		// Set a table footer view so that separators aren't shown when no data is yet present
		self.tableView.tableFooterView = UIView(frame: CGRectZero)

		// Create Feed Parser for news notification
		let rssURL = NSURL(string: Const.rssURL)
		let feedParser = MWFeedParser(feedURL: rssURL)
		feedParser.delegate = self
		feedParser.connectionType = ConnectionTypeAsynchronously
		feedParser.parse()

		updateData()
		NSTimer.every(5.minutes,updateData)
	}

	override func viewWillAppear(animated: Bool) {
		sortLots()
		tableView.reloadData()

		// Start getting location updates if the user wants lots sorted by distance
		let sortingType = NSUserDefaults.standardUserDefaults().stringForKey("SortingType")!
		if sortingType == "distance" || sortingType == "euklid" {
			if CLLocationManager.authorizationStatus() == CLAuthorizationStatus.AuthorizedWhenInUse {
				locationManager.startUpdatingLocation()
			} else {
				let alertController = UIAlertController(title: NSLocalizedString("LOCATION_DATA_ERROR_TITLE", comment: "Location Data Error"), message: NSLocalizedString("LOCATION_DATA_ERROR", comment: "Please allow location data..."), preferredStyle: UIAlertControllerStyle.Alert)
				alertController.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: "Cancel"), style: UIAlertActionStyle.Cancel, handler: nil))
				alertController.addAction(UIAlertAction(title: NSLocalizedString("SETTINGS", comment: "Settings"), style: UIAlertActionStyle.Default, handler: {
					(action) in
					UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
				}))
				presentViewController(alertController, animated: true, completion: nil)
			}
		} else {
			locationManager.stopUpdatingLocation()
		}
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "showParkinglotMap" {
			let indexPath = tableView.indexPathForSelectedRow()

			let selectedParkinglot = searchController.active ? filteredParkinglots[indexPath!.row] : parkinglots[indexPath!.row]

			let mapVC: MapViewController = segue.destinationViewController as! MapViewController
			mapVC.detailParkinglot = selectedParkinglot
			mapVC.allParkinglots = parkinglots

//			searchController.active = false
		}
	}

	/**
	Call ServerController to update all local data, catch possible errors and handle the UI based on the refresh (e.g. UIRefreshControl and the UIBarButtonItem).
	*/
	func updateData() {
		showActivityIndicator()

		ServerController.sendMetadataRequest { (supportedCities, updateError) -> () in
			switch updateError {
			case .Some(let err):
				self.showUpdateError(err)
				// Reset the UI elements showing a loading refresh
				self.stopRefreshUI()
			case .None:
				(UIApplication.sharedApplication().delegate as! AppDelegate).supportedCities = supportedCities
				let selectedCity = NSUserDefaults.standardUserDefaults().stringForKey("selectedCity")!
				let selectedCityID = supportedCities[selectedCity]!
				ServerController.sendParkinglotDataRequest(selectedCityID) {
					(lotList, timeUpdated, timeDownloaded, dataSource, updateError) in

					// Reset the UI elements showing a loading refresh
					self.stopRefreshUI()

					switch updateError {
					case .Some(let err):
						self.showUpdateError(err)
					case .None:

						self.parkinglots = lotList
						self.defaultSortedParkinglots = lotList

						if let timeUpdated = timeUpdated, timeDownloaded = timeDownloaded, dataSource = dataSource {
							self.timeUpdated = timeUpdated
							self.timeDownloaded = timeDownloaded
							self.dataSource = dataSource
						}

						// Check if date signifies that the data is possibly outdated and warn the user if that is the case
						if let timeUpdated = timeUpdated {
							let currentDate = NSDate()
							let calendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
							let dateDifference = calendar.components(NSCalendarUnit.CalendarUnitMinute, fromDate: timeUpdated, toDate: currentDate, options: NSCalendarOptions.WrapComponents)

							if dateDifference.minute >= 30 {
								dispatch_async(dispatch_get_main_queue(), { () -> Void in
									let window = UIApplication.sharedApplication().windows.last as! UIWindow
									TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("OUTDATED_DATA_WARNING_TITLE", comment: "Warning: Outdated data"), subtitle: NSLocalizedString("OUTDATED_DATA_WARNING", comment: "The server indicates that the displayed data might be outdated. It was last updated more than 30 minutes ago"), type: .Warning)
								})
							}
						}

						if let currentUserLocation = self.locationManager.location {
							for index in 0..<self.parkinglots.count {
								if let lat = self.parkinglots[index].lat, lon = self.parkinglots[index].lng, currentUserLocation = self.locationManager.location {
									let lotLocation = CLLocation(latitude: lat, longitude: lon)
									let distance = currentUserLocation.distanceFromLocation(lotLocation)
									self.parkinglots[index].distance = round(distance)
								}
							}
						}

						self.sortLots()

						// Reload the tableView on the main thread, otherwise it will only update once the user interacts with it
						dispatch_async(dispatch_get_main_queue(), { () -> Void in
							// Reload the tableView, but with a slight animation
							self.tableView.reloadSections(NSIndexSet(index: 0), withRowAnimation: UITableViewRowAnimation.Fade)
						})
					}
				}
			}
		}
	}

	/**
	Called by the request to the API in case of failure and handed the error to display to the user.
	*/
	func showUpdateError(err: ServerController.UpdateError) {
		switch err {
		case .Server, .IncompatibleAPI:
			// Give the user a notification that data from the server can't be read
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				let window = UIApplication.sharedApplication().windows.last as! UIWindow
				TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("SERVER_ERROR_TITLE", comment: "Server Error"), subtitle: NSLocalizedString("SERVER_ERROR", comment: "Couldn't read data from server. Please try again in a few moments."), type: TSMessageNotificationType.Error)
			})
		case .Request:
			// Give the user a notification that new data can't be fetched
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				let window = UIApplication.sharedApplication().windows.last as! UIWindow
				TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("REQUEST_ERROR_TITLE", comment: "Connection Error"), subtitle: NSLocalizedString("REQUEST_ERROR", comment: "Couldn't fetch data. You appear to be disconnected from the internet."), type: TSMessageNotificationType.Error)
			})
		case .Unknown:
			// Give the user a notification that an unknown error occurred
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				let window = UIApplication.sharedApplication().windows.last as! UIWindow
				TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("UNKNOWN_ERROR_TITLE", comment: "Unknown Error"), subtitle: NSLocalizedString("UNKNOWN_ERROR", comment: "An unknown error occurred. Please try again in a few moments."), type: TSMessageNotificationType.Error)
			})
		}
	}

	/**
	Sort the parkingslots array based on what is currently saved for SortingType in NSUserDefaults.
	*/
	func sortLots() {
		let sortingType = NSUserDefaults.standardUserDefaults().stringForKey("SortingType")
		switch sortingType! {
		case "distance":
			parkinglots.sort({
				(lot1: Parkinglot, lot2: Parkinglot) -> Bool in
				if let firstDistance = lot1.distance, secondDistance = lot2.distance {
					return firstDistance < secondDistance
				}
				return lot1.name < lot2.name
			})
		case "alphabetical":
			parkinglots.sort({
				$0.name < $1.name
			})
		case "free":
			parkinglots.sort({
				$0.free > $1.free
			})
		case "euklid":
			self.parkinglots.sort(sortEuclidian)
		default:
			parkinglots = defaultSortedParkinglots
		}
	}

	func sortEuclidian(lot1: Parkinglot, lot2: Parkinglot) -> Bool {
		if let distance1 = lot1.distance, distance2 = lot2.distance {
			// TODO: Also check if state is either open or unknown, others should not be sorted
			if lot1.total != 0 && lot2.total != 0 {
				var occ1 = Double(lot1.total - lot1.free) / Double(lot1.total)
				var occ2 = Double(lot2.total - lot2.free) / Double(lot2.total)
				let sqrt1 = sqrt(pow(distance1, 2.0) + pow(Double(occ1*1000), 2.0))
				let sqrt2 = sqrt(pow(distance2, 2.0) + pow(Double(occ2*1000), 2.0))

				return sqrt1 < sqrt2
			}
		}
		return lot1.free > lot2.free
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - IBActions
	// /////////////////////////////////////////////////////////////////////////

	@IBAction func settingsButtonTapped(sender: UIBarButtonItem) {
		performSegueWithIdentifier("showSettingsView", sender: self)
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - Reload Button Stuff
	// /////////////////////////////////////////////////////////////////////////

	/**
	Remove all UI that has to do with refreshing data.
	*/
	func stopRefreshUI() {
		dispatch_async(dispatch_get_main_queue(), { () -> Void in
			UIApplication.sharedApplication().networkActivityIndicatorVisible = false
			self.showReloadButton()
			self.refreshControl!.endRefreshing()
		})
	}

	/**
	Replace the right UIBarButtonItem with the reload button.
	*/
	func showReloadButton() {
		let refreshButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Refresh, target: self, action: "updateData")
		self.navigationItem.rightBarButtonItem = refreshButton
	}

	/**
	Replace the right UIBarButtonItem with a UIActivityIndicatorView.
	*/
	func showActivityIndicator() {
		UIApplication.sharedApplication().networkActivityIndicatorVisible = true
		let activityIndicator = UIActivityIndicatorView(frame: CGRectMake(0, 0, 20, 20))
		activityIndicator.color = UIColor.blackColor()
		activityIndicator.startAnimating()
		let activityItem = UIBarButtonItem(customView: activityIndicator)
		self.navigationItem.rightBarButtonItem = activityItem
	}

	@IBAction func refreshControlValueChanged(sender: UIRefreshControl) {
		updateData()
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - UITableViewDataSource
	// /////////////////////////////////////////////////////////////////////////

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		// adding 1 for timeUpdated
		// not checking its availability here because there's no reason it shouldn't be available if the rest has worked up to this point
		return searchController.active ? filteredParkinglots.count + 1 : parkinglots.count + 1
	}

	override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		if indexPath.row < parkinglots.count {
			return 60
		}
		return 30
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		var cell: ParkinglotTableViewCell = tableView.dequeueReusableCellWithIdentifier("parkinglotCell") as! ParkinglotTableViewCell

		if parkinglots.count == 0 {
			self.tableView.separatorStyle = UITableViewCellSeparatorStyle.None
		} else {
			self.tableView.separatorStyle = UITableViewCellSeparatorStyle.SingleLine
		}

		if indexPath.row >= parkinglots.count {
			var timecell: TimestampCell = tableView.dequeueReusableCellWithIdentifier("timestampCell") as! TimestampCell
			let dateFormatter = NSDateFormatter()
			dateFormatter.dateStyle = .MediumStyle
			dateFormatter.timeStyle = .ShortStyle

			if let timeUpdated = timeUpdated {
				let lastUpdatedString = NSLocalizedString("LAST_UPDATED", comment: "Updated:") + " " + dateFormatter.stringFromDate(timeUpdated) + " " + NSLocalizedString("TIME_SUFFIX", comment: "German: Uhr")
				timecell.timestampLabel.text = lastUpdatedString
			}
			return timecell
		}

		let thisLot: Parkinglot!
		let customParkinglotlist: [Parkinglot]!
		if searchController.active {
			thisLot = filteredParkinglots[indexPath.row]
			customParkinglotlist = filteredParkinglots
		} else {
			thisLot = parkinglots[indexPath.row]
			customParkinglotlist = parkinglots
		}

		cell.parkinglot = thisLot
		cell.parkinglotNameLabel.text = thisLot.name
		cell.parkinglotLoadLabel.text = "\(thisLot.free)"

		// check if location sorting is enabled, then we're displaying distance instead of address
		let sortingType = NSUserDefaults.standardUserDefaults().stringForKey("SortingType")!
		if sortingType == "distance" || sortingType == "euklid" {
			if let currentUserLocation = locationManager.location, lat = thisLot.lat, lng = thisLot.lng {
				let lotLocation = CLLocation(latitude: lat, longitude: lng)
				thisLot.distance = currentUserLocation.distanceFromLocation(lotLocation)
				cell.parkinglotAddressLabel.text = "\((round(thisLot.distance!/100))/10)km"
			} else {
				if let distance = thisLot.distance {
					cell.parkinglotAddressLabel.text = "\((round(distance/100))/10)km"
				} else {
					cell.parkinglotAddressLabel.text = NSLocalizedString("WAITING_FOR_LOCATION", comment: "waiting for location")
				}
			}
		} else if thisLot.address == "" {
			cell.parkinglotAddressLabel.text = NSLocalizedString("UNKNOWN_ADDRESS", comment: "unknown address")
		} else {
			cell.parkinglotAddressLabel.text = thisLot.address
		}

		// I kinda feel bad for writing this...
		var load = thisLot.total > 0 ? Int(round(100 - (Double(thisLot.free) / Double(thisLot.total) * 100))) : 100
		load = load < 0 ? 0 : load
		load = thisLot.state == lotstate.closed ? 100 : load

		// Maybe a future version of the scraper will be able to read the tendency as well
		if thisLot.state == lotstate.nodata && thisLot.free == -1 {
			cell.parkinglotTendencyLabel.text = NSLocalizedString("UNKNOWN_LOAD", comment: "unknown")
		} else if thisLot.state == lotstate.closed {
			cell.parkinglotTendencyLabel.text = NSLocalizedString("CLOSED", comment: "closed")
		} else {
			let localizedOccupied = NSLocalizedString("OCCUPIED", comment: "occupied")
			cell.parkinglotTendencyLabel.text = "\(load)% \(localizedOccupied)"
		}

		// Set all labels to be white, 'cause it looks awesome
		cell.parkinglotNameLabel.textColor = UIColor.whiteColor()
		cell.parkinglotAddressLabel.textColor = UIColor.whiteColor()
		cell.parkinglotLoadLabel.textColor = UIColor.whiteColor()
		cell.parkinglotTendencyLabel.textColor = UIColor.whiteColor()

		var percentage = thisLot.total > 0 ? 1 - (Double(thisLot.free) / Double(thisLot.total)) : 0.99
		if percentage < 0.1 {
			percentage = 0.1
		} else if percentage > 0.99 {
			percentage = 0.99
		}
		cell.backgroundColor = Colors.colorBasedOnPercentage(percentage, emptyLots: thisLot.free)

//        // Configure MCSwipeTableViewCell stuff
//
//		// Create view with a star image to be displayed in swiped 'backview'
//		let favView = self.viewWithImageName("favStar")
//		let unfavView = self.viewWithImageName("unfavStar")
//		let favColor = Colors.favYellow
//		let unfavColor = Colors.unfavYellow
//
//        cell.separatorInset = UIEdgeInsetsZero
//        cell.selectionStyle = UITableViewCellSelectionStyle.Gray
//
//		var favoriteLots = NSUserDefaults.standardUserDefaults().arrayForKey("favoriteLots") as! [String]
//		if contains(favoriteLots, thisLot.name) {
//			// Lot is already faved
//
//			cell.favTriangle.image = UIImage(named: "favTriangle")
//
//			cell.setSwipeGestureWithView(unfavView, color: unfavColor, mode: MCSwipeTableViewCellMode.Switch, state: MCSwipeTableViewCellState.State1) { (cell, state, mode) -> Void in
//				let index = find(favoriteLots, thisLot.name)
//				favoriteLots.removeAtIndex(index!)
//				NSLog("removed \(thisLot.name) from favorites")
//				NSUserDefaults.standardUserDefaults().setObject(favoriteLots, forKey: "favoriteLots")
//				NSUserDefaults.standardUserDefaults().synchronize()
//
//				// remove favtriangle from cell
//				(cell as! ParkinglotTableViewCell).favTriangle.image = nil
//
//				self.tableView.reloadData()
//			}
//		} else {
//			// Lot is not faved
//
//			cell.favTriangle.image = nil
//
//			cell.setSwipeGestureWithView(favView, color: favColor, mode: MCSwipeTableViewCellMode.Switch, state: MCSwipeTableViewCellState.State1) { (cell, state, mode) -> Void in
//				favoriteLots.append(thisLot.name)
//				NSLog("added \(thisLot.name) to favorites")
//				NSUserDefaults.standardUserDefaults().setObject(favoriteLots, forKey: "favoriteLots")
//				NSUserDefaults.standardUserDefaults().synchronize()
//
//				// add favtriangle to cell
//				(cell as! ParkinglotTableViewCell).favTriangle.image = UIImage(named: "favTriangle")
//
//				self.tableView.reloadData()
//			}
//		}

		return cell
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - UITableViewDelegate
	// /////////////////////////////////////////////////////////////////////////

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

		if indexPath.row >= parkinglots.count {
			if let dataSource = dataSource {
				if let let dataSourceURL = NSURL(string: dataSource) {
					UIApplication.sharedApplication().openURL(dataSourceURL)
					tableView.deselectRowAtIndexPath(indexPath, animated: true)
				}
			}
			NSLog("Looks like the datasource \(dataSource) isn't a valid URL.")
			return
		}

		let cellTitle = (tableView.cellForRowAtIndexPath(indexPath) as! ParkinglotTableViewCell).parkinglotNameLabel.text!
		for lot in parkinglots {
			if lot.name == cellTitle && lot.lat! == 0.0 {
				dispatch_async(dispatch_get_main_queue(), { () -> Void in
					let window = UIApplication.sharedApplication().windows.last as! UIWindow
					TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("NO_COORDS_WARNING_TITLE", comment: "No coordinates found"), subtitle: NSLocalizedString("NO_COORDS_WARNING", comment: "Don't have no coords, ain't showing no nothing!"), type: TSMessageNotificationType.Warning)
				})
				tableView.deselectRowAtIndexPath(indexPath, animated: true)
				return
			}
		}
		performSegueWithIdentifier("showParkinglotMap", sender: self)
		tableView.deselectRowAtIndexPath(indexPath, animated: true)
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - CLLocationManagerDelegate
	// /////////////////////////////////////////////////////////////////////////
	func locationManager(manager: CLLocationManager!, didUpdateLocations locations: [AnyObject]!) {
		let currentLocation: CLLocation = locations.last as! CLLocation

		// Cycle through all lots to assign their respective distances from the user
		for index in 0..<parkinglots.count {
			if let lat = parkinglots[index].lat, lon = parkinglots[index].lng, currentUserLocation = locationManager.location {
				let lotLocation = CLLocation(latitude: lat, longitude: lon)
//				let distance = currentLocation.distanceFromLocation(lotLocation)
				let distance = currentUserLocation.distanceFromLocation(lotLocation)
				parkinglots[index].distance = round(distance)
			}
		}

		// sort data and reload tableview
		sortLots()
		tableView.reloadData()

		// Going to have to stop refreshui as well if this is right after a refresh, in that case we haven't done this yet. Otherwise it doesn't really hurt either.
		stopRefreshUI()
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - UISearchResultsUpdating
	// /////////////////////////////////////////////////////////////////////////

	func updateSearchResultsForSearchController(searchController: UISearchController) {
		let searchString = searchController.searchBar.text

		if searchString == "" {
			filteredParkinglots = parkinglots
		} else {
			filterContentForSearch(searchString)
		}

		tableView.reloadData()
	}

	/**
	Filter the content of the parkinglot list according to what the user types in the searchbar

	:param: searchText String to search with
	*/
	func filterContentForSearch(searchText: String) {
		filteredParkinglots = parkinglots.filter({ (parkinglot: Parkinglot) -> Bool in
			let nameMatch = parkinglot.name.lowercaseString.rangeOfString(searchText.lowercaseString)
			return nameMatch != nil
		})
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - MCSwipeTableViewCellDelegate
	// /////////////////////////////////////////////////////////////////////////

//	func swipeTableViewCellDidEndSwiping(cell: MCSwipeTableViewCell!) {
//		var favorites = NSUserDefaults.standardUserDefaults().arrayForKey("favoriteLots")!
//		favorites.append((cell as! ParkinglotTableViewCell).parkinglotNameLabel.text!)
//		println(favorites)
//		NSUserDefaults.standardUserDefaults().setObject(favorites, forKey: "favoriteLots")
//	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - Helpers
	// /////////////////////////////////////////////////////////////////////////

	func viewWithImageName(imageName: String) -> UIImageView {
		let image = UIImage(named: imageName)
		let imageView = UIImageView(image: image)
		imageView.contentMode = UIViewContentMode.Center
		return imageView
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - MWFeedParser
	// /////////////////////////////////////////////////////////////////////////

	func feedParser(parser: MWFeedParser!, didParseFeedItem item: MWFeedItem!) {
		self.feedItems.append(item)
	}

	func feedParserDidFinish(parser: MWFeedParser!) {
		let lastItem = self.feedItems.first
		let request = NSURLRequest(URL: NSURL(string: lastItem!.link)!)

		// TODO: Display a modal VC with the post page of the latest post
		// Some kind of check for which notifications have been displayed needs to be built as well
	}

}
