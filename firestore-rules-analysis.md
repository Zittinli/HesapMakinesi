# Firestore rules analysis (untracked)

## Language / app
- Flutter (Dart), Firebase Auth email/password, Cloud Firestore `(default)` Standard, location `eur3`.

## Collections and fields

### users/{userId}
- email: string (required, lowercase)
- displayName: string
- isOnline: bool
- lastSeen: timestamp | null
- createdAt: timestamp | null
- CRUD: read by any signed-in user (email lookup + presence; existing product), create/update owner only, no delete
- Queries: `where('email' ==)`, `doc(uid).snapshots()`

### users/{userId}/chatPrefs/{chatId}
- pinned: bool
- pinnedAt: timestamp?
- muted: bool
- hidden: bool
- clearedAt: timestamp?
- CRUD: owner only
- Queries: collection snapshots for current user

### users/{userId}/blocked/{blockedUserId}
- createdAt: timestamp
- CRUD: owner only
- Queries: `doc(otherId).get()`

### chats/{chatId}
- participants: list<string> size 2, immutable
- lastMessage: string
- lastMessageAt: timestamp
- lastMessageSenderId: string
- unreadCounts: map<string, number>
- typing: map<string, timestamp>
- blockedBy: list<string>
- CRUD: read/update participants, create if auth in participants size 2, no delete
- Queries: `where participants array-contains uid orderBy lastMessageAt desc`

### chats/{chatId}/messages/{messageId}
- senderId: string (immutable, must be auth.uid on create)
- text: string (<= 4000)
- type: 'text' | 'image'
- mediaUrl: string | null
- createdAt: timestamp
- readBy: list<string>
- replyToId, replyToText, replyToSenderId: optional strings
- expiresAt: timestamp | null
- expireSeconds: number | null (10 | 60)
- deletedFor: list<string>
- deletedForEveryone: bool
- CRUD: read/create participant; update participant (readBy / deletedFor / deletedForEveryone); delete sender or expired
- Queries: `orderBy createdAt`

## Client operations
- send text (+ reply, + TTL)
- mark read, increment/reset unread
- typing ping
- pin/mute/hide/clear/delete-for-me via chatPrefs
- block via blocked + chats.blockedBy
- delete message for me / everyone
- purge expired messages
