require 'models/blueprints/timestamping'
require 'models/blueprints/devices'

module Dev
    module Sensors
        module Teledyne 
            device_type 'Explorer' do
                provides Base::GroundDistanceSrv
                provides Base::VelocitySrv
                provides Base::DVLSrv
            end
        end
    end
end



class DvlTeledyne::Task
    driver_for Dev::Sensors::Teledyne::Explorer, :as => 'driver', "distance" => "ground_distance", "velocity_samples" => "velocity_samples", "dvl_samples" => "velocity_samples" 
end

