# minify js controllers and target older browsers
Rake::Task['assets:precompile'].enhance do
  Dir.chdir 'public/assets/controllers' do
    files = Dir['*.js'] -
            Dir['*.js.map'].map {|file| File.basename(file, '.map')}

    unless files.empty?
      sh "esbuild", *files,
        *%w(--outdir=. --allow-overwrite --minify --target=es2020 --sourcemap)
    end
  end
end
