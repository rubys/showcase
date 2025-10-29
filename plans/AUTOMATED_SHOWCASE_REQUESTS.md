# Automated Showcase Request Processing

## Status: 📋 Planning

## Overview

Automate the new event request workflow to eliminate manual admin intervention. When a studio submits a new showcase request, the system will automatically update all production machines and send confirmation email once the showcase is ready.

## Current State

**User Flow:**
1. Studio submits new showcase request form (routed to rubix)
2. `showcases#create` saves showcase to index database
3. Calls `generate_showcases` (updates showcases.yml locally on rubix)
4. Sends email notification to requester
5. **Admin manually runs `admin#apply` later** to deploy changes to production

**Problems:**
- Manual intervention required for every new showcase request
- Delay between request submission and showcase availability
- Admin must remember to process pending requests
- Showcases.yml only updated on rubix, not on production machines

## Target State

**User Flow:**
1. Studio submits new showcase request form (routed to rubix)
2. `showcases#create` saves showcase to index database
3. **Shows real-time progress bar via WebSocket** while configuration updates
4. Background job (ConfigUpdateJob):
   - Syncs index.sqlite3 to S3
   - Updates all active Fly machines (via CGI endpoint)
   - Each machine regenerates configs and triggers prerender
   - **Broadcasts progress updates (0% → 100%) via ActionCable**
5. **User sees progress complete and is redirected to their showcase** within ~30 seconds
6. No admin intervention required

**Benefits:**
- Zero manual intervention for new showcase requests
- Fast turnaround (~30 seconds vs hours/days)
- Real-time progress feedback (no waiting/wondering)
- Immediate visual confirmation of completion
- Leverages existing ConfigUpdateJob and WebSocket infrastructure
- No email delays or deliverability issues

## Implementation Plan

### Phase 1: No Separate Job Needed

**Decision:** Reuse existing `ConfigUpdateJob` directly instead of creating a wrapper job.

**Rationale:**
- ConfigUpdateJob already supports user_id parameter for WebSocket broadcasting
- ConfigUpdateJob already has progress tracking built-in
- No need for email notifications (progress bar + redirect provides immediate feedback)
- Simpler architecture with fewer moving parts

**Status:** ✅ Already implemented (ConfigUpdateJob exists with WebSocket support)

### Phase 2: Update ShowcasesController

**File:** `app/controllers/showcases_controller.rb`

**Changes to `create` action:**

```ruby
def create
  @showcase = Showcase.new(showcase_params)

  # Infer year from start_date if year is not provided
  if @showcase.year.blank? && params[:showcase][:start_date].present?
    @showcase.year = Date.parse(params[:showcase][:start_date]).year
  end

  @showcase.order = (Showcase.maximum(:order) || 0) + 1

  respond_to do |format|
    if @showcase.save
      # Update local showcases.yml (for rubix)
      generate_showcases

      if Rails.env.test? || User.index_auth?(@authuser)
        # For tests and admin users: Send email immediately (old behavior)
        send_showcase_request_email(@showcase) unless Rails.env.test?

        # Redirect with created message
        if params[:return_to].present?
          format.html { redirect_to params[:return_to],
            notice: "#{@showcase.name} was successfully created." }
        else
          format.html { redirect_to events_location_url(@showcase.location),
            notice: "#{@showcase.name} was successfully created." }
        end
      else
        # For regular users: Enqueue config update job with progress tracking
        ConfigUpdateJob.perform_later(@authuser.id) if Rails.env.production?

        # Render progress page (instead of redirect)
        format.html { render :create_progress, status: :ok }
      end

      format.json { render :show, status: :created, location: @showcase }
    else
      # ... existing error handling ...
    end
  end
end
```

**Key Changes:**
1. **Admin users (index_auth)**: Keep existing behavior (immediate email, no automation)
   - Allows admins to manually create showcases without triggering automation
   - Useful for testing and edge cases
2. **Regular users**: Enqueue `ConfigUpdateJob` with user_id for WebSocket broadcasting
   - Render progress page instead of immediate redirect
   - User sees real-time progress bar
   - Automatic redirect on completion
