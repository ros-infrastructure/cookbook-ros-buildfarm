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

# JDK version to install
default['ros_buildfarm']['agent']['jdk_version'] = 25
default['ros_buildfarm']['agent']['windows_jdk'] = {
  '25' => {
    'full_version' => '25.0.5.1',
    'checksum' => '29e72ad8c1b024f65aa9b710e10405240531c6e6e01ba00181c9d1e3a91b841f',
    # Fixed install location, so the agent service can use an absolute path to java.exe.
    'install_dir' => 'C:\\Program Files\\Microsoft\\jdk-25',
  },
}

# Docker version installed on Windows agents.
# Must match a docker-<version>.zip available at https://download.docker.com/win/static/stable/x86_64/
default['ros_buildfarm']['agent']['windows_docker_version'] = '29.10.0'

# Directory on Windows agents holding the swarm client, the service wrapper and its logs.
default['ros_buildfarm']['agent']['windows_agent_dir'] = 'C:\\jenkins-agent'
# Jenkins workspace root on Windows agents. Kept short to stay clear of path length limits.
default['ros_buildfarm']['agent']['windows_fsroot'] = 'C:\\J'

# WinSW wraps the swarm client as a Windows service. https://github.com/winsw/winsw/releases
default['ros_buildfarm']['agent']['windows_winsw'] = {
  'version' => '2.14.0',
  'checksum' => '4ebd9dc3e817f80b2bd8c18f5bfe0d550241c1d08b57bd9694777a6e56a7b24f', # WinSW-x64.exe
}

# Prevents docker and containerd from getting updates and restarting mid build. See https://github.com/ros2/ci/issues/702
default['ros_buildfarm']['unattended_upgrades']['package_blacklist'] = %w[docker.io containerd openjdk-]
