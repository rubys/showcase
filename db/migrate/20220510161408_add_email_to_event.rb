class AddEmailToEvent < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :email, :string
    add_column :studios, :email, :string
  end
end
