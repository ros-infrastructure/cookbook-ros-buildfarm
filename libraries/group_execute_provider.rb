class Chef
  class Provider
    class GroupExecute < Chef::Provider::Execute
      provides :group_execute

      def_delegators :secondary_groups

      private

      def command
        command = new_resource.command

        if new_resource.secondary_groups
          groups = new_resource.secondary_groups
          if group
            # Always do the 'primary' group last in the call chain
            groups << group
          end
          groups.reverse.each do |secondary_group|
            command = "sg #{secondary_group} #{Shellwords.shellescape(command)}"
          end
        end

        command
      end
    end
  end
end
