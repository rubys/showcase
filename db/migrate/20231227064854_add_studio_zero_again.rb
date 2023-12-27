class AddStudioZeroAgain < ActiveRecord::Migration[7.1]
  def up
    unless Studio.where(id: 0).first
      Studio.create! name: 'Event Staff', id: 0
    end
  end
end
