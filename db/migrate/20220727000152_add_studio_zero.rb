class AddStudioZero < ActiveRecord::Migration[7.0]
  def up
    organizer = Studio.where(name: 'Organizer').first
    if organizer
      studio = Studio.create! organizer.as_json.merge(name: 'Event Staff', id: 0)

      organizer.people.each do |person|
        if person.type != 'Guest'
          person.update! studio: studio
        elsif person.package and person.package.price > 0
          person.update! studio: studio
        else
          person.update! studio: studio, type: 'Organizer', package: nil
        end
      end

      organizer.reload
      organizer.destroy
    elsif Studio.where(id: 0).first == nil
      Studio.create! name: 'Event Staff', id: 0
    end

    Person.where(studio: nil).each do |person|
      person.update! studio: studio
    end
  end

  def down
    studio = Studio.find(0)
    studio.people.each do |person|
      person.update! studio: nil
    end
    studio.destroy
  end
end
