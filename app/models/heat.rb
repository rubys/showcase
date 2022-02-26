class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  validates_associated :entry

  has_many :scores, dependent: :destroy
  has_one :solo, dependent: :destroy

  def dance_category
    if category == "Open"
      dance.open_category
    else
      dance.closed_category
    end
  end

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
