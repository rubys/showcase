task :map do
  Dir.chdir 'utils/mapper' do
    sh 'node usmap.js'
  end
end
