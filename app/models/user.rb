class User < ApplicationRecord
  validates :userid, uniqueness: true, presence: true
  validates :password, confirmation: true
  validates :email, uniqueness: true, presence: true

  @@db = ENV['RAILS_APP_OWNER'] && SQLite3::Database.new('db/index.sqlite3')

  def self.authorized?(userid, site=nil)
    return true unless @@db

    return true if site and @@auth_studio[userid]&.include?(site)
    return true if @@auth_event.include?(userid)      

    load_auth

    return true if site and @@auth_studio[userid]&.include?(site)
    @@auth_event.include?(userid)      
  end

  def self.authlist
    return [] unless @@db
    load_auth
    @@auth_event
  end

  private

    def self.load_auth
      return unless @@db
      @@auth_studio = @@db.execute('select userid, sites from users').
        map {|userid, sites| [userid, sites.to_s.split(',')]}.to_h

      event = ENV['RAILS_APP_OWNER'];
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
