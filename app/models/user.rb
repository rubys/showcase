class User < ApplicationRecord
  normalizes :userid, with: -> name { name.strip }
  normalizes :email, with: -> name { name.strip }

  validates :userid, uniqueness: true, presence: true
  validates :password, confirmation: true
  validates :email, uniqueness: true, presence: true

  has_many :locations, dependent: :nullify

  dbpath = ENV.fetch('RAILS_DB_VOLUME') { 'db' }
  @@db = ENV['RAILS_APP_OWNER'] && SQLite3::Database.new("#{dbpath}/index.sqlite3")
  @@trust_level = 0

  def self.authorized?(userid, site=nil)
    return true unless @@db

    if site
      return true if @@auth_studio[userid]&.include?(site)
      load_auth
      @@auth_studio[userid]&.include?(site)
    elsif ENV['RAILS_APP_OWNER'] == 'index'
      self.index_auth?(userid)
    else
      return true if @@auth_event.include?(userid) 
      load_auth
      @@auth_event.include?(userid)
    end    
  end

  def self.index_auth?(userid)
    # deny access if there is a user with 'index' access and this user does not
    return Rails.env.development? unless userid
    return false unless @@db && @@auth_studio[userid]
    return true if @@auth_studio[userid].include? 'index'
    return true unless @@auth_studio.any? {|user, sites| sites.include? 'index'}

    false
  end

  def self.owned?(userid, studio=nil)
    owned = studios_owned(userid)

    if owned.include? 'index'
      true
    elsif studio
      owned.include? studio.name
    else
      Studio.any? {|studio| owned.include? studio.name}
    end
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
    auth_sites = (@@db && @@auth_studio[userid]) || []
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

  def self.trust_level
    @@trust_level
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

      @@trust_level = @@db.execute('select trust_level from locations where name=' + event.inspect).first.first || 0
    end

    def self.studios_owned(userid)
      return [] unless @@db
      query = %{select name, sisters from users inner join locations
        on locations.user_id = users.id where users.userid="#{userid}"}
      @@db.execute(query).flatten.compact.split(',').uniq.join(',').split(',')
    end

    self.load_auth
end
