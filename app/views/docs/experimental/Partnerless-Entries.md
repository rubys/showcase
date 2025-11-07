# Partnerless Entries

<div data-controller="info-box">
  <div class="info-button">ⓘ</div>
  <ul class="info-box">
    <li>This feature is experimental and in the "Coming Attractions" phase.</li>
    <li>While tested, it may have unforeseen interactions with billing, reporting, or other features.</li>
    <li>Please report any issues you encounter.</li>
  </ul>
</div>

## Overview

The Partnerless Entries feature allows students to compete without a partner. This is useful for:

- Solo student competitions where dancers perform alone
- Events where a student's partner is unavailable
- Competitions specifically designed for individual performance

## How It Works

When enabled, students can select "Nobody" as their partner when creating entries. The student dances alone on the floor, but still requires an instructor (unless they are dancing with a professional).

### Behind the Scenes

The system uses a special "Nobody" person (ID 0) to represent the missing partner. This allows all existing heat scheduling, scoring, and reporting logic to continue working without modification.

## Enabling Partnerless Entries

1. Navigate to **Settings → Advanced**
2. Check the box: **"Allow students to dance without a partner (select Nobody as partner)"**
3. Click **Save**

When you enable this feature for the first time, the system automatically creates:
- A "Nobody" person with ID 0
- An "Event Staff" studio to house this special person

## Creating a Partnerless Entry

Once enabled, when creating entries for a student:

1. Go to **Entries → New** and select a student
2. In the partner dropdown, **"Nobody"** will appear as the first option
3. **"Nobody" is automatically selected** for your convenience
4. Select an instructor (required for student entries)
5. Choose your dances and categories as normal

## Display

Throughout the application, partnerless entries are displayed with a **(Solo)** suffix:

- **Heat lists**: "Jane Doe (Solo)" instead of "Jane Doe & Nobody"
- **Agendas**: Same clean display format
- **Scoring sheets**: Clearly indicates solo performance

## Important Notes

### Only for Students

The "Nobody" partner option only appears for Students. Professionals cannot create partnerless entries.

### Instructor Required

Partnerless entries must have an instructor, following the standard rule that entries require exactly one professional.

### Distinct from Solos

This feature is **different from Solo performances** (Routines):

- **Partnerless Entry**: A competitive dance without a partner, each judged separately
- **Solo/Routine**: A choreographed performance, possibly with formations

### Billing and Invoicing

The standard billing logic applies:
- Charges go to the student's studio
- Heat costs are calculated normally
- Invoice generation includes partnerless entries

⚠️ **Note**: While the billing logic has been tested, we recommend monitoring invoices when first using this feature to ensure correct calculations for your event's pricing structure.

## Feedback Welcome

This feature is in experimental status to gather real-world usage data. If you use it, please share:

- Any issues with billing, invoicing, or reporting
- Display problems in any views
- Suggestions for improvements
- Success stories!

Your feedback helps us move features from experimental to production-ready.
