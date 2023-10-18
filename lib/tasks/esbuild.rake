# minify js controllers and target older browsers
Rake::Task['assets:precompile'].enhance do
  Dir.chdir 'public/assets/controllers' do
    sh 'esbuild *_controller-*.js --outdir=. --allow-overwrite --minify --target=es2020 --sourcemap'
  end
end
