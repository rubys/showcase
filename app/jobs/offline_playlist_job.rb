class OfflinePlaylistJob < ApplicationJob
  queue_as :default

  def perform(event_id, user_id)
    event = Event.find(event_id)
    Event.current = event
    
    filename = "dj-playlist-#{event.name.parameterize}.zip"
    cache_key = "offline_playlist_#{event_id}"
    
    Rails.cache.delete(cache_key)
    
    ActionCable.server.broadcast(
      "offline_playlist_#{user_id}",
      { status: 'processing', progress: 0, message: 'Starting playlist generation...' }
    )
    
    begin
      total_heats = Solo.joins(:heat).where(heats: { category: 'Solo', number: 1.. }).count
      
      if total_heats == 0
        ActionCable.server.broadcast(
          "offline_playlist_#{user_id}",
          { status: 'error', message: 'No solos found' }
        )
        return
      end
      
      # Notify user we're finalizing the download file
      ActionCable.server.broadcast(
        "offline_playlist_#{user_id}",
        { 
          status: 'processing', 
          progress: 100, 
          message: "Finalizing download..."
        }
      )
      
      zip_path = generate_zip_file(event, user_id, total_heats)
      
      # Store just the path in cache, not the entire file
      cache_data = {
        filename: filename,
        file_path: zip_path,
        generated_at: Time.current
      }
      
      Rails.cache.write(cache_key, cache_data, expires_in: 1.hour)
      
      ActionCable.server.broadcast(
        "offline_playlist_#{user_id}",
        { 
          status: 'completed', 
          progress: 100, 
          message: 'Playlist ready for download',
          download_key: cache_key
        }
      )
    rescue => e
      Rails.logger.error "OfflinePlaylistJob failed: #{e.message}\n#{e.backtrace.join("\n")}"
      
      ActionCable.server.broadcast(
        "offline_playlist_#{user_id}",
        { status: 'error', message: "Failed to generate playlist: #{e.message}" }
      )
    end
  end
  
  private
  
  def generate_zip_file(event, user_id, total_heats)
    require 'zip'
    require 'fileutils'
    
    # Create a directory for temporary files if it doesn't exist
    temp_dir = Rails.root.join('tmp', 'offline_playlists')
    FileUtils.mkdir_p(temp_dir)
    
    # Create a unique filename
    zip_filename = "dj-playlist-#{event.id}-#{Time.current.to_i}.zip"
    zip_path = temp_dir.join(zip_filename)
    
    Zip::OutputStream.open(zip_path) do |zip|
      zip.put_next_entry("dj-playlist.html")
      
      # Stream HTML content directly to ZIP (no memory accumulation)
      generate_html_content(zip, event, user_id, total_heats)
      
      zip.put_next_entry("README.txt")
      zip.write(generate_readme_content(event))
    end
    
    # Clean up old files (older than 2 hours)
    Dir[temp_dir.join("*.zip")].each do |file|
      if File.mtime(file) < 2.hours.ago
        File.delete(file) rescue nil
      end
    end
    
    zip_path.to_s
  end
  
  def generate_html_content(zip_stream, event, user_id, total_heats)
    solos_controller = SolosController.new
    solos_controller.index
    heats = solos_controller.instance_variable_get(:@solos).map { |solo| solo.last }.flatten.sort_by { |heat| heat.number }
    
    # Write header directly to ZIP
    zip_stream.write(render_partial('solos/offline_header', event: event))
    
    processed = 0
    last_broadcast_time = Time.current
    
    heats.each do |heat|
      next if heat.number <= 0
      
      # Write each heat row directly to ZIP as we process it
      zip_stream.write(render_partial('solos/offline_heat_row', heat: heat))
      
      processed += 1
      progress = (processed.to_f / total_heats * 100).to_i
      
      # Broadcast if a second or more has elapsed since last broadcast, or if we're done
      current_time = Time.current
      if (current_time - last_broadcast_time) >= 1.0 || processed == total_heats
        ActionCable.server.broadcast(
          "offline_playlist_#{user_id}",
          { 
            status: 'processing', 
            progress: progress, 
            message: "Processing heat #{processed} of #{total_heats}..."
          }
        )
        last_broadcast_time = current_time
      end
    end
    
    # Write footer directly to ZIP
    zip_stream.write(render_partial('solos/offline_footer'))
  end
  
  def generate_readme_content(event)
    render_partial('solos/offline_readme', event: event, format: :text)
  end
  
  def render_partial(partial, format: :html, **locals)
    ApplicationController.render(
      partial: partial,
      formats: [format],
      locals: locals
    )
  end
end