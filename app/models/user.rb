class User < ApplicationRecord
  validates :userid, uniqueness: true, presence: true
  validates :password, confirmation: true
  validates :email, uniqueness: true, presence: true
end
