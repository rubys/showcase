class User < ApplicationRecord
  validates :userid, uniqueness: true, presence: true
  validates :password, confirmation: true
  validates :email, uniqueness: true, presence: true

  dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
  @@db = ENV['RAILS_APP_OWNER'] && SQLite3::Database.new("#{dbpath}/index.sqlite3")

  def self.authorized?(userid, site=nil)
    return true unless @@db

    if site
      return true if @@auth_studio[userid]&.include?(site)
      load_auth
      @@auth_studio[userid]&.include?(site)
    else
      return true if @@auth_event.include?(userid) 
      load_auth
      @@auth_event.include?(userid)
    end    
  end

  def self.index_auth?(userid)
    # deny access if there is a user with 'index' access and this user does not
    return true unless userid
    return false unless @@auth_studio[userid]
    return true if @@auth_studio[userid].include? 'index'
    return true unless @@auth_studio.any? {|user, sites| sites.include? 'index'}

    false
  end

  # list of users authorized to THIS event
  def self.authlist
    return [] unless @@db
    load_auth
    @@auth_event
  end

  # list of events this user has access to
  def self.auth_event_list(userid=ENV["HTTP_X_REMOTE_USER"])
    load_auth
    auth_sites = @@db ? @@auth_studio[userid] : []
    logger.info sites: auth_sites
    showcases = YAML.load_file('config/tenant/showcases.yml')

    root = ENV.fetch('RAILS_RELATIVE_URL_ROOT', '')

    events = []
    showcases.reverse_each do |year, sites|
      sites.each do |token, info|
        next unless auth_sites.include?(info[:name]) or  auth_sites.include?('index')
        if info[:events]
          info[:events].each do |subtoken, subinfo|
            events << "#{root}/#{year}/#{token}/#{subtoken}/".squeeze('/')
          end
        else
          events << "#{root}/#{year}/#{token}/".squeeze('/')
        end
      end
    end

    events
  end

  private

    def self.load_auth
      return unless @@db
      @@auth_studio = @@db.execute('select userid, sites from users').
        map {|userid, sites| [userid, sites.to_s.split(',')]}.to_h

      if @@auth_studio.empty?
        @@auth_studio['bootstrap'] = ['index']
      end

      event = ENV['RAILS_APP_OWNER']
      if event == 'index'
        @@auth_event = @@auth_studio.select do |userid, sites|
          not sites.empty?
        end.to_h.keys
      else
        @@auth_event = @@auth_studio.select do |userid, sites|
          sites.include? event or sites.include? 'index'
        end.to_h.keys
      end
    end

    self.load_auth
end
