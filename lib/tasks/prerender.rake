require 'yaml'

# Usage: rake prerender
# Description: Prerender all the markdown files in the app/views/docs directory
task :prerender do
  # configure the Rails environment
  ENV['RAILS_ENV'] = 'production'
  ENV['RAILS_APP_DB'] = 'index'
  ENV['RAILS_APP_SCOPE'] = '/showcase'
  Rake::Task['environment'].invoke
  public = File.join(Rails.application.root, 'public')
  Rails.application.config.assets.prefix = '/showcase/assets/'

  # get a list of all the regions and studios from the showcases.yml file
  regions = Set.new
  studios = Set.new
  showcases = YAML.load_file(File.join(Rails.application.root, 'config/tenant/showcases.yml'))
  showcases.each do |year, cities|
    cities.each do |city, data|
      regions << data[:region]
      studios << city
    end
  end

  # start with the regions/index.html files
  files = [
    ['regions/', 'regions/index.html'],
  ]

  # add the region and studio index.html files
  files += regions.map {|region| ['regions/' + region, 'regions/' + region + '.html']}
  files += studios.map {|studio| ['studios/' + studio, 'studios/' + studio + '.html']}

  # add the markdown files
  files += Dir.chdir('app/views') do
    Dir['docs/**/*.md'].map {|file| [file, file.chomp('md'), file.chomp('.md') + '.html']}
  end


  # prerender the files
  files.each do |path, html|
    env = {
      "PATH_INFO" => '/showcase/' + path,
      "REQUEST_METHOD" =>"GET"
    }

    code, headers, response = Rails.application.routes.call env

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

end
