// Created by eric_horacek on 9/13/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Epoxy
import SwiftUI
import UIKit

final class SwiftUIInEpoxyViewController: CollectionViewController {

  init() {
    super.init(layout: UICollectionViewCompositionalLayout.listNoDividers)
    setItems(items, animated: false)
  }

  private var items: [ItemModeling] {
    (1...100).map { (index: Int) in
      SwiftUIView(value: index).itemModel(dataID: index)
    }
  }
}

private final class Store: ObservableObject {
  @Published var value: Int?
}

private struct SwiftUIView: View {

  let value: Int

  @StateObject private var store = Store()

  var body: some View {
    HStack {
      Text("\(value)")
      if let storeValue = store.value {
        Spacer()
        Text("\(storeValue)").foregroundColor(storeValue == value ? .black : .red)
      }
    }
    .padding(.horizontal)
    .onAppear {
      store.value = value
    }
  }

}
