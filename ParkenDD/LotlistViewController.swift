//
//  ViewController.swift
//  ParkenDD
//
//  Created by Kilian Koeltzsch on 18/01/15.
//  Copyright (c) 2015 Kilian Koeltzsch. All rights reserved.
//

import UIKit
import CoreLocation
import MCSwipeTableViewCell
import TSMessages

class LotlistViewController: UITableViewController, CLLocationManagerDelegate, UISearchBarDelegate, UISearchControllerDelegate, UISearchResultsUpdating, MCSwipeTableViewCellDelegate {

	let locationManager = CLLocationManager()

	var searchController: UISearchController!

	var parkinglots: [Parkinglot] = []
	var defaultSortedParkinglots: [Parkinglot] = []
	var filteredParkinglots: [Parkinglot] = []

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

		updateData()
	}

	override func viewWillAppear(animated: Bool) {
		sortLots()
		tableView.reloadData()

		// Start getting location updates if the user wants lots sorted by distance
		if NSUserDefaults.standardUserDefaults().stringForKey("SortingType")! == "distance" {
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

			let selectedParkinglot: Parkinglot!
			if searchController.active {
				selectedParkinglot = filteredParkinglots[indexPath!.row]
			} else {
				selectedParkinglot = parkinglots[indexPath!.row]
			}

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

		ServerController.sendNotificationRequest { (alertTitle, alertText) -> () in
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				let alertController = UIAlertController(title: alertTitle, message: alertText, preferredStyle: UIAlertControllerStyle.Alert)
				alertController.addAction(UIAlertAction(title: "Ok", style: UIAlertActionStyle.Default, handler: nil))
				self.presentViewController(alertController, animated: true, completion: nil)
			})
		}

		ServerController.sendParkinglotDataRequest() {
			(plotList, updateError) in

			// Reset the UI elements showing a loading refresh
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				self.stopRefreshUI()
			})

			if let error = updateError {
				if error == .Request {

					// Give the user a notification that new data can't be fetched
					dispatch_async(dispatch_get_main_queue(), { () -> Void in
						let window = UIApplication.sharedApplication().windows.last as! UIWindow
						TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("REQUEST_ERROR_TITLE", comment: "Connection Error"), subtitle: NSLocalizedString("REQUEST_ERROR", comment: "Couldn't fetch data. You appear to be disconnected from the internet."), type: TSMessageNotificationType.Error)
					})

				} else if error == .Server {

					// Give the user a notification that data from the server can't be read
					dispatch_async(dispatch_get_main_queue(), { () -> Void in
						let window = UIApplication.sharedApplication().windows.last as! UIWindow
						TSMessage.showNotificationInViewController(window.rootViewController, title: NSLocalizedString("SERVER_ERROR_TITLE", comment: "Server Error"), subtitle: NSLocalizedString("SERVER_ERROR", comment: "Couldn't read data from server. Please try again in a few moments."), type: TSMessageNotificationType.Error)
					})

				}

			} else if let plotList = plotList {
				self.parkinglots = plotList
				self.defaultSortedParkinglots = plotList
				self.sortLots()

				// Reload the tableView on the main thread, otherwise it will only update once the user interacts with it
				dispatch_async(dispatch_get_main_queue(), { () -> Void in
					// Reload the tableView, but with a slight animation
					self.tableView.reloadSections(NSIndexSet(index: 0), withRowAnimation: UITableViewRowAnimation.Fade)
				})
			}
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
		default:
			parkinglots = defaultSortedParkinglots
		}
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
		UIApplication.sharedApplication().networkActivityIndicatorVisible = false
		showReloadButton()
		refreshControl!.endRefreshing()
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
		if searchController.active {
			return filteredParkinglots.count
		} else {
			return parkinglots.count
		}
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		var cell: ParkinglotTableViewCell = tableView.dequeueReusableCellWithIdentifier("parkinglotCell") as! ParkinglotTableViewCell

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

		if let thisLotAddress = parkinglotData[thisLot.name] {
			// check if location sorting is enabled, then we're displaying distance instead of address
			if NSUserDefaults.standardUserDefaults().stringForKey("SortingType")! == "distance" {
				if let distance = thisLot.distance {
					cell.parkinglotAddressLabel.text = "\((round(distance/100))/10)km"
				} else {
					cell.parkinglotAddressLabel.text = NSLocalizedString("WAITING_FOR_LOCATION", comment: "waiting for location")
				}
			} else {
				cell.parkinglotAddressLabel.text = thisLotAddress
			}
		} else {
			cell.parkinglotAddressLabel.text = NSLocalizedString("UNKNOWN_ADDRESS", comment: "unknown address")
		}

		var load: Int = Int(round(100 - (Double(thisLot.free) / Double(thisLot.count) * 100)))

		// Some cleanup
		if load < 0 {
			// Apparently there can be 52 empty spots on a 50 spot parking lot...
			load = 0
		} else if thisLot.state == lotstate.full {
			load = 100
		}

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

		var percentage = 1 - (Double(thisLot.free) / Double(thisLot.count))
		if percentage < 0.1 {
			percentage = 0.1
		} else if percentage > 0.99 {
			percentage = 0.99
		}
		cell.backgroundColor = Colors.colorBasedOnPercentage(percentage, emptyLots: thisLot.free)

		if thisLot.state == lotstate.nodata {
			cell.parkinglotLoadLabel.text = "?"
		}

        // Configure MCSwipeTableViewCell stuff

		// Create view with a star image to be displayed in swiped 'backview'
		let favView = self.viewWithImageName("favStar")
		let unfavView = self.viewWithImageName("unfavStar")
		let favColor = Colors.favYellow
		let unfavColor = Colors.unfavYellow

        cell.separatorInset = UIEdgeInsetsZero
        cell.selectionStyle = UITableViewCellSelectionStyle.Gray

		var favoriteLots = NSUserDefaults.standardUserDefaults().arrayForKey("favoriteLots") as! [String]
		if contains(favoriteLots, thisLot.name) {
			// Lot is already faved

			cell.favTriangle.image = UIImage(named: "favTriangle")

			cell.setSwipeGestureWithView(unfavView, color: unfavColor, mode: MCSwipeTableViewCellMode.Switch, state: MCSwipeTableViewCellState.State1) { (cell, state, mode) -> Void in
				let index = find(favoriteLots, thisLot.name)
				favoriteLots.removeAtIndex(index!)
				NSLog("removed \(thisLot.name) from favorites")
				NSUserDefaults.standardUserDefaults().setObject(favoriteLots, forKey: "favoriteLots")
				NSUserDefaults.standardUserDefaults().synchronize()

				// remove favtriangle from cell
				(cell as! ParkinglotTableViewCell).favTriangle.image = nil

				self.tableView.reloadData()
			}
		} else {
			// Lot is not faved

			cell.favTriangle.image = nil

			cell.setSwipeGestureWithView(favView, color: favColor, mode: MCSwipeTableViewCellMode.Switch, state: MCSwipeTableViewCellState.State1) { (cell, state, mode) -> Void in
				favoriteLots.append(thisLot.name)
				NSLog("added \(thisLot.name) to favorites")
				NSUserDefaults.standardUserDefaults().setObject(favoriteLots, forKey: "favoriteLots")
				NSUserDefaults.standardUserDefaults().synchronize()

				// add favtriangle to cell
				(cell as! ParkinglotTableViewCell).favTriangle.image = UIImage(named: "favTriangle")

				self.tableView.reloadData()
			}
		}

		return cell
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - UITableViewDelegate
	// /////////////////////////////////////////////////////////////////////////

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
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
			if let lat = parkinglots[index].lat, lon = parkinglots[index].lon {
				let lotLocation = CLLocation(latitude: lat, longitude: lon)
				let distance = currentLocation.distanceFromLocation(lotLocation)
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

	func swipeTableViewCellDidEndSwiping(cell: MCSwipeTableViewCell!) {
		var favorites = NSUserDefaults.standardUserDefaults().arrayForKey("favoriteLots")!
		favorites.append((cell as! ParkinglotTableViewCell).parkinglotNameLabel.text!)
		println(favorites)
		NSUserDefaults.standardUserDefaults().setObject(favorites, forKey: "favoriteLots")
	}

	// /////////////////////////////////////////////////////////////////////////
	// MARK: - Helpers
	// /////////////////////////////////////////////////////////////////////////

	func viewWithImageName(imageName: String) -> UIImageView {
		let image = UIImage(named: imageName)
		let imageView = UIImageView(image: image)
		imageView.contentMode = UIViewContentMode.Center
		return imageView
	}

}