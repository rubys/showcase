class Solo < ApplicationRecord
  belongs_to :heat
  belongs_to :combo_dance, class_name: 'Dance', optional: true
  belongs_to :category_override, class_name: 'Category', optional: true
  has_many :formations, dependent: :destroy
  has_one_attached :song_file

  validates_associated :heat
  validates :order, uniqueness: true

  # what to show in the 'partners' column.  Special case: show instructors if
  # on the page of the only student in the solo.
  def partners(person = nil)
    students = []
    students << heat.lead if heat.lead.type == "Student"
    students << heat.follow if heat.follow.type == "Student"

    students.delete(person) if person

    if students.empty?
      instructors
    else
      students
    end
  end

  # what to show in the 'instructors' column.  If on the page of an
  # instructor, exclude that instructor.
  def instructors(person = nil)
    if person and person.type == 'Student' and heat.partner(person).type == 'Professional'
      return []
    end

    instructors = formations.map(&:person)
    if heat.entry.instructor_id and not instructors.include? heat.entry.instructor
      instructors.unshift heat.entry.instructor
    end

    instructors.unshift heat.lead if heat.lead.type == "Professional"
    instructors.unshift heat.follow if heat.follow.type == "Professional"

    instructors.delete(person) if person
    instructors
  end
end
