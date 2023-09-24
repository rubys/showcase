class AssignJudges < ActiveRecord::Migration[7.0]
  def change
    add_column :events, :assign_judges, :integer, default: 0

    add_column :people, :present, :boolean, default: true
  end
end
