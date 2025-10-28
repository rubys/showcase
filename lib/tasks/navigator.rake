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

  desc "Generate Navigator YAML configuration (legacy)"
  task legacy: :environment do
    # Create a temporary class that includes the LegacyConfigurator
    legacy_controller = Class.new do
      include LegacyConfigurator

      def generate_map
        super
      end

      def generate_showcases
        super
      end

      def generate_navigator_config
        super
      end
    end.new

    legacy_controller.generate_navigator_config
    puts "Navigator configuration (legacy) generated at config/navigator.yml"
  end

  task prep: [ 'assets:precompile', 'prerender', 'config' ]
end