3. **Remove email notification** - Progress bar + redirect provides better UX

**Status:** ⏳ Not started

### Phase 3: Create Progress View

**File:** `app/views/showcases/create_progress.html.erb`

**Purpose:** Show real-time progress during showcase creation and config update

**Template:**
```erb
<div class="mx-auto md:w-2/3 w-full"
     data-controller="config-update"
     data-config-update-user-id-value="<%= @authuser.id %>"
     data-config-update-database-value="<%= ENV['RAILS_APP_DB'] %>"
     data-config-update-redirect-url-value="<%= params[:return_to] || studio_events_url(@showcase.location&.key) %>">

  <h1 class="font-bold text-4xl">Creating Showcase</h1>

  <div class="content my-8">
    <p class="text-lg mb-4">Your showcase request is being processed:</p>

    <ul class="list-disc ml-6 mb-6">
      <li><strong>Event:</strong> <%= @showcase.name %></li>
      <li><strong>Location:</strong> <%= @showcase.location.name %></li>
      <li><strong>Year:</strong> <%= @showcase.year %></li>
    </ul>

    <p class="text-gray-600">This will take approximately 30 seconds...</p>
  </div>

  <!-- Progress indicator -->
  <div data-config-update-target="progress" class="my-8">
    <div class="mb-2">
      <div class="w-full bg-gray-200 rounded-full h-6 overflow-hidden">
        <div data-config-update-target="progressBar"
             class="bg-blue-500 h-full text-xs font-medium text-white text-center p-0.5 leading-5 transition-all duration-300"
             style="width: 0%">
          0%
        </div>
      </div>
    </div>
    <p data-config-update-target="message" class="text-sm text-gray-600">
      Starting configuration update...
    </p>
  </div>
</div>

<script>
  // Auto-connect to WebSocket and start progress tracking
  // The config-update controller will handle everything automatically
</script>
```

**Status:** ⏳ Not started

**Note:** Keep existing `request_email.html.erb` for admin-created showcases (those that bypass automation).

### Phase 4: Update Stimulus Controller (Optional)

**File:** `app/javascript/controllers/config_update_controller.js`

**Current Implementation:** Already supports progress tracking and auto-redirect

**Potential Enhancement:** Add auto-connect on page load for progress pages (not form submissions)

```javascript
connect() {
  this.consumer = createConsumer()
  this.subscription = null

  // Auto-start progress tracking if this is a progress page (not a form page)
  if (!this.hasFormTarget && this.hasUserIdValue) {
    this.startProgressTracking()
  }
}

startProgressTracking() {
  this.progressTarget.classList.remove("hidden")
  this.updateProgress(0, "Connecting...")

  this.subscription = this.consumer.subscriptions.create(
    {
      channel: "ConfigUpdateChannel",
      user_id: this.userIdValue,
      database: this.databaseValue
    },
    {
      connected: () => {
        this.updateProgress(0, "Starting...")
      },
      received: (data) => {
        this.handleProgressUpdate(data)
      }
    }
  )
}
```

**Status:** ⏳ Optional - current controller may work as-is

### Phase 5: Testing

**Test Scenarios:**

1. **Regular User Creates Showcase (Primary Flow)**
   - User submits new showcase request
   - Verify progress page is rendered (not redirect)
   - Verify WebSocket connection established
   - Verify progress bar updates (0% → 100%)
   - Verify automatic redirect to showcase on completion
   - Verify showcase is accessible on production

2. **Admin User Creates Showcase**
   - Admin submits new showcase
   - Verify NO job is enqueued (immediate email)
   - Verify immediate redirect (no progress page)
   - Verify old behavior is preserved

3. **Job Failure Handling**
   - Simulate config update failure
   - Verify error message displayed
   - Verify error is logged
   - Verify job is marked as failed (for retry)

4. **WebSocket Connection Failure**
   - Simulate WebSocket connection failure
   - Verify graceful fallback or error message
   - Verify error is logged

