class JudgeShowAssignments < ActiveRecord::Migration[7.1]
  def up
    absent = Person.where(type: 'Judge', present: false)

    add_column :judges, :show_assignments, :string, default: 'first', null: false
    add_column :judges, :present, :boolean, default: true, null: false

    absent.each do |person|
      judge=Judge.find_or_create_by(person_id: person.id)
      judge.update(present: false)
    end

    remove_column :people, :present
  end

  def down
    add_column :people, :present, :boolean, default: true, null: false

    Judge.where(present: false).each do |judge|
      judge.person.update(present: false)
    end

    remove_column :judges, :show_assignments
    remove_column :judges, :present
  end
end
