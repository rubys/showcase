task :map do
  Dir.chdir 'utils/mapper' do
    sh 'node makemaps.js'
  end
end
