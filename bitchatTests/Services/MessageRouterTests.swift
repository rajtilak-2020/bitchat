//
// MessageRouterTests.swift
// bitchatTests
//
// Tests for MessageRouter transport selection and outbox behavior.
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

struct MessageRouterTests {

    @Test @MainActor
    func sendPrivate_usesReachableTransport() async {
        let peerID = PeerID(str: "0000000000000001")
        let transportA = MockTransport()
        let transportB = MockTransport()
        transportB.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transportA, transportB])
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m1")

        #expect(transportA.sentPrivateMessages.isEmpty)
        #expect(transportB.sentPrivateMessages.count == 1)
    }

    @Test @MainActor
    func sendPrivate_queuesThenFlushesWhenReachable() async {
        let peerID = PeerID(str: "0000000000000002")
        let transport = MockTransport()

        let router = MessageRouter(transports: [transport])
        router.sendPrivate("Queued", to: peerID, recipientNickname: "Peer", messageID: "m2")

        #expect(transport.sentPrivateMessages.isEmpty)

        transport.reachablePeers.insert(peerID)
        router.flushOutbox(for: peerID)

        #expect(transport.sentPrivateMessages.count == 1)
    }

    @Test @MainActor
    func sendPrivate_prefersConnectedTransportOverEarlierReachableOne() async {
        let peerID = PeerID(str: "0000000000000005")
        let reachableOnly = MockTransport()
        reachableOnly.reachablePeers.insert(peerID)
        let connected = MockTransport()
        connected.connectedPeers.insert(peerID)
        connected.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [reachableOnly, connected])
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m5")

        #expect(reachableOnly.sentPrivateMessages.isEmpty)
        #expect(connected.sentPrivateMessages.count == 1)
    }

    @Test @MainActor
    func sendPrivate_reachableOnlySendRetainsUntilDeliveryAck() async {
        let peerID = PeerID(str: "0000000000000006")
        let transport = MockTransport()
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m6")
        #expect(transport.sentPrivateMessages.count == 1)

        // No ack yet: a flush retries over the weak signal.
        router.flushOutbox(for: peerID)
        #expect(transport.sentPrivateMessages.count == 2)

        // Ack clears the retained copy; later flushes stop resending.
        router.markDelivered("m6")
        router.flushOutbox(for: peerID)
        #expect(transport.sentPrivateMessages.count == 2)
    }

    @Test @MainActor
    func sendPrivate_connectedSendIsNotRetained() async {
        let peerID = PeerID(str: "0000000000000007")
        let transport = MockTransport()
        transport.connectedPeers.insert(peerID)
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m7")
        #expect(transport.sentPrivateMessages.count == 1)

        router.flushOutbox(for: peerID)
        #expect(transport.sentPrivateMessages.count == 1)
    }

    @Test @MainActor
    func flushOutbox_dropsUnackedMessageAfterAttemptCap() async {
        let peerID = PeerID(str: "0000000000000008")
        let transport = MockTransport()
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m8")

        for _ in 0..<10 {
            router.flushOutbox(for: peerID)
        }

        // Initial send plus capped resends; never unbounded.
        #expect(transport.sentPrivateMessages.count == 8)
    }

    // MARK: - Drop visibility (onMessageDropped)

    @Test @MainActor
    func flushOutbox_attemptCapDropInvokesOnMessageDropped() async {
        let peerID = PeerID(str: "0000000000000009")
        let transport = MockTransport()
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        var dropped: [(messageID: String, peerID: PeerID)] = []
        router.onMessageDropped = { dropped.append(($0, $1)) }

        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m9")
        for _ in 0..<10 {
            router.flushOutbox(for: peerID)
        }

        #expect(dropped.count == 1)
        #expect(dropped.first?.messageID == "m9")
        #expect(dropped.first?.peerID == peerID)
    }

    @Test @MainActor
    func flushOutbox_ttlExpiryInvokesOnMessageDroppedAndDoesNotResend() async {
        let peerID = PeerID(str: "000000000000000a")
        let transport = MockTransport()
        let clock = MutableTestClock()

        let router = MessageRouter(transports: [transport], now: { clock.now })
        var dropped: [String] = []
        router.onMessageDropped = { messageID, _ in dropped.append(messageID) }

        // No reachable transport: the message is queued, never sent.
        router.sendPrivate("Hello", to: peerID, recipientNickname: "Peer", messageID: "m10")
        #expect(transport.sentPrivateMessages.isEmpty)

        // Past the 24h TTL the flush must drop it (visibly), not send it.
        clock.now = clock.now.addingTimeInterval(24 * 60 * 60 + 1)
        transport.reachablePeers.insert(peerID)
        router.flushOutbox(for: peerID)

        #expect(dropped == ["m10"])
        #expect(transport.sentPrivateMessages.isEmpty)

        // The drop is final: nothing is retained for later flushes.
        router.flushOutbox(for: peerID)
        #expect(dropped == ["m10"])
    }

    @Test @MainActor
    func cleanupExpiredMessages_invokesOnMessageDroppedForExpiredOnly() async {
        let peerID = PeerID(str: "000000000000000b")
        let transport = MockTransport()
        let clock = MutableTestClock()

        let router = MessageRouter(transports: [transport], now: { clock.now })
        var dropped: [String] = []
        router.onMessageDropped = { messageID, _ in dropped.append(messageID) }

        router.sendPrivate("Old", to: peerID, recipientNickname: "Peer", messageID: "m11-old")
        clock.now = clock.now.addingTimeInterval(24 * 60 * 60 - 60)
        router.sendPrivate("Fresh", to: peerID, recipientNickname: "Peer", messageID: "m11-fresh")
        clock.now = clock.now.addingTimeInterval(120)

        router.cleanupExpiredMessages()

        #expect(dropped == ["m11-old"])

        // The fresh message survived and still flushes once reachable.
        transport.reachablePeers.insert(peerID)
        router.flushOutbox(for: peerID)
        #expect(transport.sentPrivateMessages.map(\.messageID) == ["m11-fresh"])
    }

    @Test @MainActor
    func enqueue_perPeerOverflowEvictionInvokesOnMessageDropped() async {
        let peerID = PeerID(str: "000000000000000c")
        let transport = MockTransport()

        let router = MessageRouter(transports: [transport])
        var dropped: [String] = []
        router.onMessageDropped = { messageID, _ in dropped.append(messageID) }

        // No reachable transport: everything queues. The cap is 100 per peer,
        // so the 101st enqueue evicts the oldest.
        for i in 0...100 {
            router.sendPrivate("Hello \(i)", to: peerID, recipientNickname: "Peer", messageID: "q\(i)")
        }

        #expect(dropped == ["q0"])
    }

    @Test @MainActor
    func sendReadReceipt_usesReachableTransport() async {
        let peerID = PeerID(str: "0000000000000003")
        let transport = MockTransport()
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        let receipt = ReadReceipt(originalMessageID: "m3", readerID: transport.myPeerID, readerNickname: "Me")
        router.sendReadReceipt(receipt, to: peerID)

        #expect(transport.sentReadReceipts.count == 1)
    }

    @Test @MainActor
    func sendFavoriteNotification_usesConnectedOrReachable() async {
        let peerID = PeerID(str: "0000000000000004")
        let transport = MockTransport()
        transport.reachablePeers.insert(peerID)

        let router = MessageRouter(transports: [transport])
        router.sendFavoriteNotification(to: peerID, isFavorite: true)

        #expect(transport.sentFavoriteNotifications.count == 1)
    }
}

/// Mutable wall clock injected into `MessageRouter` so TTL expiry is testable
/// without real waiting.
private final class MutableTestClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}
