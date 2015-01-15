require 'rock/models/blueprints/control'
require 'rock/models/blueprints/pose'
require 'rock/models/blueprints/devices'

using_task_library 'simulation'

module Dev::Simulation
    module Mars
        device_type "Camera"
        device_type "DepthCamera"
        device_type "Actuators"
        device_type "Joints" do
            provides Base::JointsControlledSystemSrv
        end
        device_type "AuvMotion" do
            provides Base::JointsControlledSystemSrv
        end
        device_type "RangeFinder"
        device_type "HighResRangeFinder" # e.g. velodyne
        device_type "RotatingRangeFinder"
        device_type "IMU"
        device_type "Sonar"
        device_type "AuvController"
        device_type "ForceTorque6DOF"
    end
end

module Mars
    DevMars = Dev::Simulation::Mars
    class SimulatedDevice < Syskit::Composition
        add Simulation::Mars, :as => "mars"

        def self.instanciate(*args)
            cmp_task = super
            cmp_task.task_child.should_configure_after cmp_task.mars_child.start_event
            cmp_task
        end
    end


    class Task
        forward :physics_error => :failed

        def configure
            #orocos_task.enable_gui = true
            super
        end
    end
    
    class AuvMotion
        forward :lost_mars_connection => :failed

        driver_for DevMars::AuvMotion, :as => "driver"
        class Cmp < SimulatedDevice
            add Simulation::AuvMotion, :as => "task"
            export task_child.command_port
            export task_child.status_port
            provides Base::JointsControlledSystemSrv, :as => 'actuator'
        end
    end

    class AuvController
        forward :lost_mars_connection => :failed
        driver_for DevMars::AuvController, :as => "driver"
        class Cmp < SimulatedDevice
            add Simulation::AuvController, :as => "task"
        end
    end

    class IMU
        forward :lost_mars_connection => :failed
        driver_for DevMars::IMU, :as => 'driver'
        provides Base::PoseSrv, :as  => "pose"

        transformer do
            transform_output 'pose_samples', 'imu' => 'world'
        end

        class Cmp < SimulatedDevice
            add [DevMars::IMU,Base::OrientationSrv], :as => "task"
            export task_child.orientation_samples_port
            provides Base::PoseSrv, :as  => "pose"
        end
    end

    class Sonar
        forward :lost_mars_connection => :failed
        driver_for DevMars::Sonar, :as => "driver"
        provides Base::SonarScanProviderSrv, :as => "sonar_beam"
        class Cmp < SimulatedDevice
            add [DevMars::Sonar,Base::SonarScanProviderSrv], :as => "task"
            export task_child.sonarscan_port
            provides Base::SonarScanProviderSrv, :as  => "scan"
        end
    end

    class Camera
        forward :lost_mars_connection => :failed
        driver_for DevMars::Camera, :as => "driver"
        provides Base::ImageProviderSrv, :as => 'camera'

        class Cmp < SimulatedDevice
            add [DevMars::Camera,Base::ImageProviderSrv], :as => "task"
            export task_child.frame_port
            provides Base::ImageProviderSrv, :as => 'camera'
        end
    end

    class Joints
        forward :lost_mars_connection => :failed
        driver_for DevMars::Joints, :as => "driver"

        provides Base::JointsControlledSystemSrv, :as => 'actuators'

        class Cmp < SimulatedDevice
            add DevMars::Joints, :as => "task"
            export task_child.command_in_port
            export task_child.status_out_port
            provides Base::JointsControlledSystemSrv, :as => 'actuators'
        end
    end
    
    class ForceTorque6DOF
      forward :lost_mars_connection => :failed
      driver_for DevMars::ForceTorque6DOF, :as => "driver"

      class Cmp < SimulatedDevice
          add DevMars::ForceTorque6DOF, :as => "task"
          #export task_child.force_port
          #export task_child.torque_port
      end
    end

    class HighResRangeFinder
        argument :cameras

        forward :lost_mars_connection => :failed
        driver_for DevMars::HighResRangeFinder, :as => "driver"
        provides Base::PointcloudProviderSrv, :as => "pointcloud_provider"
        transformer do
            associate_frame_to_ports 'high_res_range_finder', 'pointcloud'
        end

        # Camera can be added to increase the viewing angle, but needs to be added after start of
        # the device
        def self.with_cameras(name, *viewing_angles)
            if viewing_angles.empty?
                viewing_angles = [90,180,270]
            end
            cameras = Hash.new
            viewing_angles.each {|v| cameras["#{name}#{v}"] = v }
            to_instance_requirements.
                with_arguments('cameras' => cameras)
        end

        class Cmp < SimulatedDevice
            add HighResRangeFinder, :as => "task"
            export task_child.pointcloud_port
            provides Base::PointcloudProviderSrv, :as => 'pointcloud_provider'
        end

        on :start do |event|
            cameras = arguments[:cameras]
            if cameras
                cameras.each do |name, angle|
                    puts "#{__FILE__}: Simulation::MarsHighResRangeFinder adding camera '#{name}' for angle '#{angle}'"
                    orocos_task.addCamera(name, angle)
                end
            end
        end
    end

    class RotatingLaserRangeFinder
      forward :lost_mars_connection => :failed
      driver_for DevMars::RotatingRangeFinder, :as => "driver"

      class Cmp < SimulatedDevice
          add RotatingLaserRangeFinder, :as => "task"
          export task_child.pointcloud_port
          provides Base::PointcloudProviderSrv, :as => 'pointcloud_provider'
      end
    end

    def self.define_simulated_device(profile, name, model)
        device = profile.robot.device model, :as => name
        # The SimulatedDevice subclasses expect the MARS task,not the device
        # model. Resolve the task from the device definition by removing the
        # data service selection (#to_component_model)
        #
        # to_instance_requirements is there to convert the device object into
        # an InstanceRequirements object
        device = device.to_instance_requirements.to_component_model
        composition = composition_from_device(model)
        device = yield(device) if block_given?
        composition = composition.use('task' => device)
        profile.define name, composition
        model
    end

    def self.composition_from_device(device_model, options = nil)
        SimulatedDevice.each_submodel do |cmp_m|
            if cmp_m.task_child.fullfills?(device_model)
                return cmp_m
            end
        end
        raise ArgumentError, "no composition found to represent devices of type #{device_model} in MARS"
    end
end


class Syskit::Actions::Profile
    #
    # Instead of doing
    #   define 'dynamixel', Model
    #
    # Do
    #
    #   define_simulated_device 'dynamixel', Dev::Simulation::Sonar
    #
    def define_simulated_device(name, model, &block)
        Mars.define_simulated_device(self, name, model, &block)
    end
end

