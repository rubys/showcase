#!/usr/bin/env ruby
require 'yaml'
require 'cgi'
require 'erb'
require 'json'

config = YAML.load_file("#{__dir__}/../config/tenant/showcases.yml")

config.each do |year, sites|
  sites.each do |token, info|
    db = "#{__dir__}/../db/#{year}-#{token}.sqlite3"
    info.merge! JSON.parse(`sqlite3 --json #{db} "select date from events"`).first
  end
end

CGI.new.out { ERB.new(DATA.read).result(binding) }

__END__
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
    div.info-button {position: absolute; font-size:2.25rem}
    .info-button {
      --tw-text-opacity:1;color:rgb(5 150 105/var(--tw-text-opacity));
      left:2rem;line-height:2.5rem;top:2rem
    }
  .info-box {
    --tw-border-opacity:1;
    border:4px double rgb(5 150 105/var(--tw-border-opacity));
    border-radius:.5rem;display:none;list-style-position:outside;
    list-style-type:disc;margin:2rem 1rem;padding:1rem 1rem 1rem 2rem;
    text-align:left
  }
  </style>
</head>
<body>
  <div class="container mx-auto md:w-2/3 lg:w-1/2">
    <img class="absolute right-4 top-4 h-16" src="/showcase/arthur-murray-logo.gif">
    <h1 class="mt-8 text-center font-bold text-4xl mb-8">Index of Showcases</h1>

    <div>
      <div class="info-button">&#x24D8;</div>
      <ul class="info-box">
      <li>When you see an &#x24D8; in the top left corner of the page, you
	  can click on it to see helpful hints.</li>
      <li>Click on it again to dismiss the hints.</li>
      <li>Click a city below to get started.</li>
      </ul>
    </div>

    <% config.each do |year, sites| %>
    <h2 class="font-bold text-2xl mt-4 mb-2"><%= year %></h2>

    <ul class="mt-2 list-disc list-inside">
      <% sites.each do |token, info| %>
      <li>
        <a href="<%= 
           if ENV['HTTP_X_FORWARDED_HOST']
             "#{year}/#{token}"
           else
             "#{ENV['REQUEST_SCHEME']}://#{ENV['HTTP_HOST']}:#{info[:port]}/showcase/#{year}/#{token}"
           end
         %>/">
          <span class="text-xl"><%= info[:name] %><span>
          <span class="text-slate-400">- <%= info['date'] %><span>
        </a>
      </li>
      <% end %>
    </ul>
    <% end %>
    <p>Click on the <span class="info-button">&#x24D8;</span> in the top
       left corner of this page to see helpful hints.</p>
  </div>
  <script>
    document.querySelector('.info-button').addEventListener('click', () => {
      let box = document.querySelector('.info-box');
      if (box.style.display == 'block') {
        box.style.display = 'none';
      } else {
        box.style.display = 'block';
      }
    });
  </script>
</body>
</html>
