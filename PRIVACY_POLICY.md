# bitchat Privacy Policy

*Last updated: June 2026*

## Our Commitment

bitchat is designed with privacy as its foundation. We believe private communication is a fundamental human right. This policy explains how bitchat protects your privacy.

## Summary

- **No personal data collection** - We don't collect names, emails, or phone numbers
- **No accounts or company servers** - Mesh chat works peer-to-peer; optional Nostr features use public or user-selected relays
- **No tracking** - We have no analytics, telemetry, or user tracking
- **Open source** - You can verify these claims by reading our code

## What Information bitchat Stores

### On Your Device Only

1. **Identity Keys**
   - Cryptographic private keys generated on first launch or when optional Nostr identities are created
   - Stored locally in your device's secure storage
   - Allows you to maintain "favorite" relationships across app restarts
   - Private keys never leave your device; public keys are shared when needed for messaging

2. **Nickname**
   - The display name you choose (or auto-generated)
   - Stored only on your device
   - Shared with peers you communicate with

3. **Message History** (if enabled)
   - When room owners enable retention, messages are saved locally
   - Stored encrypted on your device
   - You can delete this at any time

4. **Favorite Peers**
   - Public keys of peers you mark as favorites
   - Stored only on your device
   - Allows you to recognize these peers in future sessions

5. **Optional Location Channel State**
   - Your selected geohash channel, bookmarked geohashes, teleport flags, and bookmark display names
   - Stored locally on your device so the location-channel UI can restore your choices
   - Per-geohash Nostr identities are derived locally from a device seed stored in secure storage
   - Exact latitude and longitude are not persisted by bitchat

### Temporary Session Data

During each session, bitchat temporarily maintains:
- Active peer connections (forgotten when app closes)
- Routing information for message delivery
- Cached messages for offline peers (12 hours max)
- Your current location while optional location channels are enabled, used locally to compute geohash channels and friendly place names

## What Information is Shared

### With Other bitchat Users

When you use bitchat, nearby peers can see:
- Your chosen nickname
- Your ephemeral public key (changes each session)
- Messages you send to public rooms or directly to them
- Your approximate Bluetooth signal strength (for connection quality)

### With Room Members

When you join a password-protected room:
- Your messages are visible to others with the password
- Your nickname appears in the member list
- Room owners can see you've joined

### With Nostr Relays (Optional Features)

If you enable Nostr-backed features:
- Private fallback messages to mutual favorites are sent as encrypted NIP-17 gift wraps. Relays can see event metadata, but not message content.
- Public location-channel messages, location notes, and presence are scoped with geohash tags. Relays and other participants can see the geohash tag, event kind, timestamp, and public key used for that geohash.
- Exact GPS coordinates are not included in Nostr events by bitchat. The geohash precision you choose can still reveal an approximate area, from region-level to building-level.
- Automatic presence heartbeats are limited to low-precision geohashes (region, province, and city). More precise geohash posts happen only when you use those channels or location notes.

## What We DON'T Do

bitchat **never**:
- Collects personal information
- Sells or shares your exact GPS location
- Stores data on servers we operate
- Sells your data to advertisers or data brokers
- Uses analytics or telemetry
- Creates user profiles
- Requires registration

## Encryption

All private messages use end-to-end encryption:
- **X25519** for key exchange
- **AES-256-GCM** for message encryption
- **Ed25519** for digital signatures
- **Argon2id** for password-protected rooms

## Your Rights

You have complete control:
- **Delete Local State**: Triple-tap the logo to instantly wipe local keys, sessions, caches, and preferences
- **Leave Anytime**: Close the app and local presence stops; relay-backed presence ages out
- **No Account**: No account record exists for you to delete from us
- **Portability**: Your local state stays on your device unless you send messages, use optional relay-backed features, or export it

## Bluetooth & Permissions

bitchat requires Bluetooth permission to function:
- Used only for peer-to-peer communication
- Bluetooth is not used for tracking
- You can revoke this permission at any time in system settings

## Location Permission

Location permission is optional and is used only for location channels:
- Used to compute local geohash channels and display names
- Requested as when-in-use permission
- Exact coordinates are not shared in messages or stored by bitchat
- Selected and bookmarked geohashes may persist locally until you remove them, use panic wipe, or delete the app
- You can revoke this permission at any time in system settings

## Children's Privacy

bitchat does not knowingly collect information from children. The app has no age verification because it collects no personal information from anyone.

## Data Retention

- **Messages**: Deleted from memory when app closes (unless room retention is enabled)
- **Identity Key**: Persists until you delete the app
- **Favorites**: Persist until you remove them or delete the app
- **Location channel choices**: Selected/bookmarked geohashes persist locally until removed, panic-wiped, or the app is deleted
- **Nostr relay data**: Public geohash events and encrypted gift wraps may be retained by relays according to each relay's policy
- **Everything Else**: Exists only during active sessions

## Security Measures

- All communication is encrypted
- No accounts or company servers
- Optional Nostr relays receive only the events needed for Nostr-backed private fallback or public location channels
- Open source code for public audit
- Regular security updates
- Cryptographic signatures prevent tampering

## Changes to This Policy

If we update this policy:
- The "Last updated" date will change
- The updated policy will be included in the app
- No retroactive changes can make us collect data already held only in your app

## Contact

bitchat is an open source project. For privacy questions:
- View our source code: [https://github.com/permissionlesstech/bitchat/tree/main](https://github.com/permissionlesstech/bitchat/tree/main)
- Open an issue on GitHub
- Join the discussion in public rooms

## Philosophy

Privacy isn't just a feature—it's the entire point. bitchat proves that modern communication doesn't require surrendering your privacy. No accounts, no company servers, no analytics. Just people talking freely.

---

*This policy is released into the public domain under The Unlicense, just like bitchat itself.*
