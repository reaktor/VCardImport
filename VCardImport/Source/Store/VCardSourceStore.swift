import Foundation

class VCardSourceStore {
  private let keychainItem: KeychainItemWrapper
  private var store: InsertionOrderDictionary<String, VCardSource> = InsertionOrderDictionary()

  var isEmpty: Bool {
    return store.isEmpty
  }

  var countAll: Int {
    return store.count
  }

  var countEnabled: Int {
    return countWhere(store.values, { $0.isEnabled })
  }

  var filterEnabled: [VCardSource] {
    return filter(store.values, { $0.isEnabled })
  }

  init() {
    keychainItem = KeychainItemWrapper(
      account: Config.BundleIdentifier,
      service: Config.Persistence.CredentialsKey,
      accessGroup: nil)
  }

  subscript(index: Int) -> VCardSource {
    return store[index]
  }

  func hasSource(source: VCardSource) -> Bool {
    return store[source.id] != nil
  }

  func indexOf(source: VCardSource) -> Int? {
    return store.indexOf(source.id)
  }

  func update(source: VCardSource) {
    store[source.id] = source
  }

  func remove(index: Int) {
    store.removeValueAtIndex(index)
  }

  func move(#fromIndex: Int, toIndex: Int) {
    store.move(fromIndex: fromIndex, toIndex: toIndex)
  }

  func save() {
    saveNonSensitiveDataToUserDefaults()
    saveSensitiveDataToKeychain()
  }

  func load() {
    if let sources = loadNonSensitiveDataFromUserDefaults() {
      resetFrom(loadSensitiveDataFromKeychain(sources))
    }
  }

  // MARK: Helpers

  private func saveNonSensitiveDataToUserDefaults() {
    let sourcesData = JSONSerialization.encode(store.values.map { $0.toDictionary() })
    let defaults = NSUserDefaults.standardUserDefaults()
    defaults.setInteger(1, forKey: Config.Persistence.VersionKey)
    defaults.setObject(sourcesData, forKey: Config.Persistence.VCardSourcesKey)
    defaults.synchronize()
  }

  private func saveSensitiveDataToKeychain() {
    func credentialsToDictionary() -> [String: [String: String]] {
      var result: [String: [String: String]] = [:]
      for (id, source) in store {
        let conn = source.connection
        var cred: [String: String] = [:]
        if !conn.username.isEmpty {
          cred["username"] = conn.username
        }
        if !conn.password.isEmpty {
          cred["password"] = conn.password
        }
        if !cred.isEmpty {
          result[id] = cred
        }
      }
      return result
    }

    let credsData = JSONSerialization.encode(credentialsToDictionary())
    keychainItem.setObject(credsData, forKey: kSecAttrGeneric)
  }

  private func loadNonSensitiveDataFromUserDefaults() -> [VCardSource]? {
    if let sourcesData = NSUserDefaults
      .standardUserDefaults()
      .objectForKey(Config.Persistence.VCardSourcesKey) as? NSData {
      return (JSONSerialization.decode(sourcesData) as [[String: AnyObject]])
        .map { VCardSource.fromDictionary($0) }
    } else {
#if REAKTOR_SOURCES
      return makeDefaultSources()
#else
      return nil
#endif
    }
  }

  private func loadSensitiveDataFromKeychain(sources: [VCardSource]) -> [VCardSource] {
    if let credsData = keychainItem.objectForKey(kSecAttrGeneric) as? NSData {
      let creds = JSONSerialization.decode(credsData) as [String: [String: String]]
      return sources.map { source in
        if let cred = creds[source.id] {
          return source.with(username: cred["username"] ?? "", password: cred["password"] ?? "")
        } else {
          return source  // this source has no credentials
        }
      }
    } else {
      return sources  // no source has credentials
    }
  }

  private func resetFrom(sources: [VCardSource]) {
    var store: InsertionOrderDictionary<String, VCardSource> = InsertionOrderDictionary()
    for source in sources {
      store[source.id] = source
    }
    self.store = store
  }

#if REAKTOR_SOURCES
  private func makeDefaultSources() -> [VCardSource] {
    return [
      VCardSource(
        name: "Reaktor Contacts with images",
        connection: VCardSource.Connection(
          url: "https://opendata.reaktor.fi/vcards"),
        isEnabled: true)
    ]
  }
#endif
}
