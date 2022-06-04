class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      t.string :userid
      t.string :password
      t.string :email
      t.string :name1
      t.string :name2
      t.string :token
      t.string :link
      t.string :sites

      t.timestamps
    end
  end
end
