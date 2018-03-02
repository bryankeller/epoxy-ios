//  Created by eric_horacek on 11/7/17.
//  Copyright © 2017 Airbnb. All rights reserved.

import Foundation

public protocol TableViewEpoxyModelDataSourcePrefetching: class {
  func tableView(
    _ tableView: TableView,
    willPrefetch epoxyItems: [EpoxyableModel])

  func tableView(
    _ tableView: TableView,
    cancelPrefetchingOf epoxyItems: [EpoxyableModel])
}