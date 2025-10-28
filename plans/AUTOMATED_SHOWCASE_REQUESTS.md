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
3. **Enqueues background job** to complete the request
4. Background job:
   - Syncs index.sqlite3 to S3
   - Updates all active Fly machines (via CGI endpoint)
   - Each machine regenerates configs and triggers prerender
   - **Sends email notification once showcase is ready**
5. User receives confirmation email within ~30 seconds
6. No admin intervention required

**Benefits:**
- Zero manual intervention for new showcase requests
- Fast turnaround (~30 seconds vs hours/days)
- Consistent, reliable process
- Immediate feedback to requesters
- Leverages existing CGI infrastructure

## Implementation Plan

### Phase 1: Create NewShowcaseJob

**File:** `app/jobs/new_showcase_job.rb`

**Responsibilities:**
1. Run configuration update (reuses ConfigUpdateJob)
2. Send email notification after successful update
3. Handle errors gracefully with proper logging

**Job Parameters:**
- `showcase_id` - The showcase that was created
- `requester_userid` - The user who submitted the request (for email)
- `return_url` - Optional URL to include in email for user to view their showcase

**Implementation:**
```ruby
class NewShowcaseJob < ApplicationJob
  queue_as :default

  def perform(showcase_id, requester_userid, return_url: nil)
    @showcase = Showcase.find(showcase_id)
    @requester = User.find_by(userid: requester_userid)

    Rails.logger.info "NewShowcaseJob: Processing showcase request for #{@showcase.name}"

    # Run configuration update (reuse existing ConfigUpdateJob)
    ConfigUpdateJob.perform_now

    # Send email notification
    send_confirmation_email(return_url)

    Rails.logger.info "NewShowcaseJob: Completed successfully for #{@showcase.name}"
  rescue => e
    Rails.logger.error "NewShowcaseJob failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Send failure notification email
    send_failure_email(e.message) if @requester&.email

    raise # Re-raise to mark job as failed
  end

  private

  def send_confirmation_email(return_url)
    mail = Mail.new do
      from 'Sam Ruby <rubys@intertwingly.net>'
      to "#{@requester.name1} <#{@requester.email}>" if @requester&.email
      bcc 'Sam Ruby <rubys@intertwingly.net>'
      subject "Showcase Ready: #{@showcase.location.name} #{@showcase.year} - #{@showcase.name}"
    end

    mail.part do |part|
      part.content_type = 'multipart/related'
      part.attachments.inline[EventController.logo] =
        IO.read "public/#{EventController.logo}"
      @logo = part.attachments.first.url
      @return_url = return_url
      part.html_part = ApplicationController.render(
        template: 'showcases/confirmation_email',
        formats: [:html],
        layout: false,
        locals: {
          showcase: @showcase,
          requester_name: @requester&.name1 || 'Unknown User',
          logo: @logo,
          return_url: @return_url
        }
      )
    end

    mail.delivery_method :smtp,
      Rails.application.credentials.smtp || { address: 'mail.twc.com' }

    mail.deliver!
  rescue => e
    Rails.logger.error "Failed to send confirmation email: #{e.message}"
    # Don't raise - email failure shouldn't fail the entire job
  end

  def send_failure_email(error_message)
    mail = Mail.new do
      from 'Sam Ruby <rubys@intertwingly.net>'
      to "#{@requester.name1} <#{@requester.email}>" if @requester&.email
      bcc 'Sam Ruby <rubys@intertwingly.net>'
      subject "Showcase Request Failed: #{@showcase.location.name} #{@showcase.year} - #{@showcase.name}"
      body <<~EMAIL
        The automated processing of your showcase request has failed.

        Showcase: #{@showcase.name}
        Location: #{@showcase.location.name}
        Year: #{@showcase.year}

        Error: #{error_message}

        An administrator has been notified and will process your request manually.
      EMAIL
    end

    mail.delivery_method :smtp,
      Rails.application.credentials.smtp || { address: 'mail.twc.com' }

    mail.deliver!
  rescue => e
    Rails.logger.error "Failed to send failure notification email: #{e.message}"
  end
end
```

**Status:** ⏳ Not started

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
        # For regular users: Enqueue background job (new behavior)
        return_url = params[:return_to] || studio_events_url(@showcase.location&.key)
        NewShowcaseJob.perform_later(
          @showcase.id,
          @authuser,
          return_url: return_url
        )

        # Redirect with processing message
        format.html { redirect_to params[:return_to] || studio_events_path(@showcase.location&.key),
          notice: "#{@showcase.name} request is being processed. You will receive an email confirmation shortly." }
      end

      format.json { render :show, status: :created, location: @showcase }
    else
      # ... existing error handling ...
    end
  end
