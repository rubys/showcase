# Offline DJ List

For DJs working with unreliable event WiFi, the application now offers two complementary features to ensure music playback continues even when network connectivity is problematic.

## What's the Problem?

Event WiFi can be unreliable. Songs may start playing but then stop after a few seconds when the connection drops. This is especially problematic during live events when you need uninterrupted music playback.

## Two Solutions

The DJ list page (Solos → DJ List) provides two different approaches to offline music playback, each suited for different situations:

### 1. Cache Songs Locally (Experimental)

**Best for**: Events with intermittent WiFi or when you want to prepare ahead of time

This feature downloads songs and stores them directly in your browser for instant playback without requiring a network connection.

**How it works:**

1. Click "Cache Songs Locally" on the DJ list page
2. The system downloads songs one at a time using multiple resilience strategies
3. Cached songs are stored in your browser's IndexedDB
4. Songs automatically restore when you reload the page
5. Cached songs are highlighted with a light green background

**Key benefits:**

* **Persistent cache**: Songs remain cached across page reloads and browser sessions
* **Incremental caching**: Can cache songs in multiple sessions (e.g., 75% before event, 25% at event)
* **Automatic restoration**: Page loads instantly with cached songs ready to play
* **No action required**: Once cached, songs just work—no button clicks needed
* **Resilient downloading**: Uses three progressive strategies to handle problematic WiFi:
  1. Simple download (fastest if WiFi is good)
  2. Chunked streaming (better timeout detection)
  3. Range requests (bypasses size limits by making multiple small requests)

**Status display:**

* Shows cache statistics: "15 of 45 songs cached (45.3 MB) • Cached 2 days ago"
* Cached song rows highlighted with light green background

**Cache management:**

* Songs expire automatically after 30 days
* "Clear Cache" button to manually remove cached songs
* Cache is specific to each event (songs for different events don't interfere)

**Limitations:**

* Requires browser support for IndexedDB (all modern browsers)
* Cache storage counts toward browser storage quota
* Must use the same device and browser to access cached songs
* Don't clear browser data during the event or you'll lose the cache

**This feature is experimental** and needs real-world validation before becoming standard. Please report any issues or unexpected behavior.

### 2. Prepare Offline Version (Established)

**Best for**: Complete offline backup or when you need a standalone file

This feature generates a downloadable ZIP file containing a self-contained HTML page with all songs embedded as base64 data.

**How it works:**

1. Click "Prepare Offline Version" on the DJ list page
2. Wait for the background job to process all songs (progress bar shows status)
3. Download the generated ZIP file
4. Extract the ZIP and open the HTML file in any browser
5. All songs play from the HTML file with no network required

**Key benefits:**

* **Completely standalone**: Works on any device, any browser, no network
* **Shareable**: Can copy the HTML file to other devices
* **Guaranteed offline**: No dependencies on browser storage or connectivity

**Limitations:**

* Requires WiFi to be stable long enough to generate and download the ZIP
* Large file size (all songs embedded in one file)
* Multi-step process (generate, download, extract, open)
* Changes to the song list require regenerating the file

## Which Should You Use?

**Use "Cache Songs Locally" if:**
* You want the convenience of the regular DJ list page with offline resilience
* You can cache songs before the event when WiFi is better
* You want to cache incrementally across multiple sessions
* You prefer automatic restoration without manual steps

**Use "Prepare Offline Version" if:**
* You need a guaranteed standalone backup file
* WiFi is good enough to download the ZIP once
* You want to use the offline version on a different device
* You prefer a proven, established solution

**Use both:**
Many DJs find it helpful to use "Cache Songs Locally" as the primary approach and keep "Prepare Offline Version" as a backup plan in case of catastrophic failures.

## How to Access

Navigate to **Solos → DJ List**. At the top of the page you'll see two buttons:

* **Cache Songs Locally** (green button) - Experimental caching feature
* **Prepare Offline Version** (blue button) - Established ZIP download

## Important Notes

* **Browser storage**: Cached songs are stored in your browser's IndexedDB. Don't clear browser data during an event.
* **Same device**: Cached songs are specific to your device and browser. Use the same browser you used to cache.
* **Testing recommended**: Try caching songs before your event to ensure your device and browser support it properly.
* **Network resilience**: The caching feature tries three different download strategies to handle problematic WiFi, but very poor WiFi may still cause downloads to fail.

## Help Us Validate

The "Cache Songs Locally" feature is experimental and needs real-world validation:

1. Try it before or during your event (prepare a backup just in case)
2. Report whether downloads succeeded or failed on your event WiFi
3. Let us know about any issues, unexpected behavior, or suggestions

Your real-world feedback will help us determine if this feature is ready to become standard.

## Automatic Cleanup

Cached songs are automatically cleaned up to prevent filling your browser storage:

* Songs older than 30 days are deleted automatically when the page loads
* You can manually clear the cache anytime using the "Clear Cache" button
* Each event's songs are stored separately (other events' caches aren't affected)
