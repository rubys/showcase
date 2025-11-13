# Offline-Capable Scoring

For judges and emcees working in locations with unreliable internet connectivity, the application now offers an offline-capable scoring interface that works without a network connection and automatically syncs when connectivity returns.

## What It Does

The offline scoring interface allows judges to:

* **Score heats without internet**: All scoring functions work even when your device has no network connection
* **Automatic syncing**: Scores are saved locally on your device and automatically uploaded when connectivity is restored
* **Seamless experience**: The interface looks and behaves identically to the traditional scoring views
* **Visual feedback**: Clear indicators show WiFi status and pending score count

## How to Access

On a judge's person page, you'll see an amber-highlighted experimental section at the bottom with a link to **Offline Scoring Interface**. For emcees, a similar section provides access to **Offline Emcee Interface**.

The traditional scoring buttons at the top of the page remain available—both interfaces coexist and access the same data.

## How It Works

When you open the offline scoring interface:

1. **Initial load**: The application downloads all heat data to your device
2. **Scoring**: As you score heats, scores are saved to your device's local storage (IndexedDB)
3. **Background upload**: When online, scores are automatically uploaded to the server
4. **Status indicators**:
   - Green WiFi icon = online with no pending scores
   - Red WiFi icon with slash = offline
   - Red number + WiFi icon = number of scores waiting to upload

## Key Features

* **Info box with tips**: Click the ⓘ icon in the top left for helpful hints
* **QR code**: Share direct access to your scoring interface (links to the offline-capable version)
* **Sort order**: Choose between sorting by back number or level
* **Judge assignments**: Filter heats by assignment (first/only/mixed) when applicable
* **Unassigned heats**: Heats without judge assignments appear in red
* **Full scoring parity**: Supports all scoring modes (radio buttons, checkboxes, cards, rankings, solos, multi-dances)

## When to Use

This feature is particularly valuable for:

* **Venues with poor WiFi**: Ballrooms, convention centers, or hotels with unreliable internet
* **Backup plan**: Even with good connectivity, provides insurance against network issues
* **Remote locations**: Events in areas with limited infrastructure
* **Large events**: Reduces server load by batching uploads

## Important Notes

* **Browser storage**: Scores are stored in your browser's local storage. Don't clear browser data during an event.
* **Same device**: Return to the same device and browser to resume scoring if you navigate away.
* **Automatic sync**: Scores upload automatically when online—no manual action required.
* **Testing recommended**: Try it before your event to ensure your device and browser support it properly.
* **Comprehensive testing**: The offline interface has passed 133+ automated tests covering navigation, scoring, semi-finals, callbacks, and edge cases.

## Status: Experimental

This feature is **code complete and comprehensively tested**, but awaiting real-world validation during live events. It's designed to behave identically to the traditional scoring views, but hasn't yet been used in production.

The traditional scoring interface remains the primary option and will continue to be available. Once the offline interface has been validated by actual usage during events, it may become the default.

## Try It Out

If you'd like to help validate this feature:

1. Use it alongside the traditional views during an event
2. Report any differences in behavior or unexpected issues
3. Note any performance or usability concerns

Your feedback will help determine when this feature is ready to become the standard scoring interface.
