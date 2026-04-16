import Foundation

class FolderMonitor {
    private let folderURL: URL
    private var folderWatcher: DispatchSourceFileSystemObject?
    private let folderDescriptor: Int32
    
    var onFolderChange: (() -> Void)?
    
    private var pendingWorkItem: DispatchWorkItem?
    
    init(url: URL) {
        self.folderURL = url
        self.folderDescriptor = open(url.path, O_EVTONLY)
    }
    
    func startMonitoring() {
        guard folderDescriptor != -1 else { return }
        
        folderWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: folderDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )
        
        folderWatcher?.setEventHandler { [weak self] in
            self?.debounceChange()
        }
        
        folderWatcher?.setCancelHandler { [weak self] in
            close(self?.folderDescriptor ?? -1)
        }
        
        folderWatcher?.resume()
    }
    
    func stopMonitoring() {
        folderWatcher?.cancel()
    }
    
    private func debounceChange() {
        pendingWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.onFolderChange?()
        }
        
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}
