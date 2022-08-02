class Entry < ApplicationRecord
  validate :has_one_instructor

  belongs_to :lead, class_name: 'Person'
  belongs_to :follow, class_name: 'Person'
  belongs_to :instructor, class_name: 'Person', optional: true
  belongs_to :age
  belongs_to :level

  has_many :heats, dependent: :destroy

  def active_heats
    heats.select {|heat| heat.number >= 0}
  end

  def subject
    if lead.type == 'Professional'
      follow
    else
      lead
    end   
  end

  def subject_category(show_ages = true)
    if show_ages
      if follow.type == 'Professional' or not follow.age_id
        "G - #{age.category}"
      elsif lead.type == 'Professional' or not lead.age_id
        "L - #{age.category}"
      else
        "AC - #{age.category}"
      end
    else
      if follow.type == 'Professional'
        "G"
      elsif lead.type == 'Professional'
        "L"
      else
        "AC"
      end
    end
  end

  def subject_lvlcat(show_ages = true)
    if show_ages
      if follow.type == 'Professional'
        "G - #{level.initials} - #{age.category}"
      elsif lead.type == 'Professional'
        "L - #{level.initials} - #{age.category}"
      else
        "AC - #{level.initials} - #{age.category}"
      end
    else
      if follow.type == 'Professional'
        "G - #{level.initials}"
      elsif lead.type == 'Professional'
        "L - #{level.initials}"
      else
        "AC - #{level.initials}"
      end
    end
  end

  def partner(person)
    follow == person ? lead : follow 
  end

private

  def has_one_instructor
    instructors = 0
    instructors += 1 if lead.type == 'Professional'
    instructors += 1 if follow.type == 'Professional'
    instructors += 1 if instructor_id

    if instructors == 0
      errors.add :instructor_id, 'All entries must have an instructor'
    elsif instructors > 1
      if instructor_id
        errors.add :instructor_id, 'Entry already has an instructor'
      else
        errors.add :lead_id, 'All entries must include a student'
      end
    elsif instructor_id and instructor.type != 'Professional'
      errors.add :instructor_id, 'Instructor must be a profressional'
    end
  end
end