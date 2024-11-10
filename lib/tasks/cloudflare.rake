namespace :cloudflare do
  task :release => :prerender do
    # setup rclone (when run on a deploy release machine)
    config_rclone = "#{Dir.home}/.config/rclone"
    if not Dir.exist? config_rclone
      mkdir_p config_rclone
      IO.write "#{config_rclone}/rclone.conf",
        Rails.application.credentials.rclone_conf
    end

    # retrieve the current assets
    sh 'rclone copy CloudFlare:showcase/assets tmp/site/assets'

    # expire assets older than 3 days
    filetimes = Dir['tmp/site/assets/*'].map {|name| [name, File.mtime(name)]}.to_h
    keep = (filetimes.values.max || Time.now) - 3.days
    filetimes.each do |name, time|
      rm name if time < keep
    end

    def sync(source, dest, pattern="**/*")
      files = Dir.chdir(source) {Dir[pattern]}
      files.each do |name|
        sourcefile = File.join(source, name)
        next if File.directory?(sourcefile)
        destfile = File.join(dest, name)
        if (IO.read(sourcefile) != IO.read(destfile) rescue true)
          dir = File.dirname(destfile)
          mkdir_p dir if not Dir.exist?(dir)
          cp sourcefile, destfile
        end
      end

      files = Dir.chdir(dest) {Dir[pattern]}
      files.each do |name|
        destfile = File.join(dest, name)
        next if File.directory?(destfile)
        sourcefile = File.join(source, name)
        rm destfile if not File.exist?(sourcefile)
      end
    end

    # copy in mew/changed files
    sync "public", "tmp/site", "*.*"
    sync "public/assets", "tmp/site/assets"
    sync "public/regions", "tmp/site/regions"
    sync "public/studios", "tmp/site/studios"

    # sync the site
    sh 'rclone sync tmp/site CloudFlare:showcase'
  end

  task :deploy => "prerender:env" do
    Rake::Task["assets:precompile"].invoke
    Rake::Task["prerender"].invoke
    Rake::Task["cloudflare:release"].invoke
    cp "public/showcase.js", "cf/worker/showcase/src/index.js"
    Dir.chdir "cf/worker/showcase" do
      sh "npx wrangler deploy"
    end
    Rake::Task["assets:clobber"].invoke
  end
end
