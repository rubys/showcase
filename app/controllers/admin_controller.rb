class AdminController < ApplicationController
  def regions
    deployed = File.join(Rails.root, 'tmp', 'deployed.json')
    regions = File.join(Rails.root, 'tmp', 'regions.json')

    thread1 = Thread.new do
      stdout, status = Open3.capture2('fly', 'regions', 'list', '--json')
      if status.success? and stdout != (IO.read deployed rescue nil)
        IO.write deployed, stdout
      end
    end

    thread2 = Thread.new do
      stdout, status = Open3.capture2('fly', 'platform', 'regions', '--json')
      if status.success? and stdout != (IO.read regions rescue nil)
        IO.write regions, stdout
      end
    end

    thread1.join
    thread2.join

    @regions = JSON.parse(IO.read(regions))
    @deployed = JSON.parse(IO.read(deployed))['ProcessGroupRegions'].
      find {|process| process['Name'] == 'app'}["Regions"].sort.
      map {|code| [code, @regions.find {|region| region['Code'] == code}]}.to_h
  end
end
