namespace :nav do
  desc "Generate Navigator YAML configuration"
  task config: :environment do
    AdminController.new.generate_navigator_config
    puts "Navigator configuration generated at config/navigator.yml"
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
