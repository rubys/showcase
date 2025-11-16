class AddStudentJudgeAssignmentFields < ActiveRecord::Migration[8.0]
  def change
    # Event-level configuration: enable student judge assignments feature
    add_column :events, :student_judge_assignments, :boolean, default: false

    # Category-level configuration: opt-out of per-category scoring
    # Defaults to true - when event-level student_judge_assignments is enabled,
    # applies to all categories unless explicitly disabled
    add_column :categories, :use_category_scoring, :boolean, default: true

    # Score person tracking: which student this category score is for
    # (only used when heat_id is negative, indicating category scoring)
    add_column :scores, :person_id, :integer
    add_index :scores, :person_id

    # Composite index for efficient category score lookups
    # This allows queries like: Score.where(heat_id: -category_id, judge_id: judge.id, person_id: student.id)
    add_index :scores, [:heat_id, :judge_id, :person_id],
              name: 'index_scores_on_heat_judge_person'

    # Remove foreign key constraint on heat_id to allow negative values for category scoring
    # Category scores use heat_id = -category_id (negative value)
    remove_foreign_key :scores, :heats if foreign_key_exists?(:scores, :heats)

    # Make heat_id nullable since category scores don't reference heats
    change_column_null :scores, :heat_id, true
  end
end
