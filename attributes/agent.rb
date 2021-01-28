# Linux username which will run Jenkins Java agent process.
# This user is entirely managed by the cookbook.
default['ros_buildfarm']['agent']['agent_username'] = 'jenkins-agent'

# Java command line arguments for the Java agent process.
# Useful for configuring memory or garbage collection parameters for the agent.
default['ros_buildfarm']['agent']['java_args'] = ''

# Jenkins username used by the Jenkins agent process to authenticate.
# This user must have the following permissions. Administrative permission is not required or recommended.
#   * Computer.CONFIGURE
#   * Computer.CONNECT
#   * Computer.CREATE
#   * Computer.DELETE
#   * Computer.DISCONNECT
default['ros_buildfarm']['agent']['username'] = 'admin'

# The display name prefix that will be shown in the Jenkins web interface
default['ros_buildfarm']['agent']['nodename'] = 'agent'

# The description that will be shown in the Jenkins web interface
default['ros_buildfarm']['agent']['description'] = 'build agent'

# The number of executors determines the number of simultaneous builds which can run on agents.
# On instances with 4 virtual CPUs and 8GiB of RAM we run four executors.
# Special agents such as the agent_on_jenkins and building_repository agent MUST only have one executory to guarantee proper operation and as a result these attributes will be overriden for the recipes which create those agents..
default['ros_buildfarm']['agent']['executors'] = 4

# The set of Jenkins labels that will be applied to agents created with this recipe.
# The example build farm configurations assume that the 'buildagent' label is the default for building sourcedeb and binarydeb packages. Other labels may be used to control where other jobs run.
default['ros_buildfarm']['agent']['labels'] = %w(buildagent)