end
```

**Key Changes:**
1. **Admin users (index_auth)**: Keep existing behavior (immediate email, no job)
   - Allows admins to manually create showcases without triggering automation
   - Useful for testing and edge cases
2. **Regular users**: Enqueue `NewShowcaseJob` instead of sending email
   - Job handles config update + email
   - User sees "processing" message immediately
3. **Remove old `send_showcase_request_email` call** for regular users
   - Email now sent by job after config update completes

**Status:** ⏳ Not started

### Phase 3: Create Email Templates

**File:** `app/views/showcases/confirmation_email.html.erb`

**Purpose:** Email sent after successful automation (replaces `request_email.html.erb` for automated flow)

**Template:**
```erb
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { text-align: center; margin-bottom: 30px; }
    .logo { max-width: 200px; }
    .content { background: #f9fafb; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
    .button { display: inline-block; padding: 12px 24px; background: #3b82f6; color: white; text-decoration: none; border-radius: 6px; margin: 20px 0; }
    .footer { color: #6b7280; font-size: 14px; text-align: center; margin-top: 30px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="<%= @logo %>" alt="Logo" class="logo">
    </div>

    <h2>Your Showcase is Ready!</h2>

    <div class="content">
      <p>Hello <%= local_assigns[:requester_name] %>,</p>

      <p>Your showcase request has been successfully processed and is now live:</p>

      <ul>
        <li><strong>Event:</strong> <%= local_assigns[:showcase].name %></li>
        <li><strong>Location:</strong> <%= local_assigns[:showcase].location.name %></li>
        <li><strong>Year:</strong> <%= local_assigns[:showcase].year %></li>
        <% if local_assigns[:showcase].start_date %>
          <li><strong>Start Date:</strong> <%= local_assigns[:showcase].start_date.strftime('%B %d, %Y') %></li>
        <% end %>
      </ul>

      <% if local_assigns[:return_url] %>
        <p style="text-align: center;">
          <a href="<%= local_assigns[:return_url] %>" class="button">View Your Showcase</a>
        </p>
      <% end %>

      <p>You can now begin entering participants, heats, and other event details.</p>
    </div>

    <div class="footer">
      <p>This is an automated notification. If you have questions, please contact the administrator.</p>
    </div>
  </div>
</body>
</html>
```

**Status:** ⏳ Not started

**Note:** Keep existing `request_email.html.erb` for admin-created showcases (those that bypass automation).

### Phase 4: Testing

**Test Scenarios:**

1. **Regular User Creates Showcase (Primary Flow)**
   - User submits new showcase request
   - Verify job is enqueued
   - Verify user sees "processing" message
   - Verify config update runs successfully
   - Verify email is sent after completion
   - Verify showcase is accessible on production

2. **Admin User Creates Showcase**
   - Admin submits new showcase
   - Verify NO job is enqueued (immediate email)
   - Verify old behavior is preserved

3. **Job Failure Handling**
   - Simulate config update failure
   - Verify failure email is sent
   - Verify error is logged
   - Verify job is marked as failed (for retry)

4. **Email Delivery Failure**
   - Simulate email delivery failure
   - Verify job completes successfully (email failure doesn't fail job)
   - Verify error is logged

5. **Concurrent Requests**
   - Submit multiple showcase requests quickly
   - Verify all jobs execute successfully
   - Verify no race conditions

**Test Implementation:**
```ruby
# test/jobs/new_showcase_job_test.rb
require "test_helper"

class NewShowcaseJobTest < ActiveJob::TestCase
  test "successfully processes showcase request" do
    showcase = showcases(:pending_request)
    user = users(:studio_owner)

    assert_enqueued_with(job: NewShowcaseJob) do
      NewShowcaseJob.perform_later(showcase.id, user.userid)
    end

    perform_enqueued_jobs

    # Verify email was sent
    assert_emails 1
  end

  test "handles config update failure gracefully" do
    showcase = showcases(:pending_request)
    user = users(:studio_owner)

    # Mock config update to fail
    Open3.stub :capture3, ['', 'error', Object.new.tap { |s| s.define_singleton_method(:success?) { false } }] do
      assert_raises(RuntimeError) do
        NewShowcaseJob.perform_now(showcase.id, user.userid)
      end
    end

    # Verify failure email was sent
    assert_emails 1
  end
end
```

**Status:** ⏳ Not started

### Phase 5: Deployment & Monitoring

**Deployment Steps:**

1. **Deploy to Production**
   - Deploy updated code with NewShowcaseJob
   - Verify job queue is configured (Solid Queue or Sidekiq)
   - Verify SMTP credentials are configured

2. **Monitor First Production Use**
   - Watch logs for job execution
   - Verify config update completes successfully
   - Verify email is delivered
   - Time the end-to-end process

3. **Update Documentation**
   - Document new automated flow in CLAUDE.md
   - Update any admin guides
   - Note that admin users still bypass automation

**Monitoring Checklist:**
- [ ] Job enqueued successfully
- [ ] Config update script runs
- [ ] S3 sync completes
- [ ] All machines updated
- [ ] Prerender triggered
- [ ] Email delivered
- [ ] Total time < 60 seconds

**Status:** ⏳ Not started

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Time to showcase availability | Hours to days (manual) | <60 seconds (automated) |
| Admin intervention required | Yes (every request) | No (fully automated) |
| User feedback | Email on request submission | Email on completion (with link) |
| Reliability | Dependent on admin availability | Automated, consistent |

---

## Future Enhancements

1. **Showcase Status Dashboard**
   - Show pending/processing/completed showcases
   - Real-time status updates for users
   - Admin view to monitor automation

2. **Retry Logic**
   - Automatic retry on transient failures
   - Exponential backoff
   - Max retry limit with manual fallback

3. **Webhook Integration**
   - Trigger external systems when showcase is ready
   - Integration with calendar systems
   - Slack/Discord notifications

4. **Showcase Templates**
   - Pre-configure common showcase settings
   - Faster setup for recurring events
   - Less manual data entry

---

## References

- Related: `plans/CGI_CONFIGURATION_PLAN.md` (completed CGI infrastructure)
- Job: `app/jobs/config_update_job.rb` (reference implementation)
- Script: `script/config-update` (config update logic)
- Controller: `app/controllers/showcases_controller.rb#create` (current implementation)
