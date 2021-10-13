// Created by eric_horacek on 9/13/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Epoxy
import SwiftUI
import UIKit

// MARK: - SwiftUIToEpoxyViewController

final class SwiftUIToEpoxyViewController: CollectionViewController {

  // MARK: Lifecycle

  init() {
    super.init(layout: UICollectionViewCompositionalLayout.listNoDividers)
    setItems(items, animated: false)
  }

  // MARK: Internal

  override func viewDidLoad() {
    super.viewDidLoad()
    bottomBarInstaller.install()
  }

  // MARK: Private

  private lazy var bottomBarInstaller = BottomBarInstaller(viewController: self, bars: bars)

  private var items: [ItemModeling] {
    (1...100).map { (index: Int) in
      DemoView(id: "Row \(index) ", wordCount: index).itemModel(dataID: index)
    }
  }

  @BarModelBuilder
  private var bars: [BarModeling] {
    Divider().barModel()
    DemoView(id: "Bottom Bar", wordCount: 20).barModel()
  }
}

// MARK: - DemoView

struct DemoView: View {
  var id: String
  var wordCount: Int

  var body: some View {
    VStack(alignment: .leading) {
      Text("\(id) \(BeloIpsum.sentence(count: 1, wordCount: wordCount))")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    // Ensure that the background color underlaps the bottom safe area in the bottom bar.
    .epoxyLayoutMargins()
    .onAppear { print("\(id) appeared") }
    .onDisappear { print("\(id) disappeared") }
  }
}