5. **Concurrent Requests**
   - Submit multiple showcase requests quickly
   - Verify all jobs execute successfully
   - Verify correct progress tracking per user (no cross-contamination)
   - Verify no race conditions

**Test Implementation:**
```ruby
# test/controllers/showcases_controller_test.rb
require "test_helper"

class ShowcasesControllerTest < ActionDispatch::IntegrationTest
  test "regular user sees progress page on showcase creation" do
    sign_in_as users(:studio_owner)

    assert_difference("Showcase.count") do
      post showcases_url, params: {
        showcase: {
          name: "New Event",
          location_id: locations(:boston).id,
          year: 2025
        }
      }
    end

    assert_response :ok
    assert_select "div[data-controller='config-update']"
    assert_select "div[data-config-update-target='progress']"
  end

  test "admin user gets immediate redirect (no progress page)" do
    sign_in_as users(:admin)

    assert_difference("Showcase.count") do
      post showcases_url, params: {
        showcase: {
          name: "Admin Event",
          location_id: locations(:boston).id,
          year: 2025
        }
      }
    end

    assert_redirected_to events_location_url(locations(:boston))
    follow_redirect!
    assert_match /successfully created/, flash[:notice]
  end
end
```

**Status:** ⏳ Not started

### Phase 6: Deployment & Monitoring

**Deployment Steps:**

1. **Deploy to Production**
   - Deploy updated code with progress view
   - Verify ConfigUpdateJob is working with user_id parameter
   - Verify ActionCable/WebSocket is configured and working
   - Verify ConfigUpdateChannel is available

2. **Monitor First Production Use**
   - Watch logs for job execution
   - Verify WebSocket connection established
   - Verify progress updates broadcast correctly
   - Verify automatic redirect works
   - Time the end-to-end process

3. **Update Documentation**
   - Document new automated flow in CLAUDE.md
   - Update any admin guides
   - Note that admin users still bypass automation

**Monitoring Checklist:**
- [ ] Progress page renders correctly
- [ ] WebSocket connection established
- [ ] Job enqueued successfully
- [ ] Config update script runs
- [ ] S3 sync completes
- [ ] All machines updated
- [ ] Prerender triggered
- [ ] Progress updates broadcast (0% → 100%)
- [ ] Automatic redirect works
- [ ] Total time < 60 seconds

**Status:** ⏳ Not started

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Time to showcase availability | Hours to days (manual) | <60 seconds (automated) |
| Admin intervention required | Yes (every request) | No (fully automated) |
| User feedback | Email on request submission | Real-time progress bar + auto-redirect |
| Reliability | Dependent on admin availability | Automated, consistent |
| User experience | Submit and wait (no visibility) | Real-time progress visibility |

---

## Future Enhancements

1. **Enhanced Error Handling**
   - Better error messages in progress bar
   - Retry button on failure
   - Admin notification on persistent failures

2. **Retry Logic**
   - Automatic retry on transient failures
   - Exponential backoff
   - Max retry limit with manual fallback

3. **Progress Granularity**
   - More detailed progress messages (e.g., "Syncing to S3...", "Updating machine 1 of 3...")
   - Estimated time remaining
   - Breakdown of each step

4. **Showcase Templates**
   - Pre-configure common showcase settings
   - Faster setup for recurring events
   - Less manual data entry

5. **Email Notification (Optional)**
   - Send email in addition to progress bar
   - Useful for users who close the browser
   - Include link to newly created showcase

---

## References

- Related: `plans/CGI_CONFIGURATION_PLAN.md` (completed CGI infrastructure)
- Job: `app/jobs/config_update_job.rb` (ConfigUpdateJob with WebSocket support)
- Channel: `app/channels/config_update_channel.rb` (ActionCable channel for progress updates)
- Stimulus: `app/javascript/controllers/config_update_controller.js` (frontend progress tracking)
- Script: `script/config-update` (config update logic)
- Controller: `app/controllers/showcases_controller.rb#create` (current implementation)
- Reference Implementation: `app/controllers/users_controller.rb#password_verify` (password reset with progress bar)
