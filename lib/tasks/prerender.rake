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

  # get a list of all the regions and studios from the showcases.yml file
  regions = Set.new
  studios = {}
  years = {}
  showcases = YAML.load_file(File.join(Rails.application.root, 'config/tenant/showcases.yml'))
  showcases.each do |year, cities|
    years[year] = cities.keys if cities.is_a?(Hash)
    cities.each do |city, data|
      regions << data[:region] if data[:region]
      studios[city] = data[:region] if data[:region]
    end if cities.is_a?(Hash)
  end

  # add studios without events
  map_file = File.join(Rails.application.root, 'config/tenant/map.yml')
  if File.exist?(map_file)
    map_data = YAML.load_file(map_file)
    map_data["studios"].each do |studio, info|
      studios[studio] ||= info["region"]
    end
  end

  # start with the index.html and regions/index.html files
  files = [
    ['/', "#{ENV['FLY_APP_NAME'] == 'smooth' ? 'showcase/' : ''}index.html"],
    ['regions/', 'regions/index.html'],
  ]

  # add the region and studio index.html files
  files += regions.map {|region| ['regions/' + region, 'regions/' + region + '.html']}
  files += studios.keys.map {|studio| ['studios/' + studio, 'studios/' + studio + '.html']}
  
  # add year-based index files (e.g., /2025/, /2025/boston/)
  years.each do |year, cities|
    # Add the year index (e.g., /2025/)
    files << ["#{year}/", "#{year}/index.html"]
    
    # Add each city index within the year (e.g., /2025/boston/)
    cities.each do |city|
      next unless showcases.dig(year, city, :events)
      files << ["#{year}/#{city}/", "#{year}/#{city}/index.html"]
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
      dir = File.join(public, File.dirname(path))
      dir = File.join(public, path.chomp('/')) if path.end_with?('/')
      mkdir_p dir if not Dir.exist?(dir)
      dest = File.join(public, html)
      body = response.body.force_encoding('utf-8')
      if !File.exist?(dest) || IO.read(dest) != body
        File.write File.join(public, html), body
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

  script = <<~JS
    // Showcase worker

    const files = #{files.sort.to_h.to_json};

    const regions = #{regions.to_a.sort.to_json()};

    const studios = #{studios.sort.to_h.to_json()};
    
    const years = #{years.to_json()};

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
