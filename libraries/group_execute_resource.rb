class Chef
  class Resource
    class GroupExecute < Chef::Resource::Execute
      provides :group_execute, target_mode: true

      def secondary_groups(arg=nil)
        set_or_return(:secondary_groups, arg, :kind_of => Array)
      end
    end
  end
end
