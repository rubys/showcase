# Offline-Capable Scoring

For judges and emcees working in locations with unreliable internet connectivity, the application now offers an offline-capable scoring interface that works without a network connection and automatically syncs when connectivity returns.

## What's Different?

**This interface is designed to work exactly like the traditional scoring interface, with one key enhancement: it works offline.**

All the same scoring features you're used to are available:

* Radio buttons, checkboxes, cards, rankings
* Solo scoring and multi-dance compilations
* Sort by back number or level
* Judge assignments and filtering
* QR code sharing

The only difference is that when your internet connection drops, this interface keeps working. Your scores are saved on your device and automatically upload when connectivity returns.

## Why Two Interfaces?

Although this offline-capable version has passed 133+ automated tests and is designed to behave identically to the traditional interface, it's a complete rewrite of the scoring views. We need real-world validation before making it the standard.

**Which one should you use?**

* **Use the offline-capable interface if**: You want the peace of mind of knowing scoring will continue even if WiFi drops, or you're willing to help us validate this new implementation
* **Use the traditional interface if**: You prefer to stick with the proven, long-established interface, or if you encounter any issues with the new version

Once the offline-capable version is proven reliable through actual event usage, it will replace the traditional interface entirely.

## Limitations When Actually Offline

When your device has no internet connection, certain event management functions won't work (these limitations apply to all interfaces, not just this one):

* Scratching or adding heats requires a network connection
* Heat list counters won't update
* Users with cell phones may see heat lists, but they won't advance
* Score tallying won't occur
* Scrutineering of preliminary heats won't select couples to advance

These functions will work normally once connectivity is restored.

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

## Important Notes

* **Browser storage**: Scores are stored in your browser's local storage. Don't clear browser data during an event.
* **Same device**: Return to the same device and browser to resume scoring if you navigate away. Do not switch devices or share devices with different judges.
* **Automatic sync**: Scores upload automatically when online—no manual action required.
* **Testing recommended**: Try it before your event to ensure your device and browser support it properly.
* **Comprehensive testing**: The offline interface has passed 133+ automated tests covering navigation, scoring, semi-finals, callbacks, and edge cases.

## Help Us Validate

If you'd like to help prove this interface is ready to become the standard:

1. Use it during your event (the traditional interface remains available as a backup)
2. Report any differences in behavior compared to the traditional interface
3. Let us know about any issues or concerns

Your real-world feedback is the final step before we retire the traditional interface and make offline capability the standard for all judges.
