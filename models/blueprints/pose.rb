import_types_from 'base'

module Base
    data_service_type 'RotationSrv' do
        output_port 'rotation_samples', '/base/samples/RigidBodyState'
    end

    # Provider of a position, i.e. only of the translation part of a
    # transformation
    data_service_type 'PositionSrv' do
        output_port 'position_samples', '/base/samples/RigidBodyState'
    end

    # Provider of an orientation, i.e. only of the rotation part of a
    # transformation
    data_service_type 'OrientationSrv' do
        output_port 'orientation_samples', '/base/samples/RigidBodyState'
    end
    
    # Provider of only the Z (altitude/depth) part of a position
    #
    # This is a common provider in underwater systems, where the absolute depth
    # can easily be measured with a good accuracy
    data_service_type 'ZProviderSrv' do
        output_port 'z_samples', '/base/samples/RigidBodyState'
    end
    
    # Provider of a full orientation as well as the altitude/depth part of the
    # position
    #
    # This is a common provider in underwater systems, where the absolute depth
    # can easily be measured with a good accuracy
    data_service_type 'OrientationWithZSrv' do
        output_port 'orientation_z_samples', '/base/samples/RigidBodyState'
        provides OrientationSrv, 'orientation_samples' => 'orientation_z_samples'
        provides ZProviderSrv, 'z_samples' => 'orientation_z_samples'
    end

    # Provider of a full pose
    data_service_type 'PoseSrv' do
        output_port 'pose_samples', '/base/samples/RigidBodyState'
        provides PositionSrv,    'position_samples' => 'pose_samples'
        provides OrientationSrv, 'orientation_samples' => 'pose_samples'
        provides OrientationWithZSrv, 'orientation_z_samples' => 'pose_samples'
    end

    # Provider of a frame transformation
    data_service_type 'TransformationSrv' do
        output_port 'transformation', '/base/samples/RigidBodyState'
    end

    # Represents estimators that provide a pose that is a best estimate of the
    # global pose of the system. Because it is a best estimate, it can actually
    # jump
    #
    # It is typically a pose estimator which fuses a global position measurement
    # such as GPS
    data_service_type 'GlobalPoseSrv' do
        provides PoseSrv
    end

    # Represents pose estimators that provide a pose which is locally
    # consistent, but that will stray away from the true global pose in the long
    # run. These estimators should not jump, as it would break the local
    # consistency constraint
    #
    # It is typically an odometry on ground-based systems
    data_service_type 'RelativePoseSrv' do
        provides PoseSrv
    end

    # Represents deltas in pose (i.e. pose change between two time steps).
    # Usually, a component that provides a PoseDelta will also provide
    # RelativePose.
    data_service_type 'PoseDeltaSrv' do
        output_port 'pose_delta_samples', '/base/samples/RigidBodyState'
    end
    
    # Provider of a full velocity
    data_service_type 'VelocitySrv' do
        output_port 'velocity_samples', '/base/samples/RigidBodyState'
    end

    # Provider of a full velocity
    data_service_type 'DVLSrv' do
        output_port 'dvl_samples', '/base/samples/RigidBodyState'
    end
    
    # Provider of distance-to-ground
    #
    # This is common in underwater systems, where the distance to ground can be
    # measured directly
    data_service_type 'GroundDistanceSrv' do
        output_port 'distance', '/base/samples/RigidBodyState'
    end
end

