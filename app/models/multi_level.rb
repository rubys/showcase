class MultiLevel < ApplicationRecord
  belongs_to :dance

  validate :age_range_consistency
  validate :level_range_consistency

  private

  def age_range_consistency
    if start_age.present? != stop_age.present?
      errors.add(:base, "start_age and stop_age must both be present or both be absent")
    end
  end

  def level_range_consistency
    if start_level.present? != stop_level.present?
      errors.add(:base, "start_level and stop_level must both be present or both be absent")
    end
  end
end
