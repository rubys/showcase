namespace :nav do
  desc "Generate Navigator YAML configuration"
  task :config do
    # Use fast standalone script instead of loading full Rails environment
    # This is 24x faster than loading Rails (0.13s vs 3s)
    system "ruby script/generate_navigator_config.rb"
  end

  desc "Generate Navigator maintenance mode configuration"
  task :maintenance do
    # Generate minimal maintenance config with infrastructure but no tenants
    # Used during container startup before full config is generated
    system "ruby script/generate_navigator_config.rb --maintenance"
  end

  task prep: [ 'assets:precompile', 'prerender', 'config' ]
end
