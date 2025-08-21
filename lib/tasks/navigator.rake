namespace :nav do
  desc "Generate Navigator YAML configuration"
  task config: :environment do
    AdminController.new.generate_navigator_config
    puts "Navigator configuration generated at config/navigator.yml"
  end

  task prep: [ 'assets:precompile', 'prerender', 'config' ]
end
