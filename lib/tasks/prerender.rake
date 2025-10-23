require 'yaml'

namespace :prerender do
  task :env do
    # configure the Rails environment
    ENV['RAILS_ENV'] = 'production'
    ENV['RAILS_APP_DB'] = 'index'
    ENV['RAILS_APP_SCOPE'] = '/showcase'
    ENV['RAILS_PROXY_HOST'] ||= `hostname`
    ENV.delete('DATABASE_URL')
    Rake::Task['environment'].invoke
  end

  task :clobber do
    # remove the public docs, regions, and studios directories
    ['docs', 'regions', 'studios'].each do |dir|
      path = File.join(Rails.application.root, 'public', dir)
      if Dir.exist?(path)
      puts "Removing #{path}"
      FileUtils.rm_rf(path)
      end
    end
    
    # remove year-based directories (2022, 2023, 2024, 2025, etc.)
    Dir[File.join(Rails.application.root, 'public', '[0-9][0-9][0-9][0-9]')].each do |path|
      if Dir.exist?(path)
        puts "Removing #{path}"
        FileUtils.rm_rf(path)
      end
    end

    # remove the public/showcase.js file
    showcase_js = File.join(Rails.application.root, 'public', 'showcase.js')
    if File.exist?(showcase_js)
      puts "Removing #{showcase_js}"
      FileUtils.rm showcase_js
    end

    # remove the public/index.html file
    index_html = File.join(Rails.application.root, 'public', 'index.html')
    if File.exist?(index_html)
      puts "Removing #{index_html}"
      FileUtils.rm index_html
    end
  end
end

# Usage: rake prerender
# Description: Prerender all the markdown files in the app/views/docs directory
task :prerender => "prerender:env" do
  public = File.join(Rails.application.root, 'public')
  Rails.application.config.assets.prefix = '/showcase/assets/'

  # Load showcases and get prerenderable paths using shared module
  require_relative '../prerender_configuration'

  showcases = YAML.load_file(File.join(Rails.application.root, 'config/tenant/showcases.yml'))
  paths = PrerenderConfiguration.prerenderable_paths(showcases)

  # Add studios from map.yml that don't have events
  map_file = File.join(Rails.application.root, 'config/tenant/map.yml')
  if File.exist?(map_file)
    map_data = YAML.load_file(map_file)
    map_data["studios"].each do |studio, info|
      paths[:studios] << studio unless paths[:studios].include?(studio)
    end
    paths[:studios].sort!
  end

  # Start with the index.html and regions/index.html files
  files = [
    ['/', 'index.html'],
    ['regions/', 'regions/index.html'],
  ]

  # Add the region and studio index.html files
  files += paths[:regions].map { |region| ["regions/#{region}", "regions/#{region}.html"] }
  files += paths[:studios].map { |studio| ["studios/#{studio}", "studios/#{studio}.html"] }

  # Add year-based index files (e.g., /2025/, /2025/boston/)
  paths[:years].each do |year|
    # Add the year index (e.g., /2025/)
    files << ["#{year}/", "#{year}/index.html"]

    # Add each city index within the year (e.g., /2025/boston/)
    # Only multi-event studios (those with :events) get prerendered indexes
    if paths[:multi_event_studios][year]
      paths[:multi_event_studios][year].each do |city|
        files << ["#{year}/#{city}/", "#{year}/#{city}/index.html"]
      end
    end
  end

  # add the markdown files
  files += Dir.chdir('app/views') do
    Dir['docs/**/*.md'].map {|file| [file.chomp('.md'), file.chomp('.md') + '.html']}
  end

  files.delete ["docs/index", "docs/index.html"]
  files << ["docs/", "docs/index.html"]
  files << ["studios/", "studios/index.html"]

  # prerender the files
  files.each do |path, html|
    env = {
      "PATH_INFO" => '/showcase/' + path,
      "REQUEST_METHOD" =>"GET"
    }

    code, _headers, response = Rails.application.routes.call env

    if code == 200
      dest = File.join(public, html)
      dest_dir = File.dirname(dest)
      FileUtils.mkdir_p dest_dir unless Dir.exist?(dest_dir)
      body = response.body.force_encoding('utf-8')
      if !File.exist?(dest) || IO.read(dest) != body
        File.write dest, body
      end
    else
      puts code
      puts path
      puts response.inspect
      exit 1
    end
  end

  # add images and static html
  files += Dir.chdir('public') do
    Dir['*.*'].map {|file| [file, file]}
  end

  # Build studios hash for JavaScript (map studio to region)
  studios = {}
  showcases.each do |_year, sites|
    sites.each do |token, info|
      studios[token] = info[:region] if info[:region]
    end
  end

  # Build years hash for JavaScript (map year to list of cities)
  years = {}
  showcases.each do |year, sites|
    years[year] = sites.keys if sites.is_a?(Hash)
  end

  script = <<~JS
    // Showcase worker

    const files = #{files.sort.to_h.to_json};

    const regions = #{paths[:regions].to_json};

    const studios = #{studios.sort.to_h.to_json};

    const years = #{years.to_json};

    async function fly(request, path) {
      if (!request.headers.get("Authorization") && !path.startsWith("demo/")) {
        return new Response("Unauthorized", {
          status: 401,
          headers: { "WWW-Authenticate": 'Basic realm="Showcase"' }
        });
      }

      let url = new URL(request.url);
      url.hostname = "smooth.fly.dev";
      url.pathname = `/showcase/${path}`;
      request = new Request(url, request);

      let match;
      if (match = path.match(/\\d+\\/(\\w+)(\\/|$)/)) {
        if (studios[match[1]]) {
          request.headers.set("Fly-Prefer-Region", studios[match[1]]);
        }
      } else if (match = path.match(/regions\\/(\\w+)(\\/|$)/)) {
        if (regions.includes(match[1])) {
          request.headers.set("Fly-Prefer-Region", match[1]);
        }
      }

      return fetch(request);
    }

    async function r2(path, bucket) {
      const obj = await bucket.get(path);
      if (obj === null) {
        return new Response("Not found", { status: 404 });
      }

      const headers = new Headers();
      obj.writeHttpMetadata(headers);
      headers.set("etag", obj.httpEtag);

      return new Response(obj.body, { headers });
    }

    export default {
      async fetch(request, env, ctx) {
        let url = new URL(request.url);

        let path = url.pathname.slice(1);
        if (path == "") return new Response("Temporary Redirect", { status: 307, headers: { Location: "/regions/" } });
        if (path.startsWith('showcase/')) path = path.slice(9);

        let file = files[path];
        if (path.startsWith("assets/")) file = path;

        if (file) {
          return r2(file, env.BUCKET);
        } else {
          return fly(request, path);
        }
      },
    };
  JS

  dest = File.join(public, 'showcase.js')
  if !File.exist?(dest) || IO.read(dest) != script
    IO.write(dest, script)
  end
end
