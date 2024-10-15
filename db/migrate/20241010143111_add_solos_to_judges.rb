class AddSolosToJudges < ActiveRecord::Migration[7.1]
  def change
    add_column :judges, :review_solos, :string, default: 'All'
  end
end
