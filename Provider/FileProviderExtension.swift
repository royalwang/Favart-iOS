
import FileProvider

class FileProviderExtension: NSFileProviderExtension {
    
    enum FileError: Error {
        case identifierNotFound
        case unexpectedProviderItem
    }
    
    var fileManager = FileManager()
    
    override init() {
        super.init()
        
    }
    
    override func item(for identifier: NSFileProviderItemIdentifier) throws -> NSFileProviderItem {        
        if identifier == .rootContainer {
            return FileProviderItem.rootItem
        }
        
        guard let item = FileProviderItem(identifier: identifier) else {
            throw NSFileProviderError(.noSuchItem)
        }
        
        return item
    }
    
    override func urlForItem(withPersistentIdentifier identifier: NSFileProviderItemIdentifier) -> URL? {
        do {
            guard let item = try item(for: identifier) as? FileProviderItem else {
                return nil
            }
            
            let manager = NSFileProviderManager.default
            let rootItemURL = manager.documentStorageURL.appendingPathComponent(identifier.rawValue, isDirectory: true)
            
            return rootItemURL.appendingPathComponent(item.filename, isDirectory: item.isDirectory)
        }
        catch {
            return nil
        }
    }
    
    override func persistentIdentifierForItem(at url: URL) -> NSFileProviderItemIdentifier? {
        // resolve the given URL to a persistent identifier using a database
        let pathComponents = url.pathComponents
        
        // exploit the fact that the path structure has been defined as
        // <base storage directory>/<item identifier>/<item file name> above
        assert(pathComponents.count > 2)
        
        return NSFileProviderItemIdentifier(pathComponents[pathComponents.count - 2])
    }
    
    override func providePlaceholder(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        do {
            let fileProviderItem = try item(for: identifier)
            let placeholderURL = NSFileProviderManager.placeholderURL(for: url)
            
            // this was tricky, https://forums.developer.apple.com/thread/89113
            let placeholderDirectory = placeholderURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: placeholderDirectory.path) {
                try fileManager.createDirectory(at: placeholderDirectory, withIntermediateDirectories: true, attributes: nil)
            }

            try NSFileProviderManager.writePlaceholder(at: placeholderURL, withMetadata: fileProviderItem)
            completionHandler(nil)
        }
        catch let error {
            completionHandler(error)
        }
    }

    override func startProvidingItem(at url: URL, completionHandler: @escaping ((_ error: Error?) -> Void)) {
        guard let identifier = persistentIdentifierForItem(at: url) else {
            completionHandler(NSFileProviderError(.noSuchItem))
            return
        }
        
        let path = identifier.rawValue.base64Decoded.replacingOccurrences(of: "+", with: "/")
        
        if !fileManager.fileExists(atPath: url.path) {
            NetworkClient.shared.downloadFile(at: path, to: url) { error in
                completionHandler(error)
            }
        }
        else {
            completionHandler(nil)
        }
    }
    
    override func stopProvidingItem(at url: URL) {
        let fileHasLocalChanges = false
        
        if !fileHasLocalChanges {
            // remove the existing file to free up space
            do {
                _ = try FileManager.default.removeItem(at: url)
            } catch {
                // Handle error
            }
            
            // write out a placeholder to facilitate future property lookups
            self.providePlaceholder(at: url, completionHandler: { error in
                // TODO: handle any error, do any necessary cleanup
            })
        }
    }
    
    // MARK: - Actions
    
    /* TODO: implement the actions for items here
     each of the actions follows the same pattern:
     - make a note of the change in the local model
     - schedule a server request as a background task to inform the server of the change
     - call the completion block with the modified item in its post-modification state
     */
    
    // MARK: - Enumeration
    
    override func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier) throws -> NSFileProviderEnumerator {
        let maybeEnumerator: NSFileProviderEnumerator? = nil
        
        if containerItemIdentifier == .rootContainer {
            return FileProviderEnumerator(identifier: containerItemIdentifier)
        }
        else if containerItemIdentifier == .workingSet {
            // TODO: instantiate an enumerator for the working set
        }
        else {
            do {
                if let providerItem = try item(for: containerItemIdentifier) as? FileProviderItem {
                    if providerItem.isDirectory {
                        return FileProviderEnumerator(identifier: containerItemIdentifier)
                    }
                    else {
                        throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:])
                    }
                }
                else {
                    throw FileError.unexpectedProviderItem
                }
            }
            catch {
                throw FileError.unexpectedProviderItem
            }
        }
        
        guard let enumerator = maybeEnumerator else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError, userInfo:[:])
        }
        return enumerator
    }
    
//    override func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
//        print("INFO: Requesting thumbnails for: \(itemIdentifiers.map({ $0.rawValue })).")
//
//        return Progress(totalUnitCount: 0)
//    }
    
}
