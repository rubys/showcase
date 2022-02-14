class Entry < ApplicationRecord
  belongs_to :lead, class_name: 'Person'
  belongs_to :follow, class_name: 'Person'
  belongs_to :age
  belongs_to :level

  has_many :heats, dependent: :destroy

  def subject
    if lead.type == 'Professional'
      follow
    else
      lead
    end   
  end

  def subject_category
    if follow.type == 'Professional' or not follow.age_id
      "G - #{age.category}"
    elsif lead.type == 'Professional' or not lead.age_id
      "L - #{age.category}"
    elsif lead.age_id > follow.age_id
      "AC - #{age.category}"
    else
      "AC - #{age.category}"
    end
  end
end
