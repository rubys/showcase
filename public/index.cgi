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
</head>
<body>
  <div class="container mx-auto md:w-2/3 lg:w-1/2">
    <img class="absolute right-4 top-4 h-16" src="/showcase/arthur-murray-logo.gif">
    <h1 class="mt-8 text-center font-bold text-4xl mb-8">Index of Showcases</h1>

    <% config.each do |year, sites| %>
    <h2 class="font-bold text-2xl mt-4 mb-2"><%= year %></h2>

    <ul class="mt-2 list-disc list-inside">
      <% sites.each do |token, info| %>
      <li>
        <a href="<%= year %>/<%= token %>/">
          <span class="text-xl"><%= info[:name] %><span>
          <span class="text-slate-400">- <%= info['date'] %><span>
        </a>
      </li>
      <% end %>
    </ul>
    <% end %>
  </div>
</body>
</html>
