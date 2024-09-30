class Heat < ApplicationRecord
  belongs_to :dance
  belongs_to :entry
  validates_associated :entry

  has_many :scores, dependent: :destroy
  has_one :solo, dependent: :destroy

  def number
    return @number if @number
    value = super
    value = 0 if value.nil?
    @number = value.to_i == value ? value.to_i : value
  end

  def number= value
    @number = nil
    super value
  end

  def dance_category
    cat = if dance.heat_length or category == 'Multi'
      entry.pro ? dance.pro_multi_category : dance.multi_category
    elsif category == "Open"
      entry.pro ? dance.pro_open_category : dance.open_category
    elsif category == "Solo"
      solo.category_override || (entry.pro ? dance.pro_solo_category : dance.solo_category)
    else
      dance.closed_category
    end

    extensions = cat.extensions.order(:start_heat)
    if !cat or cat.heats == nil or extensions.empty?
      cat
    elsif extensions.first.start_heat == nil or number == nil
      cat
    elsif number < extensions.first.start_heat
      cat
    else
      extensions.reverse.find { |ext| number >= ext.start_heat } || cat
    end
  end

  def lead
    entry.lead
  end

  def follow
    entry.follow
  end

  def partner(person)
    entry.partner(person)
  end

  def subject
    entry.subject
  end

  def level
    entry.level
  end

  def studio
    subject.studio
  end

  def back
    entry.lead.back
  end
end
