class Entry < ApplicationRecord
  belongs_to :dance
  belongs_to :lead, class_name: 'Person'
  belongs_to :follow, class_name: 'Person'

  def subject
    if lead.type == 'Professional'
      follow
    else
      lead
    end   
  end

  def category
    if follow.type == 'Professional'
      "G - #{lead.category}"
    elsif lead.type == 'Professional'
      "L - #{follow.category}"
    else
      "AC - #{[lead.category, follow.category].max}"
    end
  end
end
