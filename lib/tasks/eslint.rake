task :eslint do
  sh "eslint app/javascript/controllers/*_controller.js"
end

namespace :eslint do
  task :fix do
    sh "eslint --fix app/javascript/controllers/*_controller.js"
  end
end
