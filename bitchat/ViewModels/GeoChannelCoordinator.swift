//
// GeoChannelCoordinator.swift
// bitchat
//
// Centralizes Combine wiring for location channel selection and sampling.
//

import Combine
import Foundation
import Tor

/// The narrow surface `GeoChannelCoordinator` needs from its owner.
///
/// Follows the `ChatDeliveryContext` exemplar: the coordinator depends on the
/// minimal context it actually uses instead of capturing `ChatViewModel` in
/// per-callback closures. This keeps the coordinator independently testable
/// (see `GeoChannelCoordinatorContextTests`) and makes its true dependencies
/// explicit. Held `weak` — the owner retains the coordinator, and every
/// callback was previously a `[weak viewModel]` capture.
@MainActor
protocol GeoChannelContext: AnyObject {
    func switchLocationChannel(to channel: ChannelID)
    func beginGeohashSampling(for geohashes: [String])
    func endGeohashSampling()
}

// `switchLocationChannel(to:)`, `beginGeohashSampling(for:)`, and
// `endGeohashSampling()` are satisfied by existing `ChatViewModel` members.
extension ChatViewModel: GeoChannelContext {}

@MainActor
final class GeoChannelCoordinator {
    private let locationManager: LocationChannelManager
    private let bookmarksStore: GeohashBookmarksStore
    private let torManager: TorManager

    private weak var context: (any GeoChannelContext)?

    private var cancellables = Set<AnyCancellable>()
    private var regionalGeohashes: [String] = []
    private var bookmarkedGeohashes: [String] = []

    init(
        locationManager: LocationChannelManager? = nil,
        bookmarksStore: GeohashBookmarksStore? = nil,
        torManager: TorManager? = nil,
        context: any GeoChannelContext
    ) {
        self.locationManager = locationManager ?? Self.defaultLocationManager()
        self.bookmarksStore = bookmarksStore ?? GeohashBookmarksStore.shared
        self.torManager = torManager ?? Self.defaultTorManager()
        self.context = context

        start()
    }

    func start() {
        regionalGeohashes = locationManager.availableChannels.map { $0.geohash }
        bookmarkedGeohashes = bookmarksStore.bookmarks

        locationManager.$selectedChannel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channel in
                guard let self else { return }
                Task { @MainActor in
                    self.context?.switchLocationChannel(to: channel)
                }
            }
            .store(in: &cancellables)

        locationManager.$availableChannels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] channels in
                guard let self else { return }
                self.regionalGeohashes = channels.map { $0.geohash }
                self.updateSampling()
            }
            .store(in: &cancellables)

        bookmarksStore.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bookmarks in
                guard let self else { return }
                self.bookmarkedGeohashes = bookmarks
                self.updateSampling()
            }
            .store(in: &cancellables)

        locationManager.$permissionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, state == .authorized else { return }
                Task { @MainActor [weak self] in
                    self?.locationManager.refreshChannels()
                }
            }
            .store(in: &cancellables)

        Task { @MainActor in
            self.context?.switchLocationChannel(to: self.locationManager.selectedChannel)
        }
        updateSampling()
    }

    private func updateSampling() {
        let union = Array(Set(regionalGeohashes).union(bookmarkedGeohashes))
        Task { @MainActor in
            guard !union.isEmpty else {
                context?.endGeohashSampling()
                return
            }
            if torManager.isForeground() {
                context?.beginGeohashSampling(for: union)
            } else {
                context?.endGeohashSampling()
            }
        }
    }

    func refreshSampling() {
        updateSampling()
    }
    private static func defaultLocationManager() -> LocationChannelManager {
        LocationChannelManager.shared
    }

    @MainActor
    private static func defaultTorManager() -> TorManager {
        TorManager.shared
    }
}
