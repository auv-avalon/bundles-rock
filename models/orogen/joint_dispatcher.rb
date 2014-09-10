require 'models/blueprints/control'

module JointDispatcher
    # Representation of a single dispatch in {Task}
    data_service_type 'DispatchedStatusSrv' do
        input_port 'status_in', '/base/samples/Joints'
        output_port 'status_out', '/base/samples/Joints'
        provides Base::JointsStatusSrv,
            'status_samples' => 'status_out'
    end

    data_service_type 'DispatchedCommandSrv' do
        input_port 'command_in', '/base/commands/Joints'
        output_port 'command_out', '/base/commands/Joints'
        provides Base::JointsCommandSrv,
            'command_samples' => 'command_out'
    end

    # Composition that represents a dispatched set of joint providers
    #
    # It is usually not used directly, but specialized subclasses for it are
    # created by {multiplex} instead
    class Dispatch < Syskit::Composition
        add Task, :as => 'dispatcher'
    end

    # Check if the given ports are referring to a status -- based on the given name
    def self.status_mapping?(input, output)
        return input.include?("status") || input.include?("state") || output.include?("status") || output.include?("state")
    end

    # Check if the given ports are referring to a command -- based on the given name
    def self.command_mapping?(input, output)
        return (input.include?("command") || input.include?("cmd") || output.include?("command") || output.include?("cmd"))
    end

    # Setup a composition programatically, so that it creates placeholder services for
    # each of the component that are at the receiving or giving end of the multiplexer chain
    #
    # The first argument takes a Hash using a 'prefix' as key and the controlled system type as value,
    # e.g. { "" => Base::JointsControlledSystemSrv }
    def self.multiplex_controlled_system_type(controlled_system_type_map, *conf_names)
        dispatches = Task.port_dispatch(*conf_names)

        task = Task.specialize
        dispatches = dispatches.map do |input, output|
            srv = nil
            if JointDispatcher.status_mapping?(input, output)
                srv = task.require_dynamic_service('dispatch_status', :as => "#{input}_#{output}",
                                      :status_in => input, :status_out => output)
            elsif JointDispatcher.command_mapping?(input, output)
                srv = task.require_dynamic_service('dispatch_command', :as => "#{input}_#{output}",
                                      :command_in => input, :command_out => output)
            else
                throw("Could not identify if #{input} and #{output} are joint state or command ports. Please put 'state' or 'command' in the names")
            end
            [input, output, srv]
        end


        Dispatch.new_submodel :name => "JointDispatcher::Dispatcher{#{controlled_system_type_map.keys.join(",")}}" do
            overload('dispatcher', task).
                with_conf(*conf_names)

            status_mappings = dispatches.map{|b| if(JointDispatcher.status_mapping?(b[0],b[1])) then b end}.compact
            command_mappings = dispatches.map{|b| if(JointDispatcher.command_mapping?(b[0],b[1])) then b end}.compact

            status_mappings.each do |input, _, srv|
                child = add Base::JointsStatusSrv, :as => input
                child.connect_to dispatcher_child.find_data_service(srv.name)
            end

            status_mappings.map { |_, output, _| output }.to_set.each do |output|
                export dispatcher_child.find_output_port(output)
                provides Base::JointsStatusSrv, :as => output, 'status_samples' => output
            end

            command_mappings.map { |input, _, _| input }.to_set.each do |input|
                export dispatcher_child.find_input_port(input)
                provides Base::JointsCommandConsumerSrv, :as => input, 'cmd_in' => input
            end

            command_mappings.each do |_, output, srv|
                child = add Base::JointsCommandConsumerSrv, :as => output
                dispatcher_child.find_data_service(srv.name).connect_to child
            end

            #Export controlled system types.
            # 1. Search for command inputs and status outputs that start with the given subsystem prefix.
            # 2a. If there is exactly one matching command input and command output, export the controlled system type.
            # 2b. Otherwise raise exception
            controlled_system_type_map.each do |subsystem_prefix, controlled_system_type|
                controlled_system_command_mappings = command_mappings.map { |input, _, _| input.start_with?(subsystem_prefix) ? input : nil }.compact.to_set
                controlled_system_status_mappings = status_mappings.map { |_, output, _| output.start_with?(subsystem_prefix) ? output : nil }.compact.to_set
                n_command_input_ports = controlled_system_command_mappings.size
                n_status_output_ports = controlled_system_status_mappings.size

                if n_command_input_ports == 1 && n_status_output_ports == 1
                    command_in = controlled_system_command_mappings.to_a[0]
                    status_out = controlled_system_status_mappings.to_a[0]
                    provides controlled_system_type, :as => "#{subsystem_prefix}_controlled_system",
                            :command_in => command_in, :status_out => status_out
                else
                    raise ArgumentError, "Can't map subsystem #{subsystem_prefix} to a controlled system type."\
                          "There must be _exactly_ one command input port and one status port "\
                          "that match the subsystem prefix. We have #{n_command_input_ports} "\
                          "command input ports and #{n_status_output_ports} status output ports "\
                          "with the prefix #{subsystem_prefix}."\
                          "You provided: "\
                          "     controlled_system_type_map: #{controlled_system_type_map}"\
                          "     dispatch configuration: #{dispatches}"
                end
            end
        end
    end

    # This allows to programmatically define a composition and its required
    # services based on the configuration given to the JointDispatcher
    #
    def self.multiplex(*conf_names)
        dispatches = Task.port_dispatch(*conf_names)

        task = Task.specialize
        dispatches = dispatches.map do |input, output|
            srv = task.require_dynamic_service('dispatch_status', :as => "#{input}_#{output}", :status_in => input, :status_out => output)
            [input, output, srv]
        end

        Dispatch.new_submodel :name => "JointDispatcher::Dispatcher{#{conf_names.join(",")}}" do
            overload('dispatcher', task).
                with_conf(*conf_names)

            # Create placeholder, i.e. add dependency on an external provider Base::JointsStatusSrv for a given
            # input port
            dispatches.each do |input, _, srv|
                child = add Base::JointsStatusSrv, :as => input
                child.connect_to dispatcher_child.find_data_service(srv.name)
            end

            # Export each output port and define it as a provider for Base::JointsStatusSrv
            dispatches.map { |_, output, _| output }.to_set.each do |output|
                export dispatcher_child.find_output_port(output)
                provides Base::JointsStatusSrv, 'status_samples' => output, :as => output
            end
        end
    end

    class Task
        dynamic_service DispatchedStatusSrv, :as => 'dispatch_status' do
            provides DispatchedStatusSrv, "status_in" => options[:status_in], "status_out" => options[:status_out]
            component_model.orogen_model.port_driven options[:status_in]
        end

        dynamic_service DispatchedCommandSrv, :as => 'dispatch_command' do
            provides DispatchedCommandSrv, "command_in" => options[:command_in], "command_out" => options[:command_out]
            component_model.orogen_model.port_driven options[:command_in]
        end

        # @return [Array<(String,String)>] the dispatches represented at the port
        #   level, as a map from input ports to the corresponding output port
        def self.port_dispatch(*conf_names)
            conf = Orocos.conf.resolve('joint_dispatcher::Task', conf_names, true)
            conf['dispatches'].map do |dispatch|
                # The configuration objects are using typelib values, convert to
                # proper strings
                #
                # This workarounds a bug in oroGen, which does not call #to_str
                # whenever it expects a string
                [dispatch['input'].to_str, dispatch['output'].to_str]
            end
        end
    end
end

