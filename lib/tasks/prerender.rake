require 'yaml'

namespace :prerender do
  task :env do
    # configure the Rails environment
    ENV['RAILS_ENV'] = 'production'
    ENV['RAILS_APP_DB'] = 'index'
    ENV['RAILS_APP_SCOPE'] = '/showcase'
    ENV['DATABASE_URL'] = nil
    Rake::Task['environment'].invoke
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
  showcases = YAML.load_file(File.join(Rails.application.root, 'config/tenant/showcases.yml'))
  showcases.each do |year, cities|
    cities.each do |city, data|
      regions << data[:region]
      studios[city] = data[:region]
    end
  end

  # start with the regions/index.html files
  files = [
    ['regions/', 'regions/index.html'],
  ]

  # add the region and studio index.html files
  files += regions.map {|region| ['regions/' + region, 'regions/' + region + '.html']}
  files += studios.keys.map {|studio| ['studios/' + studio, 'studios/' + studio + '.html']}

  # add the markdown files
  files += Dir.chdir('app/views') do
    Dir['docs/**/*.md'].map {|file| [file.chomp('.md'), file.chomp('.md') + '.html']}
  end

  files.delete ["docs/index", "docs/index.html"]
  files << ["docs/", "docs/index.html"]

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
      File.write File.join(public, html), response.body.force_encoding('utf-8')
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

  IO.write(File.join(public, 'showcase.js'), script)
end
