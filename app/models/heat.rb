class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry

  def lead
    entry.lead
  end

  def follow
    entry.follow
  end

  def subject
    entry.subject
  end

  def level
    subject.level
  end

  def studio
    subject.studio
  end

  def back
    entry.lead.back
  end
end
