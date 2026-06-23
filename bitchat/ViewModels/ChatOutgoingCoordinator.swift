import BitFoundation
import BitLogger
import Foundation

/// The narrow surface `ChatOutgoingCoordinator` needs from its owner.
///
/// Follows the `ChatDeliveryContext` exemplar: the coordinator depends on the
/// minimal context it actually uses instead of holding an `unowned` back-ref
/// to the whole `ChatViewModel`. This keeps the coordinator independently
/// testable (see `ChatOutgoingCoordinatorContextTests`) and makes its true
/// dependencies explicit.
@MainActor
protocol ChatOutgoingContext: AnyObject {
    // MARK: Identity & channel state
    var nickname: String { get }
    var myPeerID: PeerID { get }
    var activeChannel: ChannelID { get }
    var selectedPrivateChatPeer: PeerID? { get }
    var isTeleported: Bool { get }

    // MARK: Commands & private messages
    func handleCommand(_ command: String)
    func updatePrivateChatPeerIfNeeded()
    func sendPrivateMessage(_ content: String, to peerID: PeerID)

    // MARK: Public timeline (local echo)
    func parseMentions(from content: String) -> [String]
    /// Appends a public message via the single-writer store intent
    /// (immediate: the local echo must render without batching).
    @discardableResult
    func appendPublicMessage(_ message: BitchatMessage, to conversationID: ConversationID) -> Bool
    func addSystemMessage(_ content: String)

    // MARK: Content dedup
    func normalizedContentKey(_ content: String) -> String
    func recordContentKey(_ key: String, timestamp: Date)

    // MARK: Outbound routing
    /// Stamps "now" as the channel's last public activity (background nudges).
    /// (Single mutation path for the owner's `lastPublicActivityAt`; this
    /// coordinator never reads it.)
    func recordPublicActivity(forChannelKey key: String)
    func sendMeshMessage(_ content: String, mentions: [String], messageID: String, timestamp: Date)
    func sendGeohash(context: ChatViewModel.GeoOutgoingContext)

    // MARK: Geohash identity (shared with the other contexts)
    func deriveNostrIdentity(forGeohash geohash: String) throws -> NostrIdentity
}

extension ChatViewModel: ChatOutgoingContext {
    // `nickname`, `myPeerID`, `activeChannel`, `selectedPrivateChatPeer`,
    // `isTeleported`, `handleCommand(_:)`, `updatePrivateChatPeerIfNeeded()`,
    // `sendPrivateMessage(_:to:)`, `parseMentions(from:)`,
    // `appendPublicMessage(_:to:)`, `addSystemMessage(_:)`,
    // `normalizedContentKey(_:)`, `recordContentKey(_:timestamp:)`,
    // `sendMeshMessage(_:mentions:messageID:timestamp:)`,
    // `sendGeohash(context:)`, and `deriveNostrIdentity(forGeohash:)` are
    // shared requirements with the other contexts or satisfied by existing
    // `ChatViewModel` members. The single-writer intent op below lives next to
    // its backing state's owner.

    func recordPublicActivity(forChannelKey key: String) {
        lastPublicActivityAt[key] = Date()
    }
}

@MainActor
final class ChatOutgoingCoordinator {
    private unowned let context: any ChatOutgoingContext

    init(context: any ChatOutgoingContext) {
        self.context = context
    }

    func sendMessage(_ content: String) {
        guard let trimmed = content.trimmedOrNilIfEmpty else { return }

        if content.hasPrefix("/") {
            Task { @MainActor [weak context = self.context] in
                context?.handleCommand(content)
            }
            return
        }

        if context.selectedPrivateChatPeer != nil {
            context.updatePrivateChatPeerIfNeeded()

            if let selectedPeer = context.selectedPrivateChatPeer {
                context.sendPrivateMessage(content, to: selectedPeer)
            }
            return
        }

        let mentions = context.parseMentions(from: content)
        let preparedMessage = preparePublicMessage(content: content, trimmed: trimmed, mentions: mentions)
        guard let preparedMessage else { return }

        appendLocalEcho(preparedMessage.message)
        routePublicMessage(
            originalContent: content,
            mentions: mentions,
            geoContext: preparedMessage.geoContext,
            messageID: preparedMessage.message.id,
            timestamp: preparedMessage.message.timestamp
        )
    }
}

private extension ChatOutgoingCoordinator {
    func preparePublicMessage(
        content: String,
        trimmed: String,
        mentions: [String]
    ) -> (message: BitchatMessage, geoContext: ChatViewModel.GeoOutgoingContext?)? {
        var geoContext: ChatViewModel.GeoOutgoingContext?
        var displaySender = context.nickname
        var localSenderPeerID = context.myPeerID
        var messageID: String?
        var messageTimestamp = Date()

        switch context.activeChannel {
        case .mesh:
            break

        case .location(let channel):
            do {
                let identity = try context.deriveNostrIdentity(forGeohash: channel.geohash)
                let suffix = String(identity.publicKeyHex.suffix(4))
                displaySender = context.nickname + "#" + suffix
                localSenderPeerID = PeerID(nostr: identity.publicKeyHex)

                let teleported = context.isTeleported
                let event = try NostrProtocol.createEphemeralGeohashEvent(
                    content: trimmed,
                    geohash: channel.geohash,
                    senderIdentity: identity,
                    nickname: context.nickname,
                    teleported: teleported
                )

                messageID = event.id
                messageTimestamp = Date(timeIntervalSince1970: TimeInterval(event.created_at))
                geoContext = (
                    channel: channel,
                    event: event,
                    identity: identity,
                    teleported: teleported
                )
            } catch {
                SecureLogger.error("❌ Failed to prepare geohash message: \(error)", category: .session)
                context.addSystemMessage(
                    String(localized: "system.location.send_failed", comment: "System message when a location channel send fails")
                )
                return nil
            }
        }

        let message = BitchatMessage(
            id: messageID,
            sender: displaySender,
            content: trimmed,
            timestamp: messageTimestamp,
            isRelay: false,
            senderPeerID: localSenderPeerID,
            mentions: mentions.isEmpty ? nil : mentions
        )

        return (message, geoContext)
    }

    func appendLocalEcho(_ message: BitchatMessage) {
        context.appendPublicMessage(message, to: ConversationID(channelID: context.activeChannel))

        let contentKey = context.normalizedContentKey(message.content)
        context.recordContentKey(contentKey, timestamp: message.timestamp)
    }

    func routePublicMessage(
        originalContent: String,
        mentions: [String],
        geoContext: ChatViewModel.GeoOutgoingContext?,
        messageID: String,
        timestamp: Date
    ) {
        switch context.activeChannel {
        case .mesh:
            context.recordPublicActivity(forChannelKey: "mesh")
            context.sendMeshMessage(
                originalContent,
                mentions: mentions,
                messageID: messageID,
                timestamp: timestamp
            )

        case .location(let channel):
            context.recordPublicActivity(forChannelKey: "geo:\(channel.geohash)")

            guard let geoContext, geoContext.channel.geohash == channel.geohash else {
                SecureLogger.error("Geo: missing send context for \(channel.geohash)", category: .session)
                context.addSystemMessage(
                    String(localized: "system.location.send_failed", comment: "System message when a location channel send fails")
                )
                return
            }

            Task { @MainActor [weak context = self.context] in
                context?.sendGeohash(context: geoContext)
            }
        }
    }
}